# S02 remediation F: test notes

## F2

Nothing in F2 was compiled or run by the author. Each test below must fail if the guarded behaviour were broken.

### Item 1: no rebind after wipe (`UidScopedActivityJournal`)

- Bind A, `wipeForUid(A)`, then `bindUid(A)` returns false; the temp root has no directory for `activityJournalScopeId(A)` and the in-memory key store has no key for A. Breaking `_wipedUid` makes the bind return true.
- After that, `bindUid(null)` then `bindUid(A)` returns true (memory cleared); and `bindUid(B)` then `bindUid(A)` returns true.
- `boundUid` and `isBound`: null/false before bind, A/true after bind, null/false after `bindUid(null)` and after the wipe.
- Wipe of a bound uid whose wipe throws still refuses a rebind of that uid.

### Item 2: key deletion failure fails the wipe

- `SecureStorageJournalKeyProvider` over a `JournalSecureStorage` whose `delete` throws: `forget()` throws (and the cached key is cleared).
- `UidScopedActivityJournal.wipeForUid(A)` over a file journal with such a provider throws; through `ActivityAwareLocalDataWipe` the result is `LocalWipeIncomplete` containing `activity_journal`, and the pending marker is NOT removed.
- Retry: with `delete` working again the second `wipeForUid(A)` completes, the key is gone, and the data directories are empty (idempotent).
- Key names unchanged: default `activity_journal.key.v1`, scoped `activity_journal.key.v1.<scopeId>`.

### Item 3: binding provider (`activityJournalBindingProvider`)

Override `activityBindRetryTimerFactoryProvider` with a fake that records `(delay, callback)` and returns a cancellable `Timer`; use a scripted `AccountScopedJournal` fake.

- Bind fails once (returns false, and a variant that throws), then succeeds: no timer exists before the failure; after it exactly one timer with delay 5 s; firing the callback (no auth event) calls `bindUid` again and the journal ends bound; no further timer.
- Delays across consecutive failures are 5 s, 15 s, 60 s, 5 min, 5 min; after the 5th retry fails no new timer is created (6 `bindUid` calls in total, never more).
- A new auth value (another uid, or sign-out) cancels the pending timer (`isActive` false) and the old callback, if fired, does not call `bindUid`; at no time are two timers active.
- Provider disposal cancels the pending timer.
- Skip of the account being deleted: with `accountBeingDeletedUidProvider` = A, an auth value A results in `bindUid(null)` and never `bindUid(A)`; the retry callback for a uid that became the deleting one does not bind.
- Logging: captured `debugPrint` output contains no uid.

### Item 4: uploader after an account switch

