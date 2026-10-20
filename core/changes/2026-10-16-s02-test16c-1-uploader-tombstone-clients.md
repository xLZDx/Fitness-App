# Uploader, tombstone push, presenter and real client tests (epic 16c, 1/2)

Date: 2026-10-16. Kind: new tests.

## What changed
- New mobile/test/features/activity/repository/activity_stream_uploader_expected_uid_test.dart: create and commit receive the pass uid; ConsentAccountChangedException from create or commit ends as cancelled with nothing marked, no backoff, no failure state and no quarantine; A to B flips before create, during the PUT and during commit send nothing for B; a scoped journal bound to another account (or unbound) is never read by uploadEntry or runPending, a plain journal still uploads.
- New mobile/test/features/activity/repository/activity_tombstone_expected_uid_test.dart: authUid is passed as expectedUid; an account-changed refusal while the pass is alive keeps the id owed, leaves lastTombstonePushError and the failed set untouched and schedules the normal 60 s retry (budget advances by one); a flip to B between two pushes sends nothing for B.
- New mobile/test/features/activity/repository/activity_real_clients_expected_uid_test.dart: the real stream client and tombstone pusher with a faked FirebaseFunctions: null uid fails before any callable, payload carries expectedUid, failed-precondition plus account_changed is mapped, account_deleting is not.
- New mobile/test/features/activity/state/sync_conflict_presenter_null_uid_test.dart: a tap with a null uid does not reach the repository (control rows with uid A prove the observers see calls).

## Why
Remediation J2 and J3b bind the uploader, the tombstone push and the presenter to the initiating account.

## Affected contracts and paths
Test code only.

## Verification state
The four new files passed together (42 tests). The full final runs and findings section 16c follow in the next commit.
