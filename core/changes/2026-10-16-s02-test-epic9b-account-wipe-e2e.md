# S02 test epic 9b: account wipe e2e un-skipped (remediation B2)

## What
- `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart`: the two NOT WIRED tests of group 3 run now. `wipeImpl()` is built through `activityAwareLocalDataWipe(DeviceLocalDataWipe(...), journal, ownerStore: InMemoryActivityJournalOwnerStore())`, the same composition as `main.dart`. Both tests also assert that the inner prefs wipe ran (consent cache of the deleted account gone, the other account's kept).
- The `S02_E02_WIRED` define and the skip marker are removed.

## Why
Remediation B2 wired the journal wipe into the account deletion path and the interrupted-wipe relaunch path; the epic 7a quarantine entries are closed.

## Affected paths
- `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart`

## Verification state
Run with flutter test, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC9.md`.
