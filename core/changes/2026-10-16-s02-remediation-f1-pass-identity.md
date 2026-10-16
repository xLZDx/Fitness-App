# S02 remediation F1 (1/4): sync pass identity and pinning

## What changed

`ActivitySyncRepository` (and the `part` file `activity_sync_resolution.dart`) now run every serialized operation under a pass identity `_Pass(epoch, journalUid, authUid)` taken when the operation starts:

- `syncAll`, `syncEntry` (through `_syncLocked`), `syncBatch`, `saveSession`, `resolveConflict`, `resolveCandidate`, `applyExplicitEdit` use the new `_serial(...)` wrapper instead of `_ops.run(...)`.
- `_alive(pass)`: same epoch and, for an `AccountScopedJournal`, still bound to the uid the pass started under. Checked before EVERY journal write or delete and after every await whose result came from the journal (the `list()`/`read()`/`listTombstones()` result may belong to the next account).
- `_mayCall(pass)`: `_alive` plus the optional constructor parameter `String? Function()? authUid` (null = no check) must still equal the uid the pass started under. Evaluated synchronously immediately before every backend call and every tombstone-pusher call (no await between check and call).
- A stale pass stops with `SyncOutcome.pending` (or an empty/partial map from `syncAll`); no write, delete, `markSynced` or backend call follows.
- `_TombstoneRun` gained `aborted`; `_pushLocalTombstones` and `_maybeScheduleRetry` take the pass instead of a bare epoch.

The consumed contract `AccountScopedJournal.boundUid` / `isBound` is implemented by remediation F2 in `uid_scoped_activity_journal.dart`; a plain (non-scoped) journal skips the journal-uid check.

## Why

Four independent reviewers found the same MAJOR defect in remediation E: a `syncAll` pass of account A still in flight at an account switch acted on account B. Activity ids are deterministic, so A's server tombstones could delete B's local copies and create B tombstones, and `_syncLocked` could write a summary under B's Firebase uid.

## Affected contracts / paths

- `mobile/lib/features/activity/repository/activity_sync_repository.dart`, `activity_sync_resolution.dart`.
- New constructor parameter `authUid` (wired by F2 in `activity_wiring.dart`).
- No change to the Firestore backend or the tombstone pusher: the guard is the synchronous `authUid` check before each call.

## Verification state

Nothing was compiled or run by the author (operator rule). The test agent compiles and runs; required tests are listed in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` (heading F1).
