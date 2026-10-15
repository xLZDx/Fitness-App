# C12 server tests: final complete run

Date: 2026-10-15. Head at run time: 269e72d (C12 = 5d2c356; tests committed in this series). No production code changed in this commit.

Command (in `functions/`, project jest config, explicit paths only):
`npx jest src/__tests__/body_scan/create.test.ts src/__tests__/body_scan/estimate.test.ts src/__tests__/body_scan/validate_estimate.test.ts src/__tests__/body_scan/delete.test.ts src/__tests__/body_scan/manage.test.ts src/__tests__/body_scan/purge.test.ts src/__tests__/body_scan/guard.test.ts src/__tests__/body_scan/registry.test.ts src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts`

Result: 10 suites passed, 477 tests passed, 0 failed.

| File | Passed | Failed |
|---|---|---|
| body_scan/create.test.ts | 102 | 0 |
| body_scan/estimate.test.ts | 59 | 0 |
| body_scan/validate_estimate.test.ts | 45 | 0 |
| body_scan/delete.test.ts | 23 | 0 |
| body_scan/manage.test.ts | 41 | 0 |
| body_scan/purge.test.ts | 31 | 0 |
| body_scan/guard.test.ts | 40 | 0 |
| body_scan/registry.test.ts | 27 | 0 |
| delete_account.test.ts (extended) | 67 | 0 |
| account_deletion_reconcile.test.ts (extended) | 42 | 0 |

C12 production defects found and fixed during the series (both type errors surfaced by ts-jest; behaviour unchanged): `create.ts` Uploads cast (TS2352) and `manage.ts` pagedAction argument type (TS2345), commit "C12 tests: shared fakes and createBodyScan suite; fix two C12 type errors".

Not run / out of scope: release_guard bucket-check tests (the C12 leftovers commit 166ae42 landed, but `release_guard.test.ts` is owned by the E0 test agent), emulator suites, the Flutter side.
