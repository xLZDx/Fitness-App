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
