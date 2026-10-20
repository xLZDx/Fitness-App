# S02 test epic 2: crash matrix, commit cases and recovery (I20, I21, I40, I41, I46-I49, I54, I55)

## What
- Support: `mobile/test/support/journal_crash_matrix.dart` (fixture, three mutation kinds: re-edit put, local delete, synced marker write on a changed record; baseline log; fault runner; recovery oracle) and a read hook on the fault file system.
- Tests in `mobile/test/features/activity/repository/`:
  - `file_activity_journal_fault_test.dart`: I20 (crash after, error after, failure instead, ENOSPC at EVERY operation of each mutation plus the following read; the number of injected points is asserted), I21 (single writer, second instance refused).
  - `file_activity_journal_generation_test.dart`: I40 (the 12 named kill points, kill and thrown error, byte equality of the previous pair, state in the selected record.json, failed read-back), I41 (cases a-g, strictly selected generation, CURRENT repaired, second start stable).
  - `file_activity_journal_commit_cases_test.dart`: I46-I49 (crash cases A-D).
  - `file_activity_journal_recovery_test.dart`: I54 (first generation without COMMIT absent) and I55 (streamLost with all metadata edits preserved).
- Production fix (found by I55): `FileActivityJournal._commitStateOnly` threw `JournalIoException` for any metadata edit (sync state, overrides) of an entry whose `streams.bin` is gone, so the sync layer could not even record `upload_failed` for a stream-lost entry. A missing `streams.bin` now yields a new generation with an empty `streams.bin` and the persisted `streamLost` flag; an existing but unreadable file still aborts; an entry already known as lost keeps the flag when its metadata is rewritten.

## Why
Design 10 requires the strictly selected generation and tombstone / synced / overrides state to be asserted after a crash at every step, and design 3.5 says metadata stays usable for a stream-lost entry.

## Affected paths
`mobile/lib/features/activity/repository/file_activity_journal.dart`, `mobile/test/support/journal_crash_matrix.dart`, `mobile/test/support/journal_fault_fs.dart`, the four test files above.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/repository/file_activity_journal_fault_test.dart test/features/activity/repository/file_activity_journal_generation_test.dart test/features/activity/repository/file_activity_journal_commit_cases_test.dart test/features/activity/repository/file_activity_journal_recovery_test.dart`
Result: `All tests passed!` (82 tests).
