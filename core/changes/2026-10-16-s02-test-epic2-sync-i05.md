# S02 test epic 2: I05 synced marker only after success, idempotent replay

## What
- `mobile/test/features/activity/repository/activity_sync_test.dart` (I05 only; the broader sync tests belong to the sync epic) with `FakeSummaryBackend`.
- Production fix in `activity_sync_repository.dart` `_readAndMerge`: when the merged summary already equals the server summary the entry is marked `synced` without a write, also when no base is stored yet (lost acknowledgement before the first marker). Before, the replay wrote the same content again with the next `rev`.
- Findings document `docs/phase2/s02/S02_TEST_FINDINGS_EPIC2.md`.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/repository/activity_sync_test.dart test/features/activity/repository/activity_wipe_test.dart test/features/activity/repository/workout_ownership_repository_test.dart test/features/activity/repository/file_activity_journal_overrides_test.dart test/features/activity/repository/file_activity_journal_encryption_test.dart test/features/activity/repository/file_activity_journal_crash_test.dart test/features/activity/repository/backup_exclusion_test.dart`
Result: `All tests passed!` (69 tests); `flutter test test/android/backup_rules_test.dart`: `All tests passed!` (9).
