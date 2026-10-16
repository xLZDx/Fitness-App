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
