# S02 remediation E1 (c): wipe decorator, design docs, test notes

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Responds to GPT-PM MAJOR-01 and MAJOR-02.

## What changed
- `mobile/lib/features/activity/repository/activity_aware_local_data_wipe.dart`: the `ownerStore` constructor parameter and the owner-skip rule are gone. Account deletion calls `wipeForUid(uid)` on an `AccountScopedJournal` (the deleted uid's scope, bound or not, never another uid's scope); a plain journal falls back to `ActivityWipeCoordinator.onAccountDeleted()` (`journal.wipe()`). A failed journal wipe is still reported as `activity_journal` in `LocalWipeIncomplete` and the pending marker stays.
- `mobile/lib/features/activity/repository/activity_journal.dart`: doc comment on `ActivityWipeCoordinator` (acts on the bound journal; sign-out itself never wipes, the app does not call it yet).
- `docs/phase2/s02/S02_DESIGN.md`: section 6 table row, notes in 6.2 and 7, new item 22 in section 17 (supersedes the owner guard and wipe-on-switch of item 18).
- `docs/phase2/s02/S02_REMEDIATION_E_TEST_NOTES.md`: E1 heading with the four test files that reference removed symbols and the required coverage.

## Why
Sign-out and account switch must not destroy device-only data; account deletion must wipe exactly the deleted account's scope.

## Affected contracts and paths
`ActivityAwareLocalDataWipe({inner, journal})` (was also `ownerStore`). `activityAwareLocalDataWipe(inner, journal)` call sites in `main.dart` were already two-argument.

## Verification state
No tests, analyze or build were run (test agents follow). Four existing test files do not compile until rewritten (see the test notes).
