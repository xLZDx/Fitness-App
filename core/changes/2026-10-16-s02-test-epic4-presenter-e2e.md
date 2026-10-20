# S02 test epic 4: sync-conflict presenter and sheet, delete-wins end-to-end scenarios (I42, E04)

## What
- `mobile/test/features/activity/state/sync_conflict_presenter_test.dart` (I42): presenter over the real repository and journal with the two-device fake server (both values shown, single call on a double tap, entry leaves only after the resolution is stored, keep cloud vs keep device not swapped, offline choice, reappearance after restart, source and recalculation candidates with their action sets) and two widget tests of the choice sheet (no delete action, no coordinate or heart-rate text, a repeated show does not stack, three candidate actions each reach their own operation).
- `mobile/test/features/activity/e2e/s02_delete_wins_e2e_test.dart` (E04): scenarios 1 (delete wins), 2 (different fields, convergence, 2c explicit edit, 2d recalculation, 2e source candidate, 2f 65 explicit edits, 2g atomic resolution incl. 5600 variant), 2b, 3, 4, 5, 6 (account fence replay, no hot loop).
- No production change.

## Why
Test plan I42 and E04 (story S02-12), design 3.2 and 6.2.

## Affected paths
The two files above.

## Verification state
Command (from `mobile/`): `flutter test test/features/activity/state/sync_conflict_presenter_test.dart test/features/activity/e2e/s02_delete_wins_e2e_test.dart`
Result: green on the last run of each file (final epic run in the findings document).
