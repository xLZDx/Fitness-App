# S02 remediation A: commit, download and delete hardening

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `commit_stream.ts`: transaction 2 refuses an already-due derived expiry (clears the pending marker, caller deletes the promoted object) (A7); commit callable uses the new `ACTIVITY_COMMIT` profile (A8).
- `reconcile.ts`: repair treats an expired result as aborted; scheduled reconciler memory 1GiB (A7, A8).
- `download_urls.ts`: a stored row whose derived expiry is due is reported `expired` (A7).
- `upload_validate.ts`: separator-count bound before JSON.parse, rejection `too_many` (A8).
- `scaling.ts`: `ACTIVITY_COMMIT` profile (A8).
- `delete_activity.ts`: an unset bucket with an existing stream row fails `delete_failed`, keeps the row, logs at error level (A10; also applies to the bulk delete that reuses it).

## Why
Review findings A7, A8, A10: expiry race at commit, 32 MiB parse amplification on a 256 MiB callable, silent no-op deletion when the bucket variable is lost.

## Affected contracts and paths
Commit callable resources; `Selected` result gains `expired`; `classifyRow` gains an optional argument.

## Verification state
No tests, build, lint or typecheck were run; see `docs/phase2/s02/S02_REMEDIATION_A_TEST_NOTES.md`.
