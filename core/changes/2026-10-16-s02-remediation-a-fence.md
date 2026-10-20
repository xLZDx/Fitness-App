# S02 remediation A: abandoned fence of a live account, late sweep usage and unset bucket

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/activity_streams/fence.ts`: `writeActivityAccountFence` adds a heartbeat `touchedAt` on creation and refreshes it on every later call (earliest `fenceAt` and `lateSweepAt` are kept).
- `functions/src/activity_streams/late_sweep.ts`: for a job whose Auth user still exists, no `accountDeletionRetries/{uid}` record exists and `touchedAt` (or `fenceAt` for older documents) is older than 24 h, the fence document is deleted by compare-and-delete on the same `touchedAt` (slug `fence_cleared_live_account`, counter `clearedLive`); data is never erased while Auth exists. With the intent record present the old job is counted as `stuck`. The final recursive delete also clears `users/{uid}/usage` (A5). An unset bucket with remaining `activity_streams` rows fails the job with bare code `bucket_unset` and keeps rows and fence (A10, late-sweep part).
- `scripts/ci/check_data_access_policy.js`: allowlist line number and reason for the moved dynamic collection path.
- Docs: design 6.1 sentence, runbook section 7 and alert table, `docs/phase2/s02/S02_REMEDIATION_A_TEST_NOTES.md`.

## Why
Review findings A1 (MAJOR: an aborted deletion left a live account fenced for ever), A5 and A10. The retry refreshing `touchedAt` closes the resurrection window.

## Affected contracts and paths
`activity_account_state/{uid}` gains `touchedAt`; late-sweep result and log gain `clearedLive`.

## Verification state
No tests, build, lint or typecheck were run (test agents follow). Tests to change or add: see the test notes file.
