# UI-0 baseline audit: ADDENDUM (read-only, nothing run)

Sprint S01 part (c). Closes the gaps a product-ux and accessibility review found in `UI0_BASELINE_AUDIT.md`. Produced by a read-only code-explorer agent on 2026-10-15 for worktree `D:\Repo\Fitness_App_Phase2_s01` (line `phase2/s01-contracts`, based on `phase2/s00-split-docs`). Saved verbatim by the coordinator.

Paths are relative to the worktree root. Labels are FACT(path:line) or INFERENCE.

**HEAD and branch of the audited tree: the agent did not read the git HEAD file.** The coordinator records the commit the audit was run against as `d58ff1d6` (the commit that added the first report); the `mobile/` tree is identical between that commit and the later documentation-only commits on this branch.

**Counting limits.** Grep "count" mode counts matching lines, not occurrences. Multi-line `Text(\n'...')` calls are not counted.

**Contrast method.** All ratios below are "computed from hex" by hand, not run.
- Channel linearisation is `c/255`, then `((c+0.055)/1.055)^2.4` for values above 0.04045.
- Relative luminance is `L = 0.2126R + 0.7152G + 0.0722B`.
- Contrast ratio is `(L1+0.05)/(L2+0.05)`.
- Translucent colours are first composited over the theme `base` colour as `a*fg + (1-a)*base`, rounded to integer channels.
- Expect roughly +-0.1 arithmetic error.

## Corrections to the first report
- FACT(mobile/lib/main.dart:663-665): `MaterialApp.router.builder` wraps every route in `_InputTraceListener(child: AuroraBackground(child: ...))`. `AuroraBackground` therefore sits under every screen, including the HUD ones. The first report did not say this.
- FACT(mobile/lib/main.dart:670-694): `_InputTraceListener` is labelled "TEMPORARY ... Debug-only -- remove once the failing stage is identified ... not meant to ship". It returns `child` unchanged when `!kDebugMode`, and otherwise logs raw pointer down/up events.
- FACT(mobile/lib/shared/widgets/main_shell.dart:107-109, 157-159): the shell also has debug-only `TRACE stageG` and `stageE` prints.

## 1. Keyboard and focus

**Focus styles: none visible on the custom HUD controls.**
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart:31-59): `HudKeyboardActivation` is a bare `Focus(onKeyEvent)` that handles Enter, NumpadEnter and Space. It draws nothing on focus.
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart:22-30): its doc says `HudButton`, `HudChip` and `HudToggle` are raw `GestureDetector`s on purpose, so they get no `FocusNode` or keyboard activation for free.
- FACT(grep `focusColor|FocusableActionDetector|FocusTraversalGroup|FocusScope|Shortcuts(` over mobile/lib): no matches outside two `FocusNode` mentions in hud_surface.dart, so there is no app-defined focus ring, traversal group or shortcut map.

| Component | Focusable | Keyboard activation | Visible focus |
|---|---|---|---|
| `HudButton` (hud_surface.dart:709-715) | yes via `Focus` | yes (Enter/Space) | none, FACT |
| `HudChip` (hud_surface.dart:841-848) | yes, only when `onTap` set | yes | none, FACT |
| `HudToggle` (hud_metric.dart:586-590) | yes, when enabled | yes | none, FACT |
| `HudPanel(onTap)` (hud_surface.dart:429-436) | `Material`+`InkWell` | INFERENCE: Flutter default `ActivateIntent` | INFERENCE: InkWell default overlay from theme; not measured |
| `HudSettingRow(onTap)` (hud_metric.dart:737) | `InkWell` | same inference | same inference |
| `_NavTab` (hud_scaffold.dart:328-332) | `InkResponse` | same inference | same inference |
| `SetTimerCard` `_Primary`/`_Secondary` (set_timer_card.dart:304-306, 348-350) | no | none, FACT: bare `GestureDetector` | none |

- FACT: `GestureDetector(` appears on 17 lines in 12 files. Beyond the HUD controls above, it also appears in `login_page.dart`, `onboarding/widgets/inputs.dart`, `step_body.dart`, `measure_ruler.dart`, `body_zone_map.dart`, `exercise_reference.dart`, `progress_photos_page.dart` and `difficulty_rating_sheet.dart`. NOT VERIFIED which of those lack a keyboard path.

