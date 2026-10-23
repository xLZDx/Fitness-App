# Change record: transactional SQLite store for the offline command queue (2026-10-23)

Base: master 28b795ad. Operator decision of 2026-10-23: replace the file-journal storage of the queue with sqflite (WAL, synchronous=FULL) to close the accepted V0 residual risk (no directory sync after the atomic rename).

## What changed
- mobile/lib/features/workouts/offline/sqlite_command_queue_store.dart (new): tables meta (schema_version, scope, created), seq_counters, logical_sets (never pruned), commands (unique intent_key, state, record_json). Accept is ONE transaction (command row, logical-set row, counter), so a failure changes nothing; prune deletes only the command row of expired SYNCED records. Open applies journal_mode=WAL, synchronous=FULL and foreign_keys=ON, reads each back and fails with QueueException if one is not applied, runs quick_check and the schema, scope and created checks; on any failure the original file stays and a copy is kept as <name>.corrupt-<n>, the store opens recovery-required (accept throws QueueRecoveryRequiredException, prune does nothing). A file with no tables is treated as fresh (a crash during first creation must not brick the app).
- command_queue_store_base.dart: hooks commitAccept and commitPrune; the defaults keep the file store unchanged.
- providers.dart: production store is SQLite at <support>/offline_command_queue_db/workout_command_queue_<scope>.db. FileCommandQueueStore still compiles and is not deleted.
- pubspec.yaml: sqflite ^2.4.1, dev sqflite_common_ffi ^2.3.4 (pubspec.lock updated).
- Android backup_rules.xml and data_extraction_rules.xml exclude the database, its -wal and -shm and the legacy file queue directory.
- Tests: contract suite also runs on SQLite; new sqlite_store_test.dart (63 tests).

## Affected contracts and paths
Mobile queue storage only. No server, rules or protocol change. The queue stays behind the V0 flag path; no user-visible behaviour changes.

## Verification state (test agent)
104 tests pass on SQLite (sqlite_store_test.dart plus the contract suite on in-memory, file and SQLite stores); 158 further tests in the sender, hardening, recovery and status files pass on the in-memory and file stores (not SQLite), and five sender-ordering tests were added to the SQLite file. Not run: analyze, the rest of the suite, CI, a device. No GPT-PM review of this change (operator ended the review rounds).

## Known gaps
iOS backup exclusion is not done (there is no ios/ folder in the repo); the 400-command and 25-day warning counts have no place in the interface yet; FileCommandQueueStore is not removed; desktop tests on Linux CI need libsqlite3 installed (Windows uses winsqlite3.dll); power-loss durability is now delegated to SQLite WAL with synchronous=FULL and has not been measured on a device.
