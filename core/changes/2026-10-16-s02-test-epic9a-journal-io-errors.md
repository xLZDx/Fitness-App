# S02 test epic 9a: journal I/O error remediation tests and read-failure callers

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/repository/journal_io_error_remediation_test.dart` (new): 18 tests for remediation B1 (SF1, SF2, SF3).
- `mobile/test/features/activity/repository/journal_read_failure_callers_test.dart` (new): 6 tests that one `read()` I/O failure is retryable for the callers.
- `mobile/test/support/journal_fault_fs.dart`, `mobile/test/support/journal_harness.dart`: additive read-failure mode (`failReadWhen`, `failReadsOnOpen`).
- Production fix (defect E9a-D1): `activity_sync_repository.dart`, `activity_sync_resolution.dart`, `activity_stream_uploader.dart`, `activity_local_export.dart` catch `JournalIoException` from `ActivityJournal.read()` and return a retryable result without changing state; `activity_local_export.dart` gains the `ActivityExportUnavailable` result.
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC9.md` (new), `docs/DOCUMENT_REGISTRY.md` regenerated, decision log entry appended.

## Why
B1 made `read()` throw on I/O errors instead of dropping the entry; the callers never handled that, so one unreadable entry could abort a whole sync pass or export.

## Affected contracts and paths
`SyncOutcome.pending` now also means "local read failed, retry"; `StreamUploadOutcome.failed` likewise; `ActivityExportResult` has a new sealed subclass (no exhaustive switch over it exists in `mobile/lib`).

## Verification state
The 14 test files named in `S02_TEST_FINDINGS_EPIC9.md` ran together: `+222: All tests passed!`. No analyze, no full suite.
