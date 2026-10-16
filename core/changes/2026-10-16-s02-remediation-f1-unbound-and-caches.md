# S02 remediation F1 (2/4): account-change cache reset and unbound visibility

## What changed

In `activity_sync_repository.dart` and `activity_sync_resolution.dart`:

- `onAccountChanged()` also clears `_conflictCache` and `_conflictTried`, so account B neither sees A's cloud values nor skips its own start-up conflict retry. `_conflictView` caches a backend read only if the account epoch did not change during the read.
- `refreshState()` throws `JournalUnbound` while a scoped journal is not bound. `watch()` forwards stream errors (`onError: c.addError`), and `_publish()` reports `JournalUnbound` to the listeners, so `SyncConflictPresenter` (unchanged) sets `loadFailed` with its retry action instead of showing "loaded / in sync".
- `resolveConflict`/`resolveCandidate`/`applyExplicitEdit` return `SyncOutcome.unavailable` on an unbound journal (the presenter shows `lastFailed`); `syncEntry`/`syncBatch` return `SyncOutcome.pending` with no backend call; `syncAll` makes no backend call and returns an empty map; `saveSession` throws `JournalUnbound` (as the journal put did before).

## Why

Reviewers found (silent-failure, Flutter, reliability) that an unbound or failed-bind journal reads as empty, so the sheet showed "in sync", zero pending deletions, and `resolveConflict` returned `notFound`, which the presenter reported as not failed.

## Affected contracts

`refreshState()` can now fail with `JournalUnbound`; `watch()` can emit that error. Plain (non-scoped) journals behave as before.

## Verification state

Nothing compiled or run by the author. Tests are specified in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` (heading F1).
