# S02 test epic 6b: late sweep never erases a live account, F71 table, F72/F81/F54 gaps

## What
Production fix in `functions/src/activity_streams/late_sweep.ts`: the destructive part of the late job (object sweep, final recursive delete, lateSweepDone, fence removal) is skipped while the Auth user still exists (counter `skippedLive`, slug `skipped-live-account`, job stays armed); a failing Auth lookup fails closed. One sentence added to design 6.1. The documenting test became regression tests. New `ops_signals.test.ts` (F71 rows 1-10). `sweeps_jobs.test.ts` gained F72 withdrawn consent, F54 third interleaving and F81 deleteExisting withdrawal tests. Runbook alert row corrected to the real validator codes (`forbidden_kind`, `sha_mismatch`). The audited line number of the late_sweep call site in `check_data_access_policy.js` moved 179 to 184. Findings document updated.

## Why
An aborted account deletion left the fence and the late job erased a live user's GPS objects and activity documents (lead decision: production defect in scope). Design 9.1 says the reconciler aborts pending rows after consent withdrawal, so plan F72 (not aborted) is a plan error; the code was already right.

## Affected paths
- `functions/src/activity_streams/late_sweep.ts`
- `docs/phase2/s02/S02_DESIGN.md`
- `functions/src/__tests__/activity/ops_signals.test.ts`
- `functions/src/__tests__/activity/sweeps_jobs.test.ts`
- `runbooks/activity_stream_bucket.md`
- `scripts/ci/check_data_access_policy.js`
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC6B.md`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/retention_purge.test.ts src/__tests__/activity/sweeps_jobs.test.ts src/__tests__/activity/account_flow.test.ts src/__tests__/activity/export_downloads_telemetry.test.ts src/__tests__/activity/lifecycle_policy.test.ts src/__tests__/activity/story_map_lint.test.ts src/__tests__/activity/ops_signals.test.ts src/__tests__/activity/delete_fence.test.ts src/__tests__/activity/settings_consent.test.ts src/__tests__/activity/upload_fence.test.ts src/__tests__/activity/callable_hardening.test.ts src/__tests__/activity/commit_overlap.test.ts`. Result: Test Suites: 12 passed, 12 total; Tests: 423 passed, 423 total.