**Tab order and shell.**
- FACT(mobile/lib/shared/widgets/main_shell.dart:123-163): `Scaffold` has `body` (the page) and `bottomNavigationBar` (`HudNavBar`).
- INFERENCE: with no `FocusTraversalGroup` anywhere, Flutter's default reading-order traversal visits page content first and the nav bar last.
- FACT(mobile/lib/shared/widgets/hud/hud_scaffold.dart:274-287): tabs are `Expanded` children of a `Row`, so tab order is left to right: Home, Workouts, Scan, Progress, Profile.

**Sheets and dialogs.**
- FACT(grep `showModalBottomSheet|showDialog|showGeneralDialog` over mobile/lib): 20 matching lines across 16 files, all using the framework's modal routes. No custom focus trap or restore code exists.
- INFERENCE: Flutter's modal route scope traps focus and restores it on pop. Not tested here.
- FACT(mobile/lib/features/workouts/widgets/set_capture_sheet.dart:69-72, 156): the set sheet is `isScrollControlled: true` and the weight field has `autofocus: true`. The reps field has none.

## 2. Contrast on `HudTokens` (the live layer)

Backgrounds are the `base` token only: dark `#14182C` (L=0.0098) and light `#EEF0F6` (L=0.8715). This is not the real surface, which is photograph, veil and glass.

| Token | Dark | Light |
|---|---|---|
| textPrimary (`#FFFFFF` / `#1B2030`) | 17.55 | 14.22 |
| textSecondary (as coded; see mismatch below) | 11.50 | 9.47 |
| textTertiary | 9.56 | 7.29 |
| nav inactive ink (hud_scaffold.dart:260-261) | 9.97 | **4.40** |
| accent (`#C9FF47` / `#4B7A00`) as text or graphic | 14.94 | 4.51 |
| onAccent on accent (`#14182C` on lime / white on `#4B7A00`) | 14.94 | 5.14 |
| success (`#7BF08A` / `#2F7A3A`) | 12.26 | 4.65 |
| warning (`#FFB86B`, both themes) | 10.30 | **1.50** |
| danger (`#FF5A5A`, both themes) | 5.73 | **2.69** |
| zonePoor / zoneMid / zoneGood | 6.57 / 10.38 / 12.76 | 2.34 / 1.48 / 1.21 |

Intermediate values used:
- Dark secondary composites to about (208,209,213) with L~0.638.
- Dark tertiary composites to about (190,191,196) with L~0.522.
- Dark accent L~0.8439.
- Light secondary composites to about (57,61,76) with L~0.0473.
- Light tertiary composites to about (73,78,92) with L~0.0763.
- Light accent L~0.1541.
- Light success L~0.1483.

**Safe as text (>=4.5:1) over `base` alone.**
- Dark: every token in the table.
- Light: textPrimary, textSecondary, textTertiary, accent (4.51, marginal), onAccent, success.
- Not safe as text on light: nav inactive ink (4.40), warning, danger, and the three zone colours.

**Safe as icon or graphic (>=3:1) over `base` alone.**
- Dark: all tokens.
- Light: everything except warning (1.50), danger (2.69) and the zone colours (1.2 to 2.3).
- FACT(mobile/lib/shared/widgets/hud/hud_metric.dart:449-463): zone bars use fills at 0.85 alpha, which lowers these figures further. The marker pin and the semantic value are the other channels.

**Code-vs-comment mismatches.**
- FACT(mobile/lib/core/theme/hud_tokens.dart:278): the doc on `textSecondary` says "`rgba(255,255,255,.80)` dark / `rgba(27,32,48,.80)` light".
- FACT(mobile/lib/core/theme/hud_tokens.dart:618): the code is `0xDB1B2030`, which is ink at .86, and the comment beside it says ".86". `textTertiary` is `0xC71B2030`, which is .78.
- FACT(mobile/lib/core/theme/hud_tokens.dart:614-617): the comment above explicitly says light is "~.06 HIGHER" than dark. The doc at :278 is therefore the stale one, and the code is intentional.
- For reference, a .80 light secondary would composite to about (69,74,88) and give 7.76:1.
- FACT: the dark `warning` and `danger` hexes are identical in light, so the light theme reuses colours measured only for dark.

