# S03 test findings, step 1 (EP-0 and EP-1)

Head revision: 5bb24fcc (worktree D:\Repo\Fitness_App_Phase2_s01, branch phase2/s03d-ui-design-contract). Nothing committed.
Flutter: `where flutter` resolved to D:\flutter\bin\flutter (Flutter 3.27.1, Dart 3.6.0, revision 17025dd882).

## NEWEST RESULT (head fca06cba, same-uid re-emission fix)

Four regression tests added to `mobile/test/features/activity/journal_availability_test.dart`: DT-0-17a (bound journal plus a same-uid AuthUser with a changed display name, twice: `bindUid` called once, availability stays Open, status and generation unchanged), DT-0-17b (retry armed after a failed first bind plus a same-uid re-emission: no new attempt, the 5 s timer object stays active and is not replaced, the generation is unchanged, the original deadline still fires and the next delay is 15 s, so the index was kept), DT-0-17c (after gaveUp a same-uid re-emission restarts the bind: 7th `bindUid`, availability Open, generation increased), DT-0-17d (a uid change restarts, a sign-out unbinds with no timer, signing in again as A after the sign-out binds again).
Complete set of the 13 files, which includes the unchanged `activity_journal_binding_retry_test.dart`, same command as Run 1, real tree: `+144: All tests passed!` (144 passed, 0 failed, 0 not run). No production defect found in this round.

## Previous result (head 4b52baca, includes fe67291b)

Complete set of the 13 files, same command as Run 1, real tree: `+140: All tests passed!` (140 passed, 0 failed, 0 not run). D6 and D7 are fixed in production (DT-01-23 passes). DT-01-9 first failed against the fix only because its rule did not know the new loading frame (greeting only); that was a test defect, now the test accepts an empty frame or the greeting-only frame and still fails for any TRAIN-ordered or other partial frame. It passes.

Existing Home tests, `flutter test --timeout 90s test/features/home` (run unchanged, real tree): `+82: All tests passed!` (includes home_mode_lens_test.dart and the existing Home tests). No existing Home test failed because of the greeting-only first frame.

Note: a first attempt of this re-run collided with a concurrent `flutter test` of another agent on the shared build cache (`PathExistsException ... cache.dill.track.dill`); it was repeated and the numbers above come from the repeat.

## UPDATE after production fixes (head 8a5c7474)

Same command as Run 1 below, re-run in the real tree at head 8a5c7474: `+138 -2`, all 13 files load. The two failures are production defects that remain: D6 (home_page.dart:199, DT-01-9) and D7 (mode_providers.dart:178, DT-01-23). D1 to D5 (compile errors) are resolved by 8a5c7474. The unchanged `activity_journal_binding_retry_test.dart` passes. Every "NOT_RUN (D1..D5)" and "NOT_RUN" cell in the table below is now PASS, except DT-01-9 (FAIL, D6) and DT-01-23 (FAIL, D7). The real-tree numbers below are the pre-fix Run 1 and are kept for history.

## Commands

Run 1 (the real tree, the evidence of record), from `D:\Repo\Fitness_App_Phase2_s01\mobile`:

```
flutter test --timeout 90s test/features/activity/journal_availability_test.dart test/features/activity/repository/activity_journal_binding_retry_test.dart test/features/activity/config/activity_wiring_flag_matrix_test.dart test/features/activity/config/activity_flags_test.dart test/android/backup_rules_test.dart test/features/activity/repository/backup_exclusion_test.dart test/features/modes/mode_flags_test.dart test/features/modes/mode_state_test.dart test/features/modes/mode_migration_test.dart test/features/modes/mode_onboarding_hook_test.dart test/features/modes/mode_timer_isolation_test.dart test/features/modes/mode_ui_seams_test.dart test/features/account_deletion/mode_key_wipe_test.dart
```

Result in the real tree: `+83 -5`. Four files do not load (production compile errors, section "Production defects"), and one test fails (DT-01-23). All other loaded tests pass.

Run 2 (DIAGNOSTIC ONLY, not evidence for the production tree): the same 13 files in a scratch copy of the tree (`<scratchpad>/w/mobile`, copied with `tools/sync.sh`) in which ONLY the production compile errors were patched with the minimal fixes proposed below, to find out whether the tests themselves are right. Result: `+138 -2`; the two failures are the production defects D6 and D7. The scratch copy is not part of the repository.

## Counts

