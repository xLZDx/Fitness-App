# S02 remediation H-A, item H3: startup wiring bound to the account

Date: 2026-10-16. Area: mobile production code (`activity_wiring.dart`). Nothing was compiled or run by the author.

## Why

The startup closure of `activityCloudSyncWiringProvider` ran `syncAll`, `consentStore.signIn`, `settings.load` and
`runPending` with no uid re-check after `syncAll`, so account A's delayed continuation could act after B became
current. Resume was called before this account's consent was known.

## What changed

- The closure captures `myUid` and a start generation (incremented on every auth value with a real change, on a
  deletion that starts for the signed-in uid and on dispose). One local `current()` checks: not disposed, same
  generation, same signed-in uid, and not the account being deleted. It is re-checked after the bind, after
  `syncAll`, after `signIn` and after `load`; the closure returns silently when false. `signIn` uses `myUid`.
- `uploader.resume()` now runs only after this account's consent is loaded and verified, directly before
  `runPending` (not before `syncAll`).
- On a raw-uid change or sign-out (the block that already called `onAccountChanged` and `cancelQueued`) the wiring
  also calls `consentStore.signOut()` and `settings.reset()`. No stored consent is deleted.
- New listener on `accountBeingDeletedUidProvider`: when it becomes the signed-in uid it bumps the generation and
  calls `onAccountChanged()` and `cancelQueued()`. Stored data is untouched.
- `accountBeingDeleted` is passed to `ActivitySyncRepository` (parameter added by H-B) and to the uploader through the
  private `_accountBeingDeletedSupplier(Ref)`, created inside the provider bodies that own a `ref`
  (`activitySyncRepositoryProvider.overrideWith`, `activityStreamUploaderProvider`); it answers null after the
  owning provider is disposed.
- The binding provider is unchanged.

## Verification state

Not compiled, not run. Oracles: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md` heading H-A (item H4). Known
limit: if a deletion fails and the account stays signed in, sync and uploads resume only at the next auth change.
