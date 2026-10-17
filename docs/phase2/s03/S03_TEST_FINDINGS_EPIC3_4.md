# S03 test findings, step 4 (EP-3 and EP-4)

## FINAL RUN (step 7)

Head: 489e486d22b7fe6e37981df815c05174617db775 (re-run after production batches 16 to 18; previous final run was at 8783b58b with the identical result). Flutter `/d/flutter/bin/flutter` 3.27.1. From `mobile/`, one command:
`flutter test --timeout 60s test/features/home_page_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_clock_test.dart test/features/home/home_dashboard_test.dart test/features/home/format_schedule_label_test.dart test/features/home/suggestion_builder_test.dart test/features/progress_page_test.dart test/features/progress/progress_charts_test.dart test/features/progress/progress_stats_test.dart test/features/home/home_mode_lens_test.dart test/features/activity/data/activity_aggregates_test.dart test/features/activity/state/activity_dashboard_providers_test.dart test/features/progress/progress_dashboard_test.dart test/features/modes/sources_panel_test.dart test/features/activity/sign_out_warning_test.dart`
Result: `+247 ~2: All tests passed!` = 247 passed, 0 failed, 2 skipped. No PathExistsException. Production defects open: none.
NOT_RUN: DT-16-3 and DT-16-8 (skipped in code), DT-13-23 (G1) and DT-14-8 (G2) (measure-only gates, not run in this step), AC-LS-5/offline (no offline seam), DT-13-19 as planned (not constructible; the reachable parse form is tested).

## 0d. LATEST in-tree result (head 7888326b, includes 9b42ef53 review fixes)

One command from `mobile/` (`/d/flutter/bin/flutter` 3.27.1), same 15 files as 0c: `flutter test --timeout 60s` on the nine existing Home and Progress files plus my six files. Result: `+247 ~2: All tests passed!` (247 pass, 0 fail, 2 skipped: DT-16-3, DT-16-8).

History: 9b42ef53 did not compile (`mode_switcher_sheet.dart:127`, undeclared `state`, fixed in 7888326b); my scratch-copy run on 9b42ef53 plus a one-line patch was used meanwhile.

