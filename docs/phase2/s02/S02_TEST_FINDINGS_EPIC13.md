# S02 test findings, epic 13 (remediation G)

## Epic 13a (G1 to G5)

Head under test: fc63ec62 plus the test commits of this epic (993228e2, 5edb610e, f8e21553, c4a03ce2 and the final
commit of this section). Oracles: `S02_REMEDIATION_F_TEST_NOTES.md` heading G, design section 17 item 23, the promise
"nothing of account A reaches account B".

### Files

- New: `mobile/test/features/activity/repository/activity_sync_auth_tie_test.dart` (17 tests: G1 and G5),
  `mobile/test/features/activity/repository/activity_republish_wiring_test.dart` (21 tests: G2, G3, G4),
  `mobile/test/features/activity/e2e/s02_auth_flip_e2e_test.dart` (2 tests, real `FileActivityJournal`).
- Updated stale tests: `uid_scoped_activity_journal_test.dart` (2), `uid_scoped_journal_wipe_rebind_test.dart` (1),
  `s02_account_wipe_e2e_test.dart` (1), `activity_wiring_account_switch_test.dart` (`_ThrowingSyncRepo`),
  `file_activity_journal_encryption_test.dart` (flaky assertion, defect 4).

### Defects and shortcomings

| # | What | Layer that missed it | Layer that caught it |
|---|------|----------------------|----------------------|
| 1 | Remediation G production code compiled unchanged and met every G1 to G5 oracle; no production defect found | n/a | first compiled runs |
| 2 | Four older tests expected `bindUid(U)` to succeed after `wipeForUid(U)` of an unbound U (G4 refuses until `bindUid(null)`) | G authors: the stale-test list named fakes, not these assertions | first whole-directory run `+1260 -4: Some tests failed.` |
| 3 | `_ThrowingSyncRepo` lacked `onJournalBindingChanged` (a Fake would throw, swallowed by the wiring) | G authors (listed in notes, fixed) | test review |
| 4 | Pre-existing FLAKY test: I07 in `file_activity_journal_encryption_test.dart` searched the whole random ciphertext for the two bytes 1F 8B (probability about n/65536 per run); failed once in the second whole-directory run (`+1303 -1`), passed 3 of 3 reruns alone | epic 4 test author (an unsound oracle on random data) | second whole-directory run; fixed to check the header position only |
| 5 | My own oracle slips in the G4 tests: `wipeForUid` of an unbound uid opens the scope once to delete it, so "the factory is never asked" was wrong; corrected to "`bindUid` asks it no more" and no new file, directory or key | G notes author; me | first run of the new file (`+16 -3`) |
| 6 | The guard path `test/safety/health_rules_parity_test.dart` named in the brief does not exist; the real path is `test/features/safety/health_rules_parity_test.dart` | brief | ls / Glob |

### Commands and results (from `D:\Repo\Fitness_App_Phase2_s01\mobile`)

- `flutter test --timeout 60s test/features/activity` (first compiled run, failures-only reporter): `+1260 -4: Some tests failed.` (defect 2); fixed.
- `flutter test --timeout 60s test/features/activity/repository/activity_sync_auth_tie_test.dart`: `00:03 +17: All tests passed!`
- `flutter test --timeout 60s test/features/activity/repository/activity_republish_wiring_test.dart`: first `+18 -3: Some tests failed.` (defect 5), then `+21: All tests passed!`
- `flutter test --timeout 60s test/features/activity/e2e/s02_auth_flip_e2e_test.dart`: `00:01 +2: All tests passed!`
- `flutter test --timeout 60s test/features/activity` (second complete run): `+1303 -1: Some tests failed.` (defect 4); fixed.
- FINAL, whole directory, one command: `flutter test --timeout 60s test/features/activity` -> `03:25 +1304: All tests passed!`
- FINAL, guards: `flutter test --timeout 60s test/features/account_deletion test/core/architecture test/android/backup_rules_test.dart test/features/safety/health_rules_parity_test.dart test/adversarial/n07_team_activation_test.dart` -> `00:09 +120: All tests passed!`

### Not verified / remains

- No mutation run (operator rule); each new test's falsifiability is argued from its assertions (call counts and returned
  outcomes that change if the tie, the publish call, the raw-uid check or the marker were removed).
- The conflict-cache clearing on an anonymous to real transition is asserted through the `onAccountChanged` call in the
  wiring plus the 12a cache test, not in one combined test.
- The two accepted limits of design 17 item 23 (e, f) are documented behaviour and untested by design.
- `flutter analyze`, the full suite and builds were not run by design.
