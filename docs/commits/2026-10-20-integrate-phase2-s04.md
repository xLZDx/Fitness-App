# Integrate phase2/s04 chain (5d5723fa)

What: merges phase2/s04, which contains phase1/main, phase2/s00..s03d, s04-docs and feature/body-scan-nutrition-coach (ancestors): GPS recording (S04), activity journal, contracts and docs. 1344 files added, 98 modified, 0 deleted.
Conflicts and decisions (each hunk read on both sides):
- core/DECISION_LOG.md, core/LESSONS_LOG.md (add/add), core/DATA_INVENTORY_2026-08-11.md: append-only logs/tables, both sides kept (HEAD first, then branch); LESSONS_LOG: branch file as base plus the integration entry.
- mobile/android/app/src/main/res/xml/backup_rules.xml: kept both comment paragraphs (scan history from main, activity journal from branch). The exclude lists (both xml files) already carried the union: 5 main entries + 4 journal entries = 9.
- mobile/test/android/backup_rules_test.dart: kept both imports (journal_layout.dart and scan_history_store.dart `show kScanHistoryDir`, trap 3); test names and the comment changed from five/eight to nine (the expected set is 5 + androidBackupExclusions()).
- mobile/lib/main.dart: combined both: `activityAwareLocalDataWipe(DeviceLocalDataWipe(scanHistory: ref.read(scanHistoryStoreProvider)), activityJournal, preUnbind: ...)`.
- mobile/lib/features/recording/location/geolocator_location_source.dart (no git conflict, trap 1): the line `import a location package (S04-R-003). The` lost its `//` on the branch and the file did not parse; restored as a comment line with an explanatory note.
- Line endings of main.dart and backup_rules.xml normalised to CRLF after the scripted edit (they were CRLF).
Checks: no deleted files; no conflict markers; dart analyze: 0 errors; pub get --offline OK (geolocator resolves from cache).
Tests: smoke set plus test/features/{recording,activity,account_deletion,scanner} and test/core: 3237 pass, 9 skipped, 1 failure: journal_availability_test.dart "DT-0-10 no file or directory I/O before the bind" (path lookup count 1, expected 0). The same failure reproduces on the pristine branch tip 5d5723fa in a detached worktree, so it is a pre-existing defect of phase2/s04, not a merge effect. It is left failing (not skipped or weakened). The BASE known failure in backup_rules_test (pubspec.lock) now passes.
