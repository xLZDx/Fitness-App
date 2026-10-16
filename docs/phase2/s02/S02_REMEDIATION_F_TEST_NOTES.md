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
