#!/usr/bin/env python3
"""Validate the reissued FitnessUp v1 registers (stdlib only).

Run: C:/Python314/python.exe validate_registers.py
Exit code 0 means every check passed; 1 means at least one failed.
"""
import csv
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AMEND = os.path.join(HERE, '..')

# 91 package rows + 27 (FU-AC-092..118) + 10 (FU-AC-119 and 120..128, defined by the protocol v1.3.1
# and lifecycle rev 3 documents; FU-AC-125 is the protocol's shared-fixture row, FU-AC-128 the lifecycle caps row)
# + 11 (FU-AC-130..140). FU-AC-129 is intentionally unused.
EXPECTED_ACCEPTANCE = 91 + 27 + 10 + 11
NEW_RANGES = [(92, 118), (119, 128), (130, 140)]

errors = []


def fail(msg):
    errors.append(msg)


def load(path, expect_bom=True):
    raw = open(path, 'rb').read()
    if expect_bom and not raw.startswith(b'\xef\xbb\xbf'):
        fail(f'{os.path.basename(path)}: UTF-8 BOM missing')
    rows = list(csv.reader(io.StringIO(raw.decode('utf-8-sig'), newline='')))
    hdr = rows[0]
    out = []
    for i, r in enumerate(rows[1:], start=2):
        if len(r) != len(hdr):
            fail(f'{os.path.basename(path)} line {i}: {len(r)} cells, header has {len(hdr)}')
            continue
        out.append(dict(zip(hdr, r)))
    return hdr, out


def ids_of(cell):
    return [x for x in cell.split(';') if x]


def expand(text):
    """Expand 'FU-AC-084 to FU-AC-086' ranges and single ids found in a SUPERSESSION cell."""
    found = set()
    for a, b in re.findall(r'(FU-(?:AC-|RQ-)?\d+) to (FU-(?:AC-|RQ-)?\d+)', text):
        pa, pb = a.rsplit('-', 1), b.rsplit('-', 1)
        for n in range(int(pa[1]), int(pb[1]) + 1):
            found.add(f'{pa[0]}-{n:03d}')
    for x in re.findall(r'FU-(?:AC-|RQ-)?\d+', text):
        found.add(x)
    return found


rh, REQ = load(os.path.join(HERE, 'REQUIREMENTS.csv'))
bh, BAK = load(os.path.join(HERE, 'BACKLOG.csv'))
ah, ACC = load(os.path.join(HERE, 'ACCEPTANCE.csv'))
th, TRC = load(os.path.join(HERE, 'TRACEABILITY.csv'))

# --- headers: original layout plus one trailing amendment_note ---
for name, hdr, first in (('REQUIREMENTS', rh, 'requirement_id'), ('BACKLOG', bh, 'task_id'),
                         ('ACCEPTANCE', ah, 'acceptance_id'), ('TRACEABILITY', th, 'requirement_id')):
    if hdr[0] != first:
        fail(f'{name}: first column is {hdr[0]!r}, expected {first!r}')
    if hdr[-1] != 'amendment_note' or hdr.count('amendment_note') != 1:
        fail(f'{name}: amendment_note must be the single trailing column')
if ah[:10] != ['acceptance_id', 'requirement_id', 'task_id', 'scenario', 'expected_result', 'method', 'priority',
               'status', 'required_evidence', 'legacy_ids']:
    fail('ACCEPTANCE: 10-column layout changed')

# --- unique ids ---
def unique(rows, key, label):
    seen = {}
    for r in rows:
        k = r[key]
        if k in seen:
            fail(f'{label}: duplicate id {k}')
        seen[k] = r
    return seen


R = unique(REQ, 'requirement_id', 'REQUIREMENTS')
B = unique(BAK, 'task_id', 'BACKLOG')
A = unique(ACC, 'acceptance_id', 'ACCEPTANCE')
tr_keys = [(r['requirement_id'], r['task_id'], r['acceptance_id']) for r in TRC]
if len(set(tr_keys)) != len(tr_keys):
    fail('TRACEABILITY: duplicate (requirement, task, acceptance) rows')
tr_acc = [r['acceptance_id'] for r in TRC]
if len(set(tr_acc)) != len(tr_acc):
    fail('TRACEABILITY: an acceptance id appears more than once')

