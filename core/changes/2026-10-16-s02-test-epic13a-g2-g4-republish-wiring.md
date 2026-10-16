# S02 test epic 13a: G2 republish, G3 raw-uid reset, G4 wipe marker and deleting account

Date: 2026-10-16. Area: tests only.

## What changed

- New `mobile/test/features/activity/repository/activity_republish_wiring_test.dart` (21 tests).
- G2: a live `SyncConflictPresenter` over a real repository and scoped journal shows `loadFailed` after unbind plus
  `onAccountChanged` / `onJournalBindingChanged` with no tap, shows B's conflicts after B's bind, and an end-to-end
  case where the binding provider fails to bind B (presenter fails, no sync pass ran). `onJournalBindingChanged` after
  dispose and with a non-JournalUnbound refresh error does nothing and never throws. The binding provider and the
  cloud sync wiring publish exactly once after a success, a false result and an exception; with `cloudSync` off the
  repository provider is never read; no publish after the provider is disposed.
- G3: anonymous X then real B, real A to anonymous Y, real A to null reset once (onAccountChanged and cancelQueued);
  null to A and A to A do not; the sync still starts only for the real user.
- G4: `wipeForUid(U)` while unbound then `bindUid(U)` is refused with no new directory, file or key; `bindUid(null)`
  or another uid clears it; both queued orders; the sync wiring skips the account being deleted (control binds).

## Why

Oracles from the F test notes headings G2, G3, G4. The conflict cache clearing itself is covered by the 12a
test; here only the wiring call to `onAccountChanged` is asserted.

## Verification state

First run: `+16 -3` (three oracle slips of mine: the wipe of an unbound uid opens the factory once to delete the
scope, so "factory never asked" had to be "bindUid asks it no more"). After the fix:
`+21: All tests passed!`.