**Panel over photo: what can and cannot be computed.**
- Cannot compute: the `panel`, `chip` and `button` fills are translucent white at 1.4 to 5 percent (dark), so the effective background is the photograph plus the veil. No WebP was decoded, so no number is given for text over a photo.
- FACT(mobile/lib/core/background/hud_sky.dart:135-175): the code stores measured 95th-percentile luminance (0..255, Rec.709) per bundled photo, for the top 45 percent and the 40-100 percent band. Examples: 04_fuji_sakura 242.26 and 242.84, 02_volcano 145.08 and 150.65.
- FACT(mobile/lib/core/background/hud_sky.dart:101-115): ten scenes map to six phases (dawn, morning, day, golden, dusk, night) across two photo sets.
- FACT(mobile/lib/core/background/hud_sky.dart:148-164): a code comment records an earlier measurement of the Workouts screen at 1.39:1 for body copy and 2.51:1 for a call to action, before the `contentPanel` (`dense`) tier existed.
- NOT VERIFIED: current contrast for any panel over any photo. This needs rendered screenshots or the `denseAlphaForP95` formula plus the veil values.
- FACT(mobile/lib/core/theme/hud_tokens.dart:741-783): veil alpha per phase is 0.44 to 0.56 in dark, and a fixed 0.60 to 0.70 in light.

## 3. Text scaling at 200 percent

Sizes below are nominal size x 2.0. INFERENCE: Flutter scales linearly here, and Android 14+ nonlinear scaling is not modelled.

| Style (mobile/lib/core/theme/hud_typography.dart) | 1.0x | 2.0x |
|---|---|---|
| screenTitle | 24 | 48 |
| heroTitle | 22 | 44 |
| panelHeading | 20 | 40 |
| panelTitle | 14 | 28 |
| rowTitle | 13.5 | 27 |
| rowMeta | 10.5 | 21 |
| body | 11.5 | 23 |
| bodyStrong | 12.5 | 25 |
| label | 9.5 | 19 |
| ringLabel | 7.5 | 15 |
| navLabel | 8.5 | 17 |
| mono (default) | 10 | 20 |
| bigNumber | caller-set 34 to 72 | 68 to 144 |

What clips or truncates:
- FACT(mobile/lib/shared/widgets/hud/hud_scaffold.dart:269-270, 349-354): the nav bar is a fixed 72 high, and each label is `maxLines: 1` with ellipsis.
  - INFERENCE: at 2.0x, icon 20 + gap 6 + a 17px label (about 22 line height) is about 48 high. That fits 72, and the indicator dot at bottom 7 is just clear of the text.
  - INFERENCE: width is about 67 per tab on a 360-wide device ((360 - 24 inset)/5). A 10-letter Russian uppercase label at 17px will not fit, so it ellipsises. This is not measured.
- FACT(mobile/lib/shared/widgets/hud/hud_metric.dart:78-105): the ring label is bounded to the ring and shrunk by `FittedBox(scaleDown)`. A comment reports a 78px ring label overflowing by 11px at 2.0x and 55px at 3.0x before that fix. The result is capped at 1.0x size, so the number does not grow at 200 percent.
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart:822-831): `HudChip` text is `maxLines: 1`, ellipsis, with a 44 minimum height only and no width rule.
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart:683-689): `HudButton` text allows 2 lines in the non-centred layout and 1 line when centred.

**The three `noScaling` exceptions** (FACT):
- `mobile/lib/features/scanner/widgets/scan_viewfinder.dart:155`: hint text inside the viewfinder, with a comment saying it would collide with the brackets. Its meaning is repeated by the subtitle at the user's size.
- `mobile/lib/features/scanner/widgets/scan_match_card.dart:104`: a 20px match title.
- `mobile/lib/features/scanner/widgets/scan_glyph.dart:92`: icon glyph text, "the size IS the design".

**Decision inputs for S03-D.**
- There is no app-level text-scale clamp (`MaterialApp.builder` at mobile/lib/main.dart:663 does not set one).
- The nav bar is 72 high and five items wide. Decide whether labels may truncate, shrink, or drop to icons-only above a scale threshold.
- Roughly 16 of 28 label-sized styles sit at or below 10.5 nominal.
- `FittedBox(scaleDown)` on the ring caps growth rather than reflowing.
- NOT VERIFIED: actual layout at 2.0x on any screen. No run was made.

## 4. Touch targets