# --- counts ---
if len(REQ) != 56: fail(f'REQUIREMENTS has {len(REQ)} rows, expected 56 (no rows added or deleted)')
if len(BAK) != 56: fail(f'BACKLOG has {len(BAK)} rows, expected 56 (no rows added or deleted)')
if len(ACC) != EXPECTED_ACCEPTANCE:
    fail(f'ACCEPTANCE has {len(ACC)} rows, expected {EXPECTED_ACCEPTANCE}')
if len(TRC) != len(ACC):
    fail(f'TRACEABILITY has {len(TRC)} rows, expected one per acceptance row ({len(ACC)})')
orig = {f'FU-AC-{n:03d}' for n in range(1, 92)}
if not orig <= set(A):
    fail(f'ACCEPTANCE: original ids missing: {sorted(orig - set(A))}')
new_ids = set()
for lo, hi in NEW_RANGES:
    new_ids |= {f'FU-AC-{n:03d}' for n in range(lo, hi + 1)}
if set(A) != orig | new_ids:
    fail(f'ACCEPTANCE: unexpected id set; extra={sorted(set(A) - orig - new_ids)} missing={sorted((orig | new_ids) - set(A))}')

# --- references ---
for a in ACC:
    aid = a['acceptance_id']
    if a['requirement_id'] not in R: fail(f'{aid}: requirement {a["requirement_id"]} does not exist')
    if a['task_id'] not in B: fail(f'{aid}: task {a["task_id"]} does not exist')
    rq = R.get(a['requirement_id'])
    if rq and aid not in ids_of(rq['acceptance_ids']): fail(f'{aid}: missing from acceptance_ids of {a["requirement_id"]}')
    tk = B.get(a['task_id'])
    if tk and aid not in ids_of(tk['acceptance_ids']): fail(f'{aid}: missing from acceptance_ids of {a["task_id"]}')
    if tk and a['requirement_id'] not in ids_of(tk['requirements']): fail(f'{aid}: task {a["task_id"]} does not list {a["requirement_id"]}')
    if aid not in tr_acc: fail(f'{aid}: not in TRACEABILITY')
for t in TRC:
    k = t['acceptance_id']
    a = A.get(k)
    if a is None:
        fail(f'TRACEABILITY: dangling acceptance id {k}')
    elif (a['requirement_id'], a['task_id']) != (t['requirement_id'], t['task_id']):
        fail(f'TRACEABILITY {k}: requirement/task differ from ACCEPTANCE')
    if t['requirement_id'] not in R: fail(f'TRACEABILITY {k}: dangling requirement {t["requirement_id"]}')
    if t['task_id'] not in B: fail(f'TRACEABILITY {k}: dangling task {t["task_id"]}')
for r in REQ:
    for x in ids_of(r['acceptance_ids']):
        if x not in A: fail(f'{r["requirement_id"]}: dangling acceptance id {x}')
        elif A[x]['requirement_id'] != r['requirement_id']: fail(f'{r["requirement_id"]}: lists {x} which belongs to {A[x]["requirement_id"]}')
    if r['backlog_id'] not in B: fail(f'{r["requirement_id"]}: dangling backlog_id {r["backlog_id"]}')
    if len(set(ids_of(r['acceptance_ids']))) != len(ids_of(r['acceptance_ids'])): fail(f'{r["requirement_id"]}: duplicate acceptance ids in cell')
for b in BAK:
    for x in ids_of(b['acceptance_ids']):
        if x not in A: fail(f'{b["task_id"]}: dangling acceptance id {x}')
        elif A[x]['task_id'] != b['task_id']: fail(f'{b["task_id"]}: lists {x} which belongs to {A[x]["task_id"]}')
    for x in ids_of(b['requirements']):
        if x not in R: fail(f'{b["task_id"]}: dangling requirement {x}')

# --- every acceptance id listed in a requirement/backlog cell exists in ACCEPTANCE (covered above); reverse covered too ---

# --- new rows: NOT_RUN, P0 unless noted, exact copy of ACCEPTANCE_AMENDMENTS.csv for 092..118 ---
for aid in sorted(new_ids):
    a = A.get(aid)
    if not a: continue
    if a['status'] != 'NOT_RUN': fail(f'{aid}: status {a["status"]!r}, expected NOT_RUN')
    if a['priority'] != 'P0': fail(f'{aid}: priority {a["priority"]!r} (documents define P0)')
    if not a['amendment_note'].startswith('NEW'): fail(f'{aid}: amendment_note should start with NEW')
