# S03 test findings, epic 5B (S03-17 keyboard and pointer input)

## FINAL RUN

- Head: `8783b58bdbf569a580ed17dcb3259ec644989127` (production code frozen).
- Command, from `D:\Repo\Fitness_App_Phase2_s01\mobile`: `flutter test --timeout 60s test/shared/widgets/app_shortcuts_test.dart test/shared/widgets/shell_input_test.dart test/shared/widgets/real_pages_input_test.dart`
- Result: 63 passed, 0 failed, 0 skipped (app_shortcuts 32, shell_input 19, real_pages_input 12).
- Production defects open: none (D-1 at `mobile/lib/shared/widgets/app_shortcuts.dart:102-103` was fixed in e78925d3 and stays green).
- NOT_RUN: AC-KB-1i Home/End in rail versus page; wheel and scrollbar on the real Home and Sources pages; Cmd+Shift+M/R through AppShortcuts to the real popover and Record sheet (openers faked); Esc ordering with a popup menu above the popover; end-to-end touch-only, pointer-only and keyboard-only journeys (AC-KB-7, DT-17-1, DT-17-2); scanner page as a pushed route (DT-17-4).

Head revision of the final run: `7c961d7922cb68c90731899bef17f2f4994a3fbc` (includes the app_shortcuts fix e78925d3 and the switcher compile fix 7888326b).
Author: functional-test-reviewer. No file under `mobile/lib` was edited; nothing staged or committed.

## Command

```
cd D:\Repo\Fitness_App_Phase2_s01\mobile
flutter test --timeout 60s test/shared/widgets/app_shortcuts_test.dart test/shared/widgets/shell_input_test.dart test/shared/widgets/real_pages_input_test.dart
```
(flutter = the Flutter 3.27.1 SDK on this machine.)

## Result: 63 passed, 0 failed (final run, all three files together)

| File | Tests |
|---|---|
| `mobile/test/shared/widgets/app_shortcuts_test.dart` | 32 |
| `mobile/test/shared/widgets/shell_input_test.dart` | 19 |
| `mobile/test/shared/widgets/real_pages_input_test.dart` | 12 |

History: first run on fca06cba gave 49 passed and 2 failed (defect D-1 below). After e78925d3 both pass. One intermediate run failed to load only because 9b42ef53 did not compile (`mode_switcher_sheet.dart:127`), fixed by 7888326b.

## Coverage map (plan rows of section 7.1)

Added in real_pages_input_test: AC-KB-8 on the real chooser S-1, questions S-2 (body) and Sources S-8 (macOS shows `shell.back` labelled Back, Android shows none, ru label, Sources Back pops); AC-KB-1g Esc closes the real mode switcher at 1100 and 360 wide without navigating, and Esc with nothing open does nothing; AC-KB-5 real Progress page (wheel scrolls, Scrollbar on Expanded, none on a touch phone).

| Plan id | Where | Notes |
|---|---|---|
| AC-KB-1a | app_shortcuts_test: modifier + 1..5 on android/macOS/iOS, wrong modifier, bare digit | Ctrl vs Cmd both directions |
| AC-KB-1b | Record opener once on Cmd+Shift+R, switcher opener on Cmd+Shift+M, no Shift not bound, null opener safe | opener providers faked (popover widgets belong to other lanes) |
| AC-KB-1c | running session: Record goes to the strip destination, opener never called | |
| AC-KB-1d | Back: non-home tab to /home, /home stays, macOS Cmd+[ only | pushed-page pop FAILS (D-1) |
| AC-KB-1e | focused TextField blocks tab and Record; unfocus restores; open-surface depth blocks, closing restores | |
| AC-KB-1f | Cmd+, pushes /settings on iOS and macOS; nothing on Android (Cmd or Ctrl) | |
| AC-KB-1g | Esc with nothing open never navigates back (tab and pushed page) | popover/menu close-order part NOT_RUN |
| AC-KB-5 | Scrollbar on Expanded, absent on touch Compact, present on Compact with a mouse, mouse wheel scrolls | per-page (Home, Progress, Sources) wheel check NOT_RUN |
| AC-KB-1h support | `scrollToTop` animated, reduced-motion jump, no-client no-op | rail/bar re-select wiring NOT_RUN (covered by dock/rail owners) |
| AC-KB-8 | `ShellBackButton`: macOS Back button semantics and 48 dp height, other platforms take zero size, alwaysVisible, pop, deep-link to /home, custom onPressed, Enter activates, ru label | pages S-1, S-2, S-8 mounting the button NOT_RUN |
| DT-17-3 | modifier + 2 right after first pump; root is not a focus thief | |
| DT-17-4 | workout page and /settings opened as initial route: no tab navigation | pushed over a tab FAILS (D-1) |

## NOT_RUN

- AC-KB-1i (Home/End keys in rail versus page): not written; the rail traversal lives in `hud_side_rail_test.dart`.
- AC-KB-1g Esc ordering with a popup menu above the popover (the real switcher closes on Esc: covered in real_pages_input_test).
- AC-KB-1b Cmd+Shift+M/R wired to the real popover and Record sheet through AppShortcuts: opener providers are faked in app_shortcuts_test (the real switcher is opened by button in real_pages_input_test).
- AC-KB-5 wheel and scrollbar on the real Home and Sources pages (Progress is covered; Home needs the heavy provider set of home_mode_lens_test).
- AC-KB-7 and DT-17-1 and DT-17-2 (end-to-end touch-only, pointer-only, keyboard-only journeys): integration level, belong to e2e-runner.
- Scanner camera page as a pushed route for DT-17-4 (no such route in the stub router).

## Defects

| Id | Severity | Location | Claim | Evidence |
|---|---|---|---|---|
| D-1 (FIXED in e78925d3, re-verified green) | MAJOR | `mobile/lib/shared/widgets/app_shortcuts.dart:102-103` (`_location`), used at `:110` (`_goTab`) and `:136` (`_back`) | `_location` reads `router.routerDelegate.currentConfiguration.uri.path`, which is the base location of the match list and does NOT change when a page is pushed imperatively (`router.push`). With `/settings` (or any pushed page) open over `/progress`, `_isShellRoute` still sees `/progress`. Result 1: modifier + 1..5 call `router.go(...)` and replace the stack beneath the pushed page (DT-17-4 violated for every page pushed from a tab, e.g. a page pushed from Home). Result 2: modifier + `[` takes the shell branch and calls `router.go('/home')` instead of popping the pushed page (AC-KB-1d: shortcut and system Back differ; the user loses the tab they came from). | `app_shortcuts_test.dart` "pushed page is popped, returning to the page below": expected `/progress`, actual `/home`. "page pushed over /progress: tab shortcuts do nothing": expected `/settings`, actual `/workouts`. Initial-route variants (`/settings`, `/workout/abc` as the first location) pass, which is why the bug hides from a start-location test. Test helper reads `currentConfiguration.last.matchedLocation` to see the topmost route. |

Suggested fix (for the implementer, not applied): derive the location from the topmost match (`currentConfiguration.last.matchedLocation`) or from the navigator (`canPop()` with a pushed page on top) in `_location`; acceptance tests are the two failing tests above.

## Test-side problems fixed during authoring

- Harness wraps were missing a `ProviderScope` for `WindowSizeScope` (test bug, fixed).
- Semantics handle was disposed in a tear-down, which is too late for the end-of-test check (fixed by disposing in the test body).
- `scrollToTop` animation needs one pump before the clock starts (fixed).
- The test `location` helper originally used `uri.path` (identical to production) and therefore hid D-1; replaced by the topmost match.