| Component | Hit size (FACT unless marked) |
|---|---|
| `HudToggle` (hud_metric.dart:591-595) | 50 x 44, with the visible switch 50 x 29 |
| `HudButton` (hud_surface.dart:725-728) | min height 44, width fills the row |
| `HudChip` (hud_surface.dart:846-848) | min height 44, width hugs text with 14 horizontal padding |
| `_NavTab` (hud_scaffold.dart:326-327) | min height 44 inside a 72-high bar, width about 67 (INFERENCE from `Expanded`) |
| `HudSettingRow` (hud_metric.dart:687) | min height 44, full width |
| `HudPanel(onTap)` | no minimum; padding 18 default |
| `AppIconButton` compact (app_buttons.dart:209-213) | Material `IconButton` with `VisualDensity.compact`, icon 18; INFERENCE about 40 x 40, not measured |
| `SetTimerCard` `_Primary`/`_Secondary` (set_timer_card.dart:306-307, 350-351) | vertical padding 15, so about 52 or more high; width `Expanded` |

- FACT(mobile/lib/core/theme/hud_tokens.dart:456): `minTapTarget` is 44. The direction document asks for 48 dp.
- Min-width gaps: `HudChip` and `HudToggle` have no 48 width rule (toggle is 50). Chips and the compact icon button can fall under 48 wide.
- Recommendation for the contract: adopt 48 for new controls and document 44 as the existing HUD exception (the handoff states 44). This is a decision input, not a change.

## 5. State matrix

"Present" means found by grep or read. "Not found" means not found by that grep. Whole files were not read.

| Screen | Loading | Empty | Error | Offline | Permission denied | Retry |
|---|---|---|---|---|---|---|
| Home (mobile/lib/features/home/home_page.dart) | present (:1214 spinner in panel) | present (:183) | present (:180-181), **raw exception shown** | not found | n/a | not found |
| Workouts (mobile/lib/features/workouts/workouts_page.dart) | present (:461) | present (:517) | present (:469-489), fixed copy | offline-video prefetch card only (:554) | n/a | present (:480-485) |
| Scan (mobile/lib/features/scanner/scanner_page.dart) | partial (`_retrying`, :111) | not found | present (:105-287) | not found | present (:281-304, open Settings) | present |
| Progress (mobile/lib/features/progress/progress_page.dart) | **not distinguished** | present (:63, :95, :603) | **not distinguished** | not found | n/a | not found |
| Profile (mobile/lib/features/profile/profile_page.dart) | not found | placeholders (:434) | not found | not found | n/a | not found |
| Settings (mobile/lib/features/settings/settings_page.dart) | not found | n/a | snackbar (:33-36), **raw exception** | not found | n/a | not found |
| Onboarding (mobile/lib/features/onboarding/onboarding_page.dart) | submit spinner (`isSubmitting`, :173) | n/a | snackbar (:158-163), **raw exception** | not found | n/a | NOT VERIFIED |
| Splash (mobile/lib/features/splash/splash_page.dart) | present, 5 s auth bound (:41) | n/a | falls through to `/home` with a debug print (:111) | not found | n/a | n/a |
| Login (mobile/lib/features/auth/login_page.dart) | present (`isLoading`, :23, :130-132) | n/a | snackbar (:25-34), **raw exception** | not found | n/a | not found |
| Subscription (mobile/lib/features/subscription/subscription_page.dart) | present (:109) | NOT VERIFIED | present, `_EntitlementUnavailable` (:111-113, :1057-1084) | not found | n/a | present (:1083-1084) |

- FACT(mobile/lib/features/home/home_page.dart:180-181): `error: (e, _) => [... _SuggestionsMessage(l10n.homeCouldNotLoad('$e'))]`. ARB `homeCouldNotLoad` is "Could not load: {error}" (EN, mobile/lib/l10n/app_en.arb:1626) and the Russian equivalent (app_ru.arb:860).
- FACT: other raw-exception copy takes an argument in the ARB: `authSignInFailed` ("Sign-in failed: {arg0}", app_en.arb:435), `catalogError` ("Error: {arg0}", app_en.arb:451), `onboardingCouldNotSaveProfile` (app_en.arb:651).
- FACT(mobile/lib/features/workouts/workouts_page.dart:461-468): a code comment says an earlier version showed a raw Firestore exception, and it was replaced by `errorServiceUnavailable` plus a retry. This is the model to copy.
- FACT(mobile/lib/features/progress/progress_page.dart:31, 37, 120, 186, 281): Progress reads providers through `valueOrNull ?? const []`. INFERENCE: loading and error are indistinguishable from empty (a zero).
- FACT(grep, mobile/pubspec.yaml): no connectivity package. INFERENCE: "offline" as a screen state is absent everywhere except video caching.
- NOT VERIFIED: Profile loading and error behaviour. `profile_page.dart` has no `when()` and its provider handling was not read.

