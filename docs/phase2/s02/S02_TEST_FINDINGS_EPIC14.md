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

## Epic 14a (H-A: consent store, settings client, uploader, startup wiring)

Head under test: 4f66324d plus the test commits d2a53815, 0f7a3768, 5575d5d2 and the final commit of this section.
Oracles: `S02_REMEDIATION_H_TEST_NOTES.md` heading H-A, design section 17 items 23 and 24, the external finding
(interleavings, zero create/PUT/commit for B on A's consent) and the promise "my GPS data is never uploaded under another
account's consent". No production code was changed.

### Files

- New: `mobile/test/support/gated_prefs.dart` (gated platform preferences store),
  `mobile/test/features/activity/repository/activity_consent_account_binding_test.dart` (25 tests: store, client, uploader),
  `mobile/test/features/activity/repository/activity_consent_switch_wiring_test.dart` (17 tests: the real startup closure
  with recording fakes and with the real client, store and uploader),
  `mobile/test/features/activity/e2e/s02_consent_switch_e2e_test.dart` (2 tests over the real `FileActivityJournal`).
- Updated stale tests: `mobile/test/support/stream_upload_world.dart` (`FakeConsent.consentUid`/`followUid`), five `_Settings`
  fakes (`reset()`), `activity_wiring_account_switch_test` (resume-throws log text and the sync that now precedes it),
  `activity_stream_upload_test` (write with no account throws), `activity_stream_upload_account_binding_test` and
  `activity_stream_uploader_account_switch_test` (consent follows the flipped uid).

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | Remediation H-A production code compiled unchanged and met every oracle I wrote; no production defect found | n/a | first compiled runs |
| 2 | Five `_Settings` fakes threw `UnimplementedError: reset` (the wiring now calls `reset()`) | H-A authors (listed in the notes) | first run of `activity_wiring_account_switch_test`: `+5 -9` then `+17 -9: Some tests failed.` |
| 3 | Uploader tests that flip the uid (account binding, uploader account switch) got `skipped` instead of `cancelled` because the consent view was uid-agnostic; the notes named only the in-memory-client tests | H-A notes (incomplete list) | `+0 -7` and `+0 -6`; fixed with `FakeConsent.followUid` |
| 4 | Older assertions: resume-throws expected the outer log text and no backend call; write-before-sign-in expected a silent drop | H-A notes (second was listed, first was not) | `+13 -1` and `+10 -1` |
| 5 | My oracle slips: 16d expected B to proceed while A held the scoped-journal bind (binds are serialized); the e2e expected B to proceed while A held `syncAll` (the repository is single-flight). Both now release A first | me | first runs (`+41 -1`, `+1 -1`) |

### Commands and results (from `D:\Repo\Fitness_App_Phase2_s01\mobile`)

- First compiled run, `flutter test --timeout 60s test/features/activity/repository/activity_wiring_account_switch_test.dart`: `01:05 +17: ... -9: Some tests failed.` (defect 2); fixed.
- After the `reset()` fix: `+13 -1: ...` / `+25 -1: Some tests failed.` (defect 4); fixed.
- Per file after the fixes: wipe_wiring `+16`, republish `+21`, flag_matrix `+23`, consent_withdrawal `+12`, stream_upload `+29`, account_binding `+20`, uploader_account_switch `+7`, account_switch `+26`, retry `+22`, all ending `All tests passed!`.
- New files: `flutter test --timeout 60s test/features/activity/repository/activity_consent_switch_wiring_test.dart test/features/activity/repository/activity_consent_account_binding_test.dart` -> first `+41 -1` (defect 5), then `+42: All tests passed!`.
- `flutter test --timeout 60s test/features/activity/e2e/s02_consent_switch_e2e_test.dart` -> first `+1 -1` (defect 5), then `+2: All tests passed!`.
- FINAL, complete set (my files, whole repository and e2e directories, config): `flutter test --timeout 60s -r failures-only test/features/activity/repository test/features/activity/e2e test/features/activity/config` -> `+784: All tests passed!`

### Not verified / remains

- No mutation run (operator rule); each test's falsifiability is argued from its assertions (zero create/PUT/commit,
  `boundUid`, `consentUid`, call counts and returned outcomes that change if the uid check, generation guard or
  re-verification after an await were removed).
- The `accountBeingDeleted` supplier inside the real `activityStreamUploaderProvider` and `activityRootOverrides` is not
  tested (they build Firebase objects with no seam); the uploader and repository guards themselves are tested directly.
- The platform preferences store is a fake; real plugin timing is not covered.
- `flutter analyze`, the full suite and builds were not run by design.
