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

Summary line: `01:04 +222: All tests passed!`

### Not covered

No mutation runs (operator decision). The `activity_sync_corrupt_summary_test.dart` and the owner-guard, wipe and e2e suites belong to other agents and were not run here. `flutter analyze` was not run.

<!-- Epic 9b appends its own section below. -->
