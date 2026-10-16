# S02 test epic 6b: sweeps, late sweep, reconciler, bulk delete and the real deleteAccount flow (S02-06b)

## What
New `sweeps_jobs.test.ts` (F24, F25, F27, F28, F54, F55, F57, F58, F72, F81, F95 timing table, F80 timing, and a test that documents the OPEN RISK that the late sweep erases a live user's activity data after an aborted deletion) and `account_flow.test.ts` (the real `deleteAccount`, `reconcileAccountDeletions` and scheduled late sweep from index.ts: F26, F56, F77, F78 parts A-C, F80, F95 order, E03, E05 functions part).

## Why
Account deletion order, fence lifetime, independent cleanups and the reconciler repair rules had no tests. Plan F95 cell (a) (authDeletedAt = T - 5 min removed at T + 1 h) contradicts the design formula max(done + 1 h, authDeletedAt + 70 min) = T + 65 min; the design is followed. Plan F27 says a stored row without a summary is kept; code and design 6 remove it with its objects; the code behaviour is asserted. A storage failure in Step 2 aborts deleteAccount with a retryable error (the plan text implies it is aggregated); the aggregation is observable at Step 4 and the reconciler.

## Affected paths
- `functions/src/__tests__/activity/sweeps_jobs.test.ts`
- `functions/src/__tests__/activity/account_flow.test.ts`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/account_flow.test.ts src/__tests__/activity/sweeps_jobs.test.ts`: 2 suites, 60 tests passed. No production code changed in this commit. Not covered: offline-replay half of E05 (rules emulator, epic 5).
