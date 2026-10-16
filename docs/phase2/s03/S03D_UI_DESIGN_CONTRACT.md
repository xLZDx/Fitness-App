# S03-D UI design contract: shell, mode chooser, dashboard skeleton

Status: DRAFT revision 3 for review, not approved. Date: 2026-10-16. Authoring role: ui-designer. Worktree read: branch `phase2/s03d-ui-design-contract` (HEAD da3279f7, after the S02 merge). No code is changed by this document. The review record (revision 2 findings and the revision 3 disposition) is section 19.

**Applied in revision 3 (operator answers of 2026-10-16):** (1) one app: Phase 2 is an update of the same app with one application id, not a second app; (2) keep five tabs, Record is a button over the screen, the alternative is dropped; (3) tablet and large layouts are designed NOW for Android phone, iPhone, iPad, Android tablet and MacBook, with a window-size model, one responsive chooser, a side rail, large-screen Home, Progress and Sources, platform conventions and Mac pointer and keyboard input; (4) Apple builds are design only for now: no iOS, iPadOS or macOS build target is created in S03 and when they are created is an open operator decision; (5) the local activity history opens in the default build whatever the cloud flag says (story S03-0 stays in scope); (6) cloud retention for GPS history offers 90, 365 or 730 days only, the default is 730 days (2 years), "never" is not offered. The list of changed sections is at the top of section 19.

Purpose: a contract that the S03 build sprint (EP-1 mode state, EP-2 mode chooser and per-mode first-run questions, EP-3 Today / This week / Progress from `ActivitySession`, EP-4 sources panel) implements exactly, and that the S03 test agents can turn into functional tests. It carries the design side of two questions the operator has now answered: U-1 (whether the Scan tab is replaced by a Record tab: answered no, five tabs stay) and U-2 (tablet and large layouts now or later: answered now, for the five device families). Decisions still open are listed in section 15.

Tags: FACT = read in a repository file (path given); INFERENCE = concluded from facts; PROPOSED = design choice made here; OPEN = needs an owner's answer; UNGROUNDED = could not be verified in the repository (collected in section 17).

## 1. Sources and what was read

| Source | Used for |
|---|---|
| `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` (S03-D and S03 rows, sections 6, 10) | Scope, dependencies, U-1, U-2, D-9 defaults, DoD |
| `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` (sections 3-7) | Shell proposal, rules, S03-D DoD |
| `docs/phase2/s01/UI0_BASELINE_AUDIT.md`, `..._ADDENDUM.md`, `..._BODYSCAN_DELTA.md` | Tokens, components, states, accessibility baseline |
| `docs/phase2/s02/S02_DESIGN.md` (sections 1-4, 12) and the S02 code under `mobile/lib/features/activity/` | `ActivitySession`, journal, sync presenter surface |
| `mobile/lib/shared/widgets/main_shell.dart`, `hud/hud_scaffold.dart`, `hud/hud_surface.dart`, `hud/hud_metric.dart` | Shell and component facts |
| `mobile/lib/core/router/app_router.dart` (shell and redirect parts) | Router facts |
| `mobile/lib/core/wiring/activity_wiring.dart` (whole file), `core/config/activity_flags.dart` | Journal availability (revision 2, finding U1) |
| `mobile/lib/features/workouts/state/set_timer_providers.dart`, `rest_timer_providers.dart` | What "a workout is running" can mean (revision 2, finding U3) |
| `mobile/lib/features/progress/progress_page.dart` (lines 25-75), `features/onboarding/onboarding_page.dart` (176-193), `features/home/home_page.dart` (78-215) | Insertion points, onboarding finish, Home composition |
| `onboarding/data/step_answered.dart`, `training_context/data/training_context.dart`, `core/settings/app_settings.dart` | Existing first-run questions, locale order, settings |

Not read line by line: the rest of `home_page.dart`, `progress_page.dart` (after line 75), `workouts_page.dart`, `scanner_page.dart`, `app_router.dart` beyond the shell and redirect, `GlassAppBar`, and the ARB files beyond key greps. Where a decision depends on those it is marked OPEN or UNGROUNDED.

## 2. Repository facts this contract builds on

| # | Fact | Evidence |
|---|---|---|
| F1 | The shell is `MainShell`: a transparent `Scaffold` with `extendBody: true`, `HudSkyBackground` as body and `HudNavBar` as `bottomNavigationBar`. It has NO header; each page draws its own title. | FACT `main_shell.dart` 123-163 |
| F2 | Five tabs, hard-coded paths in this order: `/home`, `/workouts`, `/scan`, `/progress`, `/profile`. Labels from l10n keys `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`. Tabs replace each other with `context.go`; no per-tab history. | FACT `main_shell.dart` 69-96, 160 |
| F3 | Back on any non-home tab goes to `/home`; Back on `/home` leaves the app. | FACT `main_shell.dart` 111-150 |
| F4 | `HudNavBar`: floating glass pill, height 72, five equal `Expanded` tabs, selection = ink plus a 4 px accent dot, label upper-cased, one line, ellipsis; each tab is `Semantics(button, selected, label)` with a 44 px minimum height. | FACT `hud_scaffold.dart` 233-370 |
| F5 | Pushed pages (`/workout/:id`, `/exercise/:id`, `/equipment/:id`, `/form-check`, `/posture`, `/photos*`, `/body-scan*`, `/nutrition*`, settings, ...) are top-level routes OUTSIDE the `ShellRoute`; nothing mounted in `MainShell` is visible on them. 50 routes in total. | FACT audit ADDENDUM section 6; BODYSCAN_DELTA section 1 |
| F6 | `/scan` is the equipment recognition screen of the gym flow; `/photos/scan` is the body scan; `/form-check` is the form coach. | FACT audit section 8 item 11 |
| F7 | No mode enum or provider, no recording strip, no tablet layout, no connectivity package, no global offline indicator. | FACT audit sections 2, 5, 7, 10 |
| F8 | Tokens: two layers coexist; the live HUD layer is `HudTokens`. Primitives: `HudPanel` (`dense`, `secondary`, `onTap`, `semanticLabel`), `HudSheet`, `HudButton`, `HudChip`, `HudScreenBody`, `HudScreenTitle`, `HudSectionHeader`, `HudMetricRow`, `HudProgressTrack`, `HudRing`, `HudToggle`, `HudSettingRow`. `minTapTarget` = 44, `screenGutter` 16. | FACT audit sections 1, 3, 4 |
| F9 | `reduceMotion` and `context.hudMotionDuration(...)` exist; no in-app motion toggle. | FACT `hud_tokens.dart` 983-1003 (audit section 6) |
| F10 | Light HUD theme: `warning` contrast 1.50, `danger` 2.69 against the base, zone colours 1.2-2.3, accent `#4B7A00` 4.51 (no margin), nav inactive ink 4.40. Dark theme is comfortable. | FACT audit ADDENDUM section 2; a11y finding computation |
| F11 | Onboarding is mandatory and already asks goal and level, equipment, schedule, body, barriers, personal, lifestyle, health flags, nutrition, screening, preview. `TrainingContext` (gymMachines, outdoorMinimal, home, yoga) is already asked on Home with three answer states. Per D-1 `training_context` stays Phase 1. | FACT `step_answered.dart` 73-89; `training_context.dart` 13-62 |
| F12 | Home is a `HudScreenBody` of about 20 children (greeting, identity row, day panel, week section, recovery panel, quick scan row, body and nutrition cards, deload banner, summary link, upcoming, "More", suggestions). After the first frame Home may open `Day3WelcomeModal` once (launch-count based). | FACT `home_page.dart` 93-108, 118-203 |
| F13 | Progress is `FrostedScaffold` + `GlassAppBar(title: progressProgress)` + a `ListView` with padding `fromLTRB(20, 92, 20, 120)`; it is NOT a `HudScreenBody`. Child order: `_HeadlineStats`, 16 px gap, `ActivitySyncEntryCard`, `BodyScanEntryCard`, 12 px, `NutritionEntryCard`, 24 px, the "last 8 weeks" title and chart panel. Loading and error are not distinguished from empty. | FACT `progress_page.dart` 43-75; audit ADDENDUM section 5 |
| F14 | CORRECTED in revision 2. The journal provider `activityJournalProvider` defaults to null and is overridden only when `ACTIVITY_CLOUD_STREAMS` is on AND a journal opened. `openActivityJournal` returns null immediately when the flag is off; with the flag off no journal is opened, no provider is overridden and "the app behaves as it did before S02". Null therefore means EITHER "flag off" (the default build) OR "opening failed"; the two cannot be told apart from the provider alone. The sync repository provider is likewise not overridden when off. When a journal exists: `ActivityJournal.list()` returns live entries WITHOUT streams as `JournalEntry{session, state, generation, streamsLoaded}`; `JournalState.syncState` is `pending`/`synced`/`upload_failed`/`sync_conflict`; `streamLost` exists; there is no change stream. | FACT `activity_wiring.dart` 1-5, 29-41, 45-49, 64-65; `activity_journal.dart`; `journal_models.dart`; `sync_conflict_presenter.dart` |
| F15 | `ActivitySession` fields usable on a card: `sport` (`SportType`: running, trailRunning, walking, hiking, cycling, indoorCycling, mountainBiking, swimmingPool, swimmingOpenWater, rowing, strength, other), `startUtc`, `endUtc`, `utcOffsetMinutes`, `movingTimeS` (nullable), `durationMs`, `summary` (nullable numbers), `provenance` (`SourceRecord{sourceId, sourceKind, importedAt, deviceModel, appPackage, externalId}`). | FACT `activity_session.dart` 109-158; `source_record.dart` |
| F16 | `strength` is owned by the workout model, every other sport by `ActivitySession`; no dual write; "bridging or merging in the UI is S03". | FACT `workout_model_ownership.dart`; S02_DESIGN 3.6 |
| F17 | Native recordings use `sourceId = 'app'`, `SourceKind.companionApp`. `SourceKind` has five values (`platformHealth`, `bleSensor`, `vendorCloud`, `companionApp`, `fileImport`); an unknown name parses to `fileImport`. Capability-matrix ids: `health_connect`, `healthkit`, `ble_hr`, `ble_rsc`, `ble_csc`, `ble_cp`, `ble_ftms`, `wear_os`, `vendor_cloud`. `DeviceSource.healthStatus()` returns `SourceHealth{ok, permissionMissing, unavailable, stale, error}`; no adapter exists. | FACT `native_session_id.dart`; `source_kind.dart` 8-22; `device_source.dart` 88-106, 151-174 |
| F18 | No recorder exists (no location package, no foreground service) until S04-S06. | FACT audit sections 2, 6 |
| F19 | One notification channel (`workout_reminders`); a tap does not route anywhere (no tap callback registered). | FACT audit ADDENDUM section 6 |
| F20 | `AppSettings` holds theme, language, notifications, tier override. No units setting, no mode. `kSupportedLocaleCodes = ['ru', 'en']`: Russian is the FIRST entry and therefore the fallback and default experience (`AppSettings.language` defaults to Russian). | FACT `app_settings.dart` 9, 87-140 |
| F21 | Body-related flags (`BODY_SCAN_CLOUD`, `FOOD_AI`, `FOOD_LOOKUP`) are compile-time, hide widgets and never gate routes. `ScanAccess` gating is rendered today as one bare text with no action. | FACT BODYSCAN_DELTA sections 1, 3 |
| F22 | Reusable precedents: consent sheet with explicit agree/decline (`cloud_consent_sheet.dart`), error plus retry (`workouts_page.dart` 461-489), food diary states, `SemanticsService.announce` used in `check_these_chips.dart:44`, `analysis_progress_view.dart:78`, `kcal_range_slider.dart:151`. | FACT audit ADDENDUM section 5; BODYSCAN_DELTA sections 3, 5; grep |
| F23 | What a running gym workout is in code. `setTimerProvider` is a plain (not auto-dispose) `NotifierProvider<SetTimerController, SetTimerState>` driven by `Timer.periodic`; `SetTimerState{phase, setNumber, secondsLeft, totalSets, progress, running}` with phases idle, gettingReady, work, rest, done; it carries NO exercise id or route. `restTimerProvider` is app-scoped by design; its state is derived from a wall-clock `endsAt` (`isIdle`, `isPaused`, `isRunningAt(now)`, `isFinishedAt(now)`, `remaining(now)`) and a finished rest stays non-idle until `clear()`. Both survive leaving the workout page; neither survives process death. The player page lives at `/workout/:id`, outside the shell. There is no other app-level "workout in progress" flag found in the files read (UNGROUNDED for the rest of the code). | FACT `set_timer_providers.dart` 102-133, 140-218, 247; `rest_timer_providers.dart` 41-223; audit ADDENDUM section 6 |
| F24 | Onboarding finish (`_submit`) ends with `context.go('/home')`; the router redirects an onboarded signed-in user away from `/onboarding` to `/home`. `/onboarding/edit` uses the same page, so the same finish code also runs after a profile edit by an existing user. | FACT `onboarding_page.dart` 179-193; `app_router.dart` 120, 150-152 |
| F25 | HUD semantics today: `HudSettingRow` with `onTap` is `Semantics(button, label: title)` wrapping `ExcludeSemantics` (subtitle and trailing lost, no enabled/selected/hint); `HudPanel` with `semanticLabel` is button + label and excludes its subtree; `HudChip` uses its visible text as the label and `HudButton`/`HudChip` hard-code `minHeight: HudTokens.minTapTarget` (44) and single-line text. | FACT `hud_metric.dart` 734-737; `hud_surface.dart` 445-449, 700-736, 836-856 |

| F26 | (Revision 3.) Platform targets: the `mobile` folder has only an `android` platform folder; no `ios`, `macos`, `web`, `windows` or `linux` folder exists in this worktree, and `.metadata` lists only the `root` and `android` platforms. The line `ios/Runner.xcodeproj/project.pbxproj` under `unmanaged_files` in `.metadata` is a leftover reference, not a folder. One Android application id exists: `com.fitnessapp.fitness_app.sptr` (debug adds the suffix `.debug`); `minSdk` 26, `targetSdk` 36. | FACT `mobile/.metadata` 13-30; `mobile/android/app/build.gradle` 121-132, 170 |
| F27 | (Revision 3.) The Android activity declares `configChanges` for orientation, screen size, smallest screen size, screen layout, density, font scale, layout direction, locale and ui mode (so a resize or rotation does not restart it) and `windowSoftInputMode=adjustResize`. The manifest has NO `screenOrientation` attribute and NO `resizeableActivity` attribute. No code under `mobile/lib` calls `setPreferredOrientations`. So today the app rotates freely and, with `targetSdk` 36, the platform default for resizability applies (INFERENCE; not verified on a device). | FACT `AndroidManifest.xml` 50, 52; grep of `mobile/lib` |
| F28 | (Revision 3.) Responsive code today: there is no breakpoint, no `NavigationRail`, no `Shortcuts` or `CallbackShortcuts`, no `MouseRegion` or cursor, no `Scrollbar`, no `Cupertino*` widget, no menu bar and no window-size class anywhere in `mobile/lib`. `MediaQuery` is read for insets (`paddingOf`), for `disableAnimations`, for the sky image cache width and for a few sheet heights (`sizeOf(...).height * 0.75` and `* 0.8`); `LayoutBuilder` appears only inside a slider (`hud_metric.dart` 469) and one Progress chart row (`progress_page.dart` 702). Content is not width-constrained: pages fill the window width. | FACT grep of `mobile/lib`; `shell_insets.dart`; `hud_scaffold.dart` 45-56, 267; `workouts_page.dart` 1337; `ai_coach_sheet.dart` 72 |
| F29 | (Revision 3.) Fonts are bundled, not system fonts: Archivo (Latin) with Inter as the Cyrillic fallback, Barlow Condensed for display text, Roboto Mono for numbers. So type looks the same on every platform; there is no San Francisco or Roboto system-font path. Material 3 is on (`useMaterial3: true`). The page transition is a custom fade-and-scale registered for Android and iOS only (no entry for macOS), and there is no Cupertino swipe-back page. | FACT `hud_typography.dart` 18, 48-55; `app_theme.dart` 14-15, 123, 227-230, 238 |
| F30 | (Revision 3.) Input: `HudButton`, `HudChip` and `HudToggle` are built on `GestureDetector` and get keyboard activation (Enter, NumpadEnter, Space) only through `HudKeyboardActivation`; they draw no focus ring (audit). The nav tab is an `InkResponse`. No hover or cursor handling exists. `HapticFeedback` is called in exactly two files (`rest_timer.dart`, `scan_ports.dart`). The wallpaper (`HudSkyBackground`) is `BoxFit.cover`, so a wide window crops the photograph (INFERENCE for the crop). | FACT `hud_surface.dart` 20-59; `hud_scaffold.dart` 326-337; grep; `hud_sky.dart` 735 |

INFERENCE I1 (revised): `strength` lives in the other store (F16) and no recorder exists (F18), so the `ActivitySession` list is EMPTY for almost every real user during the whole of R2 alpha until S05. The first thing a Phase 1 user must NOT see is a "no activity" message above their real gym history (finding U5); the dashboard block is therefore demoted while empty (S-7).

INFERENCE I2: nothing mounted in `MainShell` is visible on pushed routes, including the workout player itself (F5).

## 3. Design principles for this contract

1. Reuse, do not invent. Every new surface is built from the HUD primitives of F8 on the live `HudTokens` layer, extended only as stated in section 9.1. No new blur radius, colour, or type family.
2. Existing flows do not move. The five tab paths and order (answer to U-1, section 5), the Back behaviour (F3), the gym QR flow, and the form coach are untouched (goal G-5).
3. Mode is a lens, not a different app. A mode changes the first cards on Home, the target of the Record action and the sort order of discipline tiles. It never removes global content and never starts, stops, or resets anything.
4. Missing is shown as missing. No zero for unknown, no estimate without a marker, no sum of energy across sports.
5. Nothing asks for a permission at launch or in the chooser. Location is not requested anywhere in S03.
6. (Rewritten in revision 3.) Local first. The operator answered OD-9 (the question "does the on-device activity history open in the default build?") on 2026-10-16: yes, always, whatever the cloud flag says. Story S03-0 (the first S03 story: open and recover the local journal at app start) is in scope, section 4.4. Today the journal is not opened in the default build (F14), so S03-0 changes that. Every dashboard surface still distinguishes journal availabilities and never offers "Try again" for a state that cannot be retried; `notEnabled` remains only as a defensive value for a build in which S03-0 is switched off (tests, overrides). Cloud wording appears only when `ACTIVITY_CLOUD_STREAMS` is on.
7. Do not promise what is not built. A mode whose recorder is not shipped is labelled as coming later and cannot be started; no copy claims dedup with external sources.

## 4. Mode model (EP-1 contract)

Modes: TRAIN, RIDE, EXPLORE, BODY (roadmap section 1).

### 4.1 Availability

| Mode | S03 availability | Reason |
|---|---|---|
| TRAIN | available | Existing gym, plans and form coach |
| BODY | available | Body scan and nutrition routes exist (F6, F21); inner features keep their own flags |
| EXPLORE | coming later | No recorder until S04/S05 |
| RIDE | coming later | No recorder until S04/S06 |

PROPOSED: availability is one table (mode to available/comingLater) so S05/S06 switch modes on by changing it. Availability is separate from D-9 monetisation (default: no paywall, no lock icons).

### 4.2 Persisted mode state (inputs and outputs, not code)

Revision 2 (finding U2): ONE persisted field decides who sees the chooser and who sees the upgrader intro. It replaces the draft's two booleans.

| Item | Values | Rule |
|---|---|---|
| `selectedMode` | train, ride, explore, body | Default TRAIN. Only an available mode can be selected. |
| `chooserStatus` | `absent`, `pending`, `migrated`, `resolved` | See the transition table below. Persisted on the device with `selectedMode`. |
| `answers[mode]` | unanswered, skipped, answered(values) | Three-state pattern of `TrainingContextAnswer` (F11). |
| Output event | `modeChanged(from, to)` | Emitted once per real change; selecting the current mode emits nothing. |

Transitions of `chooserStatus` (all writes are awaited before the navigation they precede):

