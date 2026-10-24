# Change record: ignore the android_metadata table when checking the queue schema (2026-10-24)

Base: master 30b6b286. Found on a real phone by the operator: the queue could not open and every "Mark complete" showed "queue metadata needs recovery: ... no such table: meta".

## What changed
- mobile/lib/features/workouts/offline/sqlite_command_queue_store.dart: the table list used to decide "new database" now excludes `android_metadata`, which sqflite creates in every Android database. Before, the list was never empty on Android, so the schema was not created and the next query failed.
- mobile/test/features/workouts/offline/sqlite_android_metadata_test.dart (test agent): four regression tests (only android_metadata; android_metadata plus a foreign table; valid store plus android_metadata; android_metadata plus a damaged store).

## Affected contracts and paths
An existing phone database that holds only android_metadata (left by the failed first open) is now treated as new and gets its schema. No other behaviour changes.

## Verification state
Test agent: 39 passed, 0 failed (35 existing plus 4 new, both store test files). Not verified: on a real device (sqflite_common_ffi on Windows with a hand-made table), and the tests were not shown to fail without the fix (no mutation runs by rule).