New tests (all PASS): DT-12-5 (Today card scrolled out of the cache extent and back, offset unchanged at 80); DT-12-2 split in two: offset 450 (card above the viewport edge: offset compensated and the section below holds within 1 dp) and offset 100 (card arrives inside the viewport: no compensation, offset stays 100); DT-14-10 (Progress loading to errorRetry at offset 400: the heading stays within 1 dp, so no Sources-slot height is subtracted when the slot stays); DT-14-11 (gaveUp: Try again is disabled during a manual attempt and enabled again after); DT-14-12 (account switch: with the mode state reloading the fixed tile order is used, not the previous account's RIDE order).
Test measurement changes caused by the review rule "compensate only above the viewport edge": DT-12-2 and DT-14-2 now scroll to 450/400 so the inserted block starts above the edge (at offset 100 it is inside the view and by design is not compensated). No production defects found in this round.

## 0c. earlier final in-tree result (head 3bf9d24c, includes d0b3ad54)

One command from `mobile/` (flutter `/d/flutter/bin/flutter` 3.27.1): `flutter test --timeout 60s test/features/home_page_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_clock_test.dart test/features/home/home_dashboard_test.dart test/features/home/format_schedule_label_test.dart test/features/home/suggestion_builder_test.dart test/features/progress_page_test.dart test/features/progress/progress_charts_test.dart test/features/progress/progress_stats_test.dart test/features/home/home_mode_lens_test.dart test/features/activity/data/activity_aggregates_test.dart test/features/activity/state/activity_dashboard_providers_test.dart test/features/progress/progress_dashboard_test.dart test/features/modes/sources_panel_test.dart test/features/activity/sign_out_warning_test.dart`
Result: `+242 ~2: All tests passed!` (242 pass, 0 fail, 2 skipped = DT-16-3 and DT-16-8). DT-14-2 alone: `+1: All tests passed!`. D1b is closed; D1 to D6 and C1 to C6 are all closed. Remaining NOT_RUN: DT-16-3, DT-16-8, DT-13-23, DT-14-8, AC-LS-5/offline, DT-13-19 as planned (see section 4 notes, still valid).

## 0b. Re-run after lane L12 batch 4/5 (head e35a3f66)

Command: the nine existing Home and Progress files plus my six files in one `flutter test --timeout 60s ...` from `mobile/` (same list as 0a). First result `+240 ~2 -2`; both failures were the OLD literal `expect(s.position.pixels, 100)` in DT-12-2 and DT-14-2, which is now wrong by design (the offset is compensated). That was a TEST measurement problem; I changed those two lines (test files only) to `greaterThan(100)` and kept the visible-content assertion (the content below the inserted block must not move by more than 1 dp).
After that edit (home_mode_lens_test.dart and progress_dashboard_test.dart): `+51 -1`.

- DT-12-2 (Home today card): PASS. D2 closed.
- DT-14-2 (Progress block): FAIL, production defect D1b. 'Last 8 weeks' ends 116 dp ABOVE where it started (expected y 545, actual 429). Cause: `mobile/lib/features/progress/progress_page.dart:72` (`position.jumpTo(position.pixels + height)`) adds the whole height of the arriving block (492 dp) but ignores that the Sources slot (`ProgressSourcesSlot` + 24 dp gap, 116 dp, built at lines 118-123 only while `view.kind != block`) is removed in the same frame, and it sits above 'Last 8 weeks' too. Net shift of the content is block height minus slot height. Proposed fix: compensate by the delta, e.g. record the slot height (a key on the slot) in `build` before it disappears and jump by `blockHeight - slotHeight`, or anchor on a stable child (measure the y of the first pre-existing section before and after and jump by the difference). Severity MINOR (content moves up by 116 dp when the user is scrolled). Not a test fault: the measured quantity is the position of an unchanged pre-existing heading.
- All existing Home and Progress tests PASS; all other tests of the six files PASS (125 + the fixed DT-12-2 = 126 pass, 2 skipped, 1 fail).

## 0a. Final re-run after adapting the existing Home test (head fe67291b)

D6 resolved on the test side: `mobile/test/features/home_page_test.dart` now overrides `modeStateProvider` with a settled TRAIN state (`_SettledMode`, test file only; greeting-only-while-loading is intended). Other existing tests that build `HomePage`: `home_body_check_in_card_test.dart` passes unchanged; `training_context_generation_journey_test.dart` (signs in a user) passes unchanged (+15); `composed_screen_golden_test.dart` not run (golden, out of scope).

Command (one line, from `mobile/`): `flutter test --timeout 60s test/features/home_page_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_clock_test.dart test/features/home/home_dashboard_test.dart test/features/home/format_schedule_label_test.dart test/features/home/suggestion_builder_test.dart test/features/progress_page_test.dart test/features/progress/progress_charts_test.dart test/features/progress/progress_stats_test.dart` plus my six files.
Result: `+240 ~2 -2`: all existing Home and Progress tests PASS; of my six files only the two open viewport-jump findings fail (DT-12-2 / D2 and DT-14-2 / D1, left unchanged, being fixed in lane L12 batch 4); 2 skipped (DT-16-3, DT-16-8).

## 0. Re-run IN THE TREE (supersedes the scratch-copy results below)

Head revision: fe67291b (includes the fix commit 8a5c7474 for C1 to C6, D3, D4, D5; fe67291b adds "Home shows only the greeting while the mode is unknown"). Flutter `/d/flutter/bin/flutter` 3.27.1. From `mobile/`, no scratch copy.

Command A: `flutter test --timeout 60s test/features/home/home_mode_lens_test.dart test/features/activity/data/activity_aggregates_test.dart test/features/activity/state/activity_dashboard_providers_test.dart test/features/progress/progress_dashboard_test.dart test/features/modes/sources_panel_test.dart test/features/activity/sign_out_warning_test.dart`
Result: `+125 ~2 -2`: 125 PASS, 2 skipped (DT-16-3, DT-16-8), 2 FAIL (open findings D1 and D2). Everything compiles; C1 to C6 are confirmed fixed. D3 (AC-LS-3), D4 (more line) and D5 (DT-15-5) now PASS.

Command B (existing Home and Progress tests): `flutter test --timeout 60s test/features/home_page_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_clock_test.dart test/features/home/home_dashboard_test.dart test/features/home/format_schedule_label_test.dart test/features/home/suggestion_builder_test.dart test/features/progress_page_test.dart test/features/progress/progress_charts_test.dart test/features/progress/progress_stats_test.dart`
Result: `+114 -1`: one existing test FAILS: `home_page_test.dart` "HomePage (active programme) shows the programme title and week instead of the plain bar" (line 448: key `home.programmeProgress` not found).

New production finding D6 (MAJOR for the regression gate, existing test broken): cause is INFERRED to be fe67291b, `mobile/lib/features/home/home_page.dart` (the added `if (modeState == null && name != HomeSection.greeting) continue;`). The test signs in a user and does not override the mode state, so the real `PrefsModeStore` read is still pending after its two `pump()` calls and Home shows the greeting only (the identity row with `home.programmeProgress` is skipped). It passed in my earlier scratch run (before fe67291b). Not proved by an isolating run. Proposed fix: the existing test overrides `modeStateProvider` (or mocks SharedPreferences and pumps until settled); alternatively keep the identity row out of the mode-unknown rule. The existing test file was not edited by me.

Changed expectation: DT-12-4 now asserts the new rule (while the mode state loads only `greeting` is shown, no chip, no chooser; after load the BODY order and the chip). The plan said "pre-S03 TRAIN order while loading"; the stricter shipped rule is pinned instead.

Open (unchanged by design): D1 DT-14-2 (Progress viewport jump 376 dp, `progress_page.dart:70-81,162-166`) and D2 DT-12-2 (Home today card shifts the week section 155 dp, `home_page.dart:340-342`) stay FAIL as open findings. Also unchanged by design: DT-13-7 healthkit label "Health platform" (plan says "Apple Health"); DT-13-19 as planned cannot exist (pinned parse form only); AC-SO-1 extra `signOut.keep` action and no `signOut.warningSheet` key; DT-15-1 has no 1 s cap on "Checking"; NOT_RUN: DT-16-3, DT-16-8, DT-13-23, DT-14-8, AC-LS-5/offline.

---- Earlier section (scratch copy at 5bb24fcc plus C1 to C6; kept for history) ----

Head revision: 5bb24fcc (branch phase2/s03d-ui-design-contract). Nothing committed by the test agent. Flutter: `/d/flutter/bin/flutter` (Flutter 3.27.1, Dart 3.6.0).

## 1. Production compile blockers (BLOCKER)

In-tree, nothing compiles. Command (from `mobile/`):
`flutter test --timeout 60s test/features/home/home_mode_lens_test.dart test/features/activity/data/activity_aggregates_test.dart test/features/activity/state/activity_dashboard_providers_test.dart test/features/progress/progress_dashboard_test.dart test/features/modes/sources_panel_test.dart test/features/activity/sign_out_warning_test.dart`
Result: all six files "Compilation failed". The same compile errors also stop the EXISTING tests `test/features/home_page_test.dart` and `test/features/progress_page_test.dart` (baseline run, all existing Home and Progress files fail to load).

| # | File:line | Error | Proposed minimal fix |
|---|---|---|---|
| C1 | mobile/lib/features/activity/state/journal_availability.dart:80 | `isBound`/`boundUid` not defined on `ActivityJournal`: `journal is! AccountScopedJournal` does not promote (`AccountScopedJournal` is not a subtype of `ActivityJournal`) | `final scoped = journal as AccountScopedJournal;` and use `scoped.isBound`, `scoped.boundUid` |
| C2 | mobile/lib/core/wiring/activity_wiring.dart:393 | `lastRecoveryReport` not defined on `AccountScopedJournal` (same promotion problem) | `(source as RecoveryReportSource).lastRecoveryReport` |
| C3 | mobile/lib/features/modes/pages/mode_chooser_page.dart:210 | `context.pushReplacement<void>(path)` rejected (no type argument in this go_router); the result is void so `unawaited(...)` is also invalid | `context.pushReplacement(path);` |
| C4 | mobile/lib/shared/widgets/adaptive_surface.dart:172 | `depth.opened()` on nullable `OpenSurfaceDepth?` | `depth?.opened() ?? 0` |
| C5 | mobile/lib/shared/widgets/adaptive_surface.dart:307 | `KeyDownEvent` not a type (import is `show LogicalKeyboardKey`) | add `KeyDownEvent` to the `show` list |
| C6 | mobile/lib/features/progress/widgets/progress_activity_widgets.dart:159 | `_SourcesRow` has no `key` parameter | `const _SourcesRow({super.key, ...})` |

Method used to get evidence anyway: a scratch copy of `mobile/` outside the repository (`.../scratchpad/p4/mobile`) with exactly C1 to C6 applied and my test files copied in. All results in section 3 are from that patched copy at head 5bb24fcc plus those six edits. No production file in the repository was touched.

## 2. Files written

All under `mobile/test/` (paths exact): `support/s03_step4_support.dart` (shared fakes), `features/activity/data/activity_aggregates_test.dart`, `features/activity/state/activity_dashboard_providers_test.dart`, `features/progress/progress_dashboard_test.dart`, `features/home/home_mode_lens_test.dart`, `features/modes/sources_panel_test.dart`, `features/activity/sign_out_warning_test.dart`.

## 3. Results (patched copy)

Complete set, one command (patched copy, cwd `scratchpad/p4/mobile`): `flutter test --timeout 60s <the six files above>`
Result: 129 entries: 122 PASS, 5 FAIL, 2 skipped (NOT_RUN). Aggregates 27/27 pass, providers 16/16 pass.

Existing tests run in the patched copy: `flutter test --timeout 60s test/features/home_page_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_clock_test.dart test/features/home/home_dashboard_test.dart test/features/home/format_schedule_label_test.dart test/features/home/suggestion_builder_test.dart test/features/progress_page_test.dart test/features/progress/progress_charts_test.dart test/features/progress/progress_stats_test.dart` -> `+115: All tests passed!` (existing Home and Progress tests are NOT broken by S03 once C1 to C6 are fixed; in-tree they fail only because of the compile errors).

| Ids | Status |
|---|---|
| AC-PR-5, AC-PR-7 x4, AC-PR-11, AC-SRC-6 x6, DT-13-1 to 7, 17, 19 (pinned form), 21, 22, 24 | PASS |
| DT-13-8 to 16, 18, 20 (providers) | PASS |
| AC-PR-1, 2 x2, 3 x2, 4, 6 (limited, see 5), 8, 9, 10 x2, AC-LS-4 x3, AC-LS-5 x3, DT-14-1 x2, 3, 4 x2, 5 x2, 6, 7, 9 | PASS |
| DT-14-2 | FAIL (D1) |
| AC-HM-1 to 5, AC-HM-6 x2, AC-LS-1 x3, AC-LS-2 x2, DT-12-1, 3, 4 | PASS |
| AC-LS-3 | FAIL (D3) |
| DT-12-2 | FAIL (D2) |
| DT-12 "more line" (known gap, my id: DT-12-more) | FAIL (D4) |
| AC-SRC-1 x2, 2, 3, 4, 5 x2, 5k, 7, AC-LS-6 x2, DT-15-1, 2 x2, 3 (source scan), 4 x2, 6 x2 | PASS |
| DT-15-5 | FAIL (D5) |
| AC-SO-1 x2, AC-SO-2, DT-16-1, 2, 4 x3, 5, 6, 7, 9 | PASS |
| DT-16-3, DT-16-8 | NOT_RUN (skipped in code with reason) |
| DT-13-23 (G1), DT-14-8 (G2) | NOT_RUN (measure-only, step 7 by plan) |
| AC-LS-5/offline | NOT_RUN: no offline seam without cloud sync providers |

## 4. Production defects (not compile-level)

- D1 MAJOR/MINOR (MINOR) DT-14-2: `mobile/lib/features/progress/progress_page.dart:70-81,162-166`. The All-activity block is inserted ABOVE the body-scan card in a plain `ListView` with no scroll compensation. Evidence: viewport offset 100; 'Last 8 weeks' moved from y=545 to y=921 (376 dp jump) when the journal resolved. Fix: keep the anchor (e.g. reserve the block height while loading, or adjust `ScrollController` offset by the inserted height when the user has scrolled).
- D2 MINOR DT-12-2 (S-6): `mobile/lib/features/home/home_page.dart:340-342` and `widgets/activity_today_card.dart:33`. The today card appears after the day panel with no viewport compensation: 'week' section moved 155 dp (194 to 349). Same fix class as D1.
- D3 MINOR AC-LS-3: `mobile/lib/features/home/home_page.dart:350` (`pane >= kHomeTwoPaneMinWidth`) and `widgets/home_lens.dart:107`. At 900 dp wide and text scale 2.0 the two-pane layout is still used (`home.pane.side` exists); the contract wants a single column at large text. Fix: add a text-scale condition (e.g. fall back to one column when `MediaQuery.textScalerOf(context).scale(1) > 1.3`) for the two-pane branch.
- D4 MINOR Home "more" line: `mobile/lib/features/home/widgets/activity_today_card.dart:68`. With 5 sessions today the line is a bare `+2` (`home.activityToday.more`); no ARB key exists. Fix: add an ARB key (e.g. `homeActivityTodayMore` "{n} more") in en and ru.
- D5 MAJOR DT-15-5 (RV-11): `mobile/lib/features/modes/pages/sources_page.dart:157-164`. After a successful load and a failed refresh the snapshot is kept (`lastLoadFailedAt` set), and the app row still reads "In use" (label "Recorded in this app, In use"); the contract says "Problem" plus the stale line. Fix: in the `JournalOpen` branch, when `snap.lastLoadFailedAt != null` return status `problem` with `activityStaleNotice` line and a retry that calls `activityDigestsProvider.notifier.refresh()`.

Other deviations from the plan (recorded, not failures):
- DT-13-7: plan expects "Apple Health" for source id `healthkit`; production labels it "Health platform" (no ARB key for Apple Health; sources_page comment says no Apple row exists in S03). The test pins production. MINOR spec mismatch.
- DT-13-19 cannot be written as planned: `SourceKind` has 5 values and no unknown member and the label switch is exhaustive, so an unmapped value cannot exist. Decision: the test pins the only reachable case (`SourceKind.parse` of an unknown name gives `fileImport`, label "File import"; no kind gives `unknown`). DT-13-19 as planned is NOT_RUN by design.
- AC-SO-1: production adds a fourth action `signOut.keep` ("Sign out") and the sheet has no `signOut.warningSheet` key; the test finds the sheet by its title text.
- DT-16-6: after a failed export and Cancel in the error sheet the flow returns to the warning sheet (user stays signed in), it does not end the guard; accepted as correct.
- DT-15-1: production shows "Checking" for as long as the journal is `binding` (no 1 s cap); test covers plain text/no spinner and the switch to the final status.

## 5. Remaining unverified

- Everything in section 3 is verified against a patched scratch copy, not the repository tree; re-run the six-file command in-tree after C1 to C6 are fixed.
- AC-PR-6 uses an upserted fake journal list, so it cannot detect a journal that fails to upsert (that is S02's job).
- AC-HM-1 golden is the literal pre-S03 order copied from the lens constant, not captured from the base commit (circular for the order itself; it still fails if the page reorders sections).
- AC-HM-6/traversal reaches the chip by repeated Tab only; reading order by semantics not checked.
- AC-LS-1/AC-LS-2/AC-LS-3 run Home alone (no shell/rail); widths are content widths.
- Widths use tall surfaces (3600 dp high) because the lists are lazy.
- DT-16-3 (account B after A's delete), DT-16-8 (export location), DT-13-23, DT-14-8, AC-LS-5/offline: NOT_RUN.
- No real device, no golden, no mutation runs.
