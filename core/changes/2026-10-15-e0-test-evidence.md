# E0 test evidence (complete set, final run)

Authored and run by e2e-runner. Branch `feature/body-scan-nutrition-coach`. Run heads: jest, storage, Dart on `f64c62b`; the Firestore rules group was re-run on `64dd697` plus the uncommitted `data_access_policy.test.ts` (committed with this record) after the C25 policy rows appeared. Other agents committed concurrently; no E0 source file changed between those heads except the files named in the change records.

## Commands and results

| File (test id) | Command group | Passed | Failed | Skipped/todo |
|---|---|---|---|---|
| functions/src/__tests__/feature_flags.test.ts (T02) | jest | 102 | 0 | 0 |
| functions/src/__tests__/release_guard.test.ts (T06) | jest | 80 | 0 | 0 |
| functions/src/__tests__/scaling.test.ts (T07) | jest | 122 | 0 | 0 |
| functions/src/__tests__/abuse_guard.test.ts (T08) | jest | 37 | 0 | 0 |
| functions/src/__tests__/ai_gateway.test.ts (T09) | jest | 31 | 0 | 0 |
| functions/src/monitoring/__tests__/ai_gateway_definitions.test.ts (T10) | jest | 23 | 0 | 0 |
| functions/src/__tests__/firestore_indexes_body_scan.test.ts (T11) | jest | 14 | 0 | 0 |
| functions/src/__rules__/firestore_rules.test.ts (T03) | emulator (firestore) | 339 | 0 | 0 |
| functions/src/__rules__/data_access_policy.test.ts (T05) | emulator (firestore) | 208 | 0 | 0 |
| functions/src/__rules__/storage_rules.test.ts (T04) | emulator (firestore,storage) | 82 | 0 | 0 |
| mobile/test/core/config/body_scan_flags_test.dart (T01) | flutter test | 14 | 0 | 0 |
| mobile/test/features/subscription/feature_gates_test.dart (T136) | flutter test | 8 | 0 | 0 |
| mobile/test/core/privacy/data_notice_test.dart (T137) | flutter test | 27 | 0 | 0 |

Jest group total 409 passed (7 suites). Rules group 547 passed (2 suites). Storage 82 passed. Dart 49 passed (3 files) plus T01 re-run with `--dart-define=BODY_SCAN_CLOUD=true`, `--dart-define=FOOD_AI=true` and `--dart-define=FOOD_LOOKUP=true` (14 passed each), which proves each flag reads its own define.

Commands (PowerShell form, from the worktree):

```
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/feature_flags.test.ts src/__tests__/release_guard.test.ts src/__tests__/scaling.test.ts src/__tests__/abuse_guard.test.ts src/__tests__/ai_gateway.test.ts src/monitoring/__tests__/ai_gateway_definitions.test.ts src/__tests__/firestore_indexes_body_scan.test.ts
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules src/__rules__/firestore_rules.test.ts src/__rules__/data_access_policy.test.ts
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/storage_rules.test.ts
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/core/config/body_scan_flags_test.dart test/features/subscription/feature_gates_test.dart test/core/privacy/data_notice_test.dart
```

Environment note: port 8080 on this machine is held by another process, so the two emulator commands were run with `FIREBASE_EMULATOR_CONFIG=<alternate firebase.json: firestore 8181, storage 9299>`, `FIRESTORE_EMULATOR_PORT=8181` and `STORAGE_EMULATOR_PORT=9299` (the existing, documented override mechanism). The rules and storage files are the repository's own, unchanged. JDK 21 and the storage emulator jar resolved without problems; nothing is NOT_RUN.

## Defects found (all fixed in the E0 file, each with a regression test)

1. `firestore.rules` (C01): `food_entries` was unwritable, every entry exceeded the 1000-expression budget. Fixed (inlined per-element check, ordered one-chain `rangeOk`), measured: 30 items with every optional field accepted.
2. `firestore.rules` (C01): `cloudConsent` withdrawal (key removed) was refused by an evaluation error. Fixed (absent key accepted first in `consentOk`).
3. `functions/src/nutrition_http.ts` (C02): a bare `..` or `.` path segment collapsed into path navigation. Fixed with the closed slug `upstream-invalid-request`.

## Deferred or not covered

- None deferred after C20 and C25 landed (T05 rows and the six-callable guard are real tests now).
- Not covered by E0 by design: real emulator checks of the deployed rules in production, real Vertex/OFF/USDA calls, device behaviour of the data-notice sheet (TalkBack, real keyboard).
- Residual: the rules tests prove the shapes in the map; `food_entries` per-item numeric fields are intentionally not rule-checked (only `name`), which the Dart layer and server recompute cover.
- `mobile/pubspec.lock` shows an uncommitted change (`mobile_scanner`) produced by `flutter pub get` after another agent added the dependency; it is not part of this work and was not committed.
