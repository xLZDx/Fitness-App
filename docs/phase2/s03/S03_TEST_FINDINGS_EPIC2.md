# S03 test findings, step 3 (EP-2: S03-08 to S03-11)

## Final run (latest): head 0969258b

Head revision: 0969258b (branch phase2/s03d-ui-design-contract, worktree D:\Repo\Fitness_App_Phase2_s01; includes 8a5c7474, fe67291b and fix batch 3). Real tree, no scratch copy.
Flutter: /d/flutter/bin/flutter (D:/flutter/bin/flutter), Flutter 3.27.1 stable, Dart 3.6.0. Run from `mobile/`.

Command (complete set of the files written in this step):

    flutter test --timeout 60s test/features/modes/mode_chooser_test.dart test/features/modes/mode_questions_test.dart test/features/modes/mode_switcher_test.dart test/features/modes/record_sheet_test.dart

Result line: `00:23 +96: All tests passed!` (96 written, 96 PASS, 0 FAIL, 0 skipped).
Per file: mode_chooser_test.dart 45, mode_questions_test.dart 20, mode_switcher_test.dart 16, record_sheet_test.dart 15 (all PASS).

History: 5bb24fcc: real tree did not compile (P-1 to P-5), triage in a scratch copy: 93 PASS, 3 FAIL. 8a5c7474 (compile fixes): real tree 93 PASS, 3 FAIL (DT-08-1b, DT-11-3, rail Record slot). 0969258b: all 96 PASS. The Record opener override in record_sheet_test.dart (`shellRecordSheetOpenerProvider.overrideWithValue(openRecordSheet)`) needed no change; the loading-outline change (P-7) added no failing semantics or focus assertion.

Production defects verified fixed at 0969258b by the same tests that failed before: P-6 (DT-08-1b), P-8 (DT-11-3), P-9 (rail Record slot placement test). P-7 (DT-08-3 only observed it) was not re-measured separately; the test passes.

Open production items at 0969258b:
- P-8b, MINOR: mobile/lib/features/modes/widgets/record_sheet.dart (`recordRowsFor`, body branch) still has no FOOD_AI or FOOD_LOOKUP input. Test DT-11-1b documents this by asserting 3 body rows always (it PASSES by asserting current behaviour; it will go red if flags are added, then replace it with the contract test). AC-RC-3 /flagsOff and DT-11-1 (BODY with all tiles hidden) remain weak/partial.

Superseded status notes below (the table at 8a5c7474) show the 3 earlier FAIL rows; they now PASS.

Files written (test code only; no production file was edited):
- mobile/test/features/modes/mode_epic2_harness.dart
- mobile/test/features/modes/mode_chooser_test.dart, mode_questions_test.dart, mode_switcher_test.dart, record_sheet_test.dart

## Status per test id

Names carry the plan id first. `/ru` `/en` suffixes run both locales (only AC-CH-1, 2, 3, 9 and AC-Q-4 run both; the other rows run `en`, a deviation: the plan asks both locales for every row; ru copy only differs, AC-CH-13/scale2ru runs `ru`).

### mode_chooser_test.dart (S03-08)
| Id | Status | Note |
|---|---|---|
| AC-CH-1 (ru, en) | PASS | Rect order and semantics traversal order |
| AC-CH-2 (ru, en) | PASS | sheet opens, zero writes, Continue disabled |
| AC-CH-3 (ru, en) | PASS | one selected card (widget flag and semantics) |
| AC-CH-4 | PASS | decide later + restart (stub Home and real Home) |
| AC-CH-5 pending / resolved / migrated, restart | PASS | real HomePage |
| AC-CH-6 | PASS | |
| AC-CH-7 (360, 1100) | PASS | permission, location, camera, picker channels counted: zero |
| AC-CH-9 (ru, en) | PASS | |
| AC-CH-10 (5 sizes) | PASS | |
| AC-CH-11 | PASS | |
| AC-CH-12 (599, 839, 840) | PASS | |
| AC-CH-13 hoverFocus, scale2ru | PASS | |
| AC-CH-14 | PASS | |
| AC-LS-7 | NOT_RUN by design | alias, N=0; its six tests exist under AC-CH-9..14 names with the tag `[AC-LS-7]` on AC-CH-9 and the AC-CH-10 group |
| AC-LS-11 idle, touchSelect | PASS | |
| DT-08-1 | PASS | arrow keys follow the grid |
| DT-08-1b (added) | PASS at 0969258b (FAIL at 8a5c7474) | defect P-6 fixed |
| DT-08-2 | PASS | uses TRAIN with a known training context (BODY goes to the questions page) |
| DT-08-3 | PASS | order and columns asserted, vertical shift see P-7 |
| DT-08-4 | PASS | opened from the real switcher "See all modes" |
| DT-08-5 | PASS | |
| DT-08-6 | PASS | |
| DT-08-7 (4 tests: pending, failing write, kill, resolved pushed) | PASS | |
| DT-08-8 | PASS | real HomePage, write forced to fail so status stays pending |
| DT-08-9 | PASS | real HomePage, Day-3 gate with a completer, modal shown, then settled |
| DT-08-10 | PASS | |

