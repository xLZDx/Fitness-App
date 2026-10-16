# S02 test epic 8a: abandoned fence, usage cleanup and unset bucket (A1, A5, A10)

## What
- New `functions/src/__tests__/activity/remediation_a_fence.test.ts` (15 tests): the fence heartbeat, the late sweep clearing a stale fence of a live account by compare-and-delete, the retries-record and retry-race guards, fail-closed Auth lookup, the five-entry collection list with the usage counters, and the late sweep with an unset bucket.
- Updated tests that pinned the old behaviour: `sweeps_jobs.test.ts` (skipped-live cases now respect the 24 h window and the retries record), `delete_fence.test.ts` (fence write refreshes `touchedAt`; unset-bucket delete with and without a stream row).

## Why
Remediation batch A changed the late sweep and the fence write; the old tests either failed or no longer guarded the new contract.

## Affected paths
- `functions/src/__tests__/activity/remediation_a_fence.test.ts`
- `functions/src/__tests__/activity/sweeps_jobs.test.ts`
- `functions/src/__tests__/activity/delete_fence.test.ts`

## Verification state
Run with jest, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC8.md`.
