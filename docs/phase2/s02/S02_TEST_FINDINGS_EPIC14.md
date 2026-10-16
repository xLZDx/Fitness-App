# S02 test findings, epic 14 (remediation H)

## Epic 14b (H-B: sync repository, presenter and sheet, wipe coordinator, export)

Head under test: 4f66324d plus the test commits ab84c4b1, e2be9d52, ea1910bb, aee3c590, 28b2e85a and the final commit
of this section. Oracles: `S02_REMEDIATION_H_TEST_NOTES.md` heading H-B, design section 17 items 23 and 24, and the
promise "after I switch accounts I never see or act on the previous account's conflicts".

### Files

- New: `mobile/test/support/stale_view_world.dart` (Gate, RecBackend, HookJournal),
  `mobile/test/features/activity/repository/activity_sync_deletion_flag_test.dart` (10 tests, H5),
  `mobile/test/features/activity/state/sync_conflict_presenter_reset_test.dart` (3),
  `mobile/test/features/activity/widgets/sync_conflict_sheet_account_test.dart` (4),
  `mobile/test/features/activity/repository/activity_sync_stale_state_test.dart` (11, queued tap and H7),
  `mobile/test/features/activity/repository/activity_wipe_export_account_bound_test.dart` (12, H8),
  `mobile/test/features/activity/e2e/s02_stale_view_e2e_test.dart` (1 journey over the real `FileActivityJournal`).
- Production change (one): `activity_sync_repository.dart` `syncAll` now logs the skip when the identity goes stale
  after the tombstone listing.

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | Remediation H-B code compiled unchanged (the `else ...[ ]` chain in the sheet is valid) and met every H-B oracle; the older presenter and sheet tests (+28) passed unchanged, so no stale presenter or sheet assertion exists | n/a | first compiled run |
| 2 | A mid-flight skip after `listTombstoneIds` (flag or account change) returned silently, while the notes require the `account-deleting` skip to be logged | H author and reviewers | the H5 log oracle in the new test; fixed with one `_logSkip` |
| 3 | The sheet rule "loaded but loadFailed" cannot be produced by the real presenter in one step (loadFailed keeps `loaded` true only after an error), so it is tested with a fixed presenter override | notes | test design |

Not a defect: the window between a passing `_alive` check and the delegated journal write (a blocked
`updateSyncState` completes against the newly bound journal) remains; it is an accepted limit and the test asserts only
that the cache is not filled and the outcome is `pending`.

### Commands and results (from `D:\Repo\Fitness_App_Phase2_s01\mobile`)

- `flutter test --timeout 60s -r failures-only test/features/activity/state test/features/activity/widgets` (before my tests, compile check): `+28: All tests passed!`
- `flutter test --timeout 60s test/features/activity/repository/activity_sync_deletion_flag_test.dart`: `00:06 +10: All tests passed!`
- `flutter test --timeout 60s test/features/activity/state/sync_conflict_presenter_reset_test.dart`: `00:00 +3: All tests passed!`
- `flutter test --timeout 60s test/features/activity/widgets/sync_conflict_sheet_account_test.dart`: `00:02 +4: All tests passed!`
- `flutter test --timeout 60s test/features/activity/repository/activity_sync_stale_state_test.dart`: `00:04 +11: All tests passed!`
- `flutter test --timeout 60s test/features/activity/repository/activity_wipe_export_account_bound_test.dart`: `00:03 +12: All tests passed!`
- `flutter test --timeout 60s test/features/activity/e2e/s02_stale_view_e2e_test.dart`: `00:01 +1: All tests passed!`
- FINAL, complete set: `flutter test --timeout 60s test/features/activity/state test/features/activity/widgets test/features/activity/e2e test/features/activity/repository/activity_sync_deletion_flag_test.dart test/features/activity/repository/activity_sync_stale_state_test.dart test/features/activity/repository/activity_wipe_export_account_bound_test.dart test/features/activity/repository/activity_sync_auth_tie_test.dart test/features/activity/repository/activity_sync_pass_identity_test.dart` -> `02:46 +167: All tests passed!`
- Earlier whole-directory baseline (`flutter test --timeout 60s -r failures-only test/features/activity`, run at the start): `+1264 -40: Some tests failed.`; every failing test was in agent 14a's area (stream upload, uploader account switch, wiring, republish, tombstone continuation); none was in an H-B file.

### Not verified / remains

- No mutation run (operator rule); falsifiability is argued from the assertions (call counts, byte-identical journal
  snapshots, returned outcomes, first-frame state) that change if each guard were removed.
- Real FirebaseAuth stream timing is simulated by a mutable provider or a fake stream.
- `flutter analyze`, the full suite and builds were not run by design.
