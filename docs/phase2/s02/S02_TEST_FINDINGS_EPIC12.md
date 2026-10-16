# S02 test findings, epic 12 (remediation F)

Agent 12b appends its own section below the 12a section; re-read before editing.

## Epic 12a (F1: activity_sync_repository.dart, activity_sync_resolution.dart)

Head under test: 19536185 plus the test commits of this epic.

### Files

- `mobile/test/features/activity/repository/activity_sync_pass_identity_test.dart` (new, 33 tests): pass identity (tombstone phase, entry phase, list/read awaited, saveSession, authUid mismatch, pusher blocked, conflict operations), caches, unbound journal (repository and presenter), tombstone retry (counter reset, fallback timer, phase exceptions, epoch re-check, error code, `requestTombstoneSync`).
- `mobile/test/features/activity/e2e/s02_pass_account_switch_e2e_test.dart` (new, 3 tests): real `FileActivityJournal` per account on a temp directory, in-memory keys, recording per-account cloud fake; promise "a running sync of A never touches B's data" for the entry phase, the tombstone phase and the tombstone push.
- Stale oracles updated: `activity_tombstone_continuation_test.dart` (no seventh attempt becomes six attempts plus one 60-minute fallback timer), `activity_sync_corrupt_summary_test.dart` (SF9: a clean pass now clears `lastTombstonePushError`).

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | E2 test `backoff schedule ... then no seventh attempt` encoded the pre-F1 contract (expected 6 timers, got 7) | F1 authors and reviewers (nothing was run) | epic 12a run |
| 2 | Epic 9 test SF9 (`activity_sync_corrupt_summary_test.dart`) still expected the error code to survive a clean pass; F1 clears it (expected `permission-denied`, actual null) | F1 authors (stale-test search covered only the files named in the notes) | epic 12a full directory run |
| 3 | The F1 production code compiled unchanged and met all 33 + 3 new oracles on the first run: no production defect found in F1 | n/a | n/a |

Own slip: after a hung first invocation I killed every `dart.exe` process, which may have interrupted a parallel run of agent 12b. The hang was a cold compile, not a test.

### Commands and results (from `D:\Repo\Fitness_App_Phase2_s01\mobile`)

- `flutter test test/features/activity/repository/activity_tombstone_continuation_test.dart`: first run `00:28 +33 -1: Some tests failed.` (defect 1); fixed.
- `flutter test --timeout 30s test/features/activity/repository/activity_sync_pass_identity_test.dart`: `00:10 +33: All tests passed!`
- `flutter test --timeout 30s test/features/activity/e2e/s02_pass_account_switch_e2e_test.dart`: `00:01 +3: All tests passed!`
- `flutter test --timeout 60s test/features/activity/repository test/features/activity/state test/features/activity/widgets test/features/activity/e2e`: first run `03:48 +658 -1: Some tests failed.` (defect 2); after the fix `03:14 +659: All tests passed!`

### Not verified / remains

- No mutation run (operator rule); each test's falsifiability is argued from its assertions: every switch test places a second account's entry with the SAME id and asserts it is unchanged and that no write or backend call followed the switch.
- `resolveCandidate` during a blocked cloud read is not reachable without a candidate fixture; it is covered at the local read gate (returns pending before any offer check). The stale-cloud-read variant for `resolveCandidate` remains untested.
- `flutter analyze`, the full suite and builds were not run by design.
