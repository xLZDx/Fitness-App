# S02-06b change record: deleteAllActivityStreams (bulk stream delete job)

Date: 2026-10-16. Story: S02-06b (design 5.4, 9.1; test ids F68, F81, F82, F83, F41, F60-F62).

## What changed

- New `functions/src/activity_streams/delete_all_streams.ts`, callable `deleteAllActivityStreams` (the seventh callable), exported from `functions/src/index.ts`:
  - Resumable job on `users/{uid}/activity_settings/main`: `streamDeleteJobId`, `streamDeleteCursor` (last activity id), `streamDeletePending`. At most 50 rows per call inside a 40 s budget; per row the objects of both prefixes first (reused `deleteActivityObjects`, 404 = success) then the row; answers `more` or `done`; `done` clears the job fields. Summaries, tombstones and consent are never touched.
  - Fence-aware: fence documents and Auth existence are read inside the transaction that starts a page and the one that records progress, so an account being deleted gains no settings document. The request body is ignored (no client value reaches a path or query); anonymous users refused; bare codes only.
  - Own quota `activityDeleteAll` (10 per user per day) in `QUOTAS` and `REDACTED_QUOTA_ACTIONS` (`functions/src/abuse_guard.ts`); the pinned test was not edited. Only a call that STARTS a job is charged (continuations are free; a refused start is refunded).
  - `bulkDeleteContinuationPass`: the reconciler (`reconcile.ts`, now default extra pass) advances unfinished jobs found by the collection-group query `streamDeletePending == true` (20 users per run, one page each; fenced accounts skipped).
- `firestore.indexes.json`: single-field collection-group override on `activity_settings.streamDeletePending`.

## Not done here

Consent withdrawal that chose the offer does not yet start the job: that needs a request option in `setActivityCloudSettings` (S02-05a file, outside this story's listed scope). The job fields written here are exactly what such a start must set.

## Verification state

No tests, builds or checks were run (operator rule v4).
