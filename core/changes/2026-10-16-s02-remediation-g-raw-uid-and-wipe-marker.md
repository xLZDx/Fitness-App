# S02 remediation G3 and G4: raw-uid account change, wipe marker in both branches, deleting-account skip

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: `activity_wiring.dart`, `uid_scoped_activity_journal.dart`.

## What changed

- `mobile/lib/core/wiring/activity_wiring.dart`:
  - G3: the cloud sync listener calls `onAccountChanged()` and `cancelQueued()` on any change of
    the RAW uid (previous raw uid non-null and non-empty and different from the next raw uid,
    including to null). The sync start logic still depends on the filtered `_syncUid`.
  - G4: new private `_bindableUid(Ref, String?)` (null for no user, empty uid or the account in
    `accountBeingDeletedUidProvider`) is the single place of that rule; the binding provider uses
    it twice (its `bindableUid()` and its auth listener) and the cloud sync wiring uses it before
    its own `bindUid` call (logs `account is being deleted; sync not started` and returns).
- `mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart`: G4 `wipeForUid(uid)`
  sets `_wipedUid = uid` in BOTH branches (also when the scope was not bound), so an already queued
  `bindUid(uid)` cannot re-create the scope directory or key after the wipe. Cleared by
  `bindUid(null)` or another uid, as before.

## Why

G3: the filtered uid is null for anonymous users, so anonymous X to real user B never called
`onAccountChanged` / `cancelQueued` and stale conflict caches survived. G4: the marker was only
set when the wiped scope was bound; the sync wiring also ignored the account being deleted.

## Affected contracts / paths

No public signature changed. Behaviour: an unbound `wipeForUid(uid)` followed by `bindUid(uid)`
now returns false and creates no directory or key.

## Verification state

Nothing compiled or run by the author. Tests are specified in section G of
`docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`.
