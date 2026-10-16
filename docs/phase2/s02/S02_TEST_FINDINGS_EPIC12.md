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

## Epic 12b (F2: uid_scoped_activity_journal, journal_cipher, activity_wiring, activity_stream_uploader)

Oracles: `S02_REMEDIATION_F_TEST_NOTES.md` heading F2, design 17 items 22 and 23, the promise "deleting my account erases my data and nothing brings it back". Head of the final runs: 7c790130 plus the commit of this section.

### Files
- New tests: `mobile/test/features/activity/repository/uid_scoped_journal_wipe_rebind_test.dart` (28), `activity_journal_binding_retry_test.dart` (14), `activity_stream_uploader_account_switch_test.dart` (7), `mobile/test/features/activity/e2e/s02_wipe_and_rebind_e2e_test.dart` (3).
- Updated stale tests: `uid_scoped_activity_journal_test.dart` (the epic 11a test expected `bindUid` of a wiped uid to return true at once; updated to the F2 contract: false until `bindUid(null)` or another uid, then clean), `activity_journal_wipe_wiring_test.dart` (`_Scoped` fake now implements `boundUid`/`isBound`; `idsOf` unbinds first), `mobile/test/support/journal_harness.dart` (`FakeJournalSecureStorage.failDeletes`).
- Commits: 0050c17e, 2791285a, d475e21d and the final commit of this section.

### Defects
1. Production, `UidScopedActivityJournal.bindUid` (fixed, 3 lines): after `wipeForUid(bound uid)` the journal is already unbound, so `bindUid(null)` returned at the "already unbound" early exit before `_wipedUid` was cleared; the refusal then only ended when another uid was bound. Contract: cleared by `bindUid(null)` or another uid. Layer that missed it: F2 author (nothing compiled or run) and the four reviews; found by the notes-derived test.
2. Stale oracle (test defect): epic 11a test `wipeForUid(bound uid) wipes it and leaves the journal unbound` expected `bindUid` of the wiped uid to be true; three `idsOf` helpers in the wipe wiring test did the same. Layer: the F2 notes listed the fake but not these assertions; found by the first compiled run.
3. Stale fake: `_Scoped extends Fake implements ActivityJournal, AccountScopedJournal` lacked `boundUid`/`isBound` (listed in the notes, fixed).
4. The "throwing-close wipe" test failed once at its precondition (`expect key exists after bindUid`): classified TEST DEFECT, not production: the journal creates its key lazily at the first write, `bindUid` alone creates none. Fix: create the key explicitly before the wipe; the assertion that the key is gone after the wipe is unchanged. Production close paths are best effort as the contract requires (tests: close throwing on switch, on `bindUid(null)`, on wipe).
5. Test slip of mine in the uploader file: the fake's fault hook runs before its blocking hook, so the first old-epoch test never blocked; rewritten with a blocking hook that then throws.
6. Architecture/import guard (check asked for): `test/core/architecture/*` scan only the `data/` directories of four features and `core/math`; `core/wiring/activity_wiring.dart` importing `accountBeingDeletedUidProvider` from `features/account_deletion/state` is outside them and matches existing imports in `body_scan` and `food_diary` state. All guard tests pass; no change needed.
7. No defect found in `SecureStorageJournalKeyProvider.forget` (propagates, cache cleared, idempotent), the binding provider (retry 5 s/15 s/60 s/5 min/5 min, one timer, cancel on new auth value and disposal, deleting uid skipped, no uid in logs) or the uploader reset (new run for B, A cancelled without writes, failed ids and slot cleared).
8. Observation, not changed: a wipe leaves empty hash-named skeleton directories (`journal/`, `sources/`, `quarantine/`) under the scope directory; no file and no key remain. The notes say "no directory for A"; the tests assert no file, no key and that the factory is never asked again.

### Runs
From `D:\Repo\Fitness_App_Phase2_s01\mobile`:
- First compiled run of `flutter test test/features/activity/repository/uid_scoped_activity_journal_test.dart`: `00:04 +21 -1: Some tests failed.` (defect 2). After fixing the test and the production line: `+117: All tests passed!` (the five edited or related files together: uid_scoped_activity_journal, activity_journal_wipe_wiring, journal_io_error_remediation, activity_wiring_account_switch, config).
- Intermediate: `+114 -3: Some tests failed.` (three `idsOf` assertions), then `+35 -3: Some tests failed.` (wipe wiring plus uid_scoped files, after the `idsOf` fix, still red because of the early-exit defect 1), then green after the production fix.
- `uid_scoped_journal_wipe_rebind_test.dart`: `+27 -1: Some tests failed.` (defect 4), then `+28: All tests passed!`.
- Uploader file: `+6 -1: Some tests failed.` (defect 5), then with `activity_stream_upload_test.dart` `+36: All tests passed!`. Binding retry file: `+14: All tests passed!`. E2E file: `+3: All tests passed!`.
- Complete set, first: `flutter test --reporter failures-only test/features/activity/repository test/features/activity/config test/features/activity/e2e test/features/account_deletion test/core/architecture test/android/backup_rules_test.dart` gave `+770 -1: Some tests failed.` (SF9 in 12a's `activity_sync_corrupt_summary_test.dart`, mid-edit by agent 12a), then `+771: All tests passed!`.
- Final, whole directory: `flutter test test/features/activity` -> `02:44 +1264: All tests passed!`
- Final, guards: `flutter test test/features/account_deletion test/core/architecture test/android/backup_rules_test.dart test/features/activity/repository/backup_exclusion_test.dart` -> `00:09 +116: All tests passed!`

### Not verified / remains
- The `authUid` argument of `activityRootOverrides`: building the repository calls `FirebaseFirestore.instance`, which needs an initialised Firebase app; a construction-level test would need Firebase platform mocks or a seam. Not tested.
- Real `flutter_secure_storage` delete failures and OS directory behaviour are fakes.
- No mutation run (operator rule); falsifiability argued from assertions (for example the rebind tests fail if `_wipedUid` is dropped, because the factory is asked again and a key appears).
- `flutter analyze`, full suite and builds not run by design.
