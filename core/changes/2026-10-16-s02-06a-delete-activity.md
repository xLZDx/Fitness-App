# S02-06a change record: deleteActivity callable

Date: 2026-10-16. Story: S02-06a (design 5.4, 6, 6.1, 6.2; test ids F20-F23, F59, F76, F79).

## What changed

- `functions/src/activity_streams/delete_activity.ts` (new): callable `deleteActivity` on the `RARE` profile.
  - Pipeline: auth -> `noteAppCheck` -> anonymous refused -> strict `activityId` pattern (`^act_[0-9a-f]{40}$`) -> daily quota `activityDelete` -> cascade.
  - Cascade order (F20): ONE transaction reads the fence documents and Auth existence (shared `checkAccountFence`) and writes the tombstone `users/{uid}/activity_tombstones/{id}` FIRST (`deletedAt`, `expireAt` = now + 400 days); then objects under `streams/<uid>/<id>/` and `quarantine/<uid>/<id>/` (both attempted, 404 = success, other failures aggregate to one bare `delete_failed`); then the stream index row; the summary document LAST.
  - Idempotent (F21): a rerun keeps the first tombstone, missing objects and documents are success, a failure after the tombstone is finished by the rerun (F22). No per-activity late job is scheduled.
  - Seams: `applyDeleteActivity`, `handleDeleteActivity`, `writeTombstone`, `deleteActivityObjects` take injectable Firestore, Auth existence, clock and bucket (`DeleteActivityDeps`).
  - Errors are bare codes: `invalid_request`, `account_deleting`, `account_deleted`, `quota_exceeded`, `delete_failed`. A transient Auth lookup error fails closed as `delete_failed` (F79). Logs carry slugs and counts only.
- `functions/src/abuse_guard.ts`: `QUOTAS.activityDelete = 100` and the name added to `REDACTED_QUOTA_ACTIONS`.
- `functions/src/index.ts`: export of the callable.

## Why

Delete wins (design 6.2): the tombstone is the per-activity fence that makes any later summary write (rules), upload or commit refuse, so it must exist before anything is removed.

## Deviations and notes

- Deletion is not behind the feature flag (erasure must always work); an unset bucket makes the object step a no-op.
- The quota charge is refunded only when the fence refused the call (nothing written).
- The pinned test of `REDACTED_QUOTA_ACTIONS` (`abuse_guard.test.ts`) is updated by test agents.
- The other stream callables must call `activityTombstoned` (in `fence.ts`) and answer a bare `deleted`; that is S02-04b.
- The 400-day TTL policy on `expireAt` is an operator console step (release prerequisite, design 6.2).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify F20-F23, F59, F76, F79.
