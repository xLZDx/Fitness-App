# S02 remediation I, item I2: consent contract with an unbound store, early consent bind

Date: 2026-10-16. Area: mobile production code (activity cloud consent). Nothing was compiled or run by the author
(operator rule: a test agent runs everything afterwards).

## Why

With `_store.boundUid == null`, `grant()`, `withdraw()` and `deleteCloudStreamsNow()` passed `_requireUid(null)`, sent the
server call, and only then the store write threw `StateError`: the server held granted/withdrawn while the client threw,
and `_unpersistedWithdrawals` held the key null, so a later `load()` for the real uid could resurrect a stale granted.
The unbound window was long: the consent store was bound only after the journal bind, `_bindableUid` and the whole
`syncAll` (and for the whole session when the bind failed), although consent depends on neither.

## What changed

- `mobile/lib/features/activity/repository/activity_cloud_settings_client.dart`: `grant()`, `withdraw()` and
  `ActivityConsentWithdrawal.deleteCloudStreamsNow()` throw `ConsentAccountChangedException` first thing when the store
  has no bound uid (before any state change, set insertion or server call). No signature changed.
- `mobile/lib/core/wiring/activity_wiring.dart` (startup wiring):
  - Startup closure: after a first `current()` check, `consentStore.signIn(myUid)` and `settings.load()` run BEFORE the
    journal bind and `syncAll`, each followed by a `current()` re-check; a failure is logged (type only) and the bind and
    sync still run (consent stays unknown, so no upload). The later re-checks after the bind and after `syncAll` stay;
    `uploader?.resume()` runs only after the final successful `current()` directly before `runPending`.
  - Account-change block: `consentStore.signOut()` and `settings.reset()` run FIRST, each in its own try/catch that
    logs only the runtimeType, so an exception in `onAccountChanged` cannot leave the previous account's consent bound.

## Affected contracts

No public signature changed. Behaviour: consent mutators refuse on an unbound store; the order of startup steps is now
signIn, load, bind, sync, resume. Stale tests are listed in `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`, heading I.

## Verification state

Not compiled, not run.
