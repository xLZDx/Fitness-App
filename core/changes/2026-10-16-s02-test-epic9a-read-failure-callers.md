# S02 test epic 9a: read-failure callers fix and tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- Defect E9a-D1 fix: `activity_sync_repository.dart` (`_syncLocked`, `saveSession`), `activity_sync_resolution.dart` (`resolveConflict`, `resolveCandidate`, `applyExplicitEdit`), `activity_stream_uploader.dart` (`uploadEntry`) and `activity_local_export.dart` (`exportActivity`) catch `JournalIoException` from `ActivityJournal.read()` and return a retryable result without changing state: `SyncOutcome.pending`, `StreamUploadOutcome.failed`, and the new `ActivityExportUnavailable`.
- `mobile/test/features/activity/repository/journal_read_failure_callers_test.dart` (new, 6 tests).
- Decision log entry appended; registry regenerated.

## Why
After SF3, `read()` throws on a local I/O error. No caller handled it, so one unreadable entry aborted a whole sync pass or export.

## Affected contracts and paths
`SyncOutcome.pending` and `StreamUploadOutcome.failed` also mean "local read failed, retry"; `ActivityExportResult` has a new sealed subclass (no exhaustive switch over it in `mobile/lib`).

## Verification state
The callers test passed (6 tests) and the complete set passed together; see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC9.md`.
