# S02 remediation B2: journal wipe wiring and journal owner guard

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- New `mobile/lib/features/activity/repository/activity_aware_local_data_wipe.dart`: a `LocalDataWipe` decorator that runs the inner device wipe and then the journal wipe (journal, sources, quarantine, key) and clears the owner marker. A journal left behind is reported as `activity_journal` in `LocalWipeIncomplete`.
- New `mobile/lib/features/activity/repository/activity_journal_owner.dart`: owner uid marker store (SharedPreferences key `activity.journalOwnerUid`) and `claimActivityJournal` (wipe when the marker names another uid, then record the uid; returns false on any failure).
- `mobile/lib/core/wiring/activity_wiring.dart`: `activityAwareLocalDataWipe` helper (returns the inner wipe unchanged when no journal is open), `activityJournalOwnerStoreProvider`, and the claim step before the start sync and stream upload (fail closed).
- `mobile/lib/main.dart`: `localDataWipeProvider` now uses `activityAwareLocalDataWipe(DeviceLocalDataWipe(), activityJournal)`.
- `docs/phase2/s02/S02_DESIGN.md` section 17 item 18; `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md` heading B2.

## Why
Epic 7a proved nothing in `mobile/lib` wiped the journal on account deletion (two NOT WIRED tests). The journal is device-wide, so account A's sessions could also be synced into account B's cloud after a sign-in switch. Items 1 and 2 of remediation B2 are in this one commit because both touch `activity_wiring.dart`.

## Affected contracts and paths
Account deletion (both the immediate and the interrupted-relaunch path share `localDataWipeProvider`); activity cloud sync start. Flag off: no behaviour change. The sign-out export offer and consent centre UI stay S03 scope.

## Verification state
No tests, analyzer or builds were run (batch rule). The two skipped tests in `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart` still build the plain `DeviceLocalDataWipe`; the test agent must compose the decorator and un-skip them.
