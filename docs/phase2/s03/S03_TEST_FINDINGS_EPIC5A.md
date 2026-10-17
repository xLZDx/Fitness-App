# S03 test findings: EP-5 foundations (step 2)

Head revision under test: e35a3f66 (branch phase2/s03d-ui-design-contract). History: first run 5bb24fcc (compile blocker D-0), runs at 8a5c7474, fe67291b, 0969258b (6 failures D-1..D-4), final full run at e35a3f66 below. Nothing was committed by the test agent.

Flutter: `D:lutterinlutter` (`flutter.bat`), Flutter 3.27.1 stable, Dart 3.6.0. From `mobile/`:
`flutter test --timeout 60s test/shared/widgets/window_size_test.dart test/shared/widgets/hud_primitives_extension_test.dart test/shared/widgets/nav_config_test.dart test/shared/widgets/hud_side_rail_test.dart test/shared/widgets/adaptive_surface_test.dart test/shared/widgets/dock_strip_test.dart test/features/workouts/active_session_status_test.dart test/router/back_navigation_test.dart test/shared/widgets/hud/hud_components_test.dart test/shared/widgets/shell_insets_test.dart`

## Result at e35a3f66: 0 failures

| File | Entries | Pass | Fail |
|---|---|---|---|
| shared/widgets/window_size_test.dart (S03-02) | 8 | 8 | 0 |
| shared/widgets/nav_config_test.dart (S03-04) | 10 | 10 | 0 |
| shared/widgets/hud_primitives_extension_test.dart (S03-03) | 18 | 18 | 0 |
| shared/widgets/hud_side_rail_test.dart (S03-05) | 34 | 34 | 0 |
| shared/widgets/adaptive_surface_test.dart (S03-06) | 19 | 19 | 0 |
| shared/widgets/dock_strip_test.dart (S03-07, incl. 2 announcement tests) | 35 | 35 | 0 |
| features/workouts/active_session_status_test.dart (S03-07) | 9 | 9 | 0 |
| existing, unchanged: router/back_navigation_test.dart | 10 | 10 | 0 |
| existing, unchanged: shared/widgets/hud/hud_components_test.dart | 66 | 66 | 0 |
| existing, unchanged: shared/widgets/shell_insets_test.dart | 20 | 20 | 0 |

Written by this agent: 133 entries (7 files) plus `mobile/test/support/s03_shell_harness.dart`; 133 pass.

Test-side changes after e35a3f66: rail focus nodes are now labelled `shell.destination.N` (was `shell.rail.item.N`); AC-ST-9 accessible-name checks look for a labelled Semantics inside the pill/strip; DT-07-8 re-worded to the owner-kept decision (foreign-owner provider true, status/strip/pill hidden, owner kept, owner account sees the session again); new AC-A11Y-4 tests: started / paused / resumed / ended announcements for the signed-in owner, no announcement from the 30 s tick, and silence on an account switch (captured on the `flutter/accessibility` channel).

## Production defects

Open: none found by the tests at e35a3f66.
Closed since the first run: D-0 `adaptive_surface.dart` compile errors (8a5c7474); D-1 rail destinations had no focus ring (`hud_side_rail.dart` `_RailTile`); D-2 focus lost on rail/bar swap (`main_shell.dart`); D-3 pill shown / owner handling for another account (`active_session_status.dart`, `main_shell.dart`); D-4 dock compaction at 360x480 scale 2.0 (`main_shell.dart` `compactDock`). Each had a failing test before its fix and passes now.

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
