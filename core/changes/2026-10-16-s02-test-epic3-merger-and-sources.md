# S02 test epic 3: native id, replay, quarantine, cursor and DeviceSource surface tests (U10, U11, U14, U15, U16, U23)

## What
- Tests in `mobile/test/features/activity/data/`:
  - `activity_ids_test.dart` (U10): literal sha1 vectors, determinism, 1000-uuid collision check, the 100 corpus ids against `^act_[0-9a-f]{40}$` with a negative control for the pattern.
  - `activity_merger_replay_test.dart` (U11, U23): `merge(raw ++ raw)` equals `merge(raw)` (count and canonical content), duplicate-list order, newer re-import, and five seeded shuffles of the 155 raw records.
  - `activity_quarantine_test.dart` (U14): 200 001 samples, depth 100, 10 MB string, duplicate keys (plain and escape-spelled), NaN / 1e999, boundaries (200 000, depth 32, 1 MiB) and acceptance of the 100 valid sessions.
  - `source_cursor_test.dart` (U15): round trip, corrupt bodies, truncation at every offset, foreign-source cursor.
  - `device_source_surface_test.dart` (U16): compile-level calls through `DeviceSource`, behaviour of the fake, source-text guard for `writeIfAuthorized` over `mobile/lib` with a positive control.
- Production fix (found by U14): `quarantineCheck` compared RAW key text, so `{"a":1,"a":2}` passed as "no duplicate" while `jsonDecode` keeps the last value (a smuggled override). Keys containing a backslash are now decoded before the duplicate test.

## Why
Design 9 (native id rule) and design 1 / 3.4 (A-1 quarantine, A-2 cursor, A-3 interface) need executable guards that fail when the guarded behaviour breaks.

## Affected paths
`mobile/lib/features/activity/data/activity_quarantine.dart`, the five test files above.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/data/activity_ids_test.dart test/features/activity/data/activity_merger_replay_test.dart test/features/activity/data/activity_quarantine_test.dart test/features/activity/data/source_cursor_test.dart test/features/activity/data/device_source_surface_test.dart`
Result: `All tests passed!` (53 tests).
