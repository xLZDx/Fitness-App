# S02-06a change record: mobile permission-denied decision

Date: 2026-10-16. Story: S02-06a (design 6.2; test ids I26, I37).

## What changed

- `mobile/lib/features/activity/repository/summary_write_denial.dart` (new): pure function `decideOnSummaryWriteDenied({required bool? tombstoneExists})` returning `SummaryDenialAction.deleteLocal` only when the tombstone document was read and exists, otherwise `SummaryDenialAction.markSyncConflict` (keep all local data, mark `sync_conflict`, never `synced`).

## Why

Permission-denied on a summary write is routine (rev, immutability, clamp, batch and fence rules) and must never be read as deletion; only the server tombstone proves a delete (delete wins).

## Deviations and notes

- No upload/sync code exists under `mobile/lib/features/activity` yet (the Firestore repository and sync layer arrive with a later story), so the decision is exposed as a pure function. The caller must read `activity_tombstones/{id}` (and the server summary for the merge) before calling it, apply `ActivityJournal.delete(id)` on `deleteLocal`, and `updateSyncState(id, JournalSyncState.syncConflict)` otherwise.
- A failed tombstone read (`null`) deliberately keeps the data.
- Case (5) of I26 (a local entry whose id is in the tombstone list, no write attempted) is the caller's loop over the tombstone ids using `ActivityJournal.delete`; not implemented here for lack of a sync layer.

## Verification state

No tests, builds or analysis were run (operator rule v4). Test agents verify I26 and I37 against the future repository; the pure function is directly testable.
