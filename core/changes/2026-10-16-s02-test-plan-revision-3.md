# S02 test plan revision 3 and two open points settled

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Design head: `9172534c`.

## What changed
- `docs/phase2/s02/S02_TEST_PLAN.md` aligned to design revision 3: 212 planned tests (38 Dart unit, 37 Dart integration, 35 Firestore rules emulator, 3 Storage rules, 94 functions unit with fakes, 5 fake-backed E2E; previously 181). Rewrites: I26/E04 (permission-denied never deletes without a tombstone; two-device convergence and lost-ack replay), R26 (batches of at most 10), R12, R27, F41/F60-F62 (seven callables), fence tests on the top-level server-only collection, commit state machine crash and overlap tests, recompute against an index-enforcing fake, journal and sign-out tests, telemetry caps, signals. New final section "Story to test-id map" (S02-00 to S02-10 including 04a/04b, 05a/05b, 06a/06b); step 0 (F94: the fake Firestore can produce conflicting writes).
- `docs/phase2/s02/S02_DESIGN.md`: two points the test plan could not test are settled: (1) deleted-uid reuse: Firebase Auth does not re-issue uids, the fence document is removed one hour after the late job completes; (2) a commit whose derived expiry is already due is refused with the bare code `expired` and clears the pending upload, so a re-upload pending during an expiry purge cannot revive a stream.
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
Phase 4 (test plan) must match the revised design before the GPT-PM review; two pending-on-answer tests needed a decision.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`.

## Verification state
No tests or checks were run. Not testable here and marked NOT_RUN: tombstone TTL policy creation (operator, external), Cloud Monitoring metrics and alerts, the production batch-write access-call limit (the emulator limit is printed by R35). Still open: `SportType` table, default deny of `activity_account_state`, `firestore.indexes.json` contents, export paging (`fitPaged`).
