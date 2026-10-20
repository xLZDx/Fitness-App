# S02-05b change record: purgeExpiredActivityStreams and the recompute continuation

Date: 2026-10-16. Story: S02-05b (design 5.3, 6.3; test ids F14-F19, F63-F67, F71 rows 4-5, F88, F89).

## What changed

- `functions/src/activity_streams/recompute.ts` (new): `runRecomputeContinuation` queries collection group `activity_settings` where `recomputePending == true` (at most `recomputeUsersPerRun` = 20 users), then `recomputeUser` walks the user's `activity_streams` by id in pages of 100 from `recomputeCursor` (valid only for the current `recomputeGeneration`), rewriting each row in its own transaction (`recomputeRow`; an unchanged row is not written). The cursor is advanced per page by a compare-and-set on the generation (`advanceRecomputeCursor`). When the cursor is exhausted a final pass queries the user's own rows with `settingsGeneration < current`; `recomputePending` is cleared (`clearRecomputePending`, compare-and-set on the generation) only when that pass finds nothing. A user may use `recomputePagesPerUser` pages per run, so a heavy user cannot starve the others.
- `functions/src/activity_streams/purge.ts` (new): `runActivityStreamPurge` (injectable firestore, bucket, clock and limits) and the `purgeExpiredActivityStreams` schedule (daily 03:45, europe-west1, 300 s, maxInstances 1). Order of a run: recompute continuation (half of the budget), then the candidate walk (collection group `activity_streams`, `state == stored`, `expiresAt <= now`, paged with `startAfter`), then the signals.
  - `purgeRow`: ONE transaction re-reads row, settings and summary, decides with `decidePurge`; not stored -> skipped; not due -> only rewrites a stale hint/generation; due -> deletes the object first (404 = success; an untrusted `objectPath` falls back to the activity prefix), then `state = expired`, `expiredAt`, counters cleared. Summary documents are never touched.
  - Failure: row stays `stored`, `purgeAttempts + 1`, bare `lastErrorCode`, `lastPurgeAttemptAt`, written in the same transaction. No give-up: the row is retried every run; at or past `maxPurgeAttempts` it is only counted in `cappedRows`.
  - Signal (design 6.3): one `activity_purge_event` log entry per run with purged, failures, cappedRows, oldestOverdueAgeMs (max of the oldest still-due hint and the ages of rows that failed this run), recompute backlog users and age, `missingIndex` (FAILED_PRECONDITION on any of the queries), budgetExhausted. Counts, ages and bare codes only, no uid, id or path.
  - Unset `ACTIVITY_STREAM_BUCKET`: logged no-op.
- `functions/src/index.ts`: exports `purgeExpiredActivityStreams`.

## Why

Retention must follow the user's current setting, delete only objects and never summaries, survive crashes at any step and be observable when it falls behind.

## Deviations and notes

- The final pass uses a single-field range on `settingsGeneration` and filters nothing else in the query (non-stored rows are stamped by the recompute), so it needs no composite index; the design asks for exactly two indexes.
- A `setActivityCloudSettings` retention change resets `recomputeCursor` to null (S02-05a); the recompute additionally ignores a cursor whose `recomputeGeneration` is not the current generation, so a second change always restarts the walk (test F67 wording about a reset cursor should be read against this).
- Recompute backlog age is measured from the settings document `updatedAt` (the time of the last settings change), the only timestamp available without a new field.
- The schedule runs on the default service account like the other activity functions (no dedicated tier exists for the stream bucket).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4).
