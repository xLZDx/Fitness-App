# S02 remediation H-A, item H1: consent store and settings client per account

Date: 2026-10-16. Area: mobile production code (activity cloud consent). Nothing was compiled or run by the author
(operator rule: a test agent runs everything afterwards).

## Why

GPT-PM round 12 rejected head 10288e57 with one MAJOR: `AccountScopedConsentStore` kept one mutable `_inner` for all
accounts, so a delayed `signIn(A)` could overwrite the consent cache after B became current, and B's streams could
upload under A's granted consent. Class sweeps found siblings in the settings client (state without an owner uid,
`load` racing `grant`/`withdraw`, a silently dropped write, a delete-request flag shared across accounts).

## What changed

- `mobile/lib/core/wiring/activity_wiring.dart`, `AccountScopedConsentStore`: new `String? get boundUid` (set at once
  by `signIn`), generation counter so a stale `signIn` completion does nothing, new `void signOut()` (clears the
  binding, invalidates in-flight sign-ins, deletes no stored key), reads and writes wait for the open preferences,
  `write` with no bound account throws `StateError` instead of dropping the value.
- `mobile/lib/features/activity/repository/activity_cloud_settings_client.dart`:
  - `CloudStreamsConsentStore` gains `String? get boundUid` (in-memory store: optional constructor `boundUid`;
    shared-prefs store: its uid).
  - `ActivityCloudSettingsClient`: `consentUid`, `accountUid`, `reset()`; `isGranted` is true only when the state
    belongs to the store's current uid; `load()` applies its result only if no newer state change happened and the
    store is still bound to the same uid (version counter); `grant()` writes only while the account is unchanged and
    sets the state only after the value was persisted; `withdraw()` flips memory first, persists before returning,
    refuses to send the server call when the account changed, and a failed persist never lets a later `load()` bring
    back a stored `granted`.
  - New `ConsentAccountChangedException`.
  - `ActivityConsentWithdrawal`: the delete-request guard is a set keyed by uid.
- `mobile/lib/features/activity/repository/activity_stream_uploader.dart`: `CloudStreamsConsentView` gains
  `String? get consentUid` (the uploader side that uses it is item H2).

## Affected contracts

`CloudStreamsConsentStore.boundUid`, `CloudStreamsConsentView.consentUid` (new abstract members; see the test notes
for the stale implementers), `ActivityCloudSettingsClient.{consentUid, accountUid, reset}`,
`AccountScopedConsentStore.{boundUid, signOut}`. Stored consent keys are unchanged and are never deleted.

## Verification state

Not compiled, not run. Test oracles: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md` (heading H-A, written in item
H4). The wiring that calls `signOut`/`reset` is item H3.