### mode_questions_test.dart (S03-09)
| Id | Status | Note |
|---|---|---|
| AC-Q-1 (answered, skipped, plus unanswered control) | PASS | |
| AC-Q-2 | PASS | |
| AC-Q-3 food / photos | PASS | order read with the production `homeSectionOrder` |
| AC-Q-4 (en, ru x TRAIN, BODY) | PASS | each mode has one question, so "never more than 3" is trivially true |
| AC-Q-5 | PASS | |
| AC-Q-6 | PASS | semantics disabled and reason in hint |
| DT-09-1, DT-09-2, DT-09-3 | PASS | |
| DT-09-4 | PARTIAL (PASS as single-question reduction) | no mode has two questions (`mode_question_plan.dart:76-99`); only "Back at question 1 writes nothing" is checked |
| DT-09-5 | PARTIAL (PASS as single-question reduction) | answer survives a kill and is not asked again; the "remaining one offered once" half cannot be built |
| DT-09-6 (xyz, ride, explore) | PASS | |

### mode_switcher_test.dart (S03-10)
| Id | Status | Note |
|---|---|---|
| AC-SW-1 | PASS | real HomePage and chip, two taps, visible section order equals BODY order |
| AC-SW-2 | PASS | real SetTimerController and RestTimerController with injected rest clock in the real MainShell; state and strip label unchanged, set timer still ticks. Rest timer remaining time is not re-read after the clock advance (rest deadline is wall-clock; only equality of `endsAt` is asserted) |
| AC-SW-3 scrim, sameMode (+ control) | PASS | write spy and ModeChanged bus listener |
| AC-SW-4 | PASS | |
| AC-SW-5 ride, explore | PASS | |
| AC-SH-4 | PASS | location and `HudNavBar.selectedIndex` unchanged |
| DT-10-1 | PASS | |
| DT-10-2 | PASS (partial) | ARB plural forms asserted for 1, 2, 5, 21 (ru, en); the rendered switcher can only show the count 1 because each mode has at most one question |
| DT-10-3 | PASS | |
| DT-10-4 | PASS | |
| DT-10-5 | PASS | |

### record_sheet_test.dart (S03-11)
| Id | Status | Note |
|---|---|---|
| AC-RC-1 | PASS | |
| AC-RC-2 none, scheduled | PASS | clock is `DateTime.now()` inside production (`record_sheet.dart:193`); the test uses now, so a midnight rollover could flake |
| AC-RC-3 flagsOff | PASS (weak) | production has no flag input for the meal row; the test proves one meal row that leads to `/nutrition/add` only. The contract text "meal rows equal the add_food_page tile set" cannot be checked: recordRowsFor ignores FOOD_AI and FOOD_LOOKUP |
| AC-RC-3 refused | PASS | |
| AC-RC-4 | PASS | store writes and SharedPreferences keys unchanged |
| AC-RC-5 | PASS | |
| DT-11-1 | PARTIAL | the empty state is proven with an enabled Ride (no rows); "BODY with every tile flag-hidden" cannot happen (P-8b), asserted as a contract note test `DT-11-1b` which PASSES by asserting current behaviour (3 body rows always) |
| DT-11-2 (+ control) | PASS | |
| DT-11-3 | PASS at 0969258b (FAIL at 8a5c7474) | defect P-8 fixed |
| DT-11-4 | PASS (partial) | source scan of `app_router.dart` for every destination path of `recordRowsFor`; the full "navigate with the real router" layer was not built |
| placement: anchored show popover | PASS | popover under an anchor when `anchorKey` is given |
| placement: rail Record slot | PASS at 0969258b (FAIL at 8a5c7474) | defect P-9 fixed (AC-WS-7c entry) |

