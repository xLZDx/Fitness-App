# S02 remediation E2 (a): tombstone push continuation, observability and retry

## What
- `mobile/lib/features/activity/repository/activity_sync_repository.dart`: `_pushLocalTombstones` now runs rounds of `kMaxSummaryBatch` (8) inside one `syncAll` call while the previous round pushed at least one and nothing failed, up to `kMaxTombstoneRounds` = 128 rounds (1024 deletions). A failure in a continuation round and any systemic refusal (`resource-exhausted`, `unavailable`, `permission-denied`, `unauthenticated`, `deadline-exceeded`) ends the pass at once. Ids that failed earlier in the process are tried last. Confirmed ids (server list or successful push) are kept in memory.
- Automatic retry: `_maybeScheduleRetry` schedules ONE timer after a pass that ended on a failure, an unknown server tombstone list or the round cap while tombstones are still owed. Backoff `kTombstoneRetryDelays` 60 s, 2, 4, 8, 15 min (cap); `resource-exhausted` uses the longest; at most `kMaxTombstoneRetries` = 6 per app start; timer created through the injectable `retryTimerFactory`; cancelled by `dispose()` and `cancelTombstoneRetry()`.
- `mobile/lib/features/activity/repository/sync_models.dart`: `ActivitySyncState` gains `pendingTombstones` and `lastTombstonePushError`, part of equality (so `watch()` emits on change); `isEmpty` is unchanged.

## Why
Final code gate MAJOR-03: only 8 tombstones were pushed per pass and nothing continued, so a bulk offline deletion stayed in the cloud until another sync happened.

## Affected contracts and paths
`ActivitySyncRepository` constructor gains an optional `retryTimerFactory`; `ActivitySyncState` constructor gains two optional fields. `activity_wiring.dart` is untouched.

## Verification state
No tests, analyze or build were run (test agents follow). Expectations: `docs/phase2/s02/S02_REMEDIATION_E_TEST_NOTES.md` heading E2.
