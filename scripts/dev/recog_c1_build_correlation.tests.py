# Mutation test for the correlation script's own guards.
#
# Run:  py -3 scripts/dev/recog_c1_build_correlation.tests.py
#
# A check that cannot fail proves nothing. Each mutation below corrupts the input
# in a way exactly one guard exists to catch; that guard must reject, name itself
# in its own output, and leave no manifest behind.
#
# WHY THE ASSERTION IS NOT MERELY "no manifest appeared". An earlier version of
# this file asserted only on the output file's existence, and two reviewers
# independently pointed out the same hole: a script that crashed on its first
# line -- a broken import, a moved input path -- also writes no manifest, so
# three of the four cases would have printed PASS while naming guards that never
# ran. The claim being made elsewhere ("the guards are mutation-tested") would
# then have rested on a human having traced the source, not on this suite.
#
# So each case now asserts four things: the named guard's own marker appears in
# stdout, the OTHER guards' markers do not, the exit code is non-zero, and stderr
# is empty -- an unhandled traceback can no longer pass for a deliberate refusal.
# And `test_the_test` below swaps in a stub that exits 1 immediately and requires
# every case to FAIL against it, which is the only way to show these assertions
# can still catch the hole they were written for.
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = 'scripts/dev/recog_c1_build_correlation.py'
REQS = 'core/plans/recog_c1_raw/recog_c1_server_requests_2026-09-06_07.json'
OUT = 'core/plans/RECOG_C1_SERVER_CORRELATION_2026-09-07.json'

ALL_MARKERS = ('FAIL-EXHAUSTIVENESS', 'FAIL-PURITY', 'FAIL-STRADDLE', 'FAIL-COUNT',
               'FAIL-FEASIBILITY', 'FAIL-FALSIFICATION', 'FAIL-CONTAINMENT',
               'FAIL-DUPLICATE', '104/104 correlated to')


def check(mutate, expect_written, expect_marker, stub=None, mutate_raw=None):
    """Run the script over mutated input. Returns (ok, list of complaints).

    `mutate` edits the request log; `mutate_raw` edits window 2's raw observation
    file, which is the only way to reach the guards that read the client side.
    """
    work = tempfile.mkdtemp(prefix='corrmut_')
    try:
        for rel in (SCRIPT, REQS,
                    'core/plans/recog_c1_raw/recog_c1_raw_w1.jsonl',
                    'core/plans/recog_c1_raw/recog_c1_raw_w2.jsonl'):
            dst = os.path.join(work, rel.replace('/', os.sep))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(os.path.join(REPO, rel.replace('/', os.sep)), dst)

        script_path = os.path.join(work, SCRIPT.replace('/', os.sep))
        if stub is not None:
            io.open(script_path, 'w', encoding='utf-8', newline='\n').write(stub)

        reqs_path = os.path.join(work, REQS.replace('/', os.sep))
        data = json.load(io.open(reqs_path, encoding='utf-8'))
        mutate(data)
        json.dump(data, io.open(reqs_path, 'w', encoding='utf-8'))

        if mutate_raw is not None:
            raw_path = os.path.join(
                work, 'core/plans/recog_c1_raw/recog_c1_raw_w2.jsonl'.replace('/', os.sep))
            lines = [l for l in io.open(raw_path, encoding='utf-8').read().split('\n')]
            io.open(raw_path, 'w', encoding='utf-8', newline='\n').write(
                '\n'.join(mutate_raw(lines)))

        p = subprocess.run([sys.executable, script_path], capture_output=True, text=True)
        written = os.path.exists(os.path.join(work, OUT.replace('/', os.sep)))

        bad = []
        if written != expect_written:
            bad.append(f'manifest written={written}, expected {expect_written}')
        if expect_marker not in p.stdout:
            bad.append(f'missing marker {expect_marker!r}')
        for m in ALL_MARKERS:
            if m != expect_marker and m in p.stdout:
                bad.append(f'unexpected marker {m!r} -- a different guard fired')
        want_rc = 0 if expect_written else 1
        if p.returncode != want_rc:
            bad.append(f'exit code {p.returncode}, expected {want_rc}')
        if p.stderr.strip():
            bad.append(f'stderr not empty: {p.stderr.strip().splitlines()[-1][:90]}')
        return (not bad), bad
    finally:
        shutil.rmtree(work, ignore_errors=True)


