# S02 remediation E2 (b): erasure quota, design and test notes

## What
- `functions/src/abuse_guard.ts`: `QUOTAS.activityDelete` raised from 100 to 1000 per user per day with a comment that it is privacy-erasure capacity, not an abuse limit. Per user, refund on fence refusals and all other quotas unchanged.
- `docs/phase2/s02/S02_DESIGN.md`: 5.4 starting limits, 17 item 13 wording and new item 21 (continuation rounds and cap, pending count, backoff, quota 1000, signed-URL lifetime of 15 minutes and object-before-row order).
- `docs/phase2/s02/S02_REMEDIATION_E_TEST_NOTES.md`: heading E2.

## Why
Final code gate MAJOR-03: the 100 per day delete ceiling could stop a large offline backlog from being erased in one day.

## Affected contracts and paths
`deleteActivity` daily quota. Pinned tests still expect 100 and must be updated by the test agents (listed in the test notes).

## Verification state
No tests, build or lint were run.
