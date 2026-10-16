# S02-06a change record: shared fence helper and deleteAccount fence write

Date: 2026-10-16. Story: S02-06a (design 5.4, 6.1; test ids F76, F79, F20 fence part).

## What changed

- `functions/src/activity_streams/fence.ts` (new): the one fence seam for every activity callable.
  - `FenceDeps` (Firestore, Auth-existence, clock) and `defaultFenceDeps`; moved here from `set_settings.ts`.
  - `checkAccountFence(tx, deps, uid)` reads `activity_account_state/{uid}` and `accountDeletionRetries/{uid}` inside the caller's transaction, then checks Auth existence. Returns `clear`, `account_deleting` or `account_deleted`. A transient Auth lookup error is NOT mapped: it throws so the caller fails closed with a bare code (F79).
  - `activityTombstoned(tx, deps, uid, id)` for the stream callables of S02-04b (design 6.2: a tombstoned id is refused).
  - `writeActivityAccountFence(deps, uid)`: idempotent create-if-absent of `activity_account_state/{uid}` with `fenceAt` and `lateSweepAt` (= now + 15 minutes: 10 minute signed-URL TTL plus 5 minute margin). A retry keeps the earliest values.
- `functions/src/activity_streams/paths.ts`: Firestore path builders `activitySummaryPath`, `activityStreamRowPath`, `activityTombstonePath` (validated ids only).
- `functions/src/activity_streams/set_settings.ts`: now uses `checkAccountFence` and `FenceDeps` (behaviour unchanged; `SettingsDeps` is an alias of `FenceDeps`; the previously exported `activityAccountStatePath` now lives in `fence.ts`).
- `functions/src/index.ts`: additive Step 1c in `deleteAccount` writes the fence before the first `sweepAccountData` and before `accountDeletionRetries/{uid}`; a failure aborts with a retryable `internal` error before anything is deleted.

## Why

Every callable must read the same fence the same way (design 5.4); duplicating the three reads per callable would let them drift.

## Deviations and notes

- Design 6.1 says "Step 1". In the real flow Step 1 is the Stripe cancel, which can abort the call for a live account. The fence is written after the Stripe cancel and token revocation and immediately before the first sweep, so a failed cancel can never leave a live account fenced. The fence is still written before any sweep and before the retries marker.
- The sweep additions, the late job and fence removal are S02-06b and are not implemented here. Until S02-06b exists nothing removes `activity_account_state/{uid}` (a uid is never reused, so this is inert but must be closed by S02-06b).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify with F76, F79 and the order checks of F20.
