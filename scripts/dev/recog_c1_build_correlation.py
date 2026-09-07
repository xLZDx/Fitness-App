# A server-side correlation id for every one of the 104 completed RECOG-C1
# observations, recovered from Cloud Logging without re-running a single call --
# and proved rather than fitted.
#
# WHAT rev7 ASKED FOR AND WHY IT WAS NOT MET. Verification (e) requires every
# scored row to carry a server correlation id and says a row missing one is not
# scored. The harness recorded `server_correlation_id: null` on all 104 rows,
# because `aiEquipmentRecognition` returns `{ text }` and nothing else -- no id
# ever reaches the client. All 104 were nonetheless scored. That is a real
# protocol violation, caught by the Rosetta closure review, not by me.
#
# WHAT THIS RECOVERS, AND HOW IT IS PROVED.
#
# Segmentation first, and independent of every timestamp: the Cloud Run request
# log carries a status per request. 110 requests exist across the two days --
# exactly 104 with status 200 and 6 with 401. The 104 are the completed calls;
# the 6 are the refusals of the two aborted App Check attempts. Nothing about
# that split depends on clocks.
#
# Then, within each run: the harness is strictly sequential -- one device, one
# call at a time, each awaited before the next -- so both sequences are totally
# ordered with no interleaving, and client call k is server request k once the
# counts agree. That identification is then tested, not assumed:
#
#   Does ONE constant clock offset for the whole run put EVERY server request
#   inside its own paired client [utc_start, utc_end] window?
#
# That is a feasibility question with one unknown and 52 simultaneous
# constraints, so it can fail -- and an earlier, sloppier version of this check
# did fail, twice, for two different reasons worth recording. Taking the
# earliest log line per trace picked up instance-startup lines and produced a
# 4.3s phantom outlier. Estimating the offset as a median and then testing
# residuals measured the wrong thing entirely: it read "the request reached the
# server 4.3s after the client began the call" as a wrong pairing, when the
# request was still comfortably inside the client's own window.
#
# The feasible-interval form has neither problem. It asks whether any single
# offset works, instead of guessing one and grading the guess.
#
# Reproduce:  py -3 scripts/dev/recog_c1_build_correlation.py
# Inputs and output are repo-relative, so a fresh clone rebuilds the manifest
# byte-for-byte, with no machine-specific path anywhere in it.
import io
import json
import os
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = {
    'w1': os.path.join(ROOT, 'core', 'plans', 'recog_c1_raw', 'recog_c1_raw_w1.jsonl'),
    'w2': os.path.join(ROOT, 'core', 'plans', 'recog_c1_raw', 'recog_c1_raw_w2.jsonl'),
}
REQS = os.path.join(ROOT, 'core', 'plans', 'recog_c1_raw',
                    'recog_c1_server_requests_2026-09-06_07.json')
OUT = os.path.join(ROOT, 'core', 'plans', 'RECOG_C1_SERVER_CORRELATION_2026-09-07.json')


def ts(s):
    s = s.replace('Z', '+00:00')
    if '.' in s:
        h, r = s.split('.', 1)
        f, tz = r.split('+', 1)
        s = f"{h}.{(f + '000000')[:6]}+{tz}"
    return datetime.fromisoformat(s)


runs = {}
for w, p in RAW.items():
    rows = []
    for line in io.open(p, encoding='utf-8'):
        if line.strip():
            o = json.loads(line)
            if o['record_type'] == 'observation':
                rows.append({'id': o['observation_id'], 'start': ts(o['utc_start']),
                             'end': ts(o['utc_end'])})
    rows.sort(key=lambda r: r['start'])
    runs[w] = rows

entries = json.load(io.open(REQS, encoding='utf-8'))
served = sorted([(e['trace'], ts(e['timestamp'])) for e in entries if e.get('status') == 200],
                key=lambda kv: kv[1])
refused = [e for e in entries if e.get('status') != 200]
print(f'request log: {len(entries)} requests = {len(served)} served (200) + {len(refused)} refused '
      f'(statuses {sorted({e.get("status") for e in refused})})')
print(f'client observations: {sum(len(v) for v in runs.values())}')
print()

# Two preconditions that can each sink the segmentation, checked every run
# rather than once by hand.
#
#   1. EXHAUSTIVENESS. If a served request fell outside both run windows, then
#      "52 client calls, 52 server requests" could be a coincidence -- one real
#      call missed, one stranger let in. Requiring every served request to belong
#      to exactly one window closes that.
#   2. PURITY. If a 401 landed inside a scored run, the claim that the refusals
#      belong solely to the two aborted attempts would be false, and with it the
#      timing-free segmentation.
windows = {}
for w, rows in runs.items():
    windows[w] = (rows[0]['start'].timestamp() - 60, rows[-1]['end'].timestamp() + 60)


def in_a_window(entry):
    t = ts(entry['timestamp']).timestamp()
    return [w for w, (lo, hi) in windows.items() if lo <= t <= hi]


