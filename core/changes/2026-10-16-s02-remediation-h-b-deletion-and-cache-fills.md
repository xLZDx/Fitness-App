# S02 remediation H-B, items H5 and H7: deletion in progress stops sync, conflict cache fills guarded

Date: 2026-10-16. Area: mobile production code (activity sync repository). Nothing was compiled or run by the author
(operator rule: a test agent runs everything afterwards).

## Why

Class sweeps after GPT-PM round 12 (per-account state and stale async completions) found that a sync pass or tombstone
retry running while the server-side account deletion completes could still write summaries or push tombstones (the
Firestore rules would accept the token and re-create data of a deleted account), and that the conflict cache and the
state read could be filled or assembled across an account switch.

## What changed

- `activity_sync_repository.dart`:
  - New optional constructor parameter `String? Function()? accountBeingDeleted` (the uid whose deletion is running).
  - `_deleting(pass)`; `_beginPass` returns the dead identity (epoch -1) for such a pass; `_alive` (and therefore
    `_mayCall`) refuse it; `_skipReason` reports `account-deleting` (no uid in the log).
  - `_uidMismatch(pass, expectedUid)` helper (used by item H6, committed here because it lives in this file).
  - `_markConflict` captures the pass and fills the cache only if `_alive` after the `updateSyncState` await.
  - `_conflictView(entry, session, stamp)`: backend read guarded by `_mayCall(stamp)`; cache fill only if the stamp is
    still current. `refreshState` takes a stamp (epoch, bound uid, auth uid), discards and repeats (3 attempts, then
    `JournalUnbound`) a result assembled while the identity changed. New `_viewStamp`, `_viewCurrent`.
- `activity_sync_resolution.dart`: `resolveConflict` and `resolveCandidate` gain the optional named `expectedUid`
  (committed here because the file is `part of` the repository library and shares the helper; the presenter side is
  item H6).

## Affected contracts

`ActivitySyncRepository({..., accountBeingDeleted})`, `resolveConflict(id, choice, {expectedUid})`,
`resolveCandidate(id, field, choice, {expectedUid})` (both return `SyncOutcome.pending`, no side effect, on a uid
mismatch). The wiring (H-A) passes `accountBeingDeleted`.

## Verification state

Not compiled, not run. Test notes: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`, heading H-B.
