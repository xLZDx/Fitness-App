# S02 test epic 12b (1): no rebind after wipe, key-delete failure, stale F2 fakes

## What changed
- Production (smallest fix): `mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart`, `bindUid`: `bindUid(null)` now clears `_wipedUid` before the "already unbound" early return. Before, after `wipeForUid(bound uid)` the journal was already unbound, so `bindUid(null)` returned early and the refusal of the wiped uid never ended (contract in the F2 test notes item 1: cleared by `bindUid(null)` or another uid).
- Tests: new `mobile/test/features/activity/repository/uid_scoped_journal_wipe_rebind_test.dart` (28 tests: no rebind after wipe, boundUid/isBound in every state, key delete failure fails the wipe and is retried idempotently, close paths best effort).
- Stale tests updated to the F2 contract: `uid_scoped_activity_journal_test.dart` (epic 11a expected `bindUid` of a wiped uid to succeed at once; now false until `bindUid(null)` or another uid), `activity_journal_wipe_wiring_test.dart` (`_Scoped` fake implements `boundUid`/`isBound`; `idsOf` unbinds first).
- Test support: `mobile/test/support/journal_harness.dart` `FakeJournalSecureStorage.failDeletes`.

## Why
Remediation F2 made the wipe fail visibly when the key cannot be deleted and made a wiped uid un-rebindable; its author compiled nothing.

## Affected contracts
`AccountScopedJournal.bindUid/boundUid/isBound/wipeForUid`; `SecureStorageJournalKeyProvider.forget`.

## Verification state
`flutter test` of the changed files from `mobile/`: see docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md section Epic 12b.
