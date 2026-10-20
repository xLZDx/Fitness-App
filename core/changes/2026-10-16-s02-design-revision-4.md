# S02 design revision 4 (GPT-PM round 1: 1 BLOCKER, 5 MAJOR)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Reviewed head: `59d709ff`.

## What changed
`docs/phase2/s02/S02_DESIGN.md` revised in place (section 16 holds the dispositions):
- BLOCKER-01: summary rules also require that `activity_account_state/{uid}` does not exist, so offline client writes are refused during and after account deletion; summary batches capped at 8 (two `exists()` per write); the fence is removed at `max(lateSweepDone + 1 h, authDeletedAt + 70 min)`; the late job ends with a final recursive delete of the activity collections; numbered creation and removal order in 6.1.
- MAJOR-01: cloud summary is derived; three-way merge from `baseRev` and `baseSummary`; a field changed differently on both sides stays `sync_conflict` with a user choice and is never marked synced.
- MAJOR-02: local journal uses generation directories and a `CURRENT` manifest switched by atomic rename after verification; recovery falls back to the highest verified generation.
- MAJOR-03/04/05: 100 valid sessions (each of 12 sports at least 6 times) separated from a hostile and future-schema set; positive cleanup invariant (every cleanup attempted independently, errors aggregated); section 11 is the single authoritative order with real test ids; new stories S02-11 (story-map completeness lint) and S02-12 (sync-conflict UI).

## Why
GPT-PM returned MODIFY on `59d709ff`. The test plan is aligned in the next commit (F78, corpus quotas, new tests).

## Affected contracts and paths
Documentation only: `docs/phase2/s02/S02_DESIGN.md`.

## Verification state
No tests or checks were run. OPEN: the plan has no test ids yet for S02-11 and S02-12; the 20 versus 10 access-call limit stays an open confirmation item; the fallback for a crash before `authDeletedAt` is written is an author addition to be reviewed.
