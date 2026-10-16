# S02 test findings, epic 9

## Epic 9a: journal I/O error remediation (B1: SF1, SF2, SF3) and read-failure callers

Branch `phase2/s02-unified-activity`. Oracles: `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md` heading B1, the silent-failure review items SF1-SF3, and design sections 7 and 17.

### Files

- `mobile/test/features/activity/repository/journal_io_error_remediation_test.dart` (18 tests): SF1 (COMMIT and record.json read errors keep every generation, `unreadable:<id>`, next start recovers the newest generation; a missing or invalid COMMIT still deletes only that generation), SF2 (key store throws once, real key loss, streams.bin I/O error on read, missing streams.bin, checksum mismatch, recovery with an I/O error and with a checksum mismatch), SF3 (record.json and COMMIT I/O error keep the cache entry and baseRev/baseSummary; deleted COMMIT, deleted record.json and a hash mismatch still drop the entry).
- `mobile/test/features/activity/repository/journal_read_failure_callers_test.dart` (6 tests): a single `read()` I/O failure in `syncAll`, `syncEntry`, `saveSession`, the three resolution calls, the stream uploader and the local export.
- Additive test support: `FaultInjectingJournalFileSystem.failReadWhen` (a read of an existing file throws a non-not-found `FileSystemException`) and `JournalHarness.failReadsOnOpen` (installs that fault before the recovery pass of `open()`).

### Defects

| # | Where | Defect | Fix |
|---|-------|--------|-----|
| E9a-D1 | `activity_sync_repository.dart` `_syncLocked` and `saveSession`; `activity_sync_resolution.dart` `resolveConflict`, `resolveCandidate`, `applyExplicitEdit`; `activity_stream_uploader.dart` `uploadEntry`; `activity_local_export.dart` `exportActivity` | After SF3 `ActivityJournal.read()` throws `JournalIoException`; none of the seven call sites caught it, so one unreadable entry aborted `syncAll` for every later entry, made `exportAll` throw, and let `uploadEntry` throw to its caller. | Catch `JournalIoException` at each read call site, change no state and report a retryable result: `SyncOutcome.pending` (sync, resolution, saveSession), `StreamUploadOutcome.failed` (uploader), and a new `ActivityExportUnavailable` result (export). |

The B1 production code (`journal_generation_writer.dart`, `journal_recovery.dart`, `file_activity_journal.dart`) compiled and passed all 18 B1 tests without change: no B1 defect was found.

### Run

Directory `mobile/`, head before this commit `43459c7b` plus the working tree of this commit.

```
flutter test test/features/activity/repository/journal_io_error_remediation_test.dart test/features/activity/repository/journal_read_failure_callers_test.dart test/features/activity/repository/file_activity_journal_test.dart test/features/activity/repository/file_activity_journal_order_test.dart test/features/activity/repository/file_activity_journal_generation_test.dart test/features/activity/repository/file_activity_journal_commit_cases_test.dart test/features/activity/repository/file_activity_journal_recovery_test.dart test/features/activity/repository/file_activity_journal_fault_test.dart test/features/activity/repository/file_activity_journal_crash_test.dart test/features/activity/repository/file_activity_journal_encryption_test.dart test/features/activity/repository/file_activity_journal_overrides_test.dart test/features/activity/repository/activity_stream_upload_test.dart test/features/activity/repository/activity_stream_upload_retry_test.dart test/features/activity/repository/activity_sync_test.dart
```

Summary line (final run at head `62ab9f9e`, same command): `02:06 +222: All tests passed!`

### Not covered

No mutation runs (operator decision). The `activity_sync_corrupt_summary_test.dart` and the owner-guard, wipe and e2e suites belong to other agents and were not run here. `flutter analyze` was not run.

<!-- Epic 9b appends its own section below. -->

## Epic 9b: remediation B2 client tests (journal wipe wiring, owner guard, corrupt summary, tombstone push error)

Files: `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart` (two NOT WIRED tests un-skipped, the `S02_E02_WIRED` define removed; `wipeImpl()` is built through `activityAwareLocalDataWipe` with an in-memory owner store), `mobile/test/features/activity/repository/activity_journal_wipe_wiring_test.dart` (24 tests), `mobile/test/features/activity/repository/activity_sync_corrupt_summary_test.dart` (14 tests, includes a hand-written fake Firestore for `FirestoreActivitySummaryBackend`).

### Defects found

- Production defects: none. The B2 code compiled on the first run (the generic `_read<R, T>` is fine) and all new tests passed on the first run. No production file was edited. Evidence strength: the tests were not run against deliberately broken code (no mutation runs, operator decision); each assertion names an observable that a regression would change (order of `wipe` then `write:B`, `remaining` list, backend call log empty, marker kept).
- Quarantine: the two epic 7a NOT WIRED entries are closed (tests run and pass). No new quarantine.

### Plan versus code (notes, not defects)

- The task text says a later success clears `lastTombstonePushError`. The getter doc (and the code) say it holds the last failed push and is null only when none failed in this process; nothing clears it. The test pins the documented behaviour. If a clear-on-success is wanted, it is a product decision plus a one-line change in `_pushLocalTombstones`.
- `fromFirestoreSummary` never throws on a wrong field TYPE (it only converts `Timestamp`), so at the backend a corrupt document is detected only when the snapshot itself cannot be decoded (`data()` throws). A wrong-typed value inside a readable map reaches the sync layer; that path is not covered here.
- A non-`LocalWipeIncomplete` inner error combined with a journal wipe failure is reported as `LocalWipeIncomplete(['activity_journal'])` and the inner error type is lost (not pinned).
- Not covered: real Firestore, `main.dart` composition itself (the e2e builds the same composition by hand), the auth-failure-at-launch and sign-out wiring (S03 scope).

### Run (from `mobile/`, head before the findings commit `62ab9f9e`)

Command: `flutter test test/features/activity/repository/activity_journal_wipe_wiring_test.dart test/features/activity/repository/activity_sync_corrupt_summary_test.dart test/features/activity/e2e test/features/account_deletion`

Summary line: `02:22 +156: All tests passed!` (24 + 14 new, the e2e directory including the 11-test wipe file with no skips, and the account_deletion directory).