stranded = [e for e in entries if e.get('status') == 200 and not in_a_window(e)]
overlapping = [e for e in entries if e.get('status') != 200 and in_a_window(e)]
straddling = [e for e in entries if len(in_a_window(e)) > 1]
print(f'served requests outside every run window: {len(stranded)} (must be 0)')
print(f'refusals inside a scored run window:      {len(overlapping)} (must be 0)')
print(f'requests claimed by more than one window: {len(straddling)} (must be 0)')
print()
if stranded or overlapping or straddling:
    if stranded:
        print('FAIL-EXHAUSTIVENESS: a served request lies outside every run window.')
    if overlapping:
        print('FAIL-PURITY: a refusal lies inside a scored run window.')
    if straddling:
        print('FAIL-STRADDLE: a request is claimed by more than one run window.')
    print('PRECONDITION FAILED -- the segmentation does not hold. Nothing written.')
    raise SystemExit(1)

manifest, report, ok, shift_margins = {}, {}, True, {}

for w, rows in runs.items():
    lo = rows[0]['start'].timestamp() - 60
    hi = rows[-1]['end'].timestamp() + 60
    seg = [s for s in served if lo <= s[1].timestamp() <= hi]
    print(f'{w}: {len(rows)} client calls, {len(seg)} served requests in the run window')
    if len(seg) != len(rows):
        print('  FAIL-COUNT: COUNT MISMATCH -- the ordinal identification is unavailable.')
        ok = False
        continue

    # Feasible offsets: delta must satisfy start_i <= srv_i - delta <= end_i for
    # every i simultaneously.
    lows = [(seg[i][1] - rows[i]['end']).total_seconds() for i in range(len(rows))]
    highs = [(seg[i][1] - rows[i]['start']).total_seconds() for i in range(len(rows))]
    a, b = max(lows), min(highs)
    print(f'  feasible single-offset interval: [{a:+.3f}s, {b:+.3f}s], width {b - a:.3f}s')
    if a > b:
        print('  FAIL-FEASIBILITY: EMPTY -- no single clock offset explains the pairing.')
        ok = False
        continue

    # Falsification: the same test applied to a DELIBERATELY WRONG pairing must
    # fail. Shift the pairing by k positions and re-run it. A test that accepts a
    # shifted pairing is measuring nothing at all, and this manifest would be
    # worthless.
    shifts = {}
    for k in (-3, -2, -1, 1, 2, 3):
        r2 = rows[max(0, -k):len(rows) - max(0, k)]
        s2 = seg[max(0, k):len(seg) - max(0, -k)]
        ka = max((s2[i][1] - r2[i]['end']).total_seconds() for i in range(len(r2)))
        kb = min((s2[i][1] - r2[i]['start']).total_seconds() for i in range(len(r2)))
        shifts[k] = (ka, kb, ka <= kb)
    accepted_shifts = [k for k, v in shifts.items() if v[2]]
    margins = sorted((v[0] - v[1], k) for k, v in shifts.items())
    tightest = margins[0]
    shift_margins[w] = margins
    print(f'  falsification: shifted pairings accepted: {accepted_shifts or "none"}; '
          f'narrowest rejection is shift {tightest[1]:+d}, empty by {tightest[0]:.3f}s')
    if accepted_shifts:
        print('  FAIL-FALSIFICATION: the test also accepts a wrong pairing, so it proves '
              'nothing.')
        ok = False
        continue

    delta = timedelta(seconds=(a + b) / 2)
    contained = sum(1 for i, r in enumerate(rows)
                    if r['start'] <= seg[i][1] - delta <= r['end'])
    ambiguous = []
    for i, r in enumerate(rows):
        moment = seg[i][1] - delta
        others = [o['id'] for o in rows
                  if o['id'] != r['id'] and o['start'] <= moment <= o['end']]
        if others:
            ambiguous.append((r['id'], others))

    print(f'  containment at the interval midpoint ({delta.total_seconds():+.3f}s): '
          f'{contained}/{len(rows)}')
    print(f'  server requests that also fit some OTHER observation: {len(ambiguous)}')
    for amb in ambiguous[:5]:
        print(f'    {amb[0]} also fits {amb[1]}')

    duplicates = [r['id'] for r in rows if r['id'] in manifest]
    if duplicates:
        print(f'  FAIL-DUPLICATE: observation id already correlated: {duplicates[:5]}')
        ok = False
        continue

    if contained == len(rows) and not ambiguous:
        for i, r in enumerate(rows):
            manifest[r['id']] = seg[i][0]
        report[w] = {
            'observations': len(rows),
            'feasible_offset_seconds': [round(a, 3), round(b, 3)],
            'offset_used_seconds': round(delta.total_seconds(), 3),
            'contained': contained,
            'ambiguous_pairings': 0,
            'falsification_shifts_accepted': 0,
            'narrowest_rejection': {'shift': tightest[1],
                                    'interval_empty_by_seconds': round(tightest[0], 3)},
        }
        print('  ACCEPTED: one offset satisfies all containments; at that offset no request '
              'fits another window, and no shift of -3..+3 is feasible.')
    else:
        ok = False
        print('  FAIL-CONTAINMENT: a request missed its own window, or fits more than one.')
    print()

