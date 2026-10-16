# S02 remediation G2 and G5: republish on account or binding change, skip logging

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: `ActivitySyncRepository`, `activity_wiring.dart`.

## What changed

- `mobile/lib/features/activity/repository/activity_sync_repository.dart`:
  - `onAccountChanged()` now ends by calling the new `onJournalBindingChanged()`.
  - New public `void onJournalBindingChanged()`: publishes the current state to every subscriber
    (an unbound journal reaches the stream as `JournalUnbound`); no-op after `dispose`; swallows
    and logs only the exception `runtimeType`.
  - G5: `syncAll` and `syncEntry` (`_syncLocked`) log `activity: <op> skipped (<reason>)` when the
    pass does nothing; reasons are the words `journal-unbound`, `auth-null`,
    `journal-auth-mismatch`, `pass-identity`, `auth-changed`. No uid or id is logged. Return values
    are unchanged.
- `mobile/lib/core/wiring/activity_wiring.dart`:
  - New private `_publishBindingChange(Ref)`: reads the flags, returns unless `cloudSync` is on,
    then calls `onJournalBindingChanged()`; never throws.
  - `activityJournalBindingProvider` calls it after EVERY `bindUid` completion (success, false or
    exception) while the provider is not disposed (new `disposed` flag).
  - The cloud sync wiring calls it after its own `bindUid` (in a `finally`) while not disposed
    (new `disposed` flag).

## Why

`onAccountChanged()` cleared caches but never published, and nothing published after a bind or
unbind. The non-autoDispose conflict presenter therefore kept showing the previous account's
conflicts, and after a failed bind `syncAll` never ran, so `loadFailed` was never set. A skipped
sync was invisible.

## Affected contracts / paths

Added public method `ActivitySyncRepository.onJournalBindingChanged()`. Classes that
`implements`/`Fake implements` `ActivitySyncRepository` and are reached by the wiring must now
accept this call (see the stale fake list in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`
section G).

## Verification state

Nothing compiled or run by the author. Tests are specified in section G of the notes file.
