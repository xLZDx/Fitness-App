# S03 test findings: EP-5 foundations (step 2)

Head revision under test: 7888326b (earlier: 9b42ef53) (branch phase2/s03d-ui-design-contract). History: 5bb24fcc (compile blocker D-0, then D-1..D-4), e35a3f66 (all green), 9b42ef53 below. Nothing was committed by the test agent.

Flutter: `D:lutterinlutter`, Flutter 3.27.1, Dart 3.6.0. From `mobile/`: `flutter test --timeout 60s` on window_size_test, hud_primitives_extension_test, nav_config_test, hud_side_rail_test, adaptive_surface_test, dock_strip_test (all under test/shared/widgets/), test/features/workouts/active_session_status_test.dart, plus the existing test/router/back_navigation_test.dart, test/shared/widgets/hud/hud_components_test.dart and test/shared/widgets/shell_insets_test.dart. No PathExistsException occurred.

## Final result at 7888326b: all green

Head revision 7888326b. Command: `flutter test --timeout 60s` from `mobile/` on the 7 files I wrote plus the 3 existing files (list above). No PathExistsException.

| File | Entries | Pass | Fail |
|---|---|---|---|
| window_size_test.dart | 8 | 8 | 0 |
| nav_config_test.dart | 10 | 10 | 0 |
| hud_primitives_extension_test.dart | 18 | 18 | 0 |
| hud_side_rail_test.dart | 34 | 34 | 0 |
| adaptive_surface_test.dart | 19 | 19 | 0 |
| dock_strip_test.dart | 36 | 36 | 0 |
| active_session_status_test.dart | 9 | 9 | 0 |
| existing back_navigation_test.dart | 10 | 10 | 0 |
| existing hud_components_test.dart | 66 | 66 | 0 |
| existing shell_insets_test.dart | 20 | 20 | 0 |

Written by this agent: 134 entries, 134 pass. Existing: 96 of 96 pass.

Production defects: none open. History: D-0 (adaptive_surface compile), D-1 (rail focus ring), D-2 (focus across swap), D-3 (foreign-owner pill/owner), D-4 (dock compaction) and D-5 (`mode_switcher_sheet.dart:127` compile error from 9b42ef53, fixed in 7888326b) were each found by a failing run and are closed.

## Per test id (grouped)

PASS: AC-WS-1a, AC-WS-1b (2), DT-02-1..DT-02-5; AC-SH-1, AC-SH-2 (5), DT-04-1 (en, ru); AC-KB-3 primitives (HudButton, HudChip, HudSettingRow, HudPanel at 360x800 and 1100x800), AC-KB-4 (hoverEnabled, disabled, hoverNoChange), DT-03-1 (4), DT-03-2, DT-03-3; AC-WS-2a (2), AC-WS-2b (3), AC-WS-3a (3), AC-WS-3b (2), AC-WS-3c, AC-WS-3d, AC-WS-4/fiveItems, AC-WS-6 (2), AC-WS-8 (2), AC-WS-9 (2), AC-WS-10 (4), AC-WS-11 (rail, bar), AC-KB-2, AC-KB-9 (dark, light), DT-05-1, DT-05-2, DT-05-3 (2), DT-05-5; AC-LS-8a (3), AC-LS-8b (2), AC-LS-8d, AC-WS-14a, AC-WS-14b, AC-A11Y-6a, AC-A11Y-6b, DT-06-1, DT-06-2 (2), DT-06-3, DT-06-4 (5); AC-ST-1, AC-ST-2, AC-ST-3 (10), AC-ST-4, AC-ST-5 (2), AC-ST-6, AC-ST-7, AC-ST-8, AC-SH-5, AC-WS-7a, AC-WS-7b, AC-WS-7c (opener seam only), AC-WS-12, AC-WS-13, DT-07-1, DT-07-2, DT-07-3, DT-07-4, DT-07-5, DT-07-6, DT-07-7, DT-07-9, DT-07-10, DT-07-11, DT-07-12, DT-07-13.

FAIL at e35a3f66: none (the 6 earlier failures were D-1 to D-4, fixed).

NOT_RUN (cannot be implemented in this step, with reason):
- AC-SH-3 (shell level), AC-WS-4/fourItemList, DT-04-2 (shell level): `MainShell` reads the const `kShellDestinations`, no injection seam. Partial versions are written and pass (HudNavBar with 4 items; pure `shellDestinationIndexFor`). Proposed seam: `shellDestinationsProvider`.
- AC-KB-3 entries /modeChip, /chooserCard, /sheetRow and AC-KB-4 on `modeChooser.card.train`: belong to steps 3 and 4 (RUNS-AFTER S03-08/10/12).
- AC-LS-8a/8d with the real `home.modeChip` and mode switcher content, AC-LS-8b with the chooser card `ride`, AC-LS-8c (sign-out sheet, S03-16): step 3/4. This step proves the placement component through a test host with the same anchor contract.
- AC-WS-7c `recordSheet.popover` content, AC-WS-7d (Record sheet width): step 3 (S03-11). Only the tap-to-opener seam is tested here. AC-WS-7e (Record shortcut): step 5 (S03-17).
- AC-ST-4 opened the switch through `modeStateProvider.selectMode`, not through the S-3 UI (S-3 UI is step 3).
- DT-07-13: S-3/S-5 open/close and hot-swap parts not exercised (tabs and presentation swaps only).
- DT-03-1 `ru` variant was not recorded; `en` only. Base literals were measured on a `git archive` of `c0731f91~1` (HEAD signatures are identical).
- DT-07-4: zone change is simulated by the same instant in UTC and local representation (the code has no zone seam).
- DT-07-6: rotating 360x800 to 800x360 switches to the rail presentation (width 800 is Medium and short), so the strip compaction is tested on 360x800 -> 580x340 (bar presentation, short).

## Plan-vs-code notes

- A mouse event keeps Flutter's `FocusHighlightMode.traditional`; the "no ring after pointer tap" check relies on a mouse tap not focusing the control and a touch removing the ring.
- Provider recompute in `activeSessionStatusProvider` is lazy: the driven one-shot timers are armed when the provider is read (a frame), not at the state change itself. Tests read the provider like a frame does.
- Under the test font (Ahem) `en` labels measure under 96 dp, so the 96 dp rail form is really reached (`AC-WS-3b` stub and `en` shells); `ru` always extends.

## Remaining unverified

Real-device focus ring visibility, TalkBack/VoiceOver order, contrast over photographs, real Home/Workouts/Progress pages inside the shell at 640x360 (tab pages in these tests are stub `HudScreenBody` pages), step 3-5 rows listed above, `WorkoutPlayerPage` start paths writing the owner (owner was captured directly through `ActiveSessionOwnerController.capture`). No mutation runs, no analyzer, no full-tree run were made.