## 6. S03-D inputs

**Notification channels.**
- FACT(mobile/lib/core/notifications/local_notification_service.dart:24-27): one channel only, `workout_reminders`, "Lead-time reminders for scheduled workouts".
- FACT(:128-136): importance and priority high, category reminder.
- FACT(:59): `_plugin.initialize(init)` is called with no tap callback. `payload: id` is set at :151.
- FACT(grep `onDidReceiveNotificationResponse|getNotificationAppLaunchDetails` over mobile/lib): no matches. INFERENCE: tapping a reminder opens the app but does not route to a workout.
- FACT(:80-91): notification permission is asked once per process and inexact alarms are used.
- FACT(mobile/android/app/src/main/AndroidManifest.xml:7-10): the manifest declares POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, WAKE_LOCK and VIBRATE.
- FACT: no push messaging package (grep for `firebase_messaging|FirebaseMessaging` in pubspec and lib found nothing) and no foreground-service package (grep for `flutter_foreground|foreground_service|workmanager|wakelock` found nothing).

**Unfinished-workout and resume entry points.**
- FACT(mobile/lib/features/workouts/state/rest_timer_providers.dart:1-24): the rest timer is a provider that derives remaining time from a wall-clock `endsAt`. It survives leaving the page but, INFERENCE, not process death.
- FACT(mobile/lib/features/workouts/state/set_timer_providers.dart:140-188): `SetTimerController` is a `Notifier` using `Timer.periodic`. INFERENCE: set timer state is in-memory only. Not verified that nothing persists it.
- FACT(mobile/lib/features/home/home_page.dart:458, 1015, 1115; mobile/lib/features/workouts/workouts_page.dart:1128): the only "continue" entries are cards that push `/workout/:id?day=...` from scheduled sessions. No "unfinished workout" record was found by greps (`resume|unfinished|inProgress|persist`), but the session repositories were not read. NOT VERIFIED.

**Routes outside the shell vs a recording strip.**
- FACT(mobile/lib/core/router/app_router.dart:415-560): `/workout/:id`, `/exercise/:id`, `/equipment/:id`, `/form-check`, `/posture`, `/photos*` and others are top-level routes, outside `ShellRoute`.
- FACT(mobile/lib/shared/widgets/main_shell.dart:123-163): the `HudNavBar` and any future strip live only in `MainShell`'s `Scaffold`. They are not visible on those routes.
- INFERENCE: a recording strip in the shell would be hidden whenever the user is on a pushed route, including `/workout/:id`.
- FACT(grep `GoRouter.of(context).(go|push)(`): 49 lines in 24 files push pages; `context.go|push` appears on 24 lines in 7 files.

**Back stack.**
- FACT(mobile/lib/shared/widgets/main_shell.dart:111-122): `PopScope(canPop: location == '/home')`, and Back on any other tab goes `context.go('/home')`.
- FACT(mobile/lib/shared/widgets/main_shell.dart:94-98, 160): tab selection uses `context.go`, so tabs replace each other and keep no per-tab history.
- FACT(mobile/lib/features/equipment/workout_player_page.dart:1313): the player pushes `/workouts` as a new page.
- FACT: only two files use `PopScope|WillPopScope|canPop`: `main_shell.dart` (5 lines) and `form_check_page.dart` (3). INFERENCE: no other screen guards Back against losing unsaved work.

## 7. Screen-reader semantics

- **`_BarChart`** (mobile/lib/features/progress/progress_page.dart:663-748): FACT, no `Semantics` anywhere in it.
  - Bars are `AnimatedContainer`s with no label or value. When `showLabels` is true, each bar's number is a plain `Text('${values[i]}')`.
  - INFERENCE: a screen reader reads a run of bare numbers with no axis, unit or day context. With `showLabels: false` (the month chart) nothing is announced.