Written or updated: 13 files, 140 tests (counted from run 2; 138 pass, 2 fail). Real tree: 84 tests executed (83 passed, 1 failed), 56 tests could not be executed because their files fail to compile (NOT_RUN: production compile errors). Not run for lack of implementation: none of the rows, but see "Partial rows".

Files NEW: `mobile/test/features/activity/journal_availability_test.dart`, `mobile/test/features/modes/{mode_flags,mode_state,mode_migration,mode_onboarding_hook,mode_timer_isolation,mode_ui_seams}_test.dart`, `mobile/test/features/account_deletion/mode_key_wipe_test.dart`, support `mobile/test/support/{bind_fakes,mode_fakes}.dart`.
Files UPDATED: `mobile/test/features/activity/config/activity_flags_test.dart` (default is now journal on, cloud off), `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart` (+2 default-build tests), `mobile/test/features/activity/repository/backup_exclusion_test.dart` (+DT-0-6, DT-0-7, DT-0-8 and a parser control). `mobile/test/android/backup_rules_test.dart` needed no edit (it already derives its expectation from `androidBackupExclusions()`, 8 entries per section) and is run as is. `activity_journal_binding_retry_test.dart` is UNCHANGED.

## Status per test id

| Id | File | Real tree | Scratch (patched compile errors) |
|---|---|---|---|
| DT-0-1, DT-0-2, DT-0-3a, DT-0-3b, DT-0-4, DT-0-5, DT-0-9, DT-0-10, DT-0-11, DT-0-12, DT-0-13, DT-0-14, DT-0-15a, DT-0-15b, DT-0-16 | journal_availability_test.dart | NOT_RUN (file does not compile: D1, D2) | PASS |
| DT-0-6, DT-0-7, DT-0-8 (+ parser control) | repository/backup_exclusion_test.dart | PASS | PASS |
| existing backup rules tests | android/backup_rules_test.dart | PASS | PASS |
| S03-0 default flags | config/activity_flags_test.dart | PASS | PASS |
| S03-0 default build in the flag matrix | config/activity_wiring_flag_matrix_test.dart | NOT_RUN (D1, D2) | PASS |
| binding retry regression (unchanged file) | repository/activity_journal_binding_retry_test.dart | NOT_RUN (D1, D2) | PASS, no assertion failed |
| mode flags | modes/mode_flags_test.dart | PASS | PASS |
| DT-01-1, 2, 3, 4, 5, 6, 11, 17, 18, 19, 21, 25 | modes/mode_state_test.dart | PASS | PASS |
| DT-01-23 | modes/mode_state_test.dart | FAIL (D7) | FAIL (D7) |
| AC-CH-8a (provider seam), AC-CH-8b, DT-01-10, 12, 13, 14, 16, 22 | modes/mode_migration_test.dart | PASS | PASS |
| AC-CH-8c, AC-CH-8d (x2), DT-01-15 (hookThrows, unmounted) | modes/mode_onboarding_hook_test.dart | PASS | PASS |
| DT-01-7 | modes/mode_timer_isolation_test.dart | PASS | PASS |
| DT-01-8 | modes/mode_ui_seams_test.dart | NOT_RUN (D3, D4, D5) | PASS |
| DT-01-9 | modes/mode_ui_seams_test.dart | NOT_RUN (D3, D4, D5) | FAIL (D6) |
| DT-01-20, DT-01-24 | account_deletion/mode_key_wipe_test.dart | PASS | PASS |

## Production defects (no production file was edited)