- Uid supplier returns A; start `runPending()` with a blocked `create` call; supplier switches to B, `cancelQueued()`, `resume()`; a second `runPending()` returns a DIFFERENT future than the first and performs B's uploads (create called for B's entry). Breaking the clearing makes it return A's future and B's entry is never uploaded.
- A's blocked run, once released, ends `cancelled`, calls neither `commit` nor `markStreamUploaded` and writes no `upload_failed` under B.
- A's late completion does not clear B's in-flight slot (a third `runPending()` while B runs returns B's future).
- Failed ids: an entry id that failed for A is uploaded for B after the switch (same id, same journal id in a test double) and `uploadEntry` single-flight does not hand B A's outcome.

### Wiring check

- `activityRootOverrides` with cloudSync on constructs `ActivitySyncRepository` with an `authUid` supplier (depends on F1); only construction-level, `FirebaseAuth` is not initialised in tests so do not call the supplier.

### Stale fakes to update

- `mobile/test/features/activity/repository/activity_journal_wipe_wiring_test.dart`: `_Scoped extends Fake implements ActivityJournal, AccountScopedJournal` must implement `String? get boundUid` and `bool get isBound` (a `Fake` throws on an unimplemented getter, and F1 reads `isBound`).
- `mobile/test/features/activity/repository/journal_io_error_remediation_test.dart`: `FlakyKeyProvider implements JournalKeyProvider` (interface unchanged, but its `forget()` semantics now propagate; check any test relying on a swallowed failure).
- Any test that stubbed `JournalSecureStorage.delete` to throw and expected `wipe()` to succeed.
- Tests that rely on `cancelQueued()` leaving the single-flight state intact (search `cancelQueued` in `mobile/test`).
- Tests that read the binding provider with a journal fake whose `bindUid` result was ignored (search `activityJournalBindingProvider` in `mobile/test`).

## F1

Nothing in F1 was compiled or run by the author. Each test must fail if the guarded behaviour were broken. Use a real `UidScopedActivityJournal` over temp directories (or a scripted `AccountScopedJournal`) and a backend whose calls can be blocked on a completer.

### Item A: pass identity

- Switch mid-pass, tombstone phase: journals A and B both hold activity X (same id). A's backend `listTombstoneIds` returns {X}. Block `listTombstoneIds`, `bindUid(B)` + `onAccountChanged()`, release. Assert: B's entry X still exists, B has no tombstone for X, the `syncAll` result has no `deletedLocal`. Breaking the loop check deletes X in B.
- Switch mid-pass, entry phase: block `writeSummary` for an unsynced X in A; switch to B (same X unsynced); release. Assert: no `writeSummary` call after the switch, B's X is not `synced` (`markSynced` not called on B), no `delete` on B's journal, outcome `pending`.
- Switch while `list()` / `read()` is awaited (a journal wrapper that gates the read): the result is not used, nothing is written.
- `authUid` mismatch: construct with `authUid: () => uid` where the closure value changes from A to B after the pass starts; assert `writeSummary`, `readSummary`, `tombstoneExists`, `listTombstoneIds` and the pusher are NOT called once it returns B (count calls), and the outcome is `pending`. With `authUid` returning null at start no backend call is made at all. With `authUid` null (tests) behaviour is unchanged.
- Tombstone push: pusher blocked for id 1 of 2 owed; switch; release; the pusher is not called for id 2 and the confirmed set of B is not polluted (B's own pass pushes id 2 if owed in B).
- Conflict paths: `resolveConflict`, `resolveCandidate`, `applyExplicitEdit` with the switch while `readSummary` is blocked: no `updateRecord` on B, outcome `pending`.
- Plain (non-scoped) journal: all existing tests unchanged (the journal-uid check is skipped).

### Item B: caches

- Two accounts with a conflicting X: `refreshState` for A fills the conflict cache (backend read count 1); `onAccountChanged` + bind B with a conflicting X; `refreshState` reads the backend again (count 2) and shows B's cloud values, not A's.
- `syncAll(retryConflicts: true)` for A retries the conflict once; after `onAccountChanged` the same call for B retries B's conflict (without clearing the retry marks it is skipped).
- A `readSummary` completing after the switch is not cached.

### Item C: unbound visibility

- Scoped journal never bound: `refreshState()` throws `JournalUnbound`; `watch()` emits an error; `SyncConflictPresenter` ends with `loadFailed == true`, `loaded == false`, and `retry()` re-subscribes (after a later bind and retry: `loaded == true`, `loadFailed == false`). Breaking the check yields an empty loaded state.
- `syncAll()` returns an empty map and the backend call count is 0; `syncEntry(id)` returns `pending` (not `notFound` / `synced`); `syncBatch([a, b])` returns `pending` for both; the backend is untouched.
- `resolveConflict`, `resolveCandidate`, `applyExplicitEdit` return `unavailable`; the presenter then shows `lastFailed == true` (never false). `saveSession` throws `JournalUnbound`.
- A failed bind (factory throws) behaves the same as never bound.

### Item D: tombstone retry

- Counter reset: three failed passes (attempts 3), then a clean pass; the next failure schedules the FIRST delay again (60 s), not the fourth.
- Fallback timer: after six scheduled attempts all failing, a further failed pass schedules exactly one timer of `kTombstoneFallbackDelay` (60 minutes); firing it runs a pass; at no moment are two timers active; when a pass ends clean no timer remains; `dispose`, `cancelTombstoneRetry` and `onAccountChanged` cancel it. This replaces any old assertion "no timer after six attempts".
- Exception in the tombstone phase: `listTombstones()` throws `JournalIoException` (and a variant where the pusher throws a missing-uid error): `syncAll` does not throw, a retry timer is scheduled, `lastTombstonePushError` holds the code, the state is published.
- Epoch re-check: block `listTombstones()` inside the pending-count read (second call), call `onAccountChanged()`, release: no timer is created and the attempt counter stays 0 (the next failure after a re-bind schedules the first delay).
- Error code: `listTombstoneIds` throws `SummaryBackendUnavailable`: `lastTombstonePushError == 'unavailable'` and a retry timer exists; a following fully clean pass sets it to null and `refreshState().lastTombstonePushError` is null.
- `requestTombstoneSync()`: two calls in a row never run two passes concurrently (record entry and exit of `listTombstoneIds`); an unexpected backend exception does not escape the call; it does not retry conflicts; after `dispose` it does nothing.

### Stale fakes and tests to review

Changed contracts: `ActivitySyncRepository` (new optional constructor parameter `authUid`, new method `requestTombstoneSync`, `refreshState` may throw `JournalUnbound`) and `AccountScopedJournal` (F2 adds `boundUid` / `isBound`).

- `mobile/test/features/activity/repository/activity_journal_wipe_wiring_test.dart` `_Scoped extends Fake implements ActivityJournal, AccountScopedJournal`: must implement `boundUid` and `isBound` (a `Fake` throws on the getter F1 now reads in every sync operation).
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart` `_FlakyJournal implements ActivityJournal` (noSuchMethod): not an `AccountScopedJournal`, so the unbound check is skipped; verify, no change expected. `_SlowRepo extends ActivitySyncRepository` (same file) and `mobile/test/features/activity/widgets/sync_conflict_sheet_states_test.dart` `_NoJournalRepo extends ActivitySyncRepository`: constructors unchanged (new parameter optional); check they still override `watch` / `refreshState` consistently.
- `mobile/test/features/activity/repository/activity_wiring_account_switch_test.dart` `_ThrowingSyncRepo extends Fake implements ActivitySyncRepository`: wiring does not call `requestTombstoneSync`; no change expected.
- Existing tests using a real `ActivitySyncRepository` over an UNBOUND `UidScopedActivityJournal` (search `UidScopedActivityJournal` and `bindUid` in `mobile/test`): they previously got an empty state and now get `JournalUnbound`.
- `mobile/test/features/activity/repository/activity_tombstone_continuation_test.dart`: assertions about the retry budget (no further timer, counter) must follow the fallback timer and the reset on a clean pass.
- Backend fakes (`FakeSummaryBackend`, `DeviceBackend`, `_Backend` in the continuation test) implement an unchanged interface.

## G

Nothing in G was compiled or run by the author. Each assertion below must fail if the named guard were removed. Use a real `UidScopedActivityJournal` over temp directories, a recording backend and pusher (call counters), and an `authUid` closure the test can flip.

### G1: journal uid and auth uid must agree (`activity_sync_repository.dart`, `_beginPass`, `_mayCall`)

- Journal bound to A, `authUid` returns B (the gap between `FirebaseAuth.currentUser` and the journal rebind), A holds an unsynced entry X and a local tombstone T: `syncEntry(X)` returns `pending`; `syncAll()` returns an empty map; `syncBatch([X])` returns `pending`; `resolveConflict`, `resolveCandidate` and `applyExplicitEdit` return `pending` (not `unavailable`, not `synced`); `saveSession` returns `pending` and the journal `put` count stays 0. In every case the backend call count (`readSummary`, `writeSummary`, `tombstoneExists`, `listTombstoneIds`) and the pusher call count are exactly 0. Removing the start-of-pass tie yields one `listTombstoneIds`/`writeSummary` for B's cloud.
- The same with the retry timer: schedule a retry under A (failing pusher), flip `authUid` to B without `onAccountChanged`, fire the fake timer: zero backend and pusher calls.
- Auth flips between calls: journal bound to A, `authUid` A at the start; `listTombstoneIds` returns and then `authUid` flips to B before the pusher is called for owed tombstone T: the pusher is NOT called (`_mayCall` re-check), `syncAll` returns without `deletedLocal`. Variant: the flip happens while `writeSummary` is blocked for the first of two entries: the second entry gets no backend call.
- Case sensitivity: journal bound to `Abc`, `authUid` returns `abc`: zero backend calls (exact comparison).
- `authUid` returns null at the start with a scoped bound journal: zero backend calls (fail closed, unchanged). Unbound scoped journal: unchanged (`syncAll` empty, `syncEntry` pending, resolution operations `unavailable`).
- Agreeing uids (A and A) with a scoped journal: the existing happy-path tests still pass (sync writes, tombstones pushed). Plain (non-scoped) journal, any `authUid`, and a scoped journal with a null `authUid` supplier: behaviour unchanged (the whole existing pass-identity suite).

### G2: republish on account or binding change

- Live presenter: a `ProviderContainer` with the real `SyncConflictPresenter` subscribed once (non-autoDispose) over a repository on a scoped journal bound to A with a conflict X. Call `onAccountChanged()` and unbind the journal (`bindUid(null)`) with NO tap and no `syncAll`: the presenter ends with `loadFailed == true` (or, if it models it, empty and `loaded == false`), never A's conflict list. Removing the `onJournalBindingChanged()` call from `onAccountChanged` leaves A's conflicts on screen.
- Bind of B succeeds, then `onJournalBindingChanged()`: the presenter shows B's state (B's conflicts, `loadFailed == false`) with no tap.
- Bind of B fails (factory throws): the wiring calls `onJournalBindingChanged()` and the presenter shows `loadFailed == true` although `syncAll` never ran.
- Wiring: with `cloudSync` on and a recording repository (see stale fakes), `activityJournalBindingProvider` calls `onJournalBindingChanged()` exactly once after each `bindUid` completion: a success, a `false` result and a thrown exception (three cases). The cloud sync wiring calls it once after its own `bindUid` in each of the same three cases. With `cloudSync` off the repository provider is never read (no throw, no call). After the container/provider is disposed while a `bindUid` is pending, no call is made.
- `onJournalBindingChanged()` after `dispose()` does nothing and does not throw; with a `refreshState` that throws a non-`JournalUnbound` error nothing escapes and nothing is added to the stream.
- `onAccountChanged()` itself never throws (journal unbound and bound).

### G3: raw-uid account change in the cloud sync listener

- Auth emits anonymous user X, then real user B: `onAccountChanged()` is called once and the uploader's `cancelQueued()` is called once (recording repository and uploader). Before the fix neither is called. The conflict caches of the real repository are empty afterwards (a second `refreshState` re-reads the backend).
- Real A to anonymous Y, real A to null: `onAccountChanged()` and `cancelQueued()` are called once each. Null to A (initial emission, previous raw uid null) and A to A (same raw uid): not called.
- The sync start still depends on the filtered uid: anonymous X alone starts no sync and no bind; real B after X binds B and runs `syncAll(retryConflicts: true)` once.

### G4: wipe marker in both branches, deleting account skipped

- Scoped journal, nothing bound for uid U: `wipeForUid(U)` then `bindUid(U)` returns false and no directory and no key for the scope of U exists afterwards (assert on the factory's created scope ids / the temp directory listing). Queued variant: start `bindUid(U)` (blocked factory) and `wipeForUid(U)` queued behind the mutex in either order; after both complete the bind of U is refused. Removing the marker in the unbound branch makes `bindUid(U)` create the scope.
- `bindUid(null)` or `bindUid(other)` after the wipe clears the marker: `bindUid(U)` succeeds again (semantics unchanged); the bound-branch tests of epic 9b still pass.
- Sync wiring: set `accountBeingDeletedUidProvider` to B, emit real user B: `bindUid` is NOT called on the journal, `syncAll` is not called, the debug line is logged; with the provider null the same emission binds and syncs. The binding provider behaviour is unchanged (existing tests), and both use the same `_bindableUid` helper (a code review item, no extra test).

### G5: skipped passes are logged without any uid

- Capture `debugPrint` (override `debugPrint` with a list collector and restore it): journal unbound, `syncAll()` logs `activity: syncAll skipped (journal-unbound)`; `syncEntry(id)` logs `activity: syncEntry skipped (journal-unbound)`; journal bound to A with `authUid` B logs `journal-auth-mismatch`; `authUid` null at start logs `auth-null`; an `onAccountChanged()` between the pass start and the check (blocked read) logs `pass-identity`; `authUid` flipped after the start logs `auth-changed`.
- In every case no logged line contains the uid strings used by the test (assert `isNot(contains(uidA))` and `uidB`) nor the entry id, and the return values equal the pre-G values (`pending` / empty map).
- A normal successful pass logs no `skipped` line.

### Stale fakes and tests to review (G)

Changed contract: `ActivitySyncRepository` gained the public `void onJournalBindingChanged()`; `onAccountChanged()` now publishes; no interface (`AccountScopedJournal`, `ActivityJournal`, `ActivitySummaryBackend`) changed.

- `mobile/test/features/activity/repository/activity_wiring_account_switch_test.dart` `_ThrowingSyncRepo extends Fake implements ActivitySyncRepository`: the wiring now also calls `onJournalBindingChanged()` after a bind (inside `_publishBindingChange`, which swallows and logs any throw, so the test does not fail, but any count of calls to `onAccountChanged` or a recorded call list must add `onJournalBindingChanged`). Implement `onJournalBindingChanged()` explicitly (record it) and review its `onAccountChanged` expectations: a raw-uid change (anonymous to real) now calls it too.
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart` `_SlowRepo extends ActivitySyncRepository` and `mobile/test/features/activity/widgets/sync_conflict_sheet_states_test.dart` `_NoJournalRepo extends ActivitySyncRepository`: inherit the new method; `onAccountChanged` now publishes through the overridden `refreshState`, review tests that call it with a listener attached.
- `mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart` `_Scripted extends Fake implements ActivityJournal, AccountScopedJournal` and `activity_journal_wipe_wiring_test.dart` `_Scoped extends Fake implements ActivityJournal, AccountScopedJournal`: unchanged interface; the sync repository now also reads `boundUid` / `isBound` in `_beginPass` and `_mayCall` when an `authUid` supplier is given, so both must return the scripted values (a `Fake` throws on an unimplemented getter). Check any test that builds `ActivitySyncRepository(authUid: ...)` over a scoped fake whose `boundUid` differs from the `authUid` value (it now gets `pending`).
- `mobile/test/features/activity/repository/activity_sync_pass_identity_test.dart` (12a): every test that passes `authUid` over a real scoped journal must bind the same uid the closure returns, otherwise the new tie makes the pass do nothing; the `authUid` mismatch cases there flip the closure AFTER the start, which still holds.
- Tests that call `wipeForUid(uid)` for an unbound uid and then `bindUid(uid)` expecting success (search `wipeForUid` in `mobile/test`): now refused until `bindUid(null)` or another uid.
- Tests that capture `debugPrint` output and assert exact lines of the sync repository: the new `skipped` lines are added.
