# S02 test epic 10b: ActivityFlags and wiring flag matrix tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/config/activity_flags_test.dart` (new, 12 tests): defaults, `journalEnabled` truth table, `==`, `hashCode`, `toString` distinguish all four flag combinations, `compileTime` default OFF, provider override.
- `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart` (new, 22 tests): both OFF identical to today; only `localJournal` ON opens the journal with exactly one override (no sync repository), wraps the wipe, keeps uploader and withdrawal providers null, hides the conflict card without reading the presenter; `cloudSync` ON and both ON add the sync override, uploader and start-up sync. The journal is opened for real on a temp directory with a faked `path_provider` and mocked secure storage.

## Why
Remediation D (independent `ACTIVITY_LOCAL_JOURNAL` flag); oracle `docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md`.

## Affected contracts and paths
Tests only.

## Verification state
Run by the author: 34 tests in `test/features/activity/config/`, all passed.
