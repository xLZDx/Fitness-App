# S02 remediation A: reconciler deadline and bulk-delete fairness

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/activity_streams/reconcile.ts`: extra passes receive the run deadline (A2); the pending-row abort re-reads the row and keeps everything if the upload id or intended hash changed (A4); counters and log slugs for silent skips (failed previous-object delete, bad stored object path, bad `timeCreated`) and for the object scan cycle age (A15); `oldestBulkDeleteAgeMs` in the run log.
- `functions/src/activity_streams/delete_all_streams.ts`: the continuation pass reads a bounded batch, orders it in memory by the last attempt time, stamps every attempt (`streamDeleteAttemptAt`, `streamDeleteAttempts`), records `streamDeleteStartedAt` at job start, honours the run deadline per user (A2, A3); rows with non-activity ids are deleted directly and counted (A14).
- `scripts/ci/check_data_access_policy.js`: allowlist line moved.
- Test notes extended.

## Why
Review findings A2, A3, A4, A14, A15: the continuation could overrun the run and lose `run-complete`, a failing job blocked the head of the line, and several reconciler skips were silent.

## Affected contracts and paths
Settings document gains server-only job fields `streamDeleteStartedAt`, `streamDeleteAttemptAt`, `streamDeleteAttempts`. No index change (ordering is in memory over at most 200 pending jobs).

## Verification state
No tests, build, lint or typecheck were run; see `docs/phase2/s02/S02_REMEDIATION_A_TEST_NOTES.md`.