- **`HudRing`** (mobile/lib/shared/widgets/hud/hud_metric.dart:136-141): with a `semanticsLabel`, announces the label and `value: 'NN%'` and excludes the child. Without one, it returns the painted ring and exposes its child text.
- **`HudProgressTrack` and `HudZoneBar`**: both expose `label` and `value: 'NN%'` (:358-360, :432-434).
- **`SetTimerCard`** (mobile/lib/features/workouts/widgets/set_timer_card.dart:131-181):
  - FACT: the ring is given no `semanticsLabel`, deliberately, so the countdown text and phase label stay audible.
  - FACT: `_Primary` and `_Secondary` are `Semantics(button: true)` with no label, relying on merged child text (comments at :300-301 and :344-345).
  - FACT: mute and voice are `AppIconButton`s with tooltips (:263, :277). Their tooltip text does not change with on/off state, only the icon does.
- **`RestTimer`** (mobile/lib/features/workouts/widgets/rest_timer.dart:136-141): `Semantics(label, value: '<m:ss>, NN%', excludeSemantics: true)`.
- **`set_capture_sheet.dart`**: no `Semantics` calls (grep matched only `autofocus` and `keyboardType`). Fields rely on `labelText`.
- **`coach_hud.dart`** (mobile/lib/features/form_check/widgets/coach_hud.dart): FACT, zero `Semantics` or `ExcludeSemantics` matches.
  - INFERENCE: each gauge is read as separate texts (label, value, suffix, caption) in tree order. Tone is a colour dot only.
- **Live regions** (FACT): present only in `demo_data_banner.dart:45`, `safety_disclosure.dart:67`, `scan_viewfinder.dart:133` and `scan_capture_screen.dart:593`.
  - None on the set timer, rest timer or coach counters. INFERENCE: a ticking countdown is not announced as it changes.
  - `SemanticsService.announce` was not found. `HapticFeedback.heavyImpact()` fires on rest end (rest_timer.dart:72).
- **Header semantics** (FACT): grep for `header: true` returned no matches, so no heading is exposed by the HUD scaffold.
- **`ExcludeSemantics` swallowing state**: FACT, `HudPanel` with a `semanticLabel` excludes the whole child subtree (hud_surface.dart:445-449), `HudButton`, `HudChip` and `_NavTab` do likewise for their children, and `HudSettingRow` with `onTap` excludes its subtitle and trailing widget (hud_metric.dart:737). INFERENCE: a toggle, badge or value passed as `trailing` is not announced when the row is tappable.

## 8. Reduce motion

Using `hudMotionDuration` or `reduceMotion`, FACT:
- `mobile/lib/shared/widgets/hud/hud_surface.dart:721` (button press lift).
- `mobile/lib/shared/widgets/hud/hud_metric.dart:600` (toggle).
- `mobile/lib/core/background/hud_sky.dart:729` (1.6 s photo crossfade).
- `mobile/lib/features/auth/login_page.dart:208`.
- `mobile/lib/features/workouts/widgets/set_timer_card.dart:137` (ring sweep).
- `mobile/lib/features/equipment/widgets/exercise_reference.dart:564, 590`.
- `mobile/lib/features/form_check/form_check_page.dart:82, 1615` (demo animation and fade).
- `mobile/lib/features/scanner/widgets/scan_frame.dart:108` (sweep line).
- `mobile/lib/features/form_check/widgets/coach_demo_clip.dart:193, 214, 241` (video play).
- `mobile/lib/features/onboarding/widgets/ob_shell.dart:84`, `step_body.dart:229`, `onboarding_page.dart:135, 147` (page transitions).
- `mobile/lib/features/progress/progress_page.dart:712` (bar growth).
- `mobile/lib/features/splash/splash_page.dart:62`.

Not using the helper, FACT:
- `mobile/lib/core/router/app_router.dart:140-165` (`_fadeThrough`, 360 ms fade plus slide on every `pageBuilder` route).
- `mobile/lib/core/theme/app_theme.dart:227-255` (`_FadeScalePageTransition`).
- `mobile/lib/features/splash/splash_page.dart:133` (`FadeTransition`); it does check `reduceMotion` at :62, but what it does there was not read.
- `mobile/lib/features/home/home_page.dart`: none found.
- NOT VERIFIED: whether `ScrollBehavior` bounce physics (mobile/lib/main.dart:696-701) is affected by reduce motion. It does not appear to be.
- Whole-tree animation grep shows about 30 animation lines across 16 files; not every `AnimatedSwitcher` or `TweenAnimationBuilder` duration was enumerated.

