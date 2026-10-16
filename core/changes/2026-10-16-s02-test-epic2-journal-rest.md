# S02 test epic 2: crash/pair tests, encryption, backup exclusion, wipe, ownership, overrides (I02-I04, I07-I10, I22, I24, I25, I29, I35, I36, I45)

## What
- Tests: `file_activity_journal_crash_test.dart` (I02, I03, I04, I22, I35, I36), `file_activity_journal_encryption_test.dart` (I07, I24), `backup_exclusion_test.dart` (I08), `activity_wipe_test.dart` (I09, I10, I25), `workout_ownership_repository_test.dart` (I29), `file_activity_journal_overrides_test.dart` (I45).
- Existing test updated: `mobile/test/android/backup_rules_test.dart` now expects the real set per section (four earlier entries plus the three of `androidBackupExclusions()`) and tolerates CRLF in `pubspec.lock`.
- Support: `fake_summary_backend.dart`, harness key provider made replaceable.
- Production fix: `FileActivityJournal.read` treats a `record.streamHash` that differs from the COMMIT stream checksum as stream-lost (I35).

## Why
Complete test epic 2 of story S02-02. Details and contradictions: `docs/phase2/s02/S02_TEST_FINDINGS_EPIC2.md`.

## Verification state
Command (from `mobile/`): `flutter test test/android/backup_rules_test.dart test/features/activity/repository/backup_exclusion_test.dart test/features/activity/repository/activity_wipe_test.dart test/features/activity/repository/workout_ownership_repository_test.dart test/features/activity/repository/file_activity_journal_overrides_test.dart test/features/activity/repository/file_activity_journal_encryption_test.dart test/features/activity/repository/file_activity_journal_crash_test.dart`
Result: green when run together with the sync test (see the next record).
