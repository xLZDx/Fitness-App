# S02 test epic 9b: journal wipe wiring and owner guard tests (remediation B2)

## What
- New `mobile/test/features/activity/repository/activity_journal_wipe_wiring_test.dart` (24 tests): the activity-aware wipe decorator (null journal returns the inner object, journal failure reports `activity_journal` and keeps the owner marker, inner failures still wipe the journal), the relaunch path through `finishInterruptedWipe` (marker kept on failure and retried), the owner skip (pending wipe of X leaves Y's journal), `claimActivityJournal` (wipe before the owner write, same uid and unclaimed journal never wipe, wipe, write and read failures return false) and `activityCloudSyncWiringProvider` (no `syncAll` and no upload when the claim fails, both start after a good wipe, the same uid and an unclaimed journal).

## Why
The B2 production code (decorator, owner store, claim in the wiring provider) was new and never run; the oracles are the B2 test notes and design sections 6.2, 7 and 17.

## Affected paths
- `mobile/test/features/activity/repository/activity_journal_wipe_wiring_test.dart`

## Verification state
Run with flutter test, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC9.md`.
