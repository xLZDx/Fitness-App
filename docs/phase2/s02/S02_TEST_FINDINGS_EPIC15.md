# S02 test findings, epic 15 (remediation I)

## Epic 15

Head under test: 61389563 (remediation I), test commits 7dfa4780, af1f0101, 866a05b3 and the final commit of this section. Oracles: `S02_REMEDIATION_H_TEST_NOTES.md` heading I, design section 17 item 24. Remediation I was written by an implementer who compiled nothing.

### Files

- Changed production code (one): `mobile/lib/core/wiring/activity_wiring.dart` (the early `current()` check also logs `account is being deleted; sync not started`).
- Updated stale tests: `activity_consent_withdrawal_test.dart`, `activity_stream_upload_test.dart` (bound in-memory store), `activity_consent_switch_wiring_test.dart`, `activity_wiring_account_switch_test.dart`, `activity_journal_wipe_wiring_test.dart`, `s02_consent_switch_e2e_test.dart` (new start order and "consent failure does not block bind and sync").
- New: `mobile/test/features/activity/repository/activity_sync_display_tie_test.dart` (7), `mobile/test/features/activity/widgets/sync_conflict_sheet_display_tie_test.dart` (3), `mobile/test/features/activity/repository/activity_consent_unbound_test.dart` (9).

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | Remediation I compiled unchanged; no compile error | n/a | first run |
| 2 | 27 existing tests were stale: 14 on an unbound `InMemoryCloudStreamsConsentStore` (12 withdrawal, 2 stream upload), 13 on the old start order or on "a consent failure blocks bind and sync". The notes missed `s02_consent_switch_e2e_test.dart`, the bind-failure case in `activity_journal_wipe_wiring_test.dart` and the FL6 load-throws case | notes (incomplete stale list), author | baseline whole-directory run `+1362 -27: Some tests failed.` |
| 3 | Production regression: the new early `current()` check returned silently before the branch that logged `account is being deleted; sync not started` (G4 in `activity_republish_wiring_test.dart` failed) | author, notes | baseline run; fixed with a log in the early check |
| 4 | My test slips: wrong import (`ActivitySyncState` lives in `sync_models.dart`), listener exception reported to the container zone (fixed with a guarded zone), a pumped sheet with a loaded real-repository state hung the fake-async binding for minutes with no timeout firing (control moved to the presenter; cause not investigated) | me | first runs |
| 5 | I1 and I2 production code met every new oracle; no further defect | n/a | new tests |

### Commands and results (from `D:\Repo\Fitness_App_Phase2_s01\mobile`)

- Baseline: `flutter test --timeout 60s -r failures-only test/features/activity` -> `+1362 -27: Some tests failed.`
- After the stale fixes (ten affected files): `flutter test --timeout 60s -r failures-only test/features/activity/repository/activity_consent_withdrawal_test.dart test/features/activity/repository/activity_stream_upload_test.dart test/features/activity/repository/activity_consent_switch_wiring_test.dart test/features/activity/repository/activity_wiring_account_switch_test.dart test/features/activity/repository/activity_journal_wipe_wiring_test.dart test/features/activity/repository/activity_republish_wiring_test.dart test/features/activity/e2e/s02_consent_switch_e2e_test.dart test/features/activity/config/activity_wiring_flag_matrix_test.dart test/features/activity/repository/activity_tombstone_continuation_test.dart test/features/activity/repository/activity_consent_account_binding_test.dart` -> `+205: All tests passed!`
- I1 repository tests: `flutter test --timeout 60s test/features/activity/repository/activity_sync_display_tie_test.dart` -> `+7` all passed (seen in the combined run); widget file `flutter test --timeout 60s test/features/activity/widgets/sync_conflict_sheet_display_tie_test.dart` -> `00:02 +3: All tests passed!`
- I2: `flutter test --timeout 60s test/features/activity/repository/activity_consent_unbound_test.dart` -> `00:01 +9: All tests passed!`
- FINAL 1 (head 866a05b3, clean tree): `flutter test --timeout 60s test/features/activity` -> `02:47 +1410: All tests passed!`
- FINAL 2 (head 866a05b3, clean tree): `flutter test --timeout 60s test/features/account_deletion test/core/architecture test/android/backup_rules_test.dart test/features/safety/health_rules_parity_test.dart test/adversarial/n07_team_activation_test.dart` -> `00:10 +120: All tests passed!`
- Server check: `git diff --stat cf1a4eb5..HEAD -- functions firestore.rules storage.rules firestore.indexes.json public scripts` -> empty output (no change). Jest not run.

### Not verified / remains

- No mutation run (operator rule); falsifiability is argued from assertions (list() call count zero, JournalUnbound, zero requests, boundUid null, zero create/PUT/commit).
- I1 candidates are not seeded (the guard sits before the journal read, so conflicts stand for both); `_viewCurrent` tie alone is not separable from the supplier compare.
- A loaded real-repository state in a pumped widget hangs the fake-async binding; unexplained, the presenter test covers the same state.
- A throwing `onAccountChanged` still surfaces as an uncaught listener error and skips `cancelQueued` and the new account's start (consent is unbound first, which is the guarantee); not changed.
- `flutter analyze`, builds, jest and the rules emulator were not run by design.