## 9. Layer rule evidence

All counts are matching lines under `mobile/lib`.
- `Colors.white|Colors.black`: 82 lines in 25 files, of which 3 are in `app_semantic_colors.dart` (likely doc text, not checked). The heaviest are `exercise_reference.dart` (13), `scan_capture_screen.dart` (12), `form_check_page.dart` (11), `coach_hud.dart` (7), `posture_page.dart` (6).
- `Color(0x...)` literals: 204 lines in 17 files. 177 are in the theme files (`hud_tokens.dart` 118, `app_semantic_colors.dart` 39, `app_palette.dart` 18, `hud_typography.dart` 2), 5 in shared HUD widgets, 2 in `hud_sky.dart`, and about 20 across features (`form_check_page.dart` 5, `scan_viewfinder.dart` 3, others 1-2).
- FACT(mobile/lib/core/theme/app_semantic_colors.dart:5-10): the file records an earlier count of 197 `AppPalette.*` uses, 128 `Colors.white|black` and 14 raw literals (2026-08-06). `Colors.white|black` is therefore lower now, but `AppPalette.*` was not recounted.

**Layer used by shell screens.**
- FACT: Home, Workouts and Scan use no `FrostedScaffold`. All three use `HudPanel` or other HUD primitives. Home and Workouts still read `AppSemanticColors` through `theme.colors` (home_page.dart:1234, set_timer_card.dart:121).
- FACT: Progress and Profile use `FrostedScaffold` plus `GlassAppBar` with `HudPanel` inside, so they use both layers.
- FACT: Settings, Login, Splash, Subscription, Onboarding each import both; Settings, Login, Splash and Subscription still use `FrostedScaffold`. Onboarding: NOT VERIFIED which scaffold it uses.
- FACT: `AuroraBackground` is also mounted by the root builder (see corrections), so `FrostedScaffold` screens sit over it and HUD screens sit over `HudSkyBackground` inside the shell.

## 10. Localisation and layout

- FACT(grep `Text\(\s*['"]` over mobile/lib/features): 14 lines in 12 files start a `Text` with a string literal (`coach_recorder.dart` 2, `scan_compare_screen.dart` 2, others 1 each). This under-counts, because it misses multi-line calls and `label: '...'` parameters. NOT VERIFIED: full hardcoded-string total.
- FACT(grep `AppLocalizations.of(|l10n.`): 1453 lines in 93 files use l10n.
- FACT: both ARB files have 1403 top-level keys by pattern (`^  "[A-Za-z]\w*":`), which excludes keys starting with `@`.
- FACT(grep `{x, plural,`): 16 lines in EN and 13 in RU. INFERENCE: 3 plural keys exist in EN with no matching pattern line in RU, or they are written differently. NOT VERIFIED; compare key-by-key.
- FACT: Russian plurals need `few` and `many` forms. It was not checked that the 13 RU entries include them.
- FACT(grep `MediaQuery.sizeOf|LayoutBuilder|OrientationBuilder|breakpoint`): `LayoutBuilder` is used in `progress_page.dart:694`, `hud_metric.dart:469`, `workouts_page.dart:1185`, `measure_ruler.dart:181`, `body_zone_map.dart:160`, `photo_bitmap.dart:48`, `scan_compare_screen.dart:524`. `MediaQuery.sizeOf` appears in `hud_sky.dart:627`, `workouts_page.dart:1337`, `ai_coach_sheet.dart:72`. No width breakpoints or tablet layout exist.
- FACT(grep `setPreferredOrientations|DeviceOrientation` over mobile/lib and `screenOrientation` in mobile/android/app/src/main/AndroidManifest.xml): no orientation lock found in code or manifest. The manifest `configChanges` handles orientation, fontScale and screenSize (line 50).
- NOT VERIFIED: iOS orientation. `mobile/ios/Runner/Info.plist` was not found by glob.

## Items not finished by the agent
- HEAD and branch confirmation (item 0).
- Panel-over-photo contrast numbers (item 2): needs rendered output.
- Keyboard reachability of the 12 files using `GestureDetector` beyond the HUD controls (item 1).
- Profile loading and error states; Onboarding retry; Subscription empty state (item 5).
- Session persistence across process death for the set timer and unfinished workouts (item 6).
- Key-by-key EN/RU ARB comparison and a full hardcoded-literal count (item 10).