| When | From | To | Why |
|---|---|---|---|
| App start, before the first Home frame: field absent AND the signed-in profile is onboarded | absent | `migrated` | An existing (Phase 1) user. They get the intro card, never the forced chooser. |
| Onboarding finish (`_submit` success, F24) when the field is absent | absent | `pending` | A brand-new account. The write happens before `context.go('/home')`. A profile edit via `/onboarding/edit` never changes it because the field is already set by the start-up migration. |
| Home first build with `pending` | pending | (unchanged) | Home pushes the chooser S-1 once per app start until resolved. This also covers "app killed during the chooser". No router redirect rule is added. |
| User taps Continue or Decide later in S-1, or "Choose a mode" / "Not now" on the intro card | pending or migrated | `resolved` | Single terminal state. |

Consequences: a new user who taps "Decide later" is `resolved` and never sees the intro card (the draft's contradiction); an upgrader is `migrated`, never sees the chooser by force, sees the intro card once; a new user killed mid-chooser is still `pending` and sees the chooser again. The state is per device, not per account (OPEN DQ-2: if a user signs into another account on the same device the field is not reset; owner architect). Storage location (`AppSettings`/shared preferences vs profile) is DQ-2; the contract requires restore before the first Home frame so there is no flash of the wrong mode.

### 4.3 Rules

R-M1. Changing mode never stops, pauses, resets or edits a running session or timer.
R-M2. Changing mode never changes the route or `selectedIndex` of the current tab.
R-M3. Mode change takes effect immediately on visible content and is announced (section 12).
R-M4. A notification tap, deep link or "resume" never changes the selected mode.

### 4.4 Journal availability (finding U1; a scope item)

The dashboard (S-6, S-7, S-8) reads the journal through ONE availability value with three cases, a contract input the S03 build must provide:

| Availability | Meaning | UI rule |
|---|---|---|
| `open` | Journal opened and recovered | Normal states (loading, empty, data) |
| `notEnabled` | No journal was opened because this build or test configuration does not enable it. After S03-0 this is NOT the default build any more; it remains a defined value for tests, overrides and a build that switches S03-0 off | No error, no retry, no "Problem" chip. Dashboard block hidden; Sources shows the plain line "Activity history is not active in this build." |
| `failedToOpen` | Opening or recovery threw | Error panel with "Try again" that reopens ONCE (disabled while busy); no loop |

Scope item S03-0 (ANSWERED 2026-10-16, decision OD-9: yes, always): the app opens and recovers the local journal at start regardless of `ACTIVITY_CLOUD_STREAMS`, while every cloud piece (sync repository, uploader, tombstone push, conflict card) stays behind the flag. Effect: the default build shows the real empty state and, from the first recorder sprint (S05), recorded sessions. It changes the S02 statement that with the flag off "no journal is opened" (`activity_wiring.dart` header, F14); the architect records that change in the S03-0 story. Consequences for this contract:
- In the default build (flag off) the expected availability is `open` or, after a failed open, `failedToOpen`. It is never `notEnabled`.
- Criteria written as "[flag off]" now mean "cloud flag off, journal open" (the default build). The `notEnabled` rows of the state tables remain as a defensive state that tests force by override; they are not a product state of the default build.
- The empty-journal rule is unchanged: with zero sessions the Progress tab shows only the quiet Sources row and Home shows no "Activity today" card (finding U5).

## 5. The shell (answer to U-1: five tabs, Record is a button over the screen)

U-1 was the question "should a context-sensitive Record tab replace the Scan tab?". The operator answered on 2026-10-16: no, keep five tabs; Record is a button over the screen. The five-tab shell below is the contract. Rejected alternative (two lines): a bar of Home, Mode, Record (centre), Progress, Profile was dropped because it would move the gym QR scan to two taps and leave the bar for Phase 1 users, and its centre button would act only in Train and Body during the whole R2 alpha.

Context: F1 (no header), F2/F4 (five tabs, one-line labels), F5 (pushed routes hide shell chrome), F6 (Scan is the gym QR recognition), F18 (nothing to record outside the gym until S04), F28 (no responsive code today).

### 5.1 Contract: five tabs, Record is a shell action

The same five destinations appear in two presentations chosen by window size (section 10): the floating bottom bar (compact and medium widths) and a side navigation rail (expanded width, 10.4). Destinations, order, labels, icons and paths are identical in both. Tabs unchanged: Home, Workouts, Scan, Progress, Profile; same labels, order, icons, paths. New in the shell:
1. A "dock" slot directly above the nav bar (S-4). When idle it shows a compact Record pill on Home, Workouts and Progress. While a session runs the same slot shows the Recording strip on ALL FIVE tabs (finding U7: a running workout is visible everywhere in the shell; the pill stays only where starting something makes sense).
2. A mode chip on Home only (greeting row). Progress is always the whole picture, so it has no chip (finding U4: Progress has no HUD title row, F13).
3. The Workouts tab stays "Workouts" in every mode.

Plain-words consequences:
- Nothing a Phase 1 user already uses moves. The gym QR scan stays one tap. Lowest regression risk for G-5 and for tests that assume five fixed tabs.
- The bar has no Ride, Explore or Body entry; they are reached through the Home chip, the Record pill and cards.
- The Record pill is not in the centre of the bar, so it is less prominent than the film's centre action.
- Reversible: the tab set is one configuration list (5.3).

### 5.2 Rejected within the five-tab shell: a mode-named label on the Workouts tab
It needs the tab label, icon and target page to change while the user stays on the tab (F2, F3), and no tab page exists for RIDE/EXPLORE in S03.

### 5.3 Build requirement
PROPOSED: nav items (icon, label, path, selected-index meaning) come from ONE configuration list read by `MainShell`, and BOTH presentations (bottom bar and side rail) are built from that same list, with a test that the list equals today's five tabs (AC-SH-1, AC-SH-3). This also keeps a later change of the tab set a one-place edit. The "Option B delta" lines of revision 2 are removed from the screens.

## 6. Journeys

Screen ids (S-n) refer to section 7.

### J1. First run (new account)
1. The user completes the existing onboarding (unchanged, F11). At finish, if `chooserStatus` is absent it is set to `pending` before navigating to `/home` (F24, 4.2).
2. Home builds, sees `pending`, and opens the Mode chooser S-1 once (replace, so Back does not return to the empty Home behind it).
3. The user selects one available card and presses "Continue" (the choice is saved only by Continue, so the card description can be read). "Decide later" keeps TRAIN. Both set `resolved`.
4. Per-mode questions S-2: only unknown ones, maximum 3, each with Skip.
5. The user lands on Home with the chosen lens; the Record pill is one tap from the first action (supports G-1 for what exists in S03).
Failure paths: saving the mode fails -> S-1 error state, user continues in TRAIN for the session and the chooser is offered again next start (`pending` unchanged); app killed during the chooser -> still `pending`, chooser again.

### J2. Switching mode while a workout is running (leave-and-return)
Precondition (what "running" means, finding U3, defined in S-4): a set timer is active (phase gettingReady, work or rest, running or paused) or a rest timer is running, paused, or finished-but-not-cleared within 10 minutes.
1. The user is on the workout page (`/workout/:id`, pushed, F5) with a timer running. The shell, the chip and the strip are NOT visible there.
2. They press Back (or the existing flow pops to the Workouts tab). The shell is visible again; the Recording strip appears in the dock on the tab they land on, showing the same state and elapsed time.
3. They go to Home and tap the mode chip -> Mode switcher S-3. The strip stays visible behind the sheet.
4. They choose another available mode. The lens changes; the strip content, timer and elapsed time are unchanged.
5. They tap the strip. It opens the stored destination (the workout page that started the timer; if no destination is known, `/workouts`) with the timer exactly as it was.
6. No dialog asks whether to stop anything; no timer pauses.
Edge: opening the workout page of a DIFFERENT exercise while a timer is running shows the same global timer state (the providers are not keyed by exercise, F23): existing behaviour, not changed or hidden by S03 (listed in section 16).
Edge: Record in another mode while a session runs: the pill is not shown (the strip occupies the dock). Entry points elsewhere (Home start cards) keep today's behaviour.

### J3. Returning user
1. The app opens; the last selected mode is restored before Home draws.
2. If the app was only backgrounded and a timer was running, the strip is shown at once from the live providers. If the process was killed, both timers are gone (F23) and no strip appears; no copy claims recovery (crash-safe GPS resume is S04).
3. Today and This week show local data immediately; cloud wording appears only with the cloud flag on.
4. A tapped reminder notification follows J6.

### J4. Upgrader (existing Phase 1 user, first launch with S03)
1. At start-up the migration sets `chooserStatus = migrated` (4.2). Mode is TRAIN. The five tabs and Home look as before plus the mode chip and the Record pill.
2. A non-blocking "Mode intro" card (S-6) is shown once at the top of Home. It is not shown in a Home session in which `Day3WelcomeModal` is displayed (finding U8); it appears on the next Home build instead. Actions: "Choose a mode" (opens S-1) and "Not now". Either sets `resolved`.
3. Nothing is forced; the intro never appears twice and never appears to a `pending` or `resolved` account.

### J5. Change mode when idle
Chip -> S-3 -> pick -> immediate. Available rows apply at once; "coming later" rows open the Coming-later sheet and do not change the mode.

### J6. Reminder notification tap
1. A scheduled-workout reminder is tapped (channel `workout_reminders`, payload = scheduled session id, F19). The contract requires a tap callback opening the same destination as the Home start card (`/workout/:id?day=...`).
2. Mode is not changed (R-M4). If sign-in or onboarding redirects intervene, the tap target is dropped (no deferred routing, DQ-8).
3. A session id that no longer exists lands on Home with the snackbar "That workout is no longer scheduled".
UNGROUNDED: the payload-to-route mapping and where the callback is registered.

### J7. Offline use
The dashboard and Record sheet need no network. Network-dependent BODY actions keep their own states. No global connectivity banner (F7). Offline in S03 means the cloud line is absent or says Waiting, never a blocking error.

### J8. Opening the Sources panel
Progress -> "Sources" row -> S-8. In S03 only "Recorded in this app" can contain data.

### J9. Tapping an unavailable mode
Chooser or switcher: the card says "Coming later"; tap opens a small sheet with one sentence and "Back" / "Choose Train for now". The mode does not change. No waitlist (OD-4).

### J10. Sign-out with local activity
Because the journal now always opens (OD-9 answered), a signed-in user can hold activity only on the device, so this journey no longer depends on the cloud flag. The CONDITIONAL label of revision 2 is removed: it depended on OD-8 (who builds the sign-out hooks), not on OD-9, and the design is kept unchanged. ASSUMED in revision 3 (section 15, OD-8): the warning sheet S-10 is built in S03 together with the Sources panel; the operator may still move it to the consent-centre sprint. Signing out with a non-empty journal opens a sheet "You have {n} activities stored only on this device" with "Export first (GPX/FIT)", "Sign out and delete from this device" (destructive, second confirmation), "Cancel". An empty or unavailable journal signs out with no prompt. Account deletion needs no prompt.

## 7. Screens and their states

State vocabulary: LOADING, EMPTY (valid, nothing yet), PARTIAL (missing shown as missing), ERROR, OFFLINE, NOT-AVAILABLE, SUCCESS. Journal-dependent screens use the three availabilities of 4.4. A state that does not apply is stated as n/a with the reason.

Copy strings are English; Russian is authored in the S03 build under the per-key budgets of section 13. Key names are PROPOSED. Test keys (`Key('...')`) are listed per screen and are part of the contract.

### S-1. Mode chooser (full screen route outside the ShellRoute)

Purpose: pick the first mode, or change it. Reached from J1 (while `pending`), the intro card, and the switcher "See all modes".

Layout (Compact class; Medium and Expanded layouts are in the part headed S-9 below, they are the same screen): `HudScreenTitle` "What do you want to do?" + subtitle; 2x2 grid of Mode cards C-1 (order Train, Ride / Explore, Body; gap 12; gutter 16); under the grid a description area showing the focused/selected card's description (NOT a live region, finding A7; each card carries the same description as its semantic hint); footer: primary `HudButton` "Continue" (enabled only when an available mode is selected) and, while `chooserStatus` is `pending`, text button "Decide later".

Card face: icon, one-word name, one-line blurb, optional chip ("Selected", "Coming later"). No photograph in S03 (licensed photography absent, U-3 default; the slot is reserved for UI-M). No corner brackets (capture/live device; scanner widgets unread). Keys: `modeChooser.card.train|ride|explore|body`, `modeChooser.continue`, `modeChooser.decideLater`, `modeChooser.description`, `modeChooser.saveError`.

Copy (English; mode-name sentences are full-sentence keys per mode, section 13):
| Key | EN |
|---|---|
| `modeChooserTitle` | What do you want to do? |
| `modeChooserSubtitle` | You can change this any time in two taps. |
| `modeTrainName` / `modeTrainBlurb` | Train / Gym, plans and technique |
| `modeRideName` / `modeRideBlurb` | Ride / Routes and rides |
| `modeExploreName` / `modeExploreBlurb` | Explore / Walk, run and hike |
| `modeBodyName` / `modeBodyBlurb` | Body / Progress, food and weight |
| `modeTrainDesc` | Follow your plan, scan equipment, and check your form. |
| `modeRideDesc` | Record rides and follow routes. |
| `modeExploreDesc` | Record walks, runs and hikes. |
| `modeBodyDesc` | See your progress, log food and track weight. Estimates are shown as estimates. |
| `modeComingLater` | Coming later |
| `modeSelected` | Selected |
| `modeContinue` | Continue |
| `modeDecideLater` | Decide later |
| `modeComingLaterSheetTitle` (select by mode) | Ride is coming later / Explore is coming later |
| `modeComingLaterSheetBody` | You cannot start this yet. Everything else works as before. |
| `modeComingLaterSheetAction` | Choose Train for now |
| `modeSaveError` | We could not save your choice on this device. You can continue; we will ask again next time. |

States:
| State | Behaviour |
|---|---|
| LOADING | Saved mode is read before the screen shows. If it takes over 300 ms show four card outlines with buttons disabled; no spinner (nothing loops). The grid never reorders after load. |
| EMPTY / PARTIAL / OFFLINE | n/a (four fixed cards, local, no network). |
| ERROR | Save failed: selection still works for this session; `modeChooser.saveError` shows; Continue works; `chooserStatus` stays `pending`. |
| NOT-AVAILABLE | RIDE and EXPLORE cards are ENABLED (focusable, tappable) so the sheet can open; their semantics state "Coming later" in label and hint (finding A8); they can never become selected. |
| SUCCESS | After Continue: lens applies and the route pops to Home (first run: replaces the chooser). |

Acceptance criteria (all observable; widget tests with an in-memory settings fake):
- AC-CH-1. The four keys `modeChooser.card.*` exist and appear in reading order train, ride, explore, body (compare the `Rect.top/left` order or the semantics traversal order).
- AC-CH-2. Tapping `modeChooser.card.ride` opens the Coming-later sheet; the fake settings store receives no write; `modeChooser.continue` stays disabled if nothing available is selected.
- AC-CH-3. Select train then body: exactly one card has `isSelected` in the semantics tree.
- AC-CH-4. `modeChooser.decideLater` writes `selectedMode=train` and `chooserStatus=resolved`; a fresh app start with that store does not push the chooser.
- AC-CH-5. (Rewritten, finding U2.) With `chooserStatus=pending` and no Continue/Decide later tapped, restarting the app (new `ProviderScope`, same store) pushes the chooser again on the first Home build; with `resolved` or `migrated` it does not.
- AC-CH-6. A store whose write throws shows `modeChooser.saveError`, Continue still navigates to Home, and `chooserStatus` remains `pending`.
- AC-CH-7. Pumping S-1 produces zero calls on a mocked permission method channel.
- AC-CH-8. (Rewritten.) Start-up migration: store with absent field + onboarded profile -> `migrated` and the chooser is NOT pushed; store absent + not onboarded -> stays absent; onboarding finish with absent field -> `pending` is written before navigation to `/home`; onboarding finish from `/onboarding/edit` (field already set) writes nothing.

### S-2. Per-mode first-run questions (full-screen steps in the onboarding look)

Purpose: 1-3 questions for the selected mode, each visibly changing something. Reuses `ob_shell` and `inputs` (F11 precedent); not a new framework.

Rules:
- Ask only what is unknown: onboarding answers are never asked again; for TRAIN the "where" question is skipped when `TrainingContext` is answered or skipped (F11).
- Every question has Skip (stores `skipped`, never asked again; revisit location DQ-7).
- Each states what it changes in one line.
- No health, body or location questions here.
- Maximum 3 questions per mode (DQ-6); one per screen; "Question 1 of 2" is a polite announcement on step change.

Questions (available modes only):
| Mode | Question | Options | Changes |
|---|---|---|---|
| TRAIN | "Where do you train most?" | Gym, At home, Outdoors, Yoga / Skip | Writes the existing `TrainingContext` answer; sets the first Train-lens card |
| BODY | "What do you want to start with?" | Progress photos, Food diary, Weight trend / Skip | First BODY card on Home and first row in the Record sheet; opens nothing, requests nothing |
| BODY (age refused) | Same question; options refused by the existing access gate are disabled with the existing reason text, not hidden | | Reuses `ScanAccess`; no new age rule (S14-D) |

Design stubs for later (not built): EXPLORE "Walk / Run / Hike" and an experience tier; RIDE "bike type" and the tier. The component supports single choice with Skip and a tier row, nothing more.

States: LOADING (saving: button busy and disabled, minimum 300 ms feedback shown as text "Saving", no spinner loop); ERROR (inline "We could not save this. Try again or skip." with Retry and Skip; Back and Skip always work); EMPTY / OFFLINE n/a; NOT-AVAILABLE (refused option disabled with reason).

Keys: `modeQuestion.option.<id>`, `modeQuestion.skip`, `modeQuestion.progress`.
Acceptance criteria:
- AC-Q-1. With an answered or skipped `TrainingContext`, selecting TRAIN shows zero question screens (the chooser's Continue goes straight to Home).
- AC-Q-2. Skip writes `skipped`; reopening S-1/S-3 for that mode does not show the question again.
- AC-Q-3. After answering the BODY question with "Food diary", `home.card.nutrition` precedes `home.card.bodyScan` in the Home lens key order (and the reverse for "Progress photos").
- AC-Q-4. No mode produces more than 3 question screens; `modeQuestion.progress` text count equals the number of screens shown.
- AC-Q-5. A save that throws leaves Skip and Back enabled (find by key, `isEnabled`).
- AC-Q-6. A refused option is present, `isEnabled == false` in the semantics tree, and its reason is in the same semantics node's value or hint.

### S-3. Mode switcher sheet

Purpose: switch in two taps from Home (chip). `HudSheet`; its form depends on the size class only (bottom sheet on Compact and Medium, anchored popover on Expanded, table of 10.6); scroll-controlled, safe-area aware, one instance (opening twice is a no-op, same guard as `SyncConflictSheet`).

Content: header "Choose a mode"; four rows (icon, name, blurb, check on the current one, "Coming later" chip on unavailable ones) with `Semantics(inMutuallyExclusiveGroup, selected)`; link row "See all modes" (opens S-1); a secondary line "{n} quick questions" on a mode with unanswered questions (opens S-2).

Behaviour: tapping an available row applies at once and closes the sheet (trivially reversible, so no confirm). Unavailable rows open the Coming-later sheet. Dismissal changes nothing. A running session is never listed in it and never affected (R-M1).

Copy: `modeSwitcherTitle` "Choose a mode"; `modeSwitcherSeeAll` "See all modes"; `modeSwitcherQuestions` (plural) "{n} quick questions".
States: LOADING n/a (in-memory); ERROR (save failed: lens changes for this session, snackbar "We could not save this choice on this device."); OFFLINE n/a; NOT-AVAILABLE per row.
Keys: `modeSwitcher.sheet`, `modeSwitcher.row.<mode>`, `modeSwitcher.seeAll`.

Acceptance criteria:
- AC-SW-1. From Home, tap `home.modeChip`, tap `modeSwitcher.row.body`: two taps, the Home lens key order is the BODY order and the settings store holds `body`.
- AC-SW-2. With the fake gym timer providers in a running state, after the switch `setTimerProvider` and `restTimerProvider` states are identical (by equality) and `strip` shows the same label.
- AC-SW-3. Dismiss by scrim: no write. Tapping the current mode's row: no `modeChanged` event (spy on the provider).
- AC-SW-4. Calling `SyncConflict`-style `show` twice quickly yields one `modeSwitcher.sheet` in the tree.
- AC-SW-5. Rows for ride and explore never write.

### S-4. Shell dock: Recording strip and Record pill

Purpose: the one persistent shell element above the nav bar. Idle -> Record pill (Home, Workouts, Progress). Running -> Recording strip on all five tabs (finding U7). Lives in `MainShell` between the body and the nav bar; its height is added to the bottom clearance of every tab (see "Padding" below).

#### What "a session is running" means in S03 (finding U3)
`ActiveSessionStatus` is derived from the two real providers (F23), read-only:

| Source | Strip appears when | Strip state |
|---|---|---|
| `setTimerProvider` | `phase` is gettingReady, work or rest | `running == true` -> "Workout in progress"; `running == false` -> "Paused" |
| `restTimerProvider` | not idle AND (running now OR paused OR finished less than 10 minutes ago) | running -> "Resting" + remaining time; paused -> "Paused"; finished -> "Rest finished" |

Priority when both apply: the set timer's state. `phase == done`, `idle`, or a rest finished more than 10 minutes ago (derivable from `endsAt`) hides the strip. An open workout page with no timer has no signal and is NOT a running session (the Home start card remains the way back). `ActiveSessionStatus` fields: kind, title, mode, state, elapsed or remaining (from a clock source), destination. Destination: neither provider holds an exercise id or route (F23), so S03 adds a tiny provider written by the workout page when a set or rest starts (the route string); if empty the strip opens `/workouts`. UNGROUNDED: whether another app-level "workout in progress" flag exists; the architect must confirm before build. Future sources (GPS recording, S04) implement the same `ActiveSessionStatus` without changing the strip.

#### Recording strip
Layout: width of the nav-bar inset, min height 56, `HudPanel(dense)`: state icon + word (not colour), title, mode label, time (monospace), chevron (mirrors in RTL). The whole strip is one button.

Copy: `stripWorkout` "Workout in progress"; `stripPaused` "Paused"; `stripResting` "Resting"; `stripRestDone` "Rest finished"; `stripResumeHint` "Tap to resume".

Rules:
- R-S1. At most one strip. While it shows, the pill is not shown.
- R-S2. Not visible on pushed routes, including the workout page (F5, I2). Accepted for S03 per OD-7: a user must leave the workout page to see it.
- R-S3. No modal is ever shown for the strip; tapping navigates.
- R-S4. Seconds are NOT part of the semantics (section 12).
- R-S5. Process death clears both timers; no strip, no recovery claim.

States: LOADING n/a; running/paused/resting/rest-finished as above; ERROR (a provider throws): strip hidden, no blocking error; OFFLINE n/a; EMPTY = pill.

#### Record pill
Input: selected mode and its availability. Output: opens S-5. A `HudButton` with `minHeight` 48 (extension, 9.1), right-aligned, 12 above the nav bar, icon + "Record". Copy: `recordPill` "Record".

#### Padding and compaction
- The fixed bottom clearance becomes nav bar (72) + its bottom inset + dock (56) + gap (12) only while the dock shows something. Every tab that reserves space for the nav bar must also reserve the dock. Progress is a plain `ListView` with fixed bottom padding 120 (F13): S03 changes it to 120 + dock height while the dock shows. Home and Workouts use `HudScreenBody`/`shellBottomObstruction`; the implementer confirms those paths reserve the dock without double padding (UNGROUNDED, 17.5).
- Compaction: when the visible height above the dock is under 240 dp (landscape, split screen, large text), the pill collapses to a 48x48 icon button with the same accessible name, and the strip becomes a single line 48 high. Fixed chrome (nav 72 + 14 + dock 56 + 12) is about 154 dp plus safe areas.

Keys: `shell.dock`, `shell.dock.recordPill`, `shell.dock.strip`.
On the side-rail presentation (10.4) there is no dock: the Record pill and the strip move into the rail's Record slot at the top of the rail, and the strip replaces the pill there while a session runs. Visibility differs by presentation (review of revision 3): on the bar presentation the pill shows on Home, Workouts and Progress only and the strip on all five tabs; on the rail presentation the Record slot is reserved and shown on all five tabs (idle: enabled Record button opening S-5; running: the strip), so the rail never changes height or shifts the destinations (10.4; ASSUMPTION for the operator, section 15).

Acceptance criteria:
- AC-ST-1. With idle timers: `shell.dock.recordPill` exists on `/home`, `/workouts`, `/progress` and not on `/scan`, `/profile`; `shell.dock.strip` exists nowhere.
- AC-ST-2. With `setTimerProvider` overridden to `{phase: work, running: true}`: `shell.dock.strip` exists on all five tabs and `shell.dock.recordPill` on none.
- AC-ST-3. For each row of the "running" table (set timer work running, work paused, rest phase; rest timer running, paused, finished 1 min ago, finished 11 min ago, idle; set timer done) assert strip present/absent and its state word exactly as tabulated.
- AC-ST-4. Switching mode (S-3) leaves `shell.dock.strip` semantics label and both provider states unchanged.
- AC-ST-5. Tapping the strip pushes the stored destination, or `/workouts` when the destination provider is empty.
- AC-ST-6. On a scrollable tab with the strip visible, scrolling to the end puts the last child's bottom edge above the strip's top edge (compare `Rect`s).
- AC-ST-7. Pumping `/workout/:id` shows no `shell.dock`.
- AC-ST-8. With a new `ProviderScope` (process-death simulation) no strip appears.
- AC-ST-9. At a 360x480 surface with text scale 2.0 the pill is the 48x48 icon variant and the strip is single-line; both keep a non-empty accessible name.

### S-5. Record sheet (context-sensitive start)

Purpose: the single place where "start something" is offered for the current mode. In S03 it creates no new capability; every row navigates into an existing flow.

| Mode | Rows (existing destinations) |
|---|---|
| TRAIN | "Scan equipment" -> `/scan`; "Today's workout" -> the Home day-panel start target, only if one is scheduled; "Choose a workout" -> `/workouts`; "Check my form" -> `/form-check` |
| BODY | "Body scan" -> `/body-scan`; "Add a meal" -> `/nutrition/add`; "Log weight" -> `/nutrition/weight`; flag-hidden tiles are absent, access-refused tiles are present but disabled with the reason |
| EXPLORE, RIDE | Not reachable in S03. Later: the first row is "Start {walk/run/hike/ride}", location asked only after tapping it (S04-D) |

Layout: `HudSheet`, title with the mode name (full-sentence key per mode), 56-high rows (`HudSettingRow` extended, 9.1), the first row primary (accent dot). Copy: `recordSheetTitle` (select by mode) "Record: Train" / "Record: Body"; `recordTrainScan` "Scan equipment"; `recordTrainToday` "Today's workout"; `recordTrainChoose` "Choose a workout"; `recordTrainForm` "Check my form"; `recordBodyScan` "Body scan"; `recordBodyMeal` "Add a meal"; `recordBodyWeight` "Log weight"; `recordNothingHere` "Nothing to start in this mode yet."

States: EMPTY (no rows, e.g. BODY with every tile flag-hidden): `recordNothingHere` + button "Open Train"; ERROR n/a (navigation only); OFFLINE: destinations show their own states; NOT-AVAILABLE per row; BUSY: the sheet cannot be opened while the strip shows.
Keys: `recordSheet`, `recordSheet.row.<id>`.

Acceptance criteria:
- AC-RC-1. In TRAIN, `recordSheet.row.trainScan` navigates to `/scan` (assert router location); the sheet itself triggers zero permission-channel calls.
- AC-RC-2. `recordSheet.row.trainToday` is absent when the schedule provider returns none, present (enabled) when it returns one.
- AC-RC-3. In BODY with `FOOD_AI`/`FOOD_LOOKUP` off, the meal row set matches the existing `add_food_page` tile rules; a `ScanAccess` refusal yields a row with `isEnabled == false` and the reason in the semantics value.
- AC-RC-4. Opening and closing the sheet performs no write to any repository fake.
- AC-RC-5. After navigating via a row and popping, the router location is the originating tab and no `recordSheet` remains.

Presentation: decided by size class ONLY, never by the input device, and defined in the table of 10.6 (bottom sheet on Compact; bottom sheet of at most 560 dp on Medium; popover anchored to the rail Record slot on Expanded). The same rule applies when a shortcut or the Mac menu opens it, on every tab including `/scan` and `/profile`.

### S-6. Home: mode chip, lens, activity today, upgrader intro

Purpose: Today for the current mode. Home keeps `HudScreenBody` and its panels. S03 gives every existing Home child a stable key `home.section.<name>` with no visual change (a test seam for ordering).

Changes:
1. The greeting row gains the mode chip C-2 (`home.modeChip`) at the end side. Wrap rule (finding A9): when the greeting plus chip do not fit in one line at the current width and text scale, the chip moves to its own row directly under the greeting, start-aligned; it never overlays or truncates the greeting.
2. Lens ordering. TRAIN lens: current order, unchanged. BODY lens: the body-scan and nutrition cards (non-compact) move directly under the day panel; the gym quick-scan row and gym suggestions move below "More"; global panels stay where they are. Nothing is removed.
3. "Activity today" card (`home.activityToday`, C-5) under the day panel ONLY when the journal is `open` and at least one `ActivitySession` starts today (device local zone). Absent otherwise (no zero card).
4. Upgrader intro card (`home.modeIntro`): shown iff `chooserStatus == migrated` and `Day3WelcomeModal` is not displayed in this Home session. Title "New: choose what you want to do", body "Train, Ride, Explore and Body now share one history. Pick the one you use most.", actions "Choose a mode" and "Not now" (both set `resolved`).

Copy: `homeModeChipLabel` (select by mode, accessible name) "Mode: Train. Change mode"; `homeActivityToday` "Activity today"; `modeIntroTitle`; `modeIntroBody`; `modeIntroChoose` "Choose a mode"; `modeIntroDismiss` "Not now".

States:
| State | Behaviour |
|---|---|
| LOADING | Existing Home loading kept. "Activity today" renders nothing until the journal list resolves, then inserts without moving the viewport (no skeleton). |
| EMPTY | "Activity today" absent. |
| PARTIAL | A missing metric in a row reads "No data" (section 11). |
| ERROR | `failedToOpen` or a list read error: the card is absent; Home is unaffected; the explanation lives on Sources (S-8). No new error text on Home. The raw-exception Home copy (`homeCouldNotLoad('$e')`) is not reused anywhere new. |
| NOT-AVAILABLE | `notEnabled` journal: card absent, silently. |
| OFFLINE | no change |

Acceptance criteria:
- AC-HM-1. (Rewritten, finding U6.) TRAIN lens, `chooserStatus=resolved`, journal `notEnabled` or empty: the ordered list of `home.section.*` keys equals the recorded pre-S03 order (golden list in the test) with the addition of `home.modeChip` only.
- AC-HM-2. BODY lens: `home.section.bodyScan` and `home.section.nutrition` appear before `home.section.quickScan`; the set of keys equals the TRAIN set.
- AC-HM-3. `home.activityToday` exists iff the fake journal has a session whose start, converted to the device zone, falls on the injected "today"; a `strength` fake entry never produces rows.
- AC-HM-4. (Rewritten, finding U2.) `home.modeIntro` exists iff `chooserStatus == migrated`; after "Not now" the store holds `resolved` and the card is gone after rebuild; for `pending`, `resolved` and absent it never exists; with the Day-3 modal pumped open it is not in the tree.
- AC-HM-5. A journal whose `list()` throws leaves Home with no error text matching the new keys and all pre-S03 sections present.
- AC-HM-6. Keyboard traversal from `home.section.greeting` reaches `home.modeChip` next; at text scale 2.0 and a 360 dp wide surface `home.modeChip` is on its own row (its top is below the greeting's bottom) and no overflow exception is raised.

### S-7. Progress tab: dashboard skeleton

Purpose: the whole picture across modes, independent of the selected mode. Progress is a `FrostedScaffold` + `GlassAppBar` + `ListView` (F13); S03 does not migrate it. No mode chip on Progress (finding U4).

Exact placement (finding U4) in the list, after the change:
1. `_HeadlineStats` (unchanged)
2. 16 px gap
3. `ActivitySyncEntryCard` (unchanged, still self-hiding)
4. **S-7b "All activity" block** (new) - only when the journal is `open` AND at least one session exists
5. `BodyScanEntryCard`, 12 px, `NutritionEntryCard` (unchanged)
6. **S-7a quiet slot** (new) - only when S-7b is not shown; sits right after `NutritionEntryCard`'s 24 px gap
7. "Last 8 weeks" title and chart (unchanged)

The sync card is NOT re-listed or restyled inside the new block (draft duplicate removed). Padding change: the list's bottom padding 120 becomes 120 + dock height while the dock shows (S-4). Left/right 20 and top 92 are unchanged. All new panels use the 20 px side padding of this list, not the 16 px `screenGutter` of HUD screens.

#### S-7a Quiet slot (journal `notEnabled`, or `open` with zero sessions, or loading)
One navigation row C-7 "Sources" with hint "Walks, runs and rides you record will appear on Progress." (`progressSourcesHint`). No title banner, no "No recorded activity yet", no zero, nothing above the gym data. This is the demotion rule (finding U5): a Phase 1 user with five gym workouts never sees a message implying nothing was recorded.
- LOADING: the row renders at once; the block appears later if sessions exist, inserted above the body-scan card without scrolling the viewport (a one-time layout shift is accepted; the viewport offset is preserved).
- `failedToOpen`: the row plus a C-12 error panel "Activity history on this device could not be opened." with "Try again" (re-opens once, disabled while busy, no loop).
- `notEnabled`: the row only; no error, no retry (finding U1).

#### S-7b "All activity" block (journal `open`, at least one session ever)
1. Header "All activity".
2. "This week" panel: one Discipline tile (C-6) per sport group with data this week. Groups: Walk and hike (walking, hiking), Run (running, trailRunning), Ride (cycling, indoorCycling, mountainBiking), Swim (swimmingPool, swimmingOpenWater), Row (rowing), Other (other). `strength` never appears (OD-5). If the week has no data but older sessions exist, the panel shows "No recorded activity this week." (a true statement, shown only in this case).
3. "Recent activity": latest 5 Activity rows C-4. "See all" is NOT built (DQ-5).
4. The "Sources" row C-7.
Tile content: sessions (count), moving time (sum of `movingTimeS`; sessions without it excluded from the sum with the hint "Time from {k} of {n} sessions"), distance (sum of `distanceM` where present). No energy, no cross-group total. The selected mode's groups sort first (EXPLORE: Walk and hike, Run; RIDE: Ride; others by fixed order).

Week definition (OPEN-1, finding U6): the week starts on Monday in the device time zone, fixed in S03 and injected as a function so tests control it. The existing Home week section may use a different rule (unread); the architect aligns the two (DQ-10). The implementer must not silently pick a third rule.

Copy: `progressAllActivity` "All activity"; `progressThisWeek` "This week"; `progressThisWeekEmpty` "No recorded activity this week."; `progressRecent` "Recent activity"; `progressSourcesRow` "Sources"; `progressSourcesHint`; `activityJournalFailed` "Activity history on this device could not be opened."; `activityJournalRetry` "Try again"; `activityNoData` "No data"; `activityEstimate` "Estimate"; `activityStreamLost` "Route not available on this device"; `activityTimeFrom` (plural) "Time from {k} of {n} sessions".

States summary:
| State | S-7a | S-7b |
|---|---|---|
| LOADING | Sources row only | not shown |
| EMPTY (open, zero sessions) | Sources row only | not shown |
| PARTIAL | n/a | tile metric reads "No data"; estimate marker where derived |
| ERROR (`failedToOpen`) | row + error panel + Try again | not shown |
| NOT-AVAILABLE (`notEnabled`) | row only | not shown |
| OFFLINE | no change | no change |
| SUCCESS | not shown | block shown |

Keys: `progress.slot.sources`, `progress.journalError`, `progress.journalRetry`, `progress.allActivity`, `progress.thisWeek`, `progress.tile.<group>`, `progress.recent`, `progress.recent.row.<id>`.

Acceptance criteria (those marked [flag off] run with `ACTIVITY_CLOUD_STREAMS` false and no journal override):
- AC-PR-1. [journal forced to `notEnabled` by a test override; in the default build after S03-0 the journal is `open`, and with zero sessions the same tree results] Progress renders `progress.slot.sources`, does not contain `progress.allActivity`, `progress.journalError` or any text equal to an "empty" or "unavailable" string, and the existing blocks are present in the original order.
- AC-PR-2. Journal `failedToOpen`: `progress.journalError` and `progress.journalRetry` exist; tapping retry calls the opener exactly once and the button is disabled while the future is pending; a second tap during pending adds no call.
- AC-PR-3. Journal `open` with zero sessions: same tree as AC-PR-1 (no block); with one session: `progress.allActivity` exists, `progress.slot.sources` does not, and `progress.allActivity` precedes `BodyScanEntryCard` in the child order and follows `ActivitySyncEntryCard`.
- AC-PR-4. Fixture: one run (distance 5000 m, moving time 1500 s) and one walk (moving time 600 s, no distance) this week: `progress.tile.run` shows both values; `progress.tile.walk` shows "No data" for distance; the walk's time is included; no text node anywhere in the block contains a calorie figure.
- AC-PR-5. A `strength` fake entry produces no tile and no row.
- AC-PR-6. (Rewritten, finding U6.) `put` of the same session id twice into the journal fake yields one `progress.recent.row.<id>` (relies on the S02 upsert; no external-source claim).
- AC-PR-7. Week boundaries with an injected clock: a session at 23:30 local on Sunday belongs to the week of the preceding Monday; one at 00:10 Monday belongs to the new week; the device time zone is faked to two offsets.
- AC-PR-8. The first and last children of the original Progress list are unchanged by the change except for the inserted children (compare keys).
- AC-PR-9. [flag off] Pumping Progress with a dock strip visible: the list's bottom padding equals 120 + dock height (read the `ListView.padding`).
- AC-PR-10. Numbers use the locale formatter: with `ru` the decimal separator is a comma; units are metric only.
- AC-PR-11. For a fixture with 3 running and 2 cycling sessions this week, the Run tile shows 3 sessions and the Ride tile 2; the sum of tile session counts equals 5 (no session counted in two groups).

### S-8. Sources panel (EP-4)

Purpose: an honest answer to "where does my data come from". Pushed route outside the shell; `HudScreenBody` + `HudPanel` rows.

Rows (order): "Recorded in this app" (`app`), "Health Connect" (`health_connect`), "Apple Health" (`healthkit`, listed only when the app runs on an Apple platform; no Apple build target exists in S03 (F26, OD-12), so it is not listed in any S03 build), "Bluetooth sensors" (`ble_*`), "Watch" (`wear_os`), "Other services" (`vendor_cloud`). Each row: name, one-line purpose, status chip C-11, and "May provide ..." from `kCapabilityMatrix` for yes/partial levels, "Unknown" otherwise.

Status chip vocabulary (word + icon): "In use", "Ready", "Not connected", plus for S16 the `SourceHealth` map: ok "Connected", permissionMissing "Permission needed", unavailable "Unavailable on this device", stale "Out of date", error "Problem". In S03 no adapter exists, so `healthStatus()` is not called.

App row status by journal availability: `open` with sessions "In use"; `open` empty "Ready"; `notEnabled` "Not active" with the line "Activity history is not active in this build." (no chip colour change, no retry); `failedToOpen` "Problem" with `activityJournalFailed` and "Try again" (once).

Information block: `sourcesDedupNote` "If the same workout comes from two sources, we do not yet merge them automatically." Copy: `sourcesTitle` "Sources"; `sourcesIntro` "Your activity can come from this app, your phone or your devices."; `sourceApp`, `sourceHealthConnect`, `sourceBle`, `sourceWatch`, `sourceOther` as above; status keys `sourceStatus*`; `sourceStatusNotActive` "Not active".

States: LOADING (journal being read: app chip text "Checking" for at most 1 s, plain text); EMPTY n/a (rows are static); PARTIAL n/a; ERROR/NOT-AVAILABLE as above; OFFLINE n/a. Per-source consent and delete controls are the consent-centre scope (OD-8); only an optional link to the existing Health sync card is allowed. No new deletion path.

Keys: `sources.row.<id>`, `sources.dedupNote`, `sources.app.retry`.

Acceptance criteria:
- AC-SRC-1. Journal `open` empty -> `sources.row.app` semantics contains "Ready"; after one fake session -> "In use".
- AC-SRC-2. [journal forced to `notEnabled` by override] `notEnabled`: the app row contains the not-active line, has no `sources.app.retry`, and no "Problem" text exists on the screen.
- AC-SRC-3. `failedToOpen`: "Problem" + `sources.app.retry`; retry calls the opener once.
- AC-SRC-4. Every non-app row's semantics contains "Not connected" and has no tap action (the optional health-sync link excepted).
- AC-SRC-5. `sources.dedupNote` exists; a text search of all S03 ARB additions finds none of "merged", "deduplicated" or "synced with Health Connect".
- AC-SRC-6. A provenance record with an unknown `sourceId` and each of the five `SourceKind` values renders the label of section 8.1 and never an empty label.
- AC-SRC-7. Each row is one semantics node whose label includes name and status.

### S-9. Mode chooser on large windows (merged into S-1 in revision 3)
In revision 2 S-9 was the name of a design-only drawing of the chooser for tablets, not built while U-2 (the tablet-now-or-later question) was open. U-2 is answered NOW, so S-9 is no longer a separate screen: S-1 is ONE responsive screen and this section is its large-window part. S-9 remains only as a label for the Medium and Expanded rows below. There is no carousel and no horizontal scrolling at any size.

#### S-1 layout by size class (window width as in 10.1)

| Class | Layout |
|---|---|
| Compact (under 600) | As section 7: `HudScreenTitle`, 2x2 grid, description area under the grid, footer buttons. On a short window (height under 480 dp, the single "short" threshold of 10.1) the grid is 4x1. |
| Medium (600-839) | Content centred, max width 640 dp. 2x2 grid with cards at least 200 dp wide and 120 dp high; description area under the grid; footer buttons at the end of the column. On a short window (height under 480) the grid is 4x1 and the blurb is dropped from the card face below 150 dp card width. |
| Expanded (840 and up) | Content centred, max width 960 dp, two panes: left, the 2x2 grid (cards at least 220 x 150, gap 16); right, a detail panel 320 dp wide showing the description of the focused or selected card, with the "Selected"/"Coming later" state word, and the footer buttons (Continue, Decide later) at its bottom. The panel is not a live region (A7); its text is the focused card's hint. The route is pushed outside the shell, so there is no rail on it. |

The film's focus bracket and photography stay out of S03 (U-3 default); the detail panel has NO illustration slot in S03 (no empty box is drawn; a slot is added when U-3 supplies artwork).

Idle state of the detail panel (review of revision 3): on first run, before any card is focused, hovered or tapped, the panel shows the text `modeDetailIdle` "Pick a mode to see what it does", `modeChooser.continue` is disabled, and no card `isSelected`. A tap on an available card selects it and updates the panel (touch devices have no hover, so selection is the only trigger there); a tap on a Coming-later card opens the Coming-later sheet and the panel shows that card's description with the word "Coming later". On a returning visit (switcher "See all modes") the panel starts on the current mode's description with that card selected. Hover and keyboard focus update the panel text without selecting (AC-CH-13); when the pointer leaves or focus moves off the grid, the panel returns to the selected card's description, or to the idle text when nothing is selected. Behaviour, copy, states and keys of section 7 S-1 are unchanged in every class; added keys: `modeChooser.detailPanel` (Expanded only) and `modeChooser.grid`.

Pointer and keyboard (all classes): arrow keys move focus between the four cards in the grid order (Right/Left within a row, Down/Up between rows), Space or Enter selects, and Enter on Continue confirms; hovering a card on a pointer device updates the detail panel text without selecting (Expanded) and shows the hover state of 10.9.

Acceptance criteria (widget tests with a set window size, `ru` and `en`, default text scale unless stated):
- AC-CH-9. At 360x800 the four cards are in a 2x2 grid (cards 1 and 2 share a top; card 3 is below card 1) and `modeChooser.detailPanel` does not exist.
- AC-CH-10. At 700x900 (Medium) the grid is 2x2, the content width does not exceed 640 dp, and `modeChooser.detailPanel` does not exist; at 700x420 (short) the grid is 4x1 and no overflow is raised.
- AC-CH-11. At 1100x800 (Expanded) `modeChooser.detailPanel` exists to the end side of `modeChooser.grid`, `modeChooser.continue` is inside the detail panel, the overall width does not exceed 960 dp, and the four cards keep the reading order train, ride, explore, body.
- AC-CH-12. Boundary: at exactly 599 dp the chooser has no detail panel and a 2x2 grid; at exactly 840 dp it has the detail panel; at 839 dp it does not.
- AC-CH-13. At 1100x800, hovering or focusing `modeChooser.card.body` changes the text in `modeChooser.detailPanel` to the body description without changing which card `isSelected`; at text scale 2.0 and 1100 wide, `ru`, no overflow and `didExceedMaxLines == false` for card names.
- AC-CH-14. Changing the window from 1100x800 to 360x800 (a pumped resize) keeps the selected card, the enabled state of Continue and the focus; the test records no write to the settings fake during the resize.

### S-10. Sign-out warning sheet
Designed as in J10 and kept. The sheet is the same on every size class (a modal bottom sheet on compact, a centred dialog of max width 480 dp on medium and expanded, 10.6). Acceptance: AC-SO-1 with a non-empty fake journal, the sign-out action opens `signOut.warningSheet` offering Export first, Sign out and delete from this device (second confirmation) and Cancel, and nothing is deleted before the confirmation; AC-SO-2 with an empty journal sign-out proceeds with no sheet.

## 8. Dashboard content rules

8.1 Source label from the first provenance record: by `sourceId`: `app` -> "Recorded in this app"; `health_connect` -> "Health Connect"; `healthkit` -> "Apple Health"; `wear_os` -> "Watch"; `ble_*` -> "Sensor"; otherwise by `SourceKind`: `platformHealth` -> "Health platform", `bleSensor` -> "Sensor", `vendorCloud` -> "Service", `companionApp` -> "App", `fileImport` -> "File import". `SourceKind.parse` maps any unknown name to `fileImport` (F17), so the label for an unrecognised stored kind is "File import"; an empty or missing provenance list shows "Unknown source". With several records the row shows the primary source and "+{k} sources" (plural).
8.2 Estimate marker: any value not directly measured is labelled "Estimate" (accessible description "Calculated from other data"). "How this is calculated" is not built in S03 (DQ-5).
8.3 `streamLost` shows `activityStreamLost` as a quiet chip.
8.4 Mode vs sport: EXPLORE = walking, hiking, running, trailRunning; RIDE = cycling, indoorCycling, mountainBiking; TRAIN = strength (workout model) plus rowing/other shown as "Other"; BODY owns no sport. The selected mode only changes tile sort order, never hides.
8.5 Sync chips on rows only with the cloud flag on: `pending` "Waiting to sync", `synced` nothing, `upload_failed` "Could not sync, will retry", `sync_conflict` "Needs your decision" (opens the existing sheet). Flag off: no sync wording anywhere.

## 9. Component contracts

### 9.1 What is extended and what is wrapped (findings A1, U10)

Existing primitives hard-code 44 px height, one text line and thin semantics (F25). S03 extends them with OPTIONAL parameters whose defaults reproduce today's behaviour exactly; the existing HUD tests must pass unchanged. New components are compositions of the extended primitives.

| Primitive | Extension (all optional, defaults = today) | Used by |
|---|---|---|
| `HudChip` | `minHeight` (default `minTapTarget` 44; the same value sets the hit region because the constraint wraps the tap area); `maxLines` (default 1; wrapping chips use 2); semantics: `semanticLabel`, `semanticHint`, `selected` (exposes `isSelected`), `enabled` | C-2, C-11 |
| `HudButton` | `minHeight` (default 44, hit region enlarged with it); `semanticHint` | C-8 |
| `HudPanel` | `semanticHint`, `selected`, `enabled`, `inMutuallyExclusiveGroup`; when `semanticLabel` is given the existing exclusion of the subtree stays, so callers must put every fact into the label | C-1, C-3 |
| `HudSettingRow` | `subtitle` merged into the semantic label ("title, subtitle"), `semanticHint`, `enabled`, `selected`, `trailingLabel` (merged); today the subtitle and trailing widget are excluded (F25) | C-4, C-7, C-9 |

Revision 3 adds one more optional extension to all four primitives above: `hoverStyle` (half-strength press wash), `cursor` (pointing hand when enabled) and `showFocusRing` (2 px outline on keyboard focus). Defaults are off, so the existing HUD tests pass unchanged; every NEW S03 call site turns them on. `HudKeyboardActivation` (F30) stays the keyboard activation path and also gets the focus ring.

Wrapping rather than extending is used only where a primitive cannot express the need: the radio group is a `Semantics(inMutuallyExclusiveGroup: true)` wrapper around the card/row set; the strip is `Semantics` around a `HudPanel`. No new token, colour or blur radius is introduced. Hit regions: a 48 control built on a 44 primitive must enlarge the tappable constraint, not just the painted box (test AC-A11Y-1).

### 9.2 Components

| Id | Component | Built from | Inputs | Variants / states | Events | Notes |
|---|---|---|---|---|---|---|
| C-1 | Mode card | `HudPanel` (extended) | mode, name, blurb, icon, state (normal, selected, comingLater) | grid cell (min 120 high), switcher row | `onSelect(mode)` | Selected = ink + dot + the word "Selected" (three channels). comingLater stays ENABLED (focusable and tappable) with reduced emphasis; its label contains "Coming later" and its hint "Opens details" (finding A8). Hint carries the description. |
| C-2 | Mode chip | `HudChip` (`minHeight` 48, `maxLines` 2) | mode name, icon | default | `onTap` opens S-3 | Hugs text, never below 48 high; may wrap to two lines instead of ellipsis; accessible name from `homeModeChipLabel` |
| C-3 | Recording strip | `HudPanel(dense)` | `ActiveSessionStatus` | running, paused, resting, rest finished | `onTap` resume | Section S-4 |
| C-4 | Activity row | `HudSettingRow` (extended) in a `HudPanel` | sport, start time, metrics, source label, sync chip, estimate marker | normal, partial, conflict | none in S03 (informational) | One semantic node: sport, date, key metrics, source |
| C-5 | Activity today card | `HudPanel` + C-4 | list of sessions | absent when empty | none | Max 3 rows then non-interactive "+n more" |
| C-6 | Discipline tile | `HudMetricRow` in `HudPanel(secondary)` | group, sessions, time, distance | present / "No data" | none | No energy, no ring or bar |
| C-7 | Navigation row | `HudSettingRow(onTap)` (extended) | label, hint | default | `onTap` | "Sources" |
| C-8 | Record pill | `HudButton` (`minHeight` 48) | mode, enabled | full, icon-only (compaction) | `onPressed` opens S-5 | |
| C-9 | Record sheet row | `HudSettingRow` (extended) | icon, title, description, `enabled`, reason | primary, normal, disabled | `onTap` | Reason visible and in the semantic value when disabled |
| C-10 | Question step | `ob_shell` + `inputs` | question, options, whatItChanges | single choice | `onAnswer`, `onSkip` | Not a new framework |
| C-11 | Status chip | `HudChip` (`maxLines` 2, not interactive) | text, icon | in use, ready, not connected, permission needed, unavailable, out of date, problem, not active | none | Word is never truncated: it wraps, or the chip sits on its own line below the row title (finding A4); icon excluded from semantics |
| C-12 | Info/empty/error panel | `HudPanel` | title, body, optional action | empty, error | action | No raw exception text |
| C-13 | Side navigation rail (revision 3) | `HudSurface` (`t.navBar` glass) + the nav item configuration list + C-8 / C-3 in the Record slot | items (the list of 5.3), selectedIndex, form (compact 96 dp or extended 240 dp), Record slot content | compact form, extended form | `onSelect(i)` | Section 10.4. Same semantics as the bar tabs (button, selected, label). Rendered only on the rail presentation |
| C-14 | Window-size class provider (revision 3) | Not visual: one provider reading the window width and height | window width, height, text scale | compact, medium, expanded; short flag; rail form | none | Section 10.1. Single source for class decisions; injectable in tests (a set window size) so no screen reads raw widths |
| C-15 | Adaptive surface (revision 3) | Wraps the existing `HudSheet`/`HudPanel` | content, anchor (optional), class | bottom sheet, centred dialog, anchored popover | `onDismiss` | Section 10.6. One component chooses placement by class; content is identical |

## 10. Responsive behaviour and platform families (revision 3, central section)

Scope (answer to U-2, the question "tablet and large layouts now or later?": NOW). One codebase and one app must work well on five device families: Android phone, iPhone, iPad, Android tablet and MacBook. Today the app has no responsive code at all (F28): pages fill the window width, there is no rail, no breakpoint, no pointer or shortcut handling. Everything in this section is therefore PROPOSED design, built in S03 from the HUD primitives (no new design system).

Apple targets: the repository has no `ios` or `macos` platform folder (F26). The iOS, iPadOS and macOS build targets are NOT created in S03, and when they are created is an OPEN operator decision (section 15, OD-12). This section is written so that the Apple layouts can be built later without redesign; until then the Apple-specific criteria can be tested in widget tests (a set window size, a faked `TargetPlatform`) but not on a device or simulator. No Apple store account, signing or release is promised.

### 10.1 Window-size model

The class is computed from the width of the WINDOW the app actually gets (the logical width in dp that `MediaQuery.sizeOf` reports to the shell), never from the device type or the physical screen. This is what makes split-screen, Stage Manager, resized Mac windows and foldable resizing work without special cases. PROPOSED, one provider `windowSizeClass` read once by the shell and passed down; screens never read raw widths for layout decisions.

| Class | Window width | Height rule | Navigation | Content |
|---|---|---|---|---|
| Compact | under 600 dp | any | Floating bottom bar plus dock (as today) | One column, phone layout |
| Medium | 600 to 839 dp | any | Floating bottom bar plus dock, bar width limited to 560 dp and centred | One column up to a max content width of 640 dp, two columns where 10.5 says so, side pane NOT used |
| Expanded | 840 dp and up | any | Side navigation rail replaces the bar and the dock slot (10.4) | Content pane plus optional side pane (10.5) |

Height class (second axis): "short" means window height under 480 dp (a phone in landscape, or a very short window). Rail override: when the width is 600 dp or more AND the window is short, the rail is used even though the width class is Medium. Reason: the bar plus dock take about 154 dp plus safe areas (S-4), which is nearly half of a 360 dp tall landscape phone; a rail takes width, which is plentiful there. In that case the width class stays Medium for content layout, and the content pane is the window minus the rail.

Why these numbers (INFERENCE: they follow the width-class convention used by Material 3 guidance for large screens, 600 and 840 dp; that guidance is not in the repository, so the numbers are a PROPOSED choice, not a repository fact): 600 dp is the smallest width where the bar can sit centred with a single readable column of at least 520 dp; 840 dp is where the rail replaces the bar. Choosing the same boundaries as the platform guidance means Android tablets and foldables behave as users of those devices expect. IMPORTANT (correction in the review of revision 3): the class boundary does NOT decide whether a screen has two panes. Revision 3's first draft argued that 840 dp fits a 96 dp rail, a 400 dp column and a 320 dp pane; that arithmetic left out the rail's 12 dp inset and 12 dp gap and the page gutters. The real figure is: content pane width = window width minus the rail footprint, where the rail footprint = 12 + rail width + 12 (96 dp compact form, 240 dp extended form), and 0 when there is no rail. At 840 dp the pane is 720 dp, which cannot hold a 480 dp main column, a 340 dp side pane, a 16 dp gap and 32 dp of gutters (868 dp). Two-pane layouts therefore key on the CONTENT PANE width (10.5), not on the window class. With the extended rail (text scale 1.3 and above, or a 1200 dp window) the footprint is 264 dp, so the pane is narrower still, and a 1100 dp window with the extended rail has a 836 dp pane and is single column.

Rules:
- WS-1. Boundaries are inclusive at the lower end: exactly 600 is Medium, exactly 840 is Expanded, 599.9 is Compact.
- WS-2. The class is re-evaluated on every size change. No hysteresis (it would make the boundary untestable); to avoid flicker, the swap is a rebuild with no animation.
- WS-3. A class change never changes the router location, the selected tab, the selected mode, any timer, any text the user typed, or an open sheet (an open sheet is re-laid-out for the new class, 10.6). Scroll position is promised only in this weaker form: the FIRST VISIBLE SECTION stays visible after the change, anchored by its key (`home.section.<name>` on Home, `progress.recent` and the other `progress.*` keys on Progress, `sources.row.<id>` on Sources); pixel offsets are not preserved because a column layout changes every height. (Alternative if the build prefers: one scroll controller kept across layouts; the keyed anchor is the tested promise either way.) Focus stays on the control that had it, or on the same destination in the other navigation presentation.
- WS-4. The text scale (accessibility font size) is a separate input. It never changes the width class; it changes the rail form (10.4) and may move a column to a single column when the content does not fit (10.5).
- WS-5. The maximum content width is applied INSIDE the content pane; beyond it the pane is centred and the wallpaper shows at the sides. The wallpaper stays `BoxFit.cover` (F30); how the photograph crops on a wide window is UNGROUNDED (never rendered at those aspect ratios) and goes to the visual review.

### 10.2 What each situation becomes

Window sizes below are typical values given for orientation only; the real device sizes are NOT in the repository (UNGROUNDED), so the contract and its tests use the class boundaries, not device names.

| Situation | Typical window width x height (dp) | Class and navigation |
|---|---|---|
| Android phone or iPhone, portrait | 320-430 x 640-950 | Compact, bar plus dock |
| Android phone or iPhone, landscape | 640-930 x 320-430 | Medium or Expanded by width; short, so the rail is used from 600 dp; content single pane |
| Foldable, folded (cover screen) | about 360-400 wide | Compact |
| Foldable, unfolded (inner screen), portrait or landscape | about 600-900 wide | Medium or Expanded by width; resizing while folding or unfolding is a live class change (WS-3) |
| Android tablet or iPad, portrait | 600-834 wide (smaller tablets), up to about 1024 for large ones | Medium, or Expanded from 840 dp |
| Android tablet or iPad, landscape (a first-class case) | 960-1366 wide | Expanded, rail, content plus side pane |
| Split-screen (Android) or Split View, Slide Over (iPadOS) | 320-680 wide for a half or a third | Compact or Medium by the width actually granted; the app never assumes it owns the screen |
| Stage Manager (iPadOS), free-form windows (Android desktop mode) | any width the user drags to, down to a floor the system sets (UNGROUNDED) | Class follows the width live |
| MacBook, default window | 1100 x 760 (PROPOSED default) | Expanded, rail |
| MacBook, window dragged narrower | down to the minimum of 10.9 | Medium at 600-839, Compact under 600 |
| MacBook, full screen | 1280-1800 wide | Expanded; content capped by the max content width (10.5), wallpaper at the sides |

### 10.3 Orientation, resize and the Android and Apple runtime
- Orientation is never locked in any family (F27 shows none today; the contract keeps it that way). Portrait and landscape are both first-class on tablets and iPad; landscape on phones is supported through the short-window rules.
- The Android activity already absorbs resize and rotation without restarting (F27 `configChanges`), so a live class change is a rebuild, not a process restart. Whether the app is marked resizable for split-screen and desktop windows on Android 16 and later is UNGROUNDED (no `resizeableActivity` attribute; `targetSdk` 36); the Android build story must confirm that large-screen resizing is not blocked by the manifest.
- On Apple platforms multitasking widths come from the system; the app must declare multitasking support when the iOS and iPadOS targets are created (OD-12). Nothing in S03 depends on it.
- Keyboard open (Android phone, iPhone, iPad software keyboard): these screens have no text input (unchanged), so the keyboard never resizes them; `adjustResize` stays (F27).

### 10.4 Navigation presentation: bottom bar with dock, or side rail

Both presentations come from the ONE navigation configuration list (5.3): five destinations Home, Workouts, Scan, Progress, Profile, same icons, same labels (keys `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`), same paths, same Back behaviour (F3).

When each is used:

| Window | Presentation |
|---|---|
| Width under 600 dp | Bottom bar + dock (as today, S-4) |
| Width 600 to 839 dp and window height 480 dp or more | Bottom bar + dock, bar capped at 560 dp wide and centred |
| Width 600 to 839 dp and window height under 480 dp (landscape phone, short window) | Side rail (compact form) |
| Width 840 dp and up | Side rail (compact form, or extended form under the rule below) |

Side rail contract (new component C-13, section 9.2):
- Position: start edge, inside the safe area, 12 dp inset from the window edges (the bar's `navBarInset`, F8), full height minus insets; glass surface and radius of the existing bar (`t.navBar`, `radiusDevice`, F4). No new colour or blur.
- Order, top to bottom: the PINNED Record slot, then a vertically scrollable list of the five destinations. The wallpaper and content sit to the end side of the rail. Focus order is the same top to bottom: Record slot, Home, Workouts, Scan, Progress, Profile, then the content. The slot stays pinned (it does not scroll away), so Record is always reachable; only the destinations list scrolls.
- Vertical overflow rule (review of revision 3). A landscape phone window is 360 dp high or less, and six 56 dp items plus insets exceed it. Therefore: (a) when the window height is under 480 dp each destination is 48 dp high instead of 56 (the minimum touch target stays 48 dp), the Record slot keeps its reserved height (below), and at scale 1.0 the whole rail is 64 + 5 x 48 + 24 = 328 dp, which fits 360; (b) whenever the content still does not fit (larger text scale, or a window under about 330 dp high) the destinations list scrolls vertically inside the rail, with no overflow; (c) a destination that receives keyboard focus (Tab, arrows) is scrolled fully into view; (d) a screen reader focus moving to a destination also scrolls it into view; (e) scrolling the list never moves the Record slot and never changes the selected destination.
- Compact form: 96 dp wide, icon above a one-line label, each destination at least 56 dp high (48 dp under 480 dp window height) and 96 dp wide (hit region, not only paint). Selected = ink + accent dot + `selected` semantics (the bar's three channels, F4).
- Extended form: 240 dp wide, icon and label in one row. It is used when the window width is 1200 dp or more OR when the widest of the five labels, measured in the nav-label style, upper-cased, at the CURRENT text scale and locale (a `TextPainter` measurement, not a fixed scale number), plus 16 dp of padding, no longer fits inside 96 dp. The expected switch is near scale 1.3 in Russian, but the rule is the measured width, so a longer translation or another font metric moves it correctly. Reason: Russian uppercase labels such as the Workouts label are about 10 characters and stop fitting in 96 dp at larger text; the extended form removes the truncation instead of adding ellipsis. Because the form can change when the system text scale changes, the content pane width changes with it (10.5).
- The label is never truncated in the rail (compact form budget: 11 Russian characters at scale 1.0, checked in section 13).
- Record slot is RESERVED (review of revision 3): it occupies the same 64 dp (compact form) or 56 dp (extended form) at the top of the rail on all five tabs, in idle and running states, so the five destinations never move vertically when the user changes tab or when a session starts or ends. Its states: idle = enabled button (Record icon over the visible one-word label "Record") that opens S-5; running = the strip (below); on `/scan` and `/profile` the slot is the same enabled button and opens S-5 (ASSUMPTION for the operator, section 15: the rail shows Record on every tab, unlike the bar presentation where the pill is shown only on Home, Workouts and Progress, S-4; this is the simplest way to avoid the slot appearing and vanishing, and S-5 is useful from any tab because its first row is Scan equipment).
- Running state in the compact rail (review of revision 3): the slot shows the state icon and TWO visible text lines, a short state word (`railStateRunning` "Active", `railStatePaused` "Paused", `railStateResting` "Rest", `railStateRestDone` "Done"; Russian budget 8 characters) and the elapsed or remaining time in whole minutes ("12 min", plural-aware formatter of section 13), so the running state, its kind and its duration are visible without opening anything. The accessible label is the full strip label of S-4. The extended form shows the full strip text.
- Idle Record slot label: a visible one-word label under the icon in the compact form (not icon-only), so no tooltip is needed for the primary action; compact-rail destination icons keep their visible labels. Where an icon-only Record control is still used (the compacted dock pill of S-4), its tooltip must be dismissible with Esc, hoverable and persistent while hovered or focused (WCAG 1.4.13).
- The rail is part of `MainShell`: it is present on the five tabs and absent on pushed routes (F5, I2), exactly like the bar today. Pushed pages are not redesigned in S03 (section 16).
- Bottom clearance: with the rail, tab content no longer reserves the 72 + 14 + dock space at the bottom (it reserves only the bottom safe area + 24); its start inset becomes the rail width + 12 + 16. The shell publishes both values in one inherited object (`ShellLayout`: window class, navigation presentation, rail width, bottom clearance) so no page computes them. How this reaches `HudScreenBody` and the Progress list without double padding is UNGROUNDED (17.5 extended).
- Keyboard: the rail is one focus group. Up and Down arrows move between the five destinations, Enter or Space selects, Tab moves on to the content. Home and End jump to the first and last destination ONLY while keyboard focus is inside the rail; outside it Home and End scroll the focused page (10.9). Tab order includes the pinned Record slot first.
- Semantics (review of revision 3): the rail is a container node: a `Semantics` widget with `container: true`, `explicitChildNodes: true` and the label "Main navigation" (the Flutter mechanism for a navigation landmark; Flutter has no named landmark role, so the label on a container is the contract and the content pane is not labelled the same). The bottom bar gets the same container and label. Each destination is `Semantics(button: true, selected: <bool>, label: <name>)`; the selected state is the semantics `selected` flag (and the same on the bar). A position hint "n of 5" is NOT provided: Flutter has no list-position semantics for plain buttons and adding it to the label would be read twice by screen readers that already count a group; this loss is accepted and recorded (a11y reviewer to confirm). Tooltips are not the accessible name.
- Contrast (review of revision 3): rail inactive labels and icons use the text-secondary tier of `HudTokens` (not the bar's literal inactive ink, whose light-theme ratio is 4.40, F10); the selected ink is the text-primary tier; the selected accent dot must reach 3:1 against the rail surface (non-text), and because the light accent is only 4.51 on the base the dot never carries meaning alone (ink and `selected` also do). If the build keeps the bar's literal inactive ink on the rail, the 4.40 exception of F10 is explicitly recorded for the rail as well; this contract prefers the secondary tier.
- Reduced motion (review of revision 3): the rail swap with the bar is a rebuild without animation. Every new sheet, dialog and popover route (S-3, S-5, Coming-later, S-10, Day-3) uses a no-transition or opacity-only page when `disableAnimations` is true, like the new full-screen routes (section 12).
- Swap behaviour: when a resize crosses a boundary of the table the presentation changes on the next frame, without animation; selection, route and focus are kept (WS-3).

### 10.5 Content layouts per size class

General rules. The content pane is the window minus the rail footprint (12 + rail width + 12 when the rail shows, otherwise 0), so a pushed route without a rail has a pane equal to the window. Side padding stays 16 dp (HUD screens) or 20 dp (Progress, F13). Max content width of the pane: 640 dp on Medium, 1120 dp on Expanded; wider panes centre the content.

TWO-PANE RULE (review of revision 3). A screen is laid out in two panes from the CONTENT PANE width (including its side padding), never from the window class, and falls back to the single-column Compact order when the pane is too narrow:

| Screen | Minimum main pane | Side pane | Gap | Padding | Two panes when pane width is at least | Below that |
|---|---|---|---|---|---|---|
| Home | 480 dp | 340 dp | 16 | 2 x 16 | 880 dp | Single column, Compact order (the side pane content follows the main column) |
| Progress | 480 dp (left column) | 320 dp (right column) | 16 | 2 x 20 | 880 dp | Single column, Compact order |
| Sources | 480 dp | 320 dp | 16 | 2 x 16 | 880 dp | Single column |
| Mode chooser | 456 dp (2 x 220 + 16) | 320 dp | 16 | 2 x 16 | 840 dp (window width; the chooser is a pushed route with no rail) | 2x2 grid with description under it |

Worked examples: Home at 1100 dp with the compact rail has a 980 dp pane, so two panes; at 1100 dp with the extended rail (text scale 1.3 or more) the pane is 836 dp, so ONE column; at 840 and 900 dp the pane is 720 and 780 dp, so one column; at 1024 dp (iPad landscape, compact rail) the pane is 904 dp, so two panes; at 1200 dp (extended rail) 936 dp, two panes. A tablet or Mac window in the Expanded class may therefore still show the single-column layout of Medium content, centred at the 640 dp cap on a pane under 880.

Tile columns (Progress "This week" tiles, and any future grid) come from the available width, not the class: columns = clamp(floor((available + 12) / (minimum tile width + 12)), 1, 3) with a minimum tile width of 160 dp and a 12 dp gap, where available is the width of the column that holds the tiles minus its padding. A tile never gets narrower than 160 dp. Columns never reorder content: the reading order is main column first, then side pane, and the same keys exist in every class. All states of the compact design (loading, empty, partial, error, offline, not-available) are kept unchanged; a large layout only moves panels, it never adds a state or hides content that Compact shows (Nothing is removed).

Home (S-6):

| Class | Layout |
|---|---|
| Compact | Single column, as in section 7 |
| Medium | Single column, max width 640 dp, centred; same order as Compact |
| Expanded with a pane of at least 880 dp | Two panes in a row inside the 1120 dp cap: main column (takes the rest, at least 480 dp) and side pane (fixed 340 dp, gap 16). Main: greeting and mode chip, upgrader intro card, deload banner, day panel, week section, "Activity today", and under the BODY lens the body-scan and nutrition cards directly under the day panel. Side: recovery panel, gym quick-scan row, upcoming, summary link, suggestions, "More". Under the BODY lens the quick-scan row and suggestions go to the end of the side pane. |

The lens rule of S-6 is unchanged: it reorders within the same key set. Keys: `home.pane.main`, `home.pane.side` on the two panes (Expanded only). The side pane drops below the main column (single column, Compact order, centred at the 640 dp cap) whenever the content pane is under 880 dp, for example at 900 dp with any rail, at 1100 dp with the extended rail (text scale 1.3 or more), or at 840 dp. The mode chip keeps its wrap rule (A9). `Day3WelcomeModal` is shown as a centred dialog of max width 480 dp on Medium and Expanded.

Progress, dashboard skeleton (S-7; list padding 20 and top 92 are kept, F13):

| Class | Layout |
|---|---|
| Compact | Single column in the order of section 7 |
| Medium | Single column, max width 640 dp, centred; "This week" tiles by the tile-column rule (minimum tile width 160 dp, at most 3 columns) |
| Expanded with a pane of at least 880 dp (below that: the Medium row) | A full-width headline row (`_HeadlineStats`), then two columns: left (flex 3): sync entry card, "All activity" block S-7b (tiles by the tile-column rule, at most 3, recent list) and the "Last 8 weeks" chart; right (flex 2, at least 320 dp): body-scan card, nutrition card, and the quiet Sources slot S-7a (or the Sources row of S-7b) |

Order inside each column equals the compact order restricted to that column, so the checks "S-7b follows the sync card and precedes the body-scan card" hold in Compact and Medium (single column) and become "S-7b is in the left column, the body-scan card in the right column" in Expanded. The journal error panel (failedToOpen) sits in the left column in the place of S-7b with its Try again button. Loading, empty, partial and offline behave as in section 7. The "Last 8 weeks" chart is the existing widget; it only receives the wider constraint (its own row uses `LayoutBuilder`, F28) and no table alternative is added (section 16).

Sources panel (S-8; pushed route, no rail, `HudScreenBody` kept):

| Class | Layout |
|---|---|
| Compact | Single column |
| Medium | Single column, max width 640 dp, centred |
| Expanded with a window of at least 880 dp (below that: the Medium row) | Max width 880 dp, centred: source rows in the main column (at least 480 dp), and a side pane (fixed 320 dp) holding the intro text, the dedup note and the optional Health sync link |

The rows stay non-interactive information (AC-SRC-4); no master-detail is introduced. All app-row states (In use, Ready, Not active, Problem with Try again) are in the main column.

Mode chooser S-1 and S-9 as ONE responsive screen (S-9 of revision 2 is merged into S-1, section 7): see S-1 "Layout by size class" and AC-CH-9 to AC-CH-13.

Other S03 surfaces: S-2 question steps keep the onboarding look with the content centred at max width 560 dp on Medium and Expanded. The Recording strip and Record pill live in the dock (bar presentation) or the rail Record slot (10.4); there is no dock on Expanded. The Home and Progress changes above are the only layout changes to existing tab pages in S03.

Pushed pages that S03 does not redesign (about 45 of the 50 routes, F5): PROPOSED, a shared frame centres their content at max width 840 dp on Medium and Expanded so they do not stretch to 1500 dp on a Mac window; full-bleed camera pages (scanner, form coach, body-scan and posture capture) are excluded from the frame. Whether S03 includes this frame or leaves those pages stretched is an OPEN design question (DQ-12, owner architect). How each of those pages looks on a wide window is UNGROUNDED.

### 10.6 Sheets, dialogs and popovers by class

| Surface | Compact | Medium | Expanded |
|---|---|---|---|
| S-3 Mode switcher | Modal bottom sheet | Modal bottom sheet, max width 560 dp, centred | Popover anchored under `home.modeChip`, 360 dp wide |
| S-5 Record sheet | Modal bottom sheet | Modal bottom sheet, max width 560 dp, centred | Popover anchored to the rail Record slot, 360 dp wide |
| Coming-later sheet, S-10 sign-out sheet | Modal bottom sheet | Centred dialog, max width 480 dp | Centred dialog, max width 480 dp |
| Day-3 welcome | As today | Centred dialog, 480 dp | Centred dialog, 480 dp |

Rules: every surface closes with Esc (keyboard), the system Back, a tap or click outside, and its own close/cancel action; focus moves into the surface on open (its title) and returns to the opener on close (section 12); a surface open during a class change is rebuilt in the new form with the same content, focus and scroll position. The look is the existing `HudSheet`/`HudPanel` on every family; only the placement adapts. Popovers must stay inside the window (flip above/below and clamp to the safe area). Anchors when a shortcut or the menu opens a popover (review of revision 3): the S-5 popover anchors to the rail Record slot, which is mounted on all five tabs (10.4), so it opens inside the window on `/scan` and `/profile` too; the S-3 popover anchors under `home.modeChip` on Home and, on any other tab where the chip is not mounted, opens as a centred dialog of 360 dp wide instead (never as an unanchored floating box); a popover whose anchor disappears during a resize is re-anchored or becomes the centred dialog. The Mac menu item File > Record behaves exactly like the shortcut on every tab (opens S-5); it is enabled on all five tabs and disabled only while a modal surface is open. The form follows the size class only, never the input device: a touch tap and a mouse click open the same form. Day-3 welcome and the Coming-later sheet follow the table row for their own class (Day-3: as today on Compact, centred dialog of 480 dp on Medium and Expanded; the same as 10.5).

### 10.7 Phone-width, text-scale and RTL rules (retained from revision 2, now the Compact column of the model)

| Width / condition | Behaviour |
|---|---|
| Phone 320-411 dp (primary) | As specified. Mode cards 2x2, at least 140 dp wide at 320 dp; below 150 dp the blurb is dropped from the card face and stays in the hint/description. |
| Phone landscape / height under 480 dp | No orientation lock exists. Chooser grid becomes 4x1 when the window height is under 480 dp (the one "short" threshold of 10.1); sheets scroll; dock compaction per S-4. Requirement: no overflow. |
| Text scale 2.0 | Cards grow vertically, grid stays 2 columns on Compact, blurb wraps to 3 lines then ellipsises (the description area is never truncated); the chooser scrolls. Chips (C-2, C-11) wrap to two lines; chip text is never truncated at 2.0 in Russian or English. The dock strip is two lines (title above time). The nav bar behaviour is unchanged (F4, existing limitation). The rail uses its extended form at scale 1.3 and above (10.4). |
| Keyboard open | No text input in these screens. |
| RTL (finding A10) | No RTL locale ships (F20). New code uses start/end (`EdgeInsetsDirectional`, `AlignmentDirectional`), mirrored chevrons via `Directionality`; the rail sits on the start side (right in RTL); one widget test pumps S-1 and S-4 with `TextDirection.rtl` and expects no overflow. |

### 10.8 Platform families: what is identical and what adapts

One codebase. Build targets today: Android only (F26). The Apple columns describe the design for targets that do NOT exist yet (OD-12); they cannot be run or released from this repository today.

Identical on every family (no platform branching): the five destinations and their order; copy and ARB keys; the mode model; the data rules (section 11); the HUD visual language (tokens, glass panels, colours); the bundled fonts (F29: Archivo with Inter for Cyrillic, Barlow Condensed, Roboto Mono; the theme does not use system fonts, so San Francisco and Roboto are NOT used; switching Apple builds to the system font is an OPEN design question, DQ-13, owner product-ux, and is not assumed); component look; state vocabulary; accessibility semantics; test keys.

Adaptive (decided at run time from the window size class, section 10.1, or from the platform):

| Topic | Android phone and Android tablet (Material) | iPhone, iPad, Mac (Apple conventions) |
|---|---|---|
| Base widgets | Material 3 theme is on (F29); HUD controls are custom and look the same | HUD controls look the same; no Cupertino widget is introduced (F28). Apple adaptation is behaviour and placement, not a restyle |
| Back and navigation | System Back and predictive back; on a non-home tab Back goes to Home, on Home it leaves the app (F3) | iPhone and iPad: left-edge swipe back on pushed pages (the current custom fade-and-scale transition has no edge swipe, F29, so the Apple targets need a swipe-back-capable transition for pushed routes). Mac: no swipe; a visible Back control on every pushed page that S03 touches, and Cmd+[ as the keyboard Back (Esc is NOT Back: it only closes the top-most open surface, popup or field, 10.9). Apple has no system Back button, so on a non-home tab the visible way back is the tab itself; the F3 rule applies only where the platform sends a Back event (Android Back, Cmd+[) |
| Tab re-selection | Selecting the already selected destination scrolls its page to the top (PROPOSED, identical on all families; harmless where unused) | Same |
| Sheets and popovers | Bottom sheets on Compact, popovers and centred dialogs on larger windows (10.6) | Same placement rules; on iPad and Mac popovers are the Apple pattern and are anchored to the control; on iPhone bottom sheets. Dismiss by tap outside, Esc, or swipe down on a bottom sheet |
| Safe areas | Edge-to-edge is already required at `targetSdk` 36 (INFERENCE); the existing code reads `MediaQuery.paddingOf` for bottom and top (F28) | iPhone notch or Dynamic Island and home indicator come through the same insets; iPad Stage Manager windows get their own insets; on Mac, if the window uses a full-size content view the traffic-light buttons (about 28 dp tall) overlap the top of the rail, so the rail's top inset must clear them. UNGROUNDED until a macOS runner exists |
| Text scaling | Font scale from the system; layouts are tested at 2.0 (S-1 to S-8) | Dynamic Type reaches larger sizes than 2.0 (accessibility sizes, about 3x; UNGROUNDED, Apple value not in the repository): up to 2.0 the contract is tested; above 2.0 all screens scroll and no status word may be truncated, but no layout is promised pixel-perfect. Mac has no system text scaling |
| Haptics | Light feedback on mode selection and on Continue (PROPOSED; today only the rest timer and the scanner use haptics, F30). Never the only feedback | Same calls; on iPad without haptic hardware and on Mac the call is a no-op. No required behaviour depends on it |
| Scrolling | Platform scroll physics by default (INFERENCE: the app is not known to override it; UNGROUNDED) | Bouncing physics on Apple by the same default; trackpad and wheel on Mac (10.9) |
| Health sources (S-8) | Health Connect row | Apple Health row, listed only when running on an Apple platform; no adapter exists on any platform in S03 |
| Pointer and keyboard | Tablet with mouse or hardware keyboard: 10.9 | iPad with trackpad or keyboard and Mac: 10.9 |
| Window | Free-form windows in Android desktop mode: the class model | Stage Manager and Mac windows: the class model and the Mac minimum size (10.9) |

### 10.9 Pointer, keyboard, trackpad and the MacBook window

Applies to MacBook, and equally to iPad and Android tablets when a pointer or hardware keyboard is attached. Touch targets stay at 48 dp in every family (pointer use does not shrink them).

Window (MacBook): resizable, default 1100 x 760 dp, minimum 480 x 600 dp, full screen supported. Below 600 dp wide the Compact layout applies, which the model already supports from 320 dp. The window size values are set by the future macOS runner, not by Dart code (UNGROUNDED, no macOS target); remembering the last window size is a runner feature and is PROPOSED, not required.

Pointer:
- Every enabled interactive control (cards, chips, buttons, rows, rail items, Record) has a hover state and the pointing-hand cursor; disabled controls show the default arrow; non-interactive text shows the arrow, selectable text (none in S03) the text cursor.
- Hover uses the same press geometry and accent wash the controls already have (F30) at half strength; no new colour. The exact token is UNGROUNDED.
- Hover never reveals information that is not also reachable otherwise; tooltips (500 ms) only repeat the accessible name on icon-only controls (compact-rail Record, compacted dock pill).
- Click, double click and right click: single click activates; no double-click or right-click behaviour is defined in S03 (no custom context menus).
- Scroll wheel and two-finger trackpad scroll move every scrollable page and sheet; a visible scrollbar appears on scroll views of Expanded windows and wherever a mouse is attached; pinch and rotate gestures are ignored. No screen requires a drag, swipe, long-press or pinch: S03 adds no gestures, and every gesture that exists elsewhere has a button path (the rule is tested, AC-KB-6).

Focus: on keyboard-driven focus every focusable control of the S03 surfaces draws the 2 px outline of section 12 (not on mouse click). Existing HUD controls on pages S03 does not touch still draw none (F30); that is a known limit on Mac and iPad with keyboards (section 16).

Keyboard (hardware keyboard on Mac, iPad and Android tablet; the modifier is Cmd on Apple platforms and Ctrl on Android). Shortcuts are inactive while a text field has focus, except Esc, and while a modal surface is open only Esc and Tab work.

| Shortcut | Action |
|---|---|
| Cmd/Ctrl + 1 to 5 | Go to Home, Workouts, Scan, Progress, Profile (the order of the navigation list) |
| Cmd/Ctrl + Shift + R | Record: idle opens the Record sheet (S-5); while the strip shows it opens the strip destination. In S03 nothing is started or stopped by it (no recorder exists, F18); when the recorder sprints land, the same key starts and stops, with a confirmation before stopping. Reserved now so it does not change later |
| Cmd/Ctrl + Shift + M | Open the mode switcher (S-3) |
| Cmd/Ctrl + [ | Back, with the same result as system Back (F3) |
| Esc | Precedence: (1) close the top-most open sheet, popover or dialog; (2) otherwise close a focused popup or leave a focused text field; (3) otherwise nothing. Esc never navigates back |
| Selected destination activated again | Scrolls that page to the top (no route change) |
| Cmd + , (Mac and iPad) | Open Settings |
| Tab and Shift + Tab | Move focus; order in section 12 |
| Arrow keys | Move within the rail, the chooser grid and the switcher rows |
| Enter and Space | Activate the focused control |
| Page Up, Page Down, Home, End | Scroll the focused page; Home and End act on the rail only while keyboard focus is inside the rail |

Conflict check: UNGROUNDED. The shortcut set was NOT checked against macOS, iPadOS or VoiceOver defaults in this revision (no Apple system is available to the author). Known risks to verify: Cmd+1 to 5 and Cmd+, are conventional on macOS; Cmd+Shift+M and Cmd+Shift+R may collide with system or app-level commands in some contexts; Cmd+[ is the usual Back in browsers. The a11y-architect and a Mac check decide the final set (DQ-15). VoiceOver uses Control+Option as its modifier, so the Cmd combinations above are not expected to collide with it (INFERENCE, not verified).

Menu bar (macOS only, PROPOSED, built together with the macOS target through the platform menu API; not in S03 code): App menu with About and Settings (Cmd+,); File with Record (Cmd+Shift+R) and Close Window; View with the five destinations (Cmd+1 to 5) and a Mode submenu (Train, Ride, Explore, Body; Ride and Explore disabled and labelled "Coming later"; the submenu title opens S-3 with Cmd+Shift+M); the standard Window and Help menus. Menu items enable and disable with the same availability rules as the app, and no function exists only in the menu.

Trackpad back swipe on Mac: not provided (Cmd+[ and the visible Back control are the paths).

## 11. Data honesty and copy rules
1. Unknown is "No data"; zero only when the source reports zero.
2. Estimates carry "Estimate"; no range is invented in S03.
3. No cross-sport energy; no cross-group total of sessions or time in S03.
4. Sync/cloud words appear only with `ACTIVITY_CLOUD_STREAMS` on.
5. Never say "merged", "deduplicated" or "synced with Health Connect".
6. No body-shaming, medical claim or streak pressure; BODY copy reuses existing strings.
7. (Revision 3.) Retention wording. Any copy about how long GPS history is kept in the cloud offers exactly three expiry choices, 90 days, 365 days and 730 days (2 years), with 730 days as the default; "never" is NOT offered anywhere (S02 answer of 2026-10-16). The S03 screens do not contain a retention control (the consent centre does, OD-8), but any text or test fixture in S03 that names retention uses these values, and a text search of S03 ARB additions finds no "never keep" or "forever" wording. Lengthening a setting does not bring back expired history, shortening applies at the next purge (S02 5.3).
8. Errors are plain sentences with a next step, never exception text; tone models: `errorServiceUnavailable`, `foodDiaryError` + `foodDiaryErrorBody`. "Not available" states are neutral statements, not errors, and never offer a retry that cannot succeed.

## 12. Accessibility

Target: WCAG 2.2 AA on the new surfaces, validated by the independent a11y review. Observable acceptance criteria are in section 14.

| Topic | Requirement |
|---|---|
| Touch targets | New controls (C-1, C-2, C-8, C-9 rows, sheet buttons) at least 48x48 dp including the hit region (9.1); existing HUD controls keep 44 (DQ-3). 8 dp between adjacent targets. |
| Focus order | Chooser: title, four cards in reading order, Continue, Decide later. Home: greeting, `home.modeChip`, then the existing order. Dock: after tab content, before the nav bar. Sheets trap focus; first focus is the sheet title (header, focusable, as in `cloud_consent_sheet.dart`); closing returns focus to the opening control. |
| Visible focus | The HUD controls draw none today (audit). The new controls draw a 2 px outline in the text-primary token with 2 px offset, visible in both themes; retrofit of old controls is outside S03 (section 16). |
| Semantics (via the 9.1 extensions) | Mode card: button, `isSelected`, in an exclusive group, label "Train, Gym, plans and technique", hint = description; comingLater: label "Ride, Routes and rides, Coming later", hint "Opens details", enabled. Mode chip: button, label per `homeModeChipLabel`. Strip: button; label "Workout in progress, 12 minutes" (minutes only), hint "Tap to resume"; the visible seconds are inside `ExcludeSemantics`. Headers: `Semantics(header: true)` on the title of S-1, S-3, S-5, S-8, S-7b. Status chips are read as text; the icon is excluded. Disabled rows expose their reason in the value. |
| Announcements | Use `SemanticsService.announce` (repo precedent F22), polite: mode change ("Mode changed to Ride"), strip transitions (started, paused, resumed, ended: a removed node cannot hold a live region), question step ("Question 1 of 2"), save failure the user just triggered. NOT announced: the ticking time, the chooser description (finding A7: the description is the card hint), loading placeholders. |
| Contrast | Floor 4.5:1 for text and 3:1 for non-text/icons against the effective surface. Dark theme: all `HudTokens` text tiers pass over `base` (audit table). Light theme (finding A8/A9): accent `#4B7A00` is 4.51:1 with no margin and so is NOT used as text on new surfaces (selection dot and icons only, with the word "Selected" carrying the meaning); `warning` (1.50) and `danger` (2.69) are never text or sole signal; the nav inactive ink 4.40 is a recorded pre-existing exception, not changed here. Surfaces over the sky photo use the `dense` tier; panel-over-photo contrast is unmeasured (17.8). |
| Colour independence | Selection = ink + dot + word; status = word + icon. |
| Reduced motion | Uses `context.hudMotionDuration`; no looping animation anywhere in S03 and no indeterminate progress indicator (finding A5): loading states are static (outlines, text "Checking"/"Saving"). Every new sheet, dialog and popover route (S-3, S-5, Coming-later, S-10, Day-3) also gets a no-transition or opacity-only transition when `disableAnimations` is true (AC-WS-14). New full-screen routes (S-1, S-8) are built with a page builder that returns a no-transition page when `disableAnimations` is true, because the router's `_fadeThrough` ignores reduced motion (audit section 8). |
| Text scale | Layouts hold at 2.0 (section 10). Russian is the default locale (F20) so every check below runs in `ru` first. |
| Keyboard | Controls activate with Enter/Space; cards reachable by Tab/arrow; Esc closes sheets. |
| Charts | None introduced; no table alternative needed until S15. |
| Large screens (revision 3) | Reading and focus order follow the layout: rail (Record slot, then the five destinations), then the main column, then the side pane (Home, Progress, Sources, chooser detail panel). Visual order and focus order never disagree; the side pane is never first. A class change keeps focus on the same control or the same destination (WS-3). The rail is one landmark labelled "Main navigation" (the bar gets the same label); the content pane is the main landmark. |
| Rail semantics | Mechanism in 10.4: a container `Semantics` labelled "Main navigation" (no "n of 5" position hint, loss accepted). Each destination: button, `selected`, label (not upper-cased in the tree, as the bar, F4); Record slot: button with the accessible name "Record" or the strip label; compact-rail icons carry a tooltip with the same name; the extended form's visible label equals the accessible name. |
| Pointer (revision 3) | Hover and cursor on every enabled control (10.9); hover state is not the only indication of anything; targets stay 48 dp; tooltips repeat names only; no drag, swipe, long-press or pinch is required anywhere in S03 (WCAG 2.5.1 pointer gestures, 2.5.7 dragging alternatives). |
| Keyboard, full (revision 3) | Everything reachable by Tab; focus ring on keyboard focus for all new controls; arrow-key groups for the rail, the chooser grid and the switcher; shortcuts of 10.9 never trap focus and never fire inside a text field or a modal; Esc closes the top-most surface; a popover opens focus on its title and returns it to the opener. No keyboard trap (WCAG 2.1.2). |
| Per family | Android: TalkBack, system Back, font scale. iPhone and iPad: VoiceOver, Dynamic Type, Full Keyboard Access, Reduce Motion, Switch Control (design intent; no Apple build exists, so these are NOT_RUN until OD-12 is answered and the targets are built). Mac: VoiceOver, keyboard navigation, Reduce Motion. The Flutter semantics tree is the same on all families; the contract does not claim Apple screen-reader behaviour was observed. |
| Reflow and zoom | At 400 percent equivalent (a 320 dp window at text scale 2.0, or a window narrowed to 480 dp on Mac) every S03 screen reflows to the Compact layout without horizontal scrolling (WCAG 1.4.10). |

## 13. Localization (finding A2: Russian is the default locale)

- Russian is the first supported locale and the fallback (F20). Strings are authored in English here (git rule), but every key MUST ship with a Russian value in the S03 build and be tested in `ru` first.
- Sentences that embed a mode name are NOT built by interpolating a name (Russian declension breaks). Each such sentence is an ICU `select` on the mode (`{mode, select, train{...} ride{...} explore{...} body{...} other{...}}`) or four full-sentence keys: `modeComingLaterSheetTitle`, `recordSheetTitle`, `homeModeChipLabel`, `stripModeLabel`, `modeSwitcherCurrent`. The visible mode name alone comes from the name key.
- Counts use ICU plural with the Russian forms one/few/many/other: `modeSwitcherQuestions`, `activityTimeFrom`, the "+{k} sources" label, the J10 count, and the spoken strip duration. The spoken duration is a localized, plural-aware formatter ("12 minutes" with the correct Russian form), not an English string with a number.
- Per-key length budgets (finding A2). The Russian word for a mode name can be about 1.6-2x the English length ("Train" becomes a ten-character word); the draft's flat 1.35 factor is withdrawn. Budgets are in characters of the Russian string and must be met at scale 1.0 without ellipsis, and wrap (not truncate) at 2.0:

| Element | Budget (Russian chars) | Overflow rule |
|---|---|---|
| Mode name on a card | 14 | wraps to 2 lines |
| Card blurb | 40 | 2 lines at 1.0, 3 at 2.0, then ellipsis |
| Mode chip text | 16 | wraps to 2 lines |
| Status chip word | 22 | wraps to 2 lines, never truncated |
| Button labels (Continue, Decide later, Try again) | 18 | wraps (HudButton allows two lines when not centred) |
| Sheet row title / description | 28 / 60 | description wraps |
| Strip title | 24 | wraps to a second line |
| Section headers | 28 | wraps |
| Nav labels in the bottom bar | unchanged (five-tab shell) | existing one-line ellipsis |
| Nav labels in the side rail (revision 3) | 11 in the compact form (96 dp), 18 in the extended form (240 dp) | never truncated; at text scale 1.3 and above or window 1200 dp and above the extended form is used |
| Side pane section titles (Home, Progress, Sources) | 28 | wraps; side panes are 320-340 dp wide, so a title of 28 Russian characters at scale 1.0 must fit in two lines |
| Detail panel description (chooser, Expanded) | 60 | wraps in the 320 dp panel, never ellipsised |

- Large screens (revision 3): Russian stays the default and first-checked locale. The rail and the side panes are the narrowest places Russian text must fit: the rail's compact form holds a label of up to 11 characters (FACT per the lead agent's reading of `mobile/lib/l10n/app_ru.arb`, closed after the review of revision 3: the five Russian labels are Главная, Тренировки, Скан, Прогресс, Профиль; the longest is "Тренировки" at 10 characters, so the 11-character budget holds at scale 1.0; the pixel width in the rail is measured by AC-WS-3, not assumed); side panes are 320-340 dp wide. Each large-screen test runs `ru` first, at scale 1.0 and 2.0, at 1100 dp wide.
- Verification mechanism: a test runs each new screen in `ru` at scale 2.0 and, for each contract key listed in section 7, asserts `RenderParagraph.didExceedMaxLines == false` for status chip words, chip text, button labels and headers; where the budget allows ellipsis (blurb) it asserts the first 24 characters are visible. A pseudo-locale run (every string length x1.6 with accents) is added for keys whose Russian value is not yet authored.
- Number, date, duration formatting through `intl` with the resolved locale (`AppLanguage.resolvedLocaleCode`). Units are metric only in S03; no units setting exists (F20, DQ-4); strings carry no hard-coded "km".
- Mode names are stable product vocabulary; the Russian equivalents are decided in the translation pass and recorded in the ARB.

## 14. Acceptance summary, cross-cutting criteria and test seams

Per-screen criteria are in section 7. Cross-cutting criteria (all observable in widget tests; a test never depends on a real OS dialog):

- AC-SH-1. The shell nav configuration list has exactly five entries with paths `/home`, `/workouts`, `/scan`, `/progress`, `/profile` in that order and labels from the keys `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`.
- AC-SH-2. Back from any non-home tab ends at `/home`; Back on `/home` pops out (F3 unchanged; reuse the existing shell test).
- AC-SH-3. The nav bar is built from the configuration list; changing the list changes the bar (test with a 4-item list).
- AC-SH-4. Switching mode changes neither the router location nor `HudNavBar.selectedIndex`.
- AC-SH-5. `shell.dock.recordPill` and `shell.dock.strip` are never in the tree together.
- AC-SH-6. (Rewritten, finding U6.) With `permission_handler`'s method channel mocked to record calls, pumping S-1, S-2, S-3, S-5 (without following a row), S-6, S-7 and S-8 produces zero calls. Static check: no import of a location or permission package under the new S03 files.
- AC-REG-1. The existing scanner and equipment tests pass unchanged; `/scan` still routes as before (G-5).
- AC-REG-2. `isDemoGatedPath` behaviour for `/community`, `/celebrity-plans`, `/contribute`, `/moderate`, `/team/*` is unchanged.
- AC-REG-3. [flag off] Existing Home and Progress widget tests pass unchanged with default providers.
- AC-REG-4. With `ACTIVITY_CLOUD_STREAMS` off no sync wording is present in the S03 widgets (text search of the pumped trees).
- AC-A11Y-1. (Rewritten, findings A1, A3.) For each new interactive control (C-1, C-2, C-8, C-9, sheet buttons, strip, and, after the review of revision 3, the five rail destinations and `shell.rail.record`, with the rail's "Main navigation" container, see AC-WS-11) use `tester.getSemantics(find.byKey(...))` and assert with `matchesSemantics`: role (`isButton`), non-empty `label`, expected `hint`, `isSelected`/`isEnabled` where specified, `hasTapAction`, and a size of at least 48x48 from `tester.getSize` of the tappable ancestor (the hit region, not only the painted box).
- AC-A11Y-2. Headers: `isHeader` is true for the titles of S-1, S-3, S-5, S-7b ("All activity"), S-8.
- AC-A11Y-3. Focus: sending Tab key events on S-1 visits the four cards, Continue, Decide later in that order; opening S-3 from `home.modeChip` and closing it returns focus to `home.modeChip`; the first focused node inside a sheet is its header.
- AC-A11Y-4. Announcements: capture messages on the accessibility channel (the transport of `SemanticsService.announce`); a mode change emits one message containing the new mode name; strip transitions started, paused, resumed, ended each emit one; advancing a fake clock by 30 seconds emits none and the strip's semantics label is unchanged until the minute boundary.
- AC-A11Y-5. Text scale 2.0 in `ru` and `en` on a 360x640 surface for every new screen S-1, S-2, S-3, S-4 (strip and pill), S-5, S-6 (chip row, intro card, activity today), S-7a/S-7b, S-8: no `RenderFlex` overflow exception AND `didExceedMaxLines == false` for the keyed status-chip words, chip texts, button labels and headers.
- AC-A11Y-6. Reduced motion: under `MediaQuery(disableAnimations: true)`, `context.hudMotionDuration(d)` as used by the new widgets resolves per `hud_tokens.dart` (the test asserts the documented zero/reduced result), `pumpAndSettle` returns without waiting, and no `CircularProgressIndicator`/`LinearProgressIndicator` indeterminate exists in S03 trees.
- AC-A11Y-7. RTL: S-1 and S-4 pump in `TextDirection.rtl` without overflow.
- AC-A11Y-8. Contrast: the new components use only `HudTokens` text tiers (static test greps new files for `Color(0x` and `Colors.`; none allowed) and no use of `warning`/`danger`/zone colours as a text style.

Large-screen, size-class, pointer, keyboard and per-family criteria (revision 3). Each is a widget test with a set window size (`tester.view.physicalSize` with a device pixel ratio of 1.0), a set text scale and, where stated, a faked `TargetPlatform`; none needs a device. "Window WxH" means logical dp.

Window-size model and navigation (10.1, 10.4):
- AC-WS-1. The class provider returns compact at 599 wide, medium at 600 and 839, expanded at 840 (any height of 480 or more). At 700x420 the class is medium and the short flag is true; at 500x420 the class is compact and short.
- AC-WS-2. Navigation presentation: 360x800 and 700x900 show `shell.bottomBar` and no `shell.rail`; 700x420, 900x400 and 1100x800 show `shell.rail` and no `shell.bottomBar`. At 700x900 the bar is at most 560 dp wide.
- AC-WS-3. Rail form (rewritten after review): at 1100x800 and text scale 1.0 `shell.rail` is 96 dp wide (compact form); at 1200x800 it is 240 dp (extended). In `ru`, at 1100x800 and text scales 1.0, 1.15 and 1.29, for each scale the test measures the widest of the five upper-cased labels (Главная, Тренировки, Скан, Прогресс, Профиль) with a `TextPainter` in the nav-label style at that scale; if the measured width + 16 is at most 96 the rail is 96 dp wide and no label overflows, otherwise the rail is 240 dp wide. The test also asserts the form is extended at scale 2.0.
- AC-WS-10. Rail vertical fit: at 640x360 and 800x360, text scales 1.0, 1.3 and 2.0, locale `ru`: no `RenderFlex` overflow; the five destinations and `shell.rail.record` are all reachable by Tab (and the five by arrow keys); each destination's hit height from `tester.getSize` is at least 48 dp; a destination focused by Tab is fully inside the window (scrolled into view); `shell.rail.record` keeps the same top `Rect` while the list scrolls.
- AC-WS-11. Rail semantics: with `matchesSemantics` the rail container has the label "Main navigation" and is a container node; each destination is a button with a non-empty label, `isSelected` true only for the current tab, and `hasTapAction`; the same holds for the bottom bar's container and tabs; `shell.rail.record` is a button with the label "Record" (idle) or the strip label (running).
- AC-WS-12. Stable rail geometry: at 1100x800, the top `Rect` of the Progress destination is identical on all five tabs (`/home`, `/workouts`, `/scan`, `/progress`, `/profile`) with idle timers and with a running set timer; `shell.rail.record` exists and is enabled on all five tabs in the idle state.
- AC-WS-13. Compact-rail running state: at 1100x800, text scale 1.0, `ru`, with a set timer running then paused, the visible text nodes inside `shell.rail.record` (state word, minutes) exist, differ between running and paused, and raise no overflow; the idle slot shows the visible label "Record".
- AC-WS-14. Reduced motion for surfaces: with `disableAnimations` true, opening S-3 and S-5 reaches the final state after one `pump` (no `pumpAndSettle` needed); resizing 360x800 to 1100x800 with S-3 open changes it from a bottom sheet to a popover, focus stays on the surface title, and the scroll offset of the sheet is kept.
- AC-WS-4. Rail content: `shell.rail` contains five destination nodes in the order of AC-SH-1, plus `shell.rail.record` above them; the same list drives the bar (AC-SH-3) and the rail (a 4-item test list gives 4 rail destinations).
- AC-WS-5. Live swap: pump at 1100x800 on `/progress` with the rail, resize to 360x800 then back; the router location stays `/progress`, `HudNavBar.selectedIndex` equals the rail selection (3), a fake running timer state is unchanged, and the focused destination is the Progress one in both presentations (WS-3).
- AC-WS-6. Rail visibility follows the shell: on a pushed route (`/workout/:id`, `/settings`) at 1100x800 neither `shell.rail` nor `shell.bottomBar` exists.
- AC-WS-7. Rail Record slot (rewritten after review): at 1100x800 with idle timers `shell.rail.record` is the enabled Record button on all five tabs; with `setTimerProvider` running it is the strip on all five tabs; the dock `shell.dock` does not exist in the rail presentation. Tapping it opens S-5 as an anchored popover (`recordSheet.popover`) at 1100x800, as a bottom sheet of at most 560 dp at 700x420 (Medium with rail) and as a bottom sheet at 360x800 (bar presentation, where AC-ST-1 still holds: pill only on Home, Workouts, Progress). The Record shortcut on `/scan` at 1100x800 opens S-5 and the popover `Rect` lies fully inside the window.
- AC-WS-8. Bottom clearance: with the rail, the last child of a scrollable tab ends at most 24 dp plus the bottom inset above the window bottom (no dock space reserved) and the first child starts at least rail width + 12 + 16 from the start edge.
- AC-WS-9. Orientation: 800x360 and 360x800 pump every tab without overflow; no call to a preferred-orientation channel is made by the app (the mocked `SystemChrome` channel records none).

Screens by class (10.5):
- AC-LS-9. Narrow-pane fallback (review of revision 3): Home, Progress, Sources and the mode chooser at 840x800 and 900x800, at text scales 1.0, 1.3 and 2.0, locale `ru`: no overflow, no horizontal scroll (the scroll extent on the horizontal axis is zero), and below each minimum of the two-pane table (pane under 880 dp; chooser window under 840 dp) the key order equals the Compact order and neither `home.pane.side`, the Progress right column nor `modeChooser.detailPanel` exists (the chooser has its detail panel at exactly 840 and wider). Also: Home at 1100x800 has two panes at scale 1.0 (pane 980 dp) and ONE column at scale 1.3 (extended rail, pane 836 dp); at 1200x800 (extended rail, pane 936 dp) two panes; Progress tiles use the tile-column rule (never narrower than 160 dp: assert every tile width at least 160 dp at 360x800, 700x900 and 1100x800).
- AC-LS-10. Scroll anchors (WS-3, review of revision 3): scroll Home so that `home.section.upcoming` is the first visible section, resize 700x900 to 1100x800 and back; the section is still on screen after each change. The same for Progress with `progress.recent`.
- AC-LS-11. Chooser idle state: at 1100x800 on first run `modeChooser.detailPanel` shows `modeDetailIdle`, `modeChooser.continue` is disabled and no card `isSelected`; a touch tap on `modeChooser.card.body` (no hover event) selects it and the panel shows the body description; no illustration placeholder node exists.
- AC-LS-1. Home at 1100x800 and text scale 1.0: `home.pane.main` and `home.pane.side` exist side by side, the side pane is 340 dp wide, the content width does not exceed 1120 dp, and the union of `home.section.*` keys equals the Compact key set (nothing removed). At 700x900 and 360x800 neither pane key exists and the order equals the Compact order.
- AC-LS-2. Home lens at 1100x800: with the BODY lens `home.section.bodyScan` and `home.section.nutrition` precede `home.section.quickScan` in the main-then-side reading order; with TRAIN they equal the pre-S03 relative order.
- AC-LS-3. Home at 900x800 with text scale 2.0: the side pane is below the main column (single column) and no overflow is raised.
- AC-LS-4. Progress at 1100x800 with a journal holding one session: `progress.allActivity` is in the left column, the body-scan card in the right column (compare `Rect.left`), tile columns equal clamp(floor((available + 12) / 172), 1, 3) for the left column's available width (3 per row at 1100x800 with scale 1.0); at 700x900 one column with the same rule applied to the 640 dp column; at 360x800 the order is exactly AC-PR-3.
- AC-LS-5. Progress states at 1100x800: journal `failedToOpen` shows `progress.journalError` and `progress.journalRetry` in the left column; zero sessions shows only `progress.slot.sources` (right column) and no `progress.allActivity`; an offline fake changes nothing; loading shows the Sources row first. The same assertions as AC-PR-1 to AC-PR-3 hold with columns instead of order.
- AC-LS-6. Sources at 1100x800: the main column holds all `sources.row.*`, the side pane holds `sources.dedupNote`, the width does not exceed 880 dp, and AC-SRC-1 to AC-SRC-7 still pass. At 700x900 and below it is one column.
- AC-LS-7. Chooser: AC-CH-9 to AC-CH-14.
- AC-LS-8. Surfaces by class (10.6): S-3 is a bottom sheet at 360x800, a bottom sheet of at most 560 dp wide at 700x900, and a popover (`modeSwitcher.popover`) whose rectangle lies inside the window and below `home.modeChip` at 1100x800. The Coming-later and sign-out surfaces are centred dialogs of at most 480 dp at 700x900 and 1100x800. Esc closes each of them with no write to any fake store, and focus returns to the opening control.

Pointer, keyboard and focus (10.9, section 12):
- AC-KB-1. Shortcuts at 1100x800 with a faked Apple platform (Cmd) and a faked Android platform (Ctrl): the modifier + 1 to 5 reach `/home`, `/workouts`, `/scan`, `/progress`, `/profile`; modifier + Shift + M opens `modeSwitcher.sheet` or popover; modifier + Shift + R opens the Record surface (or, with a running timer, pushes the strip destination); modifier + `[` behaves like system Back (AC-SH-2). None of them fires while a `TextField` is focused or a modal is open (assert no navigation). Extended after review: modifier + `,` pushes `/settings` on Apple platforms (faked iOS and macOS) and does nothing on faked Android; Esc precedence: with a popover open Esc closes only the popover; with a focused popup menu or field open Esc closes that first; with nothing open Esc does NOT navigate back (Esc-as-Back is dropped, 10.8); modifier + `[` on a non-home tab goes to `/home`, on a pushed page pops it; re-selecting the selected destination (click or Enter) scrolls its page to the top, with no route change; on a pushed page at 1100x760 under the faked macOS platform a visible Back control exists (AC-KB-8). Home and End move rail focus only while focus is inside `shell.rail`; with focus in a page they scroll it.
- AC-KB-2. Rail arrows: with focus on the first destination, Down moves focus to the next destination, End to the last, Home to the first; Enter selects (router location changes); Tab leaves the rail to the content.
- AC-KB-3. Focus ring: for each new control (rail destinations, `shell.rail.record`, `home.modeChip`, chooser cards, sheet rows) focus moved by a Tab key event shows the 2 px outline (the focused node paints the ring: find the `showFocusRing` decoration), and a pointer tap does not.
- AC-KB-4. Hover and cursor: a test mouse gesture hovering an enabled `modeChooser.card.train` sets the pointing-hand cursor (the `MouseRegion` cursor) and the hover style; a disabled control shows the basic cursor; hovering changes no selection and no semantics label.
- AC-KB-5. Scroll and scrollbar: a mouse-wheel `PointerScrollEvent` over Home, Progress and Sources scrolls them; at 1100x800 a `Scrollbar` exists on each main scroll view.
- AC-KB-6. No gesture-only path: a static check over the new S03 files finds no `onLongPress`, `onHorizontalDrag*`, `onScale*`, `Dismissible` or `onPan*` handler; every interaction in S-1 to S-8 is operable with taps, keys and clicks only.
- AC-KB-8. Visible Back on Apple desktop (10.8): UNGROUNDED whether HUD pages already show a Back control (not read). Contract: under the faked macOS platform every pushed page that S03 touches or frames (S-1, S-2, S-8, and framed pages if DQ-12 is yes) exposes a Back control found by `find.byKey(Key('shell.back'))` with a button role and the label "Back"; pages that S03 does not touch are listed in section 16 as not guaranteed.
- AC-KB-9. Contrast of rail ink (review of revision 3, token-level test): the rail's inactive ink (text-secondary tier) over the rail surface reaches at least 4.5:1 and the selected ink (text-primary) at least 4.5:1, in the light and dark `HudTokens` (computed from the token values with a contrast function, not from pixels); the selected accent dot reaches at least 3:1; if the literal bar ink is kept for the rail the test instead asserts the recorded 4.40 exception value and fails if it worsens.
- AC-KB-7. Windows without a pointer: the same flows at 360x800 with touch events only pass unchanged (shortcuts and hover are additive).

Per family (10.8; Apple cases use a faked `TargetPlatform` and are widget tests only, no Apple build exists):
- AC-FAM-1. `TargetPlatform.android` at 360x800 and at 1100x800: system Back on a non-home tab goes to `/home` (F3); the S-4 and S-5 criteria pass.
- AC-FAM-2. `TargetPlatform.iOS` at 390x844 and `TargetPlatform.macOS` at 1100x760: the identical key sets, copy and semantics of the Android run (compare the sets of keyed nodes and their labels); no `Cupertino*` widget appears (static check); the Apple Health row is absent in S03 (AC-SRC list unchanged).
- AC-FAM-3. Safe areas: with `MediaQuery.padding` set to a top of 59 and a bottom of 34 (iPhone-like) and to a bottom of 0 and a top of 28 (Mac title area) the dock or rail, the first and the last child do not overlap the insets (compare `Rect`s).
- AC-FAM-4. Text scale: S-1, S-3, S-5, S-6, S-7, S-8 and the rail at scale 2.0 in `ru` and `en` at 360x800, 700x900 and 1100x800: no overflow and `didExceedMaxLines == false` for status words, chip texts, button labels, headers and rail labels (extends AC-A11Y-5 to the three classes).
- AC-FAM-5. Haptics: selecting a mode and tapping Continue call the haptic channel once each on the faked mobile platforms and do not fail when the channel is absent (the Mac case).
- AC-FAM-6. Reduced motion and RTL on large windows: S-1 at 1100x800 with `disableAnimations` has no animation; with `TextDirection.rtl` the rail sits on the right and the detail panel on the left, with no overflow (extends AC-A11Y-6 and AC-A11Y-7).

Retention copy (section 11 rule 7):
- AC-RET-1. S03 has NO screen that shows the retention choice (the consent centre does, OD-8), so what is testable in S03 is only: (a) a text search of the S03 ARB additions (the keys added by this sprint, listed in the sprint's change record) finds no "never keep", "forever", "indefinitely" or "never" in a retention sentence; (b) if any S03 widget, fixture or constant names a retention value, a static check asserts its allowed set is exactly {90, 365, 730} and the default is 730; (c) the S-8 Sources screen contains no retention text. A UI test of the retention control itself belongs to the consent-centre sprint.

Test seams the build must provide (contract items, not code): window-size injection (`windowSizeClass` provider overridable, plus the real `tester.view` size); keys `shell.bottomBar`, `shell.rail`, `shell.rail.record`, `shell.back`, `modeDetailIdle` text, a `TextPainter`-measurable nav-label style, `home.pane.main`, `home.pane.side`, `modeChooser.grid`, `modeChooser.detailPanel`, `modeSwitcher.popover`, `recordSheet.popover`, `signOut.warningSheet`; an injectable `TargetPlatform`; an injectable text scale; keys listed per screen; `home.section.<name>` keys on existing Home children; an injectable clock for week/today; an injectable journal availability; injectable timer providers (already providers); an in-memory settings store for `selectedMode` and `chooserStatus`.

Real-device checks (focus ring visibility, TalkBack reading order, actual contrast over photographs) are NOT_RUN by the test agents and go to the independent a11y review.

## 15. Open operator decisions

Each states the decision in words, the default, and what each answer does. Owner is the operator unless noted.

ANSWERED by the operator on 2026-10-16 (kept for the record, no longer open):

- OD-1 (question U-1: replace the Scan tab with a Record tab, or keep five tabs?). ANSWERED 2026-10-16: keep five tabs, Record is a button over the screen (a pill above the bar, or the Record slot of the side rail). Section 5.
- OD-2 (question U-2: tablet and large layouts now or later?). ANSWERED 2026-10-16: NOW, for Android phone, iPhone, iPad, Android tablet and MacBook. Section 10. Consequence for effort: S03 grows by the window-size provider, the rail, large-screen Home, Progress, Sources and chooser, and pointer and keyboard support; the effort estimate is UNKNOWN and belongs to the sprint planner.
- OD-9 (question: does the on-device activity history open in the default build?). ANSWERED 2026-10-16: yes, always, whatever the cloud flag says; story S03-0 stays in scope. Section 4.4.
- Retention (S02 question: which expiry values for cloud GPS history?). ANSWERED 2026-10-16: 90, 365 or 730 days; default 730 days (2 years); "never" is not offered. Section 11 rule 7. Privacy wording status (updated after the review of revision 3, reported by the lead agent, not re-verified by this author): the retention text was DONE in the revision of 2026-10-16: the wording moved to `scripts/legal/legal_text.py` and "or never" was removed from the page and from the ARB key `legalPrivacyBody` (`app_en.arb`, `app_ru.arb`). Remaining: the Russian S02 paragraphs are still missing, and the whole privacy wording is still a DRAFT pending the operator's approval (OD-11). This document does not edit that text.
- One app (answer 1). ANSWERED 2026-10-16: Phase 2 is an update of the same app with one application id (F26), not a second app.

OD-3 (decision D-9). Are any modes or features paid or gated? Default: no paywall, no lock icons. Any gating needs a locked card state and an upsell path, neither designed here.

OD-4. What happens when a user taps a mode that is not built yet? Recommended: "Coming later" sheet, mode unchanged, nothing collected. Alternative A: allow selecting it (the lens then has nothing to show; looks broken). Alternative B: a "tell me when ready" option (needs a notification consent and storage; privacy-relevant, not designed).

OD-5. (Changed.) How do gym (strength) workouts show on the new dashboard, which reads only the activity store? Recommended: the "All activity" block shows only recorded activity and is not shown at all until a first recorded session exists. A Phase 1 user with five gym workouts sees nothing new on Progress except one quiet "Sources" row whose hint reads "Walks, runs and rides you record will appear on Progress." They never see "No recorded activity yet" above their real gym data, but also never see their gym work inside "This week" until a later sprint bridges the stores. Alternative: add a read-only Gym tile fed by the existing workout readers (needs a verified duration/count reader, UNGROUNDED; extra S03 scope). Alternative: copy gym workouts into the activity store (rejected by S02 3.6 unless reopened).

OD-6. (Changed.) Where does the first-run chooser sit for a brand-new account, and who is spared it? Recommended: after the existing onboarding, shown from Home while a persisted "chooser status" is "pending"; the status is set to "pending" at the end of onboarding only if it was never set, and existing users are marked "migrated" at app start and see only a one-time intro card, never the forced chooser. Consequence: a new user who taps "Decide later" is marked "resolved" and sees no intro card; an upgrader is never forced; a user killed mid-chooser sees it again next start. Alternative: choose before onboarding (first screen "What do you want to do?", feels faster for the 3-minute goal, but changes onboarding and its redirect rules and picks a mode before the app knows the user). Note: the status is stored per device, not per account (DQ-2).

OD-7. (Changed.) A running gym workout lives on its own pushed page (`/workout/:id`), outside the shell. Is it acceptable that the Recording strip is not shown on that page and on other pushed pages (equipment, exercise, settings, body scan, nutrition) in S03? What it means in plain words: while a set or rest timer runs, a user who is on the workout page sees no strip and no mode chip; they have to go Back to a tab, where the strip then shows on all five tabs and returns them to the workout with one tap. Recommended: accept for S03 (the only session is a gym workout with its own screen); the persistent indicator for background GPS is designed in S04-D. Alternative: an app-wide overlay so the strip shows on every page (touches all 50 routes and every page's bottom edge; higher regression risk, not designed).

OD-8. Scope of the consent centre and the sign-out warning. S02 assigned the consent centre UI to S03 and left the sign-out warning UI to a UI story, but the S03 roadmap row lists only EP-1..EP-4. Recommended: S03 builds the Sources panel and, if agreed, the sign-out sheet (J10); the full consent centre becomes its own design sprint before S04. If neither is built, the S02 sign-out hooks stay unused and signing out has no warning for data held only on the device.

Still-open decisions (the operator decides; each states what changes). New items carry the next free numbers; OD-3 to OD-8 above are unchanged in meaning.

- OD-10. First-release region: in which countries or stores does the first Phase 2 release ship? The operator decides the list; a narrower list (for example one region) reduces the languages, legal pages and store listings to prepare and the privacy review scope, a wider list adds them. The design does not depend on it except Russian-first copy (section 13). UNGROUNDED: the roadmap wording of this decision was not re-read for this revision.
- OD-11. Privacy wording approval: who approves the changed privacy page text (retention 90/365/730 days, no "never") and when. Approving lets the generator source be changed and the pages regenerated; until then the in-app page and the contract disagree about "never".
- OD-3 (monetisation per mode, roadmap decision D-9) is STILL OPEN and is listed once, above in this section; its default stands: all new modes behind flags and no new paywall.
- OD-13. Fate of the master branch name: whether the repository's main branch keeps its current name or is renamed. It changes nothing in the UI; it decides branch and release-note wording and tooling paths. (Mapped from the coordinator's list; the roadmap register code for it was not re-read: UNGROUNDED.)
- OD-14. Legal status of the third-party dossier: whether the third-party material gathered for Phase 2 may be used or quoted. If yes, the sources and the Sources-panel wording can reference it; if no, S03 copy refers to no third-party source. S03 copy as written makes no such reference. (Mapped from the coordinator's list; register code not re-read: UNGROUNDED.)
- OD-12. When Apple build targets are created: iOS, iPadOS and macOS targets do NOT exist (F26) and are NOT created in S03. The operator decides when (never in Phase 2, with S03, or in a later sprint) and whether store accounts and signing are arranged. Earlier means the Apple criteria of 10.8, 10.9 and AC-FAM become runnable on simulators and devices and need a Mac for building; later means they stay widget tests with a faked platform. The layouts need no redesign either way. Nothing is promised about Apple stores, accounts or signing.

Items below are product-ux or architecture questions (owner given), listed so none is decided silently:
- DQ-1 CLOSED by 4.2 (single `chooserStatus` field, migration at start, `pending` written at onboarding finish, chooser shown from Home).
- DQ-2 (architect): store `selectedMode`/`chooserStatus` in `AppSettings`/preferences or the profile; per-device vs per-account behaviour on account switch.
- DQ-3 (a11y-architect): adopt 48 dp for new controls with 44 dp as the HUD exception; assumed yes.
- DQ-4 (product-ux): metric only, no units setting in S03; assumed.
- DQ-5 (product-ux): "See all" history and "How this is calculated" deferred to S05/S15; assumed.
- DQ-6 (product-ux): at most 3 questions per mode in S03 (direction said 3-5); assumed.
- DQ-7 (product-ux): where a skipped mode question can be revisited (Profile or Settings row); not specified.
- DQ-8 (architect): deferred routing of a notification tap through sign-in/onboarding redirects; assumed dropped.
- DQ-9 (product-ux): photos on cards wait for U-3 (default: licensed photography only, none exists); lime corner wedges (U-5) not used in app UI.
- DQ-10 (architect): align the "week" rule of S-7b (Monday, device zone) with the existing Home week section.
- DQ-11 (architect): confirm that `ActiveSessionStatus` can be built from `setTimerProvider`, `restTimerProvider` plus the new destination provider with no other app-level workout flag.
- DQ-12 (architect): does S03 include the shared frame that caps the width of pushed pages it does not redesign (10.5), or are they left stretched on wide windows? Assumed: the frame is included for non-camera pages.
- DQ-13 (product-ux): do Apple builds keep the bundled fonts (assumed) or switch to the system font? Decide before the Apple targets are built.
- DQ-14 (architect): rail-form switch at text scale 1.3 and window 1200 dp, rail-over-landscape-phone rule (width 600+ and height under 480), and the Mac minimum window 480 x 600 are PROPOSED values; confirm or change.
- DQ-16 (operator, assumptions added after the review of revision 3): (a) the rail shows an enabled Record button on all five tabs, including Scan and Profile, where the bar shows no pill (chosen to keep the rail from jumping); the alternative is a disabled slot with a reason, which wastes the slot; (b) Esc never means Back; (c) two-pane layouts need a content pane of at least 880 dp, so a 1100 dp window with large text shows one column; (d) rail form switches by measured label width, not by a fixed scale; (e) compact-rail running state shows a short state word and minutes, not the extended form.
- DQ-15 (a11y-architect and product-ux): the keyboard shortcut set of 10.9 (Cmd/Ctrl+1-5, +Shift+M, +Shift+R, +[) is PROPOSED; confirm no conflict with system or screen-reader shortcuts.

## 16. Known limits of the current app (not fixed by S03)
- Existing HUD controls show no focus indicator; legacy-scaffold pages remain; raw exception text still appears on Home, Settings, Login and Onboarding errors; Progress cannot tell loading from empty for its existing blocks; the router's page transition ignores reduced motion (only the new routes are patched, section 12).
- No global offline indicator; none added.
- Gym timers do not survive process death.
- The set timer and rest timer are global, not keyed by exercise: opening another exercise's page while one runs shows the same timer (existing behaviour).
- The nav bar's one-line labels truncate at large text and in Russian (existing).
- No chart-to-table alternative exists; none is added.
- (Revision 3.) About 45 pushed pages are not redesigned for large windows (10.5); at best they get the width-cap frame (DQ-12). Full-bleed camera pages (scanner, form coach, body-scan capture) on tablets and Mac windows were never run (UNGROUNDED).
- Existing HUD controls draw no focus ring (F30), so keyboard users on Mac, iPad and Android tablets see none on legacy controls; only the new S03 controls do.
- Apple targets do not exist; every Apple criterion is a widget test with a faked platform, not a device observation.

## 17. What could not be grounded in the repository
1. (CLOSED for onboarding finish: F24.) Still open: whether `/onboarding/edit` is the only second entry into the same finish code.
2. Whether `scan_frame.dart` draws corner brackets; the chooser avoids brackets.
3. The existing Home week rule and whether a reader exposes gym workout duration and count (OD-5 alternative, DQ-10).
4. The journal has no change stream; the dashboard's refresh after `put`/`delete` is an architect question.
5. How the dock height reaches `shellBottomObstruction` and `HudScreenBody` (`reserveNavBar`) without double padding.
6. The notification payload-to-route mapping and where the tap callback is registered.
7. Real Russian strings and widths: the budgets of section 13 are proposals, to be measured in the translation pass.
8. Contrast of panels over photographs (never measured).
9. Whether any licensed photography or mode artwork exists (none found in the files read).
10. The backend state of the cloud flag path; section 8.5 wording is designed without a running backend.
11. Behaviour at 200 percent text on any existing screen was never run.
12. Whether `GlassAppBar` accepts actions (irrelevant now: Progress has no chip).
13. Whether another app-level "workout in progress" flag exists beyond the two timers (DQ-11).
14. (Revision 3.) The window-size breakpoints (600 and 840 dp) follow Material 3 large-screen guidance that is not in the repository; typical device window sizes in 10.2 are from general knowledge, not repository facts.
15. Apple specifics: Stage Manager and Split View minimum widths, Dynamic Type maximum scale, macOS traffic-light overlap, iPad multitasking declaration, macOS minimum window size and menu bar API behaviour. No Apple target exists to check them.
16. Whether the manifest allows free resizing on Android 16 and later (no `resizeableActivity` attribute, `targetSdk` 36), and whether the app overrides scroll physics.
17. Hover and press tokens: the exact accent-wash value and where it lives (10.9).
18. How the shell publishes bottom clearance and start inset to `HudScreenBody` and the Progress list for the rail (10.4), extending item 5.
19. CLOSED (review of revision 3): the Russian navigation labels are Главная, Тренировки, Скан, Прогресс, Профиль (longest 10 characters, from `app_ru.arb` as reported by the lead agent). Still unmeasured: their pixel widths in the rail, covered by AC-WS-3.
20. How the wallpaper crops on wide windows, and how pushed pages and camera pages look on wide windows (10.1 WS-5, 10.5).
21. Whether HUD pages show a visible Back control (needed on Mac and iPad, 10.8); not read.
22. CLOSED (review of revision 3): the privacy wording moved to `scripts/legal/legal_text.py` and "or never" was removed (lead agent's report, section 15); still open: the missing Russian S02 paragraphs and operator approval (OD-11). The phrase had been added only to the hand-edited public page (the generator source and the ARB files did not contain the S02 wording), which is why a search of `app_en.arb` found nothing; commit 849abd5e ported the wording into its real source and removed it.
23. The roadmap register entries behind OD-10, OD-13 and OD-14 were not re-read; their descriptions come from the coordinator's message.

## 18. Review handoff
- product-ux-reviewer: re-check section 10 (window-size model, rail, per-class Home, Progress, Sources, chooser), J1-J10 (J10 no longer conditional), S-4 with the rail Record slot, S-9 merge into S-1, OD-5/6/7/8 wording, section 15 plain-words sentences.
- a11y-architect: sections 9.1 (hover, cursor, focus ring), 12 (large screens, pointer, keyboard, per family, reflow), 13 (rail and side pane budgets), 14 (AC-WS, AC-LS, AC-KB, AC-FAM, AC-A11Y-1..8), the shortcut set of 10.9.
- architect: DQ-2, DQ-10, DQ-11, DQ-12, DQ-14, S03-0 (journal always opens and the changed S02 statement), the nav configuration list (5.3) shared by bar and rail, `ShellLayout` and inset plumbing (10.4, 17.5, 17.18), manifest resizability (17.16), the primitive extensions (9.1).
- GPT-PM: whole contract after those reviews; the still-open decisions OD-3, OD-8, OD-10 to OD-14 go to the operator in plain Russian, not decided here.
- Build gate: S03 starts when this contract is approved. U-1, U-2 and OD-9 are answered and no longer gate it; OD-12 (Apple targets) does not gate S03.

## 19. Review disposition (revisions 2 and 3)

### Changed sections in revision 3 (for the reviewers)
Header and "Applied in revision 3" note; 2 (new facts F26-F30); 3 (principles 2 and 6); 4.4 (journal always opens); 5 (rewritten: five-tab shell is the contract, 5.3 build requirement); J10 and S-10 (no longer conditional); S-1 (pointer to the large-window layout), S-4 and S-5 (rail Record slot, presentation by class), S-8 (Apple Health row wording), S-9 (merged into S-1, new layouts and AC-CH-9 to 14); 9.1 and 9.2 (hover, cursor, focus ring; C-13 rail, C-14 window class, C-15 adaptive surface); 10 (rewritten: window-size model, rail, per-class Home, Progress, Sources, surfaces, platform families, Mac and pointer input); 11 (rule 7 retention); 12 (large screens, rail semantics, pointer, keyboard, per family, reflow); 13 (rail and side-pane budgets); 14 (AC-WS, AC-LS, AC-KB, AC-FAM, AC-RET, test seams; AC-PR-1 and AC-SRC-2 wording); 15 (answered items, new open items OD-10 to OD-14, DQ-12 to DQ-15); 16, 17, 18 (extended); 19 (this table).

### Revision 3 disposition

| # | Change | Operator answer | Why |
|---|---|---|---|
| R3-1 | Header, "Applied in revision 3" note, status "not approved", F26 (one application id) | 1 (one app) and all | The text assumed no second app; the single id `com.fitnessapp.fitness_app.sptr` is the fact (F26). No wording of the document assumed two apps, so nothing else was removed |
| R3-2 | Section 5 rewritten as the five-tab contract; Option B dropped with a two-line rejected note; "Option B delta" lines and the recommendation framing removed; 5.3 one configuration list for bar and rail | 2 (U-1 answered: five tabs) | U-1 is decided; the document must not present it as open |
| R3-3 | Section 10 rewritten as the window-size model: Compact under 600 dp, Medium 600 to 839, Expanded 840 and up, plus a "short" rule (height under 480) that moves a landscape phone of 600 dp or more to the rail; live-resize rules WS-1 to WS-5; situation table for phone, foldable, tablet, split-screen, Stage Manager, Mac | 3 (U-2 answered: large layouts now) | Width of the window, not device type, makes split-screen, Stage Manager, Mac windows and foldables work with one rule |
| R3-4 | S-1 and S-9 merged into one responsive chooser; criteria AC-CH-9 to AC-CH-14 | 3 | S-9 was a design-only drawing; it now has acceptance criteria per size class |
| R3-5 | Side rail (10.4, C-13) replaces the bottom bar and dock on Expanded and on short Medium windows; Record slot; swap rules; rail forms (96 dp or 240 dp) | 3 | Dock space is wasted on wide or short windows; rail form switches avoid truncating long Russian labels |
| R3-6 | Home, Progress, Sources layouts for Medium and Expanded (10.5) with all states kept; sheets, dialogs and popovers by class (10.6) | 3 | Columns, max widths and side panes requested; nothing removed from Compact content |
| R3-7 | Platform families (10.8): identical versus adaptive per family; Apple conventions for back, sheets, safe areas, text scale, haptics; fonts stay bundled | 3 and 4 | Requested per-family conventions; the theme bundles fonts so system fonts are not assumed (DQ-13) |
| R3-8 | Pointer, keyboard, trackpad, Mac window, shortcuts and menu bar (10.9); hover, cursor and focus ring primitive extensions; no gesture-only path | 3 | Requested Mac and tablet input support; the repository has no hover, cursor, shortcut or focus-ring code (F28, F30) |
| R3-9 | Apple builds stated as design only: no iOS, iPadOS or macOS target in S03 (F26); OD-12 open; Apple criteria are widget tests with a faked platform; no store, account or signing promise | 4 | The repository has only an `android` platform folder |
| R3-10 | Section 4.4, principle 6, J10, S-10, AC-PR-1, AC-SRC-2: journal always opens; `notEnabled` kept only as a test and override state; J10 and S-10 no longer labelled conditional | 5 (OD-9 answered) | S03-0 is in scope. J10's condition was actually OD-8 (who builds the sign-out hooks), so OD-8 stays open and S-10 is ASSUMED built in S03 |
| R3-11 | Retention rule 7 in section 11, AC-RET-1, section 15 note about the privacy wording generator (`scripts/legal/build_legal.py`, ARB key `legalPrivacyBody`) | 6 | 90, 365 or 730 days, default 730, no "never"; the privacy page change is outside this document |
| R3-12 | Sections 12, 13, 14: large-screen, pointer, keyboard, rail and per-family criteria and budgets; test seams | 3 | Each new criterion is a widget test with a set window size and text scale |
| R3-13 | Section 15: U-1, U-2, OD-9, retention and one-app marked ANSWERED 2026-10-16; open items OD-3, OD-10 to OD-14 each with a plain-words consequence; DQ-12 to DQ-15 added | 1 to 6 | Answered items leave the open list; still-open decisions stay visible |
| R3-14 | Sections 16, 17, 18 updated | 3 and 4 | New known limits and ungrounded items; reviewer handoff re-aimed at the delta |

### Revision 2 disposition

All cited facts were re-read in the repository before editing; every finding is factually correct. None is rejected. Where a finding was partly adopted differently, the row says so.

| Finding | Verdict | Section(s) changed |
|---|---|---|
| U1 BLOCKER journal null with flag off | Accepted (verified `activity_wiring.dart` 1-5, 32, 49, 65) | F14 corrected; principle 6; 4.4 (three availabilities, scope item S03-0); S-6, S-7, S-8 states; AC-PR-1/2, AC-SRC-2/3, AC-REG-3; OD-9 new |
| U2 chooser/intro contradiction | Accepted (verified `onboarding_page.dart` 192, `app_router.dart` 150-152; also found `/onboarding/edit` shares the finish code) | 4.2 (single `chooserStatus` with transition table), J1, J4, S-1 AC-CH-4/5/8, S-6 AC-HM-4, OD-6, DQ-1 closed, 17.1 |
| U3 running session undefined | Accepted (verified `set_timer_providers.dart`, `rest_timer_providers.dart`; neither carries an exercise id) | F23, S-4 "running" table and destination provider, J2 leave-and-return, OD-7, AC-ST-2..5, DQ-11 |
| U4 Progress placement | Accepted (verified `progress_page.dart` 43-75). Adopted differently: the mode chip is REMOVED from Progress instead of placed in the app bar | F13, S-7 exact placement and padding, 5.1, S-4 padding |
| U5 empty block above gym data | Accepted | I1, S-7a/S-7b demotion rule, OD-5 |
| U6 untestable criteria | Accepted | Keys per screen; all AC rewritten (AC-CH-5/8, AC-HM-1/4, AC-PR-6/7, AC-SH-6, AC-A11Y-*); section 14 test seams; week rule fixed as Monday/device zone (OPEN-1, DQ-10) |
| U7 strip on Scan/Profile | Accepted (strip on all five tabs) | 5.1, S-4, AC-ST-1/2, OD-1, OD-7 |
| U8 Day-3 modal stacking | Accepted (verified `home_page.dart` 93-108) | J4, S-6 intro rule, AC-HM-4 |
| U9 missing source kinds | Accepted (verified `source_kind.dart`) | 8.1, AC-SRC-6 |
| U10 48 dp on 44 dp primitives | Accepted (verified `hud_surface.dart` 728, 848) | 9.1, C-2/C-8, AC-A11Y-1 |
| A1 HUD semantics cannot express contract | Accepted (verified `hud_metric.dart` 734-737, `hud_surface.dart` 445-449, 836-856) | 9.1 (extend vs wrap), 9.2, 12, AC-A11Y-1 |
| A2 Russian default and budgets | Accepted (verified `app_settings.dart` 9) | 13 (select/plural, per-key budgets, mechanism), F20, S-1 copy |
| A3 criteria coverage | Accepted | 14 (AC-A11Y-1..8) |
| A4 chips truncate | Accepted | 9.1, C-2, C-11, 10, AC-A11Y-5 |
| A5 looping indicator and route transition | Accepted | 12 reduced motion, S-1/S-2/S-7 loading, AC-A11Y-6 |
| A6 strip label cadence, announce | Accepted (precedent `SemanticsService.announce` verified) | S-4, 12, AC-A11Y-4 |
| A7 description live region | Accepted | S-1 layout, 12 |
| A8 coming-later enabled, contrast floor | Accepted | C-1, S-1 states, 12 contrast |
| A9 greeting wrap, dock in landscape, light-theme nav exception | Accepted | S-6 change 1, S-4 compaction, 12 contrast, 10 |
| A10 RTL | Accepted | 10, AC-A11Y-7 |

### Revision 3 review disposition

Sources: UX = product-ux-reviewer (4 MAJOR, 6 MINOR); A11Y = a11y-architect (3 MAJOR, 6 MINOR). Both converge on items 1 to 3. All twelve items were applied; none rejected.

| # | Finding (source, severity) | How fixed |
|---|---|---|
| 1 | Rail overflows a 360 dp high landscape window (UX and A11Y, MAJOR) | 10.4: pinned Record slot, scrollable destinations list, 48 dp items under 480 dp height, focus scrolled into view; AC-WS-10 |
| 2 | Two-pane arithmetic wrong; no narrow-pane fallback (UX and A11Y, MAJOR) | 10.1 arithmetic corrected; 10.5 two-pane rule from content pane width with minimums (880 dp; chooser 840 dp), worked examples, tile-column rule (160 dp minimum); AC-LS-4 rewritten, AC-LS-9 |
| 3 | S-5 contradicts 10.6; two "short" thresholds (UX MAJOR, A11Y minor) | S-5 paragraph replaced by a pointer to 10.6, form by size class only; S-3 text aligned; Day-3 aligned; one threshold (480 dp) in S-1 and 10.7 |
| 4 | Rail Record slot appears and vanishes per tab (UX M1) | 10.4 reserved slot on all five tabs; S-4 visibility by presentation; anchor and Mac menu rules in 10.6; AC-WS-7 rewritten, AC-WS-12 |
| 5 | Compact rail hides running state; icon-only Record (UX M2, A11Y m2) | 10.4 two-line state word and minutes, visible "Record" label, tooltip rule (WCAG 1.4.13); AC-WS-13 |
| 6 | Scroll position promise too strong (UX M4) | WS-3 weakened to a keyed first-visible-section anchor; AC-LS-10 |
| 7 | Chooser idle state undefined (UX m3) | S-9: `modeDetailIdle` text, Continue disabled, no illustration slot, touch tap updates the panel; AC-LS-11 |
| 8 | Back, Esc, keyboard gaps (UX m5, A11Y m5) | Esc precedence and Esc-as-Back dropped (10.8, 10.9); Home/End only inside the rail; tab re-select scroll-to-top; visible Back on Mac pushed pages (AC-KB-8); AC-KB-1 extended; shortcut conflict check recorded as UNGROUNDED |
| 9 | Housekeeping (UX m6, A11Y m3) | OD-3 listed once; privacy wording status reworded as done/draft; AC-RET-1 made testable for what S03 contains; Russian labels closed from `app_ru.arb`; AC-WS-3 measured with `TextPainter` at 1.0, 1.15, 1.29 |
| 10 | Rail semantics unnamed (A11Y m1) | 10.4 container `Semantics` labelled "Main navigation", `selected` flag, position hint loss accepted; AC-A11Y-1 extended; AC-WS-11 |
| 11 | Contrast of rail ink (A11Y m4) | 10.4 text-secondary tier or recorded 4.40 exception, dot 3:1; AC-KB-9 token-level test |
| 12 | Reduced motion for new routes (A11Y m6) | 10.4 and section 12: no-transition or opacity-only for every new sheet, dialog, popover; AC-WS-14 includes the open-surface resize test |

Not fixed: nothing. Unverified and left UNGROUNDED: the shortcut set against macOS, iPadOS and VoiceOver defaults; whether HUD pages already have a visible Back control; the Russian pixel widths in the rail (measured by AC-WS-3 in the build).
