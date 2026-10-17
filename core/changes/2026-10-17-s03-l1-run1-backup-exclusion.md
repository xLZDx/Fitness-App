# S03 lane L1 run 1: backup exclusion for the per-account journal tree

Date: 2026-10-17. Kind: production fix (data protection), part of story S03-0.

## What changed
- mobile/lib/features/activity/repository/journal_layout.dart: new constant `kScopedJournalRootDirName = 'activity_journal'`; it is the fourth entry of `kActivityBackupExcludedDirs`; header comments describe the real layout.
- mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart: `fileActivityJournalFactory` builds its root path from the constant instead of a string literal. The resulting path is byte-for-byte the same.
- mobile/android/app/src/main/res/xml/backup_rules.xml and data_extraction_rules.xml (cloud backup and device transfer sections): `<exclude domain="file" path="activity_journal" />`.
- mobile/test/features/activity/repository/backup_exclusion_test.dart and mobile/test/android/backup_rules_test.dart: expected lists now have four entries; titles and comments updated.

## Why
The S02 exclusion named directories directly under the support directory, but the production journal lives under `activity_journal/<scopeId>`. S03 switches the journal on by default, so the exclusion has to match the real tree first.

## Affected contracts and paths
Backup and device-transfer behaviour of the Android app: the whole `activity_journal` tree (every account scope) is excluded. No runtime behaviour of the journal changes. The local journal flag default is NOT changed in this commit.

## Verification state
Nothing was run by the coordinator or the implementation agent. The checker and the Android rule tests are exercised by the test agents after epic 0; until then the status is NOT_RUN.
