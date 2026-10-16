# S02 remediation H: test notes

Each section is written by the agent that made the change. Nothing here was compiled or run by the author.

## H-B: sync repository, conflict presenter and sheet, wipe coordinator, export

Each oracle must fail if the named guard were removed.

1. Deletion in progress (H5). Build the repository with `accountBeingDeleted: () => 'uidA'` returned only after the pass
   started. Block `listTombstoneIds` (or a tombstone push) in an in-flight `syncAll`, set the flag, release. Assert zero
   `writeSummary`, zero `create`, zero tombstone pusher calls and zero journal writes after the flag; the skip is logged
   as `account-deleting` without a uid. Also: a `syncAll` started while the flag equals the journal uid or auth uid does
   nothing; the scheduled tombstone retry timer does nothing.
2. Presenter reset (H6). Override `syncConflictUidProvider` with a mutable source. State under A has conflicts and a busy
   key; switch to B. Assert the first state is `loaded == false`, empty `sync`, empty `busy`, `lastFailed == false`, and
   that the sheet shows `activitySync.loading` and no card key of A.
3. Failed bind after A to B (H6). The repository stream errors after the switch: `loadFailed == true`, `sync` empty; the
   sheet shows `activitySync.error` and finds NO `activitySync.conflict.<A id>` key and no candidate card.
4. Queued tap (H6). Tap keep device under A while `syncAll` is blocked; switch the journal to B (same deterministic id
   in a `sync_conflict` state); release. Assert the outcome is `SyncOutcome.pending`, B's entry state, record and
   backend writes are unchanged, and the presenter state of B has no `busy` key left over from A. Repeat for
   `resolveCandidate`, and call `resolveConflict(id, choice, expectedUid: 'A')` directly under B.
5. Cache fill across a switch (H7). Block `updateSyncState` inside `_markConflict`, switch the account, release; assert
   `refreshState` for B does not return A's cloud values (cache empty). Same for a blocked `readSummary` in
   `_conflictView`.
6. `refreshState` across a switch (H7). Block `list()` or `readSummary`, switch the bound uid, release; assert the
   returned state never contains an entry id or field value of A combined with a read made under B (it holds B's state
   or throws `JournalUnbound`).
7. Sign-out wipe (H8). `onSignOut` with a hook whose `confirmWipe` switches the bound uid A to B before returning true:
   assert B's data is intact and `wipeForUid` was not called for B; without a switch assert `wipeForUid('A')` ran and
   B (when present) is untouched. Plain journal: `wipe()` still runs.
8. Export (H8). `exportAll` where the uid changes during `list()` and, separately, during the Nth per-activity read:
   assert the result is a single `ActivityExportAccountChanged` and contains no file; without a change all files are
   returned and belong to one account.

### Stale fakes and tests to update

- New members: none on an interface (the new constructor parameter of `ActivitySyncRepository` and the new named
  parameters of the extension methods are optional; extension methods are not members, so a `Fake implements
  ActivitySyncRepository` is unaffected: `_RecRepo` in `activity_republish_wiring_test.dart`, `_ThrowingSyncRepo` in
  `activity_wiring_account_switch_test.dart`; subclasses `_SlowRepo` in `sync_conflict_view_errors_test.dart` and
  `_NoJournalRepo` in `sync_conflict_sheet_states_test.dart` need no change).
- `ActivityExportResult` is sealed and gained `ActivityExportAccountChanged`: any exhaustive `switch` over it needs the
  case (none found in `mobile/lib` or `mobile/test`).
- Presenter and sheet tests that build `syncConflictPresenterProvider` now also depend on `syncConflictUidProvider`,
  which defaults to `authUserProvider` (the mock auth repository by default). Override `syncConflictUidProvider`
  directly; a test that expects cards in an error state (`loadFailed == true`) now fails by design.
- Tests that call `refreshState` while switching the account mid-read now get the new account's state (or
  `JournalUnbound`), not the old one.

## H-A: consent store, settings client, uploader, startup wiring

Nothing here was compiled or run by the author. Each oracle must fail if the named guard were removed. "Gate" means a
`Completer` the test releases at a chosen moment (deterministic interleaving, no sleeps). Use
`SharedPreferences.setMockInitialValues` for the store tests.

### Consent store (`AccountScopedConsentStore`)