_all_margins = sorted((m, w, k) for w, ms in shift_margins.items() for m, k in ms)

if ok and len(manifest) == 104 and len(set(manifest.values())) == 104:
    print(f'falsification margins across both runs: narrowest {_all_margins[0][0]:.3f}s '
          f'({_all_margins[0][1]} shift {_all_margins[0][2]:+d}), '
          f'then {_all_margins[1][0]:.3f}s .. {_all_margins[-1][0]:.3f}s')
    json.dump({
        'what': ('A server-side correlation id for every completed RECOG-C1 observation, recovered '
                 'from Cloud Logging AFTER the run.'),
        'why_it_was_not_recorded': ('aiEquipmentRecognition returns { text } and nothing else, so no '
                                    'server id ever reaches the client. The harness recorded null on '
                                    'all 104 rows and they were scored anyway, which violates rev7 '
                                    'verification (e). This file is the remediation of that '
                                    'violation, not a claim that it did not happen.'),
        'id_kind': 'Cloud Trace id of the Cloud Run request that served the call',
        'recorded_by_harness': False,
        'recovered_after_the_fact': True,
        # Precise about which half is timing-free. GPT-PM's closure review caught
        # this as a MINOR: the 104/6 split is timestamp-independent, but sorting
        # the 104 into w1 and w2 plainly is not.
        'segmentation': ('Two steps, and only the first is timing-free. (1) The request log carries '
                         '110 requests, split by HTTP status alone into exactly 104 with status 200 '
                         'and 6 with 401 -- the 104 completed calls and the 6 refusals of the two '
                         'aborted App Check attempts. No timestamp is consulted. (2) The 104 are '
                         'then assigned to run 1 or run 2 by their timestamps against the two '
                         'recorded run windows, which are disjoint and 38 hours apart; that step '
                         'does use clock evidence, and the exhaustiveness check (every served '
                         'request in exactly one window, none in two, none in neither) is what '
                         'holds it.'),
        # Computed, never typed. The first version of this sentence carried a
        # hand-written range that was wrong by more than double at the top end,
        # and it was wrong exactly because it was a literal sitting next to the
        # code that could have produced it.
        'falsification': ('The same feasibility test was re-run on pairings shifted by -3..+3 '
                          'positions. All twelve shifted pairings are infeasible, so the test can '
                          'reject a wrong answer and its acceptance of the true pairing is '
                          'evidence rather than arithmetic. Reported by the narrowest margin '
                          'rather than the most flattering: the tightest rejection is '
                          f'{_all_margins[0][1]} at shift {_all_margins[0][2]:+d}, whose feasible '
                          f'interval is empty by only {_all_margins[0][0]:.3f}s; the other eleven '
                          f'fail by {_all_margins[1][0]:.3f}s to {_all_margins[-1][0]:.3f}s.'),
        'method': ('Ordinal pairing within each strictly sequential run, then tested three ways. '
                   '(1) FEASIBILITY: there exists ONE constant clock offset per run under which '
                   'every server request falls inside its own paired client [utc_start, utc_end] '
                   'window -- one unknown against 52 simultaneous constraints, feasible interval '
                   'non-empty. (2) LOCAL UNIQUENESS: at the offset derived from that pairing, no '
                   'server request falls inside any OTHER observation window. (3) FALSIFICATION: '
                   'every positional shift of -3..+3 is infeasible under its own re-derived '
                   'interval.'),
        'what_is_not_claimed': ('This does not enumerate all 52! permutations. Checks (2) and (3) '
                                'rule out other windows AT the derived offset and all near '
                                'reorderings; they do not exhaustively exclude some distant '
                                'permutation paired with a different offset. Given strictly '
                                'sequential, non-overlapping calls on one device that is strong '
                                'evidence -- but it is evidence, and the difference is stated here '
                                'rather than rounded up to a proof.'),
        'runs': report,
        'observations': len(manifest),
        'distinct_traces': len(set(manifest.values())),
        'correlation': manifest,
    }, io.open(OUT, 'w', encoding='utf-8'), indent=1, sort_keys=True)
    print(f'104/104 correlated to {len(set(manifest.values()))} distinct server traces.')
    print(f'written: {OUT}')
else:
    print('NOT ESTABLISHED -- nothing written. A protocol deviation must be reported instead.')
    # Exit non-zero on every path that does not write a manifest, matching the
    # precondition block above. Before this, a genuine rejection exited 0 and any
    # wrapper trusting the return code read it as success.
    raise SystemExit(1)
