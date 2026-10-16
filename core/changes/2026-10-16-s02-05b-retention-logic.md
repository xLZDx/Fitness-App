# S02-05b change record: pure retention and purge logic

Date: 2026-10-16. Story: S02-05b (design 5.3, 6.3; test ids F15, F18, F63, F65-F67, F89 depend on this logic).

## What changed

- `functions/src/activity_streams/retention.ts` (new): pure functions and injectable types, no Firestore, Storage or clock access.
  - Expiry: reuses `activityDateMs`, `derivedExpiryMs` and `timestampMs` from `upload_common.ts` (no second copy of the arithmetic). `resolveStartMs` takes the summary `startUtc`, then the server-written row `activityDateUtc`/`receivedAt`, then the 2000-01-01 floor (a row of unknown age is due under a finite retention; "never" is never due).
  - `decidePurge`: `skip` (row no longer `stored`), `keep` (with `rewriteHint` when hint or generation is stale) or `purge`; due means derived expiry `<= now`. The stored hint is only compared for rewriting, never used to decide due.
  - `planRecomputeRow`: `hint` for a stored row whose hint or generation differs, `stamp` for a non-stored row with an older generation, `none` otherwise (a rerun after a crash writes nothing twice).
  - Cursor and batch helpers: `effectiveRecomputeCursor` (valid only for the current `recomputeGeneration`), `nextCursor`, `isLastPage`, `budgetExhausted`, `recomputeDeadlineMs`.
  - Signals: `overdueAgeMs`, `maxAgeMs`, `backlogAgeMs`, `isMissingIndexError`.
  - Path parsers `parseStreamRowPath` and `parseSettingsPath` so a collection-group hit that is not exactly `users/{uid}/activity_streams/{id}` or `users/{uid}/activity_settings/main` is skipped.
  - `RetentionDeps` (firestore, bucket, clock) and `RetentionLimits` (purge page, recompute page, users per run, pages per user, attempt cap, run budget) with `DEFAULT_RETENTION_LIMITS`.
- `functions/src/body_scan/purge.ts`: `PAGE` is now exported (one word), so the activity purge reuses the same page constant as design 5.3 asks.

## Why

Expiry arithmetic, the hint rewrite rule, batch/cursor logic and the metrics must be testable without a database, and must share one definition of "due" with the upload callables.

## Deviations and notes

- The recompute continuation gets half of the shared run budget (`RECOMPUTE_BUDGET_SHARE`) so a large backlog can never starve the purge itself (an unpurged due stream is the privacy defect).
- Non-stored rows with an older generation are stamped by the recompute; otherwise the per-user final pass (`settingsGeneration < current`) would never come back empty for a user with an `expired` row.

## Verification state

No tests, builds, lint or type checks were run (operator rule v4).
