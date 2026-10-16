# S02-02 change record: file-system seam, journal layout constants and backup exclusion

Date: 2026-10-16. Story: S02-02 "Local journal" (design 3.4, 10; test ids I08, I19, I20).

## What changed

- New `mobile/lib/features/activity/repository/journal_errors.dart`: typed journal errors (`JournalStorageFullException`, `JournalIoException`, `JournalKeyUnavailable`, tombstone, read-only, invalid id, already-open, not-started). A write failure carries the pending session so a recording can be retried from memory.
- New `journal_file_system.dart`: the injectable `JournalFileSystem` seam (create dir, read, list, open-for-write with separate write / flush / fsync / close steps, atomic rename, delete, modified time) and the `dart:io` implementation. The seam has no directory-fsync operation. `isDiskFull` maps ENOSPC / EDQUOT / Windows disk-full codes.
- New `journal_layout.dart`: layout names (`journal`, `sources`, `quarantine`, `CURRENT`, `COMMIT`, `record.json`, `streams.bin`, `index.jsonl`), the single list of backup-excluded directories, the checker `backupXmlExcludesJournal`, and the `BackupExclusionMarker` interface for iOS.
- `backup_rules.xml` and `data_extraction_rules.xml` (cloud-backup and device-transfer) now exclude `domain="file"` paths `journal`, `sources`, `quarantine`.
- `mobile/IOS_PERMISSIONS_TODO.md`: records that the native iOS marker is a follow-up because the iOS project does not exist.

## Why

Design 3.4 and GPS-PRIV-083: routes and heart rate must not travel in Android backups or device transfer; design 10 and test plan I19/I20 need a seam that exposes every write step to fault injection.

## Affected contracts and paths

`mobile/lib/features/activity/repository/` (new, outside `activity/data`), the two Android XML files, `IOS_PERMISSIONS_TODO.md`. The existing `mobile/test/android/backup_rules_test.dart` asserts EXACTLY four exclusions per section and will fail until the test agents update its expected set (not changed here: no tests are written in this story).

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