1. Stale sign-in. `signIn('A')` is started and its `SharedPreferences.getInstance` is gated (inject through a subclass or
   a mock-values channel gate); `signOut()` then `signIn('B')` complete first; release A. Assert `boundUid == 'B'`, reads
   and writes hit B's key (`activity.cloudStreamsConsent.B`) and A's key was never written. Removing the generation guard
   makes `boundUid`/`_inner` become A.
2. Stale completion after sign-out: `signIn('A')` gated, `signOut()`, release. Assert `boundUid == null`, `read()` is
   `unknown`, and `write(granted)` throws `StateError`.
3. `signOut()` deletes no key: A granted and persisted, `signOut()`, then raw prefs still hold `granted` under A's key;
   `signIn('A')` reads `granted` again.
4. `write` with no account throws `StateError` (replaces the old test "before sign-in the scoped store ... drops
   writes", `activity_stream_upload_test.dart` ~line 234, which must now expect the throw). A write issued while
   `signIn('A')` is still opening waits and lands under A's key.

### Settings client (`ActivityCloudSettingsClient`)

5. Delayed `load` of A after B is current: store bound to A, `load()` gated inside `read()`; `signOut()`, `signIn('B')`,
   `load()` for B completes (B granted). Release A. Assert `consentUid == 'B'`, `state` is B's, `isGranted` true only
   for B. Without the uid/version check A's value overwrites B's.
6. `isGranted` false unless the state's uid equals the store's bound uid: A granted loaded, `signIn('B')` without `load`
   gives `isGranted == false` and `consentUid == 'A'`; `reset()` gives `unknown`, `consentUid == null`.
7. `grant()` started under A (callable gated), switch to B, release: throws `ConsentAccountChangedException`, B's key and
   B's in-memory state stay untouched, `isGranted` false for B. A write failure in `grant()` leaves the state unchanged.
8. `withdraw()` persists before it returns (the store write is complete; reading the store gives `withdrawn`), and a
   later `load()` yields `withdrawn`, never the earlier stored `granted`. When the store write throws, `withdraw` still
   sends the callable, then rethrows; a following `load()` still yields `withdrawn` (not the stale `granted`).
9. Withdraw before `signIn` completes: `signIn('A')` gated, `withdraw()` started, release, `load()`. Assert the stored
   value is `withdrawn` and the state is `withdrawn`.
10. `withdraw()` whose store write is gated: switch to B before release; the callable is NOT invoked (zero requests) and
    `ConsentAccountChangedException` is thrown.
11. `ActivityConsentWithdrawal`: A's `deleteCloudStreamsNow()` then, after the switch to B, B's `deleteCloudStreamsNow()`
    reaches the callable (two `deleteExisting` requests in total, one per account); a second call for the same account is
    a no-op; a failed call allows a retry for that account. The old "once per instance" assertion changes to "once per
    account".

### Uploader (`ActivityStreamUploader`)

12. Consent uid required: uploader with `currentUid: () => 'B'` and a consent view that is granted with
    `consentUid == 'A'` (and another with `consentUid == null`): zero create/PUT/commit, `runPending` and `uploadEntry`
    return without a network call. With `consentUid == 'B'` the upload runs (control).
13. A granted / B unknown, A granted / B withdrawn, stale completion after sign-out: drive the real client plus
    `AccountScopedConsentStore` through the switch with the startup chain gated; assert zero create/PUT/commit for B and
    `isGranted == false` for B until B's own `load()`.
14. A to B to A within one upload: scoped journal bound A, gate the commit, `bindUid('B')` then `bindUid('A')`, release.
    Assert `markStreamUploaded` was NOT called (the entry of A stays `streamUploadPending`) because the uploader epoch
    changed (`cancelQueued` on the switch) and, separately without `cancelQueued`, because the scoped journal's
    `boundUid` changed between the check and the mark (use a journal whose `boundUid` flips to another value). The same
    for the `uploadFailed` update after the retry cap.
15. Deletion in progress stops an in-flight upload: `accountBeingDeleted` returns null at start, then the run's uid after
    `create` returned; assert no PUT and no commit. Return it before `create`: assert no create. Constructed without the
    parameter nothing changes.

### Startup wiring (`activityCloudSyncWiringProvider`)

16. Delayed continuation of A: gate `syncAll` of A, switch auth to B (real change), release A. Assert A's continuation
    calls no `signIn('A')`, no `load`, no `resume`, no `runPending`; B's chain runs once with `signIn('B')`. Repeat with
    the gate on `signIn` (a gated `_Consent.signIn`), on `load`, and on the journal bind. Removing the `current()`
    re-check after the respective await makes the old chain continue.
17. Resume after consent: record events; assert the order `bind, sync, signIn, load, resume, run` and that on a
    `load` that throws, or on a switch during `load`, `resume` and `runPending` are never recorded.
18. Account change resets: raw uid A to B, A to null, anonymous X to B: `consentStore.signOut()` and `settings.reset()` are
    called once each, before B's `signIn`; stored consent keys of A remain.
19. Deletion in progress: set `accountBeingDeletedUidProvider` to the signed-in uid while a start is gated: the repository
    gets `onAccountChanged()`, the uploader gets `cancelQueued()`, and the released chain performs no `signIn`, `load`
    and `runPending`. A value that is not the signed-in uid does nothing. The repository (override of
    `activitySyncRepositoryProvider` in `activityRootOverrides`) and the uploader receive an `accountBeingDeleted`
    supplier that reads this provider (assert through the real `activityStreamUploaderProvider`: set the provider, an
    in-flight upload stops before the next network step).

### Stale fakes and tests to update

- New abstract member `CloudStreamsConsentView.consentUid`: `FakeConsent` (`mobile/test/support/stream_upload_world.dart`
  line 168) is a plain `implements` and must add `String? get consentUid` (return a settable field, default: the uid
  the test's uploader runs for). `ActivityCloudSettingsClient` implements it.
- New abstract member `CloudStreamsConsentStore.boundUid`: implementers are `InMemoryCloudStreamsConsentStore` (optional
  constructor `boundUid`), `SharedPrefsCloudStreamsConsentStore` and `AccountScopedConsentStore`, all updated; no other
  implementer exists in `mobile/lib` or `mobile/test`.
- `Fake implements ActivityCloudSettingsClient` (no compile error, but a runtime `UnimplementedError` now that the
  wiring calls `reset()`; add `void reset() {}` and, where `deleteCloudStreamsNow` is used, `String? get accountUid`):
  `_Settings` in `activity_journal_wipe_wiring_test.dart` (line 114), `activity_wiring_account_switch_test.dart`
  (line 55), `activity_republish_wiring_test.dart` (line 92), `activity_tombstone_continuation_test.dart` (line 226),
  `activity_wiring_flag_matrix_test.dart` (line 55).
- `_Consent extends AccountScopedConsentStore` in the same five files: `signIn` is now `Future<void> signIn(String uid)`
  (non-async); their `async` overrides stay valid. `signOut()` is inherited and real. Tests that expect `resume` before
  `syncAll` must change: `activity_journal_wipe_wiring_test.dart` (the test near line 378 asserting the journal is
  bound before the uploader resumes: `resume` is now recorded after `signIn`/`load`, still after the bind) and any
  account-switch test that lists `resume` before `sync`.
- A fake uploader or `_RecUploader` with `resume`/`runPending` counters (`activity_journal_wipe_wiring_test.dart`
  ~line 108): `resume` is now not called when consent loading fails or the account changed.
- Tests using `ActivityCloudSettingsClient` with the in-memory store and an uploader with `currentUid`
  (`activity_stream_upload_test.dart` ~line 151 and `activity_consent_withdrawal_test.dart`): the uploader now needs
  `consentUid == currentUid()`. Construct `InMemoryCloudStreamsConsentStore(boundUid: 'uid')` and run the uploader
  with `currentUid: () => 'uid'`, and call `client.load()` (or `grant()`) so `consentUid` is set; a client that was
  never loaded has `consentUid == null` and `isGranted == false` only when the store's uid is non-null.
- `activity_stream_upload_test.dart` ~line 234 (write before sign-in is dropped): now throws `StateError`.
- `activity_consent_withdrawal_test.dart`: `deleteCloudStreamsNow` "exactly once per instance" is "once per account";
  `withdraw()` on a client whose store has no account (scoped store) now throws before returning.
- Uploader tests that call `cancelQueued()` between commit and the journal mark and expect `uploaded` plus a marked
  entry: the outcome is now `cancelled` and the entry stays pending.