for t in TRC:
    if t['acceptance_id'] in new_ids and t['evidence'] != '':
        fail(f'TRACEABILITY {t["acceptance_id"]}: evidence should be empty for a new row')
am_path = os.path.join(AMEND, 'ACCEPTANCE_AMENDMENTS.csv')
am = {r['acceptance_id']: r for r in csv.DictReader(open(am_path, encoding='utf-8-sig', newline=''))}
if len(am) != 27: fail(f'ACCEPTANCE_AMENDMENTS.csv has {len(am)} rows, expected 27')
for aid, r in am.items():
    a = A.get(aid)
    if a is None: continue
    for col in ah[:10]:
        if a[col] != r[col]: fail(f'{aid}: column {col} differs from ACCEPTANCE_AMENDMENTS.csv')
for r in ACC:
    if r['acceptance_id'] in orig and r['status'] not in ('NOT_RUN',):
        fail(f'{r["acceptance_id"]}: original row status is {r["status"]!r} (expected unchanged NOT_RUN)')

FORBIDDEN_PROTO = ('honoured by the trigger with a tombstone', 'LEGACY_DELETE', 'LEGACY_DIVERGENT', 'workout_legacy_ledger')
_proto = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'design', 'OFFLINE_COMMAND_PROTOCOL.md'), encoding='utf-8').read()
for _w in FORBIDDEN_PROTO:
    for _ln in _proto.splitlines():
        if _w in _ln and 'replaces' not in _ln and 'removed' not in _ln and 'no longer' not in _ln and 'Version 1.' not in _ln:
            fail(f'OFFLINE_COMMAND_PROTOCOL.md: withdrawn wording {_w!r} in an active line')

# --- SUPERSESSION: every affected row carries an amendment_note ---
sup_path = os.path.join(AMEND, 'SUPERSESSION.csv')
sup = list(csv.DictReader(open(sup_path, encoding='utf-8-sig', newline='')))
need_note = {'requirements': set(), 'tasks': set(), 'acceptance': set()}
for s in sup:
    cell = s['package_rows']
    ids = expand(cell)
    if 'their tasks and acceptance rows' in cell:
        for rid in [i for i in ids if i.startswith('FU-RQ-')]:
            ids.add('FU-' + rid[-3:])
            ids |= {x for x in ids_of(R[rid]['acceptance_ids']) if x in orig}
    for i in ids:
        if i.startswith('FU-RQ-'): need_note['requirements'].add(i)
        elif i.startswith('FU-AC-'): need_note['acceptance'].add(i)
        elif re.fullmatch(r'FU-\d+', i): need_note['tasks'].add(i)
    for i in expand(s['new_acceptance_ids']):
        if i.startswith('FU-AC-') and i not in A:
            fail(f'SUPERSESSION new_acceptance_ids {i} not in ACCEPTANCE')
for i in need_note['requirements']:
    if i not in R: fail(f'SUPERSESSION names unknown requirement {i}')
    elif not R[i]['amendment_note']: fail(f'{i}: SUPERSESSION row but empty amendment_note')
for i in need_note['tasks']:
    if i not in B: fail(f'SUPERSESSION names unknown task {i}')
    elif not B[i]['amendment_note']: fail(f'{i}: SUPERSESSION row but empty amendment_note')
for i in need_note['acceptance']:
    if i not in A: fail(f'SUPERSESSION names unknown acceptance {i}')
    elif not A[i]['amendment_note']: fail(f'{i}: SUPERSESSION row but empty amendment_note')
for t in TRC:
    if A.get(t['acceptance_id'], {}).get('amendment_note') and not t['amendment_note']:
        fail(f'TRACEABILITY {t["acceptance_id"]}: acceptance row is amended but trace row has no note')

# --- semantic scan: no active text may still require online-only behavior ---
BAD = ('online-only', 'remain online')
for name, rows in (('REQUIREMENTS', REQ), ('BACKLOG', BAK), ('ACCEPTANCE', ACC), ('TRACEABILITY', TRC)):
    for r in rows:
        for col, val in r.items():
            if col == 'amendment_note': continue
            low = val.lower()
            for bad in BAD:
                if bad in low:
                    fail(f'{name} {list(r.values())[0]} column {col}: active text contains {bad!r}')
