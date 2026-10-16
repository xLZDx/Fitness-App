# S02 final complete run

## Dart side

Head: `45c747b0` on branch `phase2/s02-unified-activity`. `git status --short` was empty (clean worktree) before the run.
Working directory: `D:\Repo\Fitness_App_Phase2_s01\mobile`. No tests or production code were changed.

| # | Command | Summary line | Skipped |
|---|---------|--------------|---------|
| 1 | `flutter test test/features/activity` | `+1117: All tests passed!` | 0 |
| 2 | `flutter test test/features/account_deletion test/features/safety/health_rules_parity_test.dart test/adversarial/n07_team_activation_test.dart` | `+97: All tests passed!` | 0 |
| 3 | `flutter test test/android/backup_rules_test.dart test/core/architecture/pure_data_layer_guard_test.dart test/core/architecture/import_graph_guard_test.dart` | `+23: All tests passed!` | 0 |
| 4 | `flutter test test/features/activity/e2e/s02_account_wipe_e2e_test.dart` (already inside run 1, rerun alone to confirm skips) | `+11: All tests passed!` | 0 |

Notes:

- Run 3 is the explicit list of files outside the already-run directories that import `features/activity/` (found with Grep under `mobile/test`). No file outside `test/features/activity` imports `activity_wiring` or the activity-world `test/support` helpers.
- The two previously documented skips in the account wipe e2e file are gone: no `~N` skipped marker appears in any summary line.
- Failures: none. Not run by instruction: flutter analyze, build, full-repo mobile suite.

## Server side

Head at the start of the server runs: `4af1cb43` (`git status --short` showed only the untracked Dart file `mobile/test/features/activity/repository/activity_wiring_account_switch_test.dart`). The worktree head moved to `38781330` (Dart-side commits) before the last re-runs; only test files under `functions/src/__tests__` were edited by this run. Branch `phase2/s02-unified-activity`. Working directory `functions` unless noted.

| # | Command | Summary lines |
|---|---------|---------------|
| 1 | `npx jest src/__tests__/activity` | `Test Suites: 26 passed, 26 total` / `Tests:       744 passed, 744 total` |
| 2 | `npx jest src/__tests__/s02_remediation_a_policy.test.ts src/__tests__/scaling.test.ts` | `Test Suites: 2 passed, 2 total` / `Tests:       191 passed, 191 total` |
| 3 | `FIREBASE_EMULATOR_CONFIG=<alt config, ports 18080/19299, outside the repository> FIRESTORE_EMULATOR_PORT=18080 STORAGE_EMULATOR_PORT=19299 node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/s02_` | `Test Suites: 6 passed, 6 total` / `Tests:       289 passed, 289 total` (all six `s02_*` rules files) |
| 4 | `npx jest src/__tests__/abuse_guard.test.ts src/__tests__/account_export.test.ts src/__tests__/account_export_paging.test.ts src/__tests__/guard_scripts.test.ts` (final run of the same batch together with the three files in row 5) | `PASS` for all four files; batch summary `Tests: 6 failed, 269 passed, 275 total` was before the row 5 fixes (the 6 failures were the stale fakes below) |
| 5 | `npx jest src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts src/__tests__/firestore_indexes_body_scan.test.ts` (after the fixes) | `Test Suites: 3 passed, 3 total` / `Tests:       124 passed, 124 total` |
| 6 | `node scripts/ci/test_check_data_access_policy.js` (repo root) | `All mutation-proof cases passed (RED on injection, GREEN on the real fix).` exit 0 |
| 7 | `node scripts/ci/test_check_ru_en_drift.js` | `All self-tests passed.` exit 0 |
| 8 | `node scripts/ci/check_ttl_overrides.js firestore.indexes.json` | `OK -- every required TTL policy is declared as a fieldOverride with ttl: true.` exit 0 |
| 9 | `node scripts/ci/check_data_lifecycle_coverage.js` | `OK -- every in-use collection has a lifecycle policy entry.` exit 0 (note: `activity_reconcile_state` has no current code/rules reference, review only) |

The story-map lint is a jest suite (`story_map_lint.test.ts`) and lifecycle policy is `lifecycle_policy.test.ts`; both are inside row 1.

### Stale expectations fixed (test-only, no product change)

Before the fixes, rows 4/5 files gave 74 failures in `delete_account.test.ts` and `account_deletion_reconcile.test.ts` and 2 in `firestore_indexes_body_scan.test.ts`.

- `functions/src/__tests__/delete_account.test.ts` and `account_deletion_reconcile.test.ts`: the Firestore fakes had no `tx.set`. S02-06a added Step 1c of `deleteAccount` (`writeActivityAccountFence`, a transaction that calls `tx.set` on `activity_account_state/{uid}`), so the fake threw and `deleteAccount` returned its documented "Your account has not been deleted" internal error. Added a no-op `tx.set` to both fakes (and in `delete_account.test.ts` the fake counts a transaction as a commit only when it has pending update/delete ops, so booking-sweep commit assertions still count only booking commits). The production behaviour (fence write aborts the deletion on failure) is correct and is covered by `activity/delete_fence.test.ts`.
- `functions/src/__tests__/firestore_indexes_body_scan.test.ts`: the exact-set pins did not know the S02 index `activity_streams:state+expiresAt` and the four S02 TTL overrides; and `firebase.json` storage now also has a `predeploy` block (S00 deploy guard). Pins updated to the real file contents (`fb.storage.rules` is asserted instead of whole-object equality).

### Observations and not run

- `node scripts/ci/check_data_access_policy.js` (not in the S02 findings list) exits 1 with 5 unresolved non-literal `.collection()` calls in `functions/src/body_scan/manage.ts` (218, 317, 355) and `functions/src/nutrition_cache.ts` (74, 109). None is an S02 file; not investigated further and not changed.
- Not run by instruction: lint, typecheck, build, full-repo suites. Mutation runs were not performed (operator decision). The emulator alternate config lived in the session scratchpad, not in the repository.