| Id | Sev | Where | Evidence | Proposed minimal fix | Blocks |
|---|---|---|---|---|---|
| D1 | BLOCKER | mobile/lib/core/wiring/activity_wiring.dart:393 | `Error: The getter 'lastRecoveryReport' isn't defined for the class 'AccountScopedJournal'` (`final source = scoped; if (source is! RecoveryReportSource) return;` does not promote to an unrelated interface) | `final Object source = scoped;` | every test that imports the wiring (availability, retry regression, flag matrix, any app boot) |
| D2 | BLOCKER | mobile/lib/features/activity/state/journal_availability.dart:80 | `Error: The getter 'isBound' / 'boundUid' isn't defined for the class 'ActivityJournal'` (line 70 `journal is! AccountScopedJournal` does not promote an `ActivityJournal`) | use a pattern: `switch (journal) { case final AccountScopedJournal s: ... }` or `(journal as AccountScopedJournal).isBound` | same as D1 |
| D3 | BLOCKER | mobile/lib/features/modes/pages/mode_chooser_page.dart:210 | `Error: Expected 0 type arguments` for `context.pushReplacement<void>(path)`; with the type argument removed the next error is `This expression has type 'void' and can't be used` for `unawaited(...)` | `context.pushReplacement(path);` (go_router 16 returns void) | the chooser page and every test importing it |
| D4 | BLOCKER | mobile/lib/shared/widgets/adaptive_surface.dart:172 and :307 | :172 `Method 'opened' cannot be called on 'OpenSurfaceDepth?' because it is potentially null`; :307 `'KeyDownEvent' isn't a type` (import is `show LogicalKeyboardKey`) | :172 `depth!.opened()` (or guard); :307 add `KeyDownEvent` to the `show` list | Home, chooser, sheets |
| D5 | BLOCKER | mobile/lib/features/progress/widgets/progress_activity_widgets.dart:159 (constructor at :128) | `No named parameter with the name 'key'` for `_SourcesRow(key: ...)` | add `super.key` to `_SourcesRow({super.key, required this.title, this.subtitle})` | Home/Progress imports |
| D6 | MAJOR | mobile/lib/features/home/home_page.dart:199 (`homeLensOf(modeState?.selectedMode ?? AppMode.train)`; `modeState` is null while the mode state loads, :194-196) | DT-01-9 (scratch run): with stored BODY and a delayed read, frame 0 renders the TRAIN section order (`... dayPanel, week, recovery, quickScan, bodyScan ...`) and only later the BODY order (`... dayPanel, bodyScan, nutrition, week ...`). Contract 4.2: no flash of the wrong mode | while `modeState` is null render a loading frame (no lens sections) instead of defaulting to TRAIN | contract 4.2 |
| D7 | MINOR (debug-only crash, release returns the right value) | mobile/lib/features/modes/state/mode_providers.dart:178 (`ModeNotifier._refusal`, `ref.read(authUserProvider)`) | DT-01-23: a stale notifier used after the auth user changed but before the rebuild throws `AssertionError: Cannot use ref functions after the dependency of a provider changed but before the provider rebuilt` (element.dart:675) instead of returning `saveFailed` | keep the current auth uid in a field refreshed by a `ref.listen`, or catch the assertion and return `saveFailed` | AC for stale references |

More compile errors may exist in files none of my tests import; run 2 shows that after D1 to D5 the tests of this step compile.

## Notes and plan inconsistencies found

- Plan DT-0-7 says "7 entries"; the real count is 4 constants and 8 entries per XML section (4 older ones plus 4 journal ones). The tests use the constants, so they do not hard-code 7.
- Plan DT-01-1 lists an unknown mode string as `unreadable(corrupt)`; the codec and design 5.1 return a value with `train` in memory (the test asserts the codec behaviour and zero writes).
- Plan DT-0-9 "counts are kept after gaveUp": in the code the counts are only read after a successful bind; the test covers gave up followed by a manual success.
- DT-01-12 as implemented: the migration never decides for a profile that was not onboarded first, so both interleavings end as `pending` with one write; plus a direct test that two concurrent `initIfAbsent` calls write once.

## Partial rows and remaining unverified items

- AC-CH-8a: proved at the provider seam (store holds `migrated` + `train` after the warm-up, before any UI). The "first Home frame and router location /home" part with the real app router and real Home is NOT_RUN (needs the real app boot; D3 to D5 block it in the real tree).
- DT-0-4: the dashboard widget in the `notEnabled` scope ("no error, no retry") is NOT_RUN: the dashboard widgets belong to a later step.
- DT-0-2: proved with provider results (uploader and withdrawal null, sync repository not built, override list length 1 versus 2); there are no network or upload spies because the cloud objects are never constructed with the flag off.
- DT-01-21: uses a host that watches `modeWarmUpProvider` exactly as `FitnessApp.build` does, with a positive control that a `modeStateProvider` watcher does rebuild; the real `FitnessApp` was not counted.
- DT-01-8 expects the location after the write to be `/home` or `/mode-questions/train`.
- Rows of the other test files in `mobile/test/features/modes/` (chooser, record sheet, sources) were written by another agent and are not part of this step; they were not run for this report.
- No device, no mutation run, no analyzer. Run 2 is diagnostic and must be repeated in the real tree after D1 to D5 are fixed.
