# S02 test epic 5: golden seam, policy cells, debug_sessions, Storage rules, client constants (R22, R23, R24, R25, S01-S03, I30, I34)

## What
- `functions/src/__rules__/s02_activity_golden_rules.test.ts`: R25 (all 100 Dart-produced golden summaries accepted after the ISO-string to timestamp conversion; the raw unconverted fixture is refused; 11 mutated key classes on three samples, each followed by the unmutated control) and R22 (client create of `debug_sessions` denied; kept apart from the permanent floor).
- `functions/src/__rules__/data_access_policy.test.ts`: R23 and R24 as the two hand-written CONDITIONAL cells named by `scripts/ci/data_lifecycle_policy.json` (`activities/create`, `activities/update`); the stale CONDITIONAL cell test for `debug_sessions/create` was removed (the policy cell is NONE since S02-09).
- `functions/src/__rules__/firestore_rules.test.ts`: two stale expectations updated to the S02-09 rule (`debug_sessions` create by a signed-in user and by Alice in the canary test is now refused).
- `functions/src/__rules__/storage_rules.test.ts`: S01 (owner, other user, canary, anonymous cannot read, write, list or delete `streams/` and `quarantine/` objects in the default bucket), S02 (owner cannot create under `quarantine/`), S03 (loosening guard with mutated copies).
- `mobile/test/features/activity/repository/activity_rules_constants_test.dart`: I30 (an explicit edit naming `startUtc` or `sport` is rejected, a legal edit keeps both and the id) and I34 (constant 8, 9 refused whole with zero writes and no conflict, 500-entry flush never exceeds 8 per backend call).
- No production change in this commit.

## Why
Test plan epic 5. The two stale tests failed against the committed S02-09 rule and are test defects. `clearStorage` does not remove objects between tests of the Storage emulator, so S02 uses a path no other test seeds.

## Affected paths
The files above.

## Verification state
Firestore and Storage emulators on alternative ports (port 8080 is held by another process on this machine). `npx jest --config jest.rules.config.js` on storage, golden, data_access_policy and firestore_rules test files: all passed (684 tests, before the last two fixes; storage 93 and golden and firestore_rules re-run green afterwards). Dart: `flutter test test/features/activity/repository/activity_rules_constants_test.dart` -> `+5: All tests passed!`.
