# S02 test epic 12b (2): journal binding retry and deleting-account skip

## What changed
- New `mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart` (14 tests): fake timer factory and scripted `AccountScopedJournal`; a failed (false or throwing) bind retries after 5 s, 15 s, 60 s, 5 min, 5 min then stops (six binds), never two pending timers, a new auth value / sign-out / provider disposal cancels the pending timer and a forced stale callback binds nothing, no raw uid in logs, the account being deleted (`accountBeingDeletedUidProvider`) is skipped and unbound, a pending retry for a uid that became the deleting one does not bind.
- No production change: the binding provider behaved as the F2 notes describe on the first run.

## Why
Remediation F2 item 3 (fail-closed bind result had no consumer) had no test.

## Affected contracts
`activityJournalBindingProvider`, `activityBindRetryTimerFactoryProvider`, `kActivityBindRetryDelays`.

## Verification state
`flutter test` of the file: `+14: All tests passed!`; complete runs in docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md section Epic 12b.
Not covered: the `authUid` argument of `activityRootOverrides` (constructing the repository calls `FirebaseFirestore.instance`, which needs an initialised Firebase app).