# withdrawn online admission protocol vocabulary must not remain in ACTIVE text of any row
WITHDRAWN = ('preparewor' + 'koutcommand', 'admission token', 'open admission', 'closed_no_effect', 'birth epoch')
ALLOWED_WITHDRAWN = {}  # (file, row id) -> reason; empty: no row states that the withdrawn protocol is still active
for name, rows in (('REQUIREMENTS', REQ), ('BACKLOG', BAK), ('ACCEPTANCE', ACC), ('TRACEABILITY', TRC)):
    for r in rows:
        rid = list(r.values())[0]
        for col, val in r.items():
            if col == 'amendment_note' or (name, rid) in ALLOWED_WITHDRAWN: continue
            for w in WITHDRAWN:
                if w in val.lower():
                    fail(f'{name} {rid} column {col}: active text contains withdrawn term {w!r}')
for aid in ('FU-AC-012', 'FU-AC-058', 'FU-AC-059', 'FU-AC-060', 'FU-AC-081'):
    if 'REWRITTEN IN PLACE' not in A[aid]['amendment_note']: fail(f'{aid}: must be REWRITTEN IN PLACE (old text in note)')
if 'M-05 stays open' not in A['FU-AC-130']['amendment_note'] and 'M-05 stays open' not in R['FU-RQ-001']['amendment_note']:
    fail('M-05 must be recorded as PARTIAL / open')
for name, rows in (('REQUIREMENTS', REQ), ('BACKLOG', BAK), ('ACCEPTANCE', ACC), ('TRACEABILITY', TRC)):
    for r in rows:
        if re.search(r'closes? (RECONCILIATION )?M-05', r['amendment_note'], re.I):
            fail(f'{name} {list(r.values())[0]}: note says M-05 is closed; it is PARTIAL')
if 'UNKNOWN' not in A['FU-AC-130']['expected_result'] or 'FAILS' not in A['FU-AC-130']['expected_result']:
    fail('FU-AC-130: known/unknown inventory requirement missing')
for aid in ('FU-AC-125', 'FU-AC-128'):
    if aid not in A: fail(f'{aid}: missing')
for rid in ('FU-RQ-015',):
    if 'online' in R[rid]['title'].lower(): fail(f'{rid}: title still mentions online')
for aid in ('FU-AC-015', 'FU-AC-064'):
    a = A[aid]
    if not a['amendment_note'].startswith('REWRITTEN IN PLACE'): fail(f'{aid}: note must start with REWRITTEN IN PLACE')
    old_marker = 'online-only' if aid == 'FU-AC-015' else 'No durable queued mutation appears later'
    if old_marker not in a['amendment_note']: fail(f'{aid}: old wording not preserved in note')
    if 'pending sync' not in a['expected_result']: fail(f'{aid}: rewritten text must describe pending sync / durable local acceptance')
if not B['FU-015']['amendment_note'].startswith('REWRITTEN IN PLACE') or not R['FU-RQ-015']['amendment_note'].startswith('REWRITTEN IN PLACE'):
    fail('FU-RQ-015 / FU-015: note must start with REWRITTEN IN PLACE')
a67 = A['FU-AC-067']['expected_result']
if 'WAITING_FOR_READY' not in a67 or 'StartSet' not in a67 or 'not required to start a set' not in a67:
    fail('FU-AC-067: must state that a bare go is not required and StartSet is the waiting-state action')
if 'substring matching' in A['FU-AC-067']['expected_result'] and 'otherwise' not in A['FU-AC-067']['expected_result']:
    fail('FU-AC-067: rewrite incomplete')

if errors:
    print(f'FAILED: {len(errors)} problem(s)')
    for e in errors:
        print('  -', e)
    sys.exit(1)
print(f'OK: requirements={len(REQ)} backlog={len(BAK)} acceptance={len(ACC)} (91+27+10+11={EXPECTED_ACCEPTANCE}) '
      f'traceability={len(TRC)}; new rows={len(new_ids)} all NOT_RUN; superseded rows with notes: '
      f'req={len(need_note["requirements"])} task={len(need_note["tasks"])} acc={len(need_note["acceptance"])}')