def m_refusal_inside(d):
    """Turn one served request inside window 1 into a 401. PURITY must fire."""
    for e in d:
        if e['status'] == 200 and e['timestamp'].startswith('2026-09-06T00:05'):
            e['status'] = 401
            return
    raise AssertionError('no target found for the purity mutation')


def m_stranded_served(d):
    """Move one served request far outside both runs. EXHAUSTIVENESS must fire."""
    for e in d:
        if e['status'] == 200:
            e['timestamp'] = '2026-09-06T12:00:00.000000Z'
            return


def m_displace_one(d):
    """Move one request 2.5 minutes later, still inside its own run window.

    Note what this actually does, because the obvious description is wrong: the
    script re-sorts every served request by timestamp, so the moved entry does
    not simply sit 2.5 minutes off its own slot -- it lands roughly thirteen
    positions later in the global order and pushes every request in between down
    by one. The preconditions still pass (it stays inside window 1, and the count
    is still 52 to 52), so it reaches FEASIBILITY, which is the guard this case
    exists to exercise. A reviewer caught the earlier docstring here claiming an
    isolated single-request outlier; the guard was right, the story was not.
    """
    served = sorted([e for e in d if e['status'] == 200], key=lambda e: e['timestamp'])
    served[25]['timestamp'] = '2026-09-06T00:07:30.000000Z'


def m_none(d):
    return


def raw_duplicate_id(lines):
    """Rename one window-2 observation to a window-1 id. DUPLICATE must fire.

    The manifest is a dict keyed by observation id, so a collision would silently
    overwrite the earlier entry and quietly correlate 103 observations while
    reporting 104. This is the mutation that proves the guard against it is real.
    """
    out = []
    swapped = False
    for line in lines:
        if not swapped and '"record_type":"observation"' in line and '"w2-p26-A-1"' in line:
            line = line.replace('"w2-p26-A-1"', '"w1-p00-A-1"')
            swapped = True
        out.append(line)
    # The ids are read from the real files rather than guessed: window 2 starts at
    # pair p26, not p00, and the raw JSON is compact with no space after the
    # colon. An earlier version of this mutation assumed both and silently found
    # nothing -- which the assert below turns into a failure instead of a pass.
    assert swapped, 'no window-2 observation found to rename'
    return out


CASES = [
    (m_refusal_inside, 'a 401 inside a scored run window', False, 'FAIL-PURITY'),
    (m_stranded_served, 'a served request outside both runs', False, 'FAIL-EXHAUSTIVENESS'),
    (m_displace_one, 'one request displaced inside its own run', False, 'FAIL-FEASIBILITY'),
    (m_none, 'unmutated input -- the harness must not be the reason', True, '104/104 correlated to'),
]

# Reaches the client-side guard, so it carries its own raw mutation.
RAW_CASES = [
    (raw_duplicate_id, 'a window-2 observation renamed onto a window-1 id', False,
     'FAIL-DUPLICATE'),
]

STUB = 'raise SystemExit(1)\n'

results = []
for mutate, label, expect_written, marker in CASES:
    ok, bad = check(mutate, expect_written, marker)
    results.append(ok)
    print(f'{"PASS" if ok else "FAIL"}  {label}  [{marker}]')
    for b in bad:
        print(f'        {b}')

for mutate_raw, label, expect_written, marker in RAW_CASES:
    ok, bad = check(m_none, expect_written, marker, mutate_raw=mutate_raw)
    results.append(ok)
    print(f'{"PASS" if ok else "FAIL"}  {label}  [{marker}]')
    for b in bad:
        print(f'        {b}')

# The test of the test: against a script that refuses everything by exiting
# immediately, every case above must FAIL. If any still passed, this suite would
# be measuring the absence of a file rather than the presence of a guard.
print()
survivors = []
for mutate, label, expect_written, marker in CASES:
    ok, _ = check(mutate, expect_written, marker, stub=STUB)
    if ok:
        survivors.append(label)
for mutate_raw, label, expect_written, marker in RAW_CASES:
    ok, _ = check(m_none, expect_written, marker, stub=STUB, mutate_raw=mutate_raw)
    if ok:
        survivors.append(label)
stub_ok = not survivors
print(f'{"PASS" if stub_ok else "FAIL"}  test_the_test: a stub that exits 1 immediately is '
      f'rejected by every case')
for sv in survivors:
    print(f'        still passed against the stub: {sv}')

results.append(stub_ok)
print()
print('mutation test:', 'ALL PASS' if all(results) else 'FAILURES ABOVE')
raise SystemExit(0 if all(results) else 1)
