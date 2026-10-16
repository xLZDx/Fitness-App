# S02 test epic 7a: E02 account wipe, E05 Dart half, consent cache fix

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- Added `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart`: the journal wipe seam on files (kill, relaunch with auth failure, kill at every file-system operation of the wipe, stale repository, sign-out with export offer, declined sign-out), the Dart half of E05 (offline put replayed against the deletion fence), and two real app-flow tests that are skipped because the journal wipe is not wired.
- Production fix in `mobile/lib/features/account_deletion/data/local_data_wipe.dart`: prefix `activity.` added to the per-uid feature prefixes, so `activity.cloudStreamsConsent.<uid>` is erased with the account.
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md`: epic 7a section with exactly what the app shell does not wire.

## Why
Plan E02 (085) and the Dart half of E05. The consent cache of a deleted account survived on the device.

## Affected contracts and paths
Device-local wipe of a deleted account; test files; findings document.

## Verification state
`flutter test` of the E02 file: 9 passed, 2 skipped (NOT WIRED, owner sprint lead, 2026-10-16). With `--dart-define=S02_E02_WIRED=true` the two skipped tests fail as documented. `test/features/account_deletion`: 90 passed. The journal wipe is still not wired into the app shell (see the findings).
