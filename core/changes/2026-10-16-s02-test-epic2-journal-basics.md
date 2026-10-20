# S02 test epic 2: journal basics (I01, I06, I18, I19, I23) and test doubles

## What
- New support code `mobile/test/support/journal_fault_fs.dart` (in-memory file system, fault-injecting wrapper with a per-operation log, crash/error/ENOSPC injection at an exact operation index, no directory-sync operation) and `mobile/test/support/journal_harness.dart` (restartable journal harness, fake clock, fake secure storage, session builder with the 7351 latitude and .25 heart-rate sentinels).
- New tests in `mobile/test/features/activity/repository/`: `file_activity_journal_test.dart` (I01 on real files, I06, I18, I23) and `file_activity_journal_order_test.dart` (I19, exact operation order).
- Production fix: `journal_errors.dart` `JournalInvalidIdException` was declared `const` but its initializer calls `substring`, which does not compile; the `const` is removed (no caller used it as a constant).

## Why
Test epic 2 (story S02-02, local journal) needs an injectable file system seam and an exact write-order oracle.

## Affected paths
`mobile/lib/features/activity/repository/journal_errors.dart`, `mobile/test/support/journal_*.dart`, `mobile/test/features/activity/repository/`.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/repository/file_activity_journal_test.dart test/features/activity/repository/file_activity_journal_order_test.dart`
Result: `All tests passed!` (25 tests).
