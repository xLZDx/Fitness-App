# S02 design and test plan revision 6 (GPT-PM round 3 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `dc6b2178`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 6: summary overrides are dropped only when an input of their own field changes (per-field `inputRev` counter versus `atInputRev`), never by metadata-only journal mutations (synced marker, tombstone, base revision and base summary, queue state, replay of a lost acknowledgement, new generation); a generation without a valid `COMMIT` marker never becomes an active activity, also when it is the first generation of an activity, and `streamLost` applies only to a committed generation. Section 11 test-id cells synced; section 16 has the round 3 rows.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 6: 237 planned tests (41 Dart unit, 55 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 231). New I50-I55; rewritten U41, I35, I41, I43, I44, I45, I39, I31.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 3 left two MAJOR items open: the override drop rule used the general record sequence, which also grows on metadata-only mutations, and the recovery text still allowed a valid but uncommitted first generation to appear as `streamLost`.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. A read-only cross-check outside the repository follows in the commit evidence. NOT_RUN: everything that needs code. GPT-PM round 4 is the next step.
