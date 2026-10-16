# S02 remediation F1 (3/4): tombstone retry budget, fallback timer, phase errors

## What changed

`activity_sync_repository.dart`:

- New constant `kTombstoneFallbackDelay = Duration(minutes: 60)`. After `kMaxTombstoneRetries` scheduled attempts `_maybeScheduleRetry` keeps ONE fallback timer (same single `_retryTimer` slot, so never two) while tombstones are still owed; it stops when a pass ends clean, and is cancelled by `dispose`, `cancelTombstoneRetry` and `onAccountChanged`.
- `_retryAttempts` and `_lastTombstonePushError` are reset after a pass that ends with no failure and no round cap (nothing owed).
- The tombstone phase of `syncAll` is wrapped: any exception (journal I/O from `listTombstones()`, a missing uid) records its error code, schedules a retry and the pass still publishes state.
- `_maybeScheduleRetry` catches a failing pending-count read (treated as "owed") and re-checks the pass identity, disposal and the timer slot after the await before touching the budget or the timer.
- `_lastTombstonePushError` is set to `'unavailable'` when `listTombstoneIds` fails.
- New public `Future<void> requestTombstoneSync()`: one normal serialized `syncAll()` (no conflict retry) through the existing `_ops` queue; errors are logged with their runtimeType, never thrown. No production local-delete caller exists in S02 (grep of `mobile/lib`: `_journal.delete` is only called inside the sync layer), so only the method is added; the S03 delete UI must call it (recorded in the design handoff).

## Why

After about 44 minutes offline or on quota exhaustion no timer existed for the rest of the session; exceptions in the tombstone phase escaped before scheduling; the error code was never set on a listing failure.

## Verification state

Nothing compiled or run by the author. Tests: `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` (heading F1). The existing assertion that no timer exists after six attempts must be updated to the fallback behaviour.
