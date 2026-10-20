# S02 test epic 9b: corrupt cloud summary and tombstone push error code tests (remediation B2)

## What
- New `mobile/test/features/activity/repository/activity_sync_corrupt_summary_test.dart` (14 tests): `FirestoreActivitySummaryBackend` over a hand-written fake Firestore (parse failure is `SummaryCorrupt`, fetch failure, timeout and missing sign-in stay `SummaryBackendUnavailable`); the sync layer with a backend that throws `SummaryCorrupt` (outcome `conflict`, entry `sync_conflict`, local data intact, nothing written, no retry loop, conflict view `cloudKnown == false`, `resolveConflict` returns `conflict`, recovery once the copy is readable); `lastTombstonePushError` (code, type name, retry on the next pass, no error on success).

## Why
The B2 code for SF4 and SF9 was new and never run; the oracles are the B2 test notes and design 6.2.

## Affected paths
- `mobile/test/features/activity/repository/activity_sync_corrupt_summary_test.dart`

## Verification state
Run with flutter test, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC9.md`.
