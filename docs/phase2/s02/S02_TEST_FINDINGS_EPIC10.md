# S02 test findings, epic 10

Sections are appended per agent. Agent 10b appends its own section below.

## Epic 10a: conflict view error, loading and retry states (FL1, FL2)

Oracles: `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md` (FL1, FL2) and the Flutter review of remediation C (commit 0b6a2aa0). Production code under test had never been compiled or run.

### Files
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart` (7 tests): real `ActivitySyncRepository` over the in-memory journal harness; a scripted backend (`FirebaseException` permission-denied from `readSummary`) and a flaky journal wrapper (`list()` throws).
- `mobile/test/features/activity/widgets/sync_conflict_sheet_states_test.dart` (8 tests): real presenter and widgets over a repository subclass whose `watch()` stream the test controls.

### Coverage map
| Contract | Test |
| --- | --- |
| FL1: generic backend read failure keeps the conflict, `cloudKnown: false`, no fields, no zone error, no stream error | state test 1 |
| FL1: failed read is not cached | state test 2 |
| FL1: journal `list()` failure is a stream error, no zone error, no silent empty state | state test 3 |
| FL2 presenter: `loaded false` before first emission; `loadFailed true, loaded false` after failure; retry re-subscribes and recovers; repeated failure | state tests 4-7 |
| FL2 sheet: spinner (`activitySync.loading`) and no empty text before first emission; empty text after a loaded empty state | widget test 1 |
| FL2 sheet: error + retry after a stream error; retry re-subscribes (`watch()` twice), error cleared, loading again, then the conflict card | widget tests 2-4 |
| Entry card: hidden while loading and when loaded empty; visible with items; visible on load failure and opens the sheet with error + retry; flag off builds nothing and never watches | widget tests 5-8 |

### Defects
- D10a-1 (MAJOR): `ActivitySyncEntryCard` returned `SizedBox.shrink()` whenever `hasItems` was false, including when `loadFailed` was true. After a load failure the user could never open the sheet, so the retry action was unreachable. Reproduced by the widget test "visible when the load failed" (found 0 widgets with key `activitySync.entryCard`). Fix: `mobile/lib/features/activity/widgets/activity_sync_entry_card.dart` now shows the card when `hasItems || loadFailed`. Test green after the fix.
- No compile errors and no other defects found in remediation C (FL1 repository and presenter code, FL2 sheet states behaved as specified).

### Notes
- Entry card while `loaded` is false and no error: stays hidden (no items yet). This is as the notes imply; not a defect.

### Run
Command (from `mobile/`):
`flutter test test/features/activity/state test/features/activity/widgets test/features/activity/repository/activity_sync_test.dart test/features/activity/repository/activity_sync_corrupt_summary_test.dart`
Summary line: `00:10 +47: All tests passed!`

### Not covered
Pixels and layout of the sheet (NOT_RUN by design); the real Firestore adapter; FL5 and FL6 (agent 10b).

## Epic 10b (agent 10b): uploader account binding, wiring, flag matrix, rules mirror

### Tests written
- `mobile/test/features/activity/repository/activity_stream_upload_account_binding_test.dart` (20): uid flip to another uid and to null before create, PUT, commit, `markStreamUploaded` and the `upload_failed` mark -> `cancelled`, no later call, no mark; `runPending` stops before the next entry; single-flight for `runPending` and `uploadEntry`.
- `mobile/test/features/activity/repository/activity_wiring_account_switch_test.dart` (20): cancel on A->B, A->null, A->guest; resume only after a successful claim and a still-matching uid; failed claim calls no resume/syncAll/runPending; FL6 exceptions are logged and do not escape; flag-off has no side effects.
- `mobile/test/features/activity/config/activity_flags_test.dart` (12) and `activity_wiring_flag_matrix_test.dart` (22): flag matrix of the D notes.
- `mobile/test/features/activity/data/primary_source_id_parity_test.dart` (27): Dart mirror vs `schema.ts` (lines 128, 168, copied literally) vs `firestore.rules` on one table.
- `mobile/test/support/stream_upload_world.dart`: `makeUploader` takes an optional `currentUid` (additive).

### Defects
- D10b-1 (test defect, caused by remediation C): the fake `_Uploader` in `activity_journal_wipe_wiring_test.dart` (epic 9b) did not implement `cancelQueued()` and `resume()`, which the wiring now calls. The guarded closure caught the resulting error, so 3 tests ("wipe works", "same uid", "unclaimed journal") failed because `runPending` was never reached. Fixed by adding both no-op overrides to the fake.
- No compile errors and no production defects found in remediation C (uploader binding, single-flight, wiring guard) or remediation D (flag, wiring, rules mirror); every new test passed on first run after trivial test-code fixes.

### Notes
- An auth stream error keeps the last known uid (Riverpod keeps the previous value), so a stream error mid-claim does not cancel the claim. This is not specified by the notes and was not pinned.

### Run
Command (from `mobile/`):
`flutter test test/features/activity/repository/activity_stream_upload_account_binding_test.dart test/features/activity/repository/activity_wiring_account_switch_test.dart test/features/activity/config test/features/activity/data/primary_source_id_parity_test.dart test/features/activity/repository/activity_stream_upload_test.dart test/features/activity/repository/activity_stream_upload_retry_test.dart test/features/activity/repository/activity_consent_withdrawal_test.dart test/features/activity/repository/activity_journal_wipe_wiring_test.dart test/features/activity/data/summary_allowlist_parity_test.dart test/features/activity/data/activity_cloud_summary_test.dart test/features/activity/data/summary_golden_test.dart test/features/activity/repository/firestore_activity_repository_test.dart test/features/activity/e2e`
Summary line: `02:41 +263: All tests passed!`

### Not covered
Real Firebase/Firestore adapters, a real device keystore for `openActivityJournal` (secure storage and path_provider are faked), `--dart-define` reading of `compileTime` (default build only), the Functions-side tests.