## Production defects (table as found at 8a5c7474; P-6, P-7, P-8, P-9 fixed at 0969258b, P-8b open)

| Id | Sev | File:line | Failing test | Evidence | Proposed minimal fix |
|---|---|---|---|---|---|
| P-6 | MAJOR | mobile/lib/features/modes/pages/mode_chooser_page.dart:399-513 (grid, panel and buttons share one default traversal group) | mode_chooser_test.dart `DT-08-1b` | At 1100x800 after one card is selected, Tab visits only train, ride, Continue, Decide later (seen set {train, ride}); explore and body are skipped for keyboard Tab users (arrow keys still reach them). At 360x800 Tab order is correct | Wrap the content in `FocusTraversalGroup(policy: OrderedTraversalPolicy())` and give train, ride, explore, body, Continue, Decide later `FocusTraversalOrder(NumericFocusOrder(n))` |
| P-8 | MINOR (plan severity L) | mobile/lib/features/modes/widgets/record_sheet.dart:87-100 (`recordRowsFor`, body branch) and :188-196 | record_sheet_test.dart `DT-11-3` | BODY answer "food" is stored, yet `bodyScan` row stays above `bodyMeal` (meal row top 646 vs scan row top 579 in the same sheet) | pass the BODY answer into `recordRowsFor` and put `kRecordBodyMeal` first (and `kRecordBodyWeight` first for `weight`) |
| P-8b | MINOR | same function | record_sheet_test.dart `DT-11-1b` (documents current behaviour) | `recordRowsFor(body)` always returns 3 rows and takes no FOOD_AI or FOOD_LOOKUP input, so AC-RC-3 /flagsOff and DT-11-1 (BODY with all tiles hidden) cannot be satisfied or tested as written | add flag inputs (BodyScanFlags) to the row builder, or confirm in the design that Record rows deliberately ignore the flags and change the plan rows |
| P-9 | MAJOR (known lane note) | mobile/lib/shared/widgets/main_shell.dart:171 (`_openRecord` passes no anchor) and mobile/lib/features/modes/widgets/record_sheet.dart:123 | record_sheet_test.dart `rail Record slot opens the sheet under the slot` | At 1100x800 tapping `shell.rail.record` opens the Record sheet centred in the window (sheet centre dx 550, offset from centre 0.0), not hanging at the rail slot; `ShellRecordSheetOpener` has no anchor parameter | give the rail Record slot a `GlobalKey`, extend `ShellRecordSheetOpener` with `{GlobalKey? anchorKey}` and pass it from `main_shell.dart:171` |
| P-7 | MINOR | mobile/lib/features/modes/widgets/mode_card.dart:80-93 | DT-08-3 (passes; observation) | loading outline cards are shorter than loaded cards: second-row cards move down 25 dp (245 to 270) when the load completes; order and columns are unchanged | give the outline the same min height as the loaded card, or accept |

Closed by 8a5c7474 (found by the first run at 5bb24fcc): P-1 adaptive_surface.dart:172 null promotion; P-2 adaptive_surface.dart:307 missing KeyDownEvent import; P-3 mode_chooser_page.dart:210 `pushReplacement<void>`; P-4 journal_availability.dart:80 and P-5 activity_wiring.dart:393 (no promotion to an unrelated class); progress_activity_widgets.dart:159 `_SourcesRow` missing `super.key`. Confirmed by the successful compile of the final run.

## Remaining unverified items

- No device, TalkBack or VoiceOver check; semantics are read from the Flutter semantics tree.
- Only `en` is run for most rows (see the note at the top); `ru` copy fit is checked only for AC-CH-13/scale2ru and the plural forms.
- DT-09-4, DT-09-5 (two-question flows) cannot be exercised; DT-10-2 rendered counts above 1 cannot be shown by production data.
- DT-11-4 uses a source scan, not a real-router navigation; `/workout/:id` is matched by prefix.
- AC-RC-3 and DT-11-1 as written in the plan need flag inputs production does not have (P-8b).
- Test files written by other steps were not run here; the TP-3 earlier files (hud_primitives_extension, adaptive_surface, dock_strip, hud_side_rail) were not included in this run.
- Static module-level open flags (`_comingLaterOpen`, `_switcherOpen`, `_recordOpen`) leak between tests if a surface is left open (a failing test cascaded in the first run); tests close surfaces explicitly. No mutation runs were made.
