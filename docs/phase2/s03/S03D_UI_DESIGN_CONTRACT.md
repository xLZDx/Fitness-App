# S03-D UI design contract: shell, mode chooser, dashboard skeleton

Status: DRAFT revision 2 for GPT-PM review, after product-ux-reviewer (findings U1-U10) and a11y-architect (findings A1-A10). Not approved. Date: 2026-10-16. Authoring role: ui-designer. Worktree read: branch `phase2/s02-unified-activity` (S02 is in test and review while this is written). No code is changed by this document. The review record is the table in section 19.

**Operator answers of 2026-10-16 (recorded after the S02 merge; this revision 2 text predates them and revision 3 must apply them):** U-1: keep five tabs, Record is a button over the screen (the contract default; Option B is dropped). U-2: tablet and large layouts NOW, and the design must cover Android phone, iPhone, iPad, Android tablet and MacBook (not tablets only); S-9 stops being a drawing and needs acceptance criteria, a responsive chooser, a side rail and a large-screen Progress, plus platform conventions per family (Material on Android, Apple conventions on iPhone, iPad and Mac) and pointer and keyboard input for the MacBook. OD-9: the local journal opens in the default build regardless of the cloud flag (story S03-0 stays in scope). Retention (S02): "never" is not offered, the default expiry is 2 years. One app: Phase 2 ships as an update of the same app, not as a second app. Not decided: whether iOS, iPadOS and macOS builds are created in S03 or later (the repository has only an `android` platform folder today).

Purpose: a contract that the S03 build sprint (EP-1 mode state, EP-2 mode chooser and per-mode first-run questions, EP-3 Today / This week / Progress from `ActivitySession`, EP-4 sources panel) implements exactly, and that the S03 test agents can turn into functional tests. It resolves the design side of open questions U-1 (replace the Scan tab or not) and U-2 (tablet now or later); the decisions themselves belong to the operator and are listed in section 15.

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

INFERENCE I1 (revised): `strength` lives in the other store (F16) and no recorder exists (F18), so the `ActivitySession` list is EMPTY for almost every real user during the whole of R2 alpha until S05. The first thing a Phase 1 user must NOT see is a "no activity" message above their real gym history (finding U5); the dashboard block is therefore demoted while empty (S-7).

INFERENCE I2: nothing mounted in `MainShell` is visible on pushed routes, including the workout player itself (F5).

## 3. Design principles for this contract

1. Reuse, do not invent. Every new surface is built from the HUD primitives of F8 on the live `HudTokens` layer, extended only as stated in section 9.1. No new blur radius, colour, or type family.
2. Existing flows do not move. The five tab paths and order (under the recommended option), the Back behaviour (F3), the gym QR flow, and the form coach are untouched (goal G-5).
3. Mode is a lens, not a different app. A mode changes the first cards on Home, the target of the Record action and the sort order of discipline tiles. It never removes global content and never starts, stops, or resets anything.
4. Missing is shown as missing. No zero for unknown, no estimate without a marker, no sum of energy across sports.
5. Nothing asks for a permission at launch or in the chooser. Location is not requested anywhere in S03.
6. (Rewritten, finding U1.) Local first WHEN the local journal exists. In the default build the journal does not exist today (F14). This contract therefore carries an explicit scope item (OD-9, story S03-0, section 4.4): open the local journal independent of the cloud flag. Every dashboard surface distinguishes three journal availabilities (open, not enabled, failed to open) and never offers "Try again" for "not enabled". Cloud wording appears only when `ACTIVITY_CLOUD_STREAMS` is on.
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
R-M2. Changing mode never changes the route or `selectedIndex` of the current tab (both U-1 options; Option B's mode tab excepted, 5.3).
R-M3. Mode change takes effect immediately on visible content and is announced (section 12).
R-M4. A notification tap, deep link or "resume" never changes the selected mode.

### 4.4 Journal availability (finding U1; a scope item)

The dashboard (S-6, S-7, S-8) reads the journal through ONE availability value with three cases, a contract input the S03 build must provide:

| Availability | Meaning | UI rule |
|---|---|---|
| `open` | Journal opened and recovered | Normal states (loading, empty, data) |
| `notEnabled` | No journal was opened because the build does not enable it (today's default) | No error, no retry, no "Problem" chip. Dashboard block hidden; Sources shows the plain line "Activity history is not active in this build." |
| `failedToOpen` | Opening or recovery threw | Error panel with "Try again" that reopens ONCE (disabled while busy); no loop |

Recommended scope item (S03-0, needs architect and operator confirmation, OD-9): open and recover the local journal at app start regardless of `ACTIVITY_CLOUD_STREAMS`, while every cloud piece (sync repository, uploader, tombstone push, conflict card) stays behind the flag. Effect: the default build can show the real empty state and a recorded session as soon as a recorder exists; without it, in the default build the new dashboard never shows anything and cannot be tested without overrides. It changes the S02 statement that with the flag off "no journal is opened" (activity_wiring.dart header), so it is not made silently here. If OD-9 is answered "no", availability is `notEnabled` in the default build, and every journey/acceptance criterion marked [flag off] below holds with that value.

## 5. Shell options for U-1

Context: F1 (no header), F2/F4 (five tabs, one-line labels), F5 (pushed routes hide shell chrome), F6 (Scan is the gym QR recognition), F18 (nothing to record outside the gym until S04).

### 5.1 Option A (recommended and roadmap default): keep five tabs, Record is a shell action

Tabs unchanged: Home, Workouts, Scan, Progress, Profile; same labels, order, icons, paths. New in the shell:
1. A "dock" slot directly above the nav bar (S-4). When idle it shows a compact Record pill on Home, Workouts and Progress. While a session runs the same slot shows the Recording strip on ALL FIVE tabs (finding U7: a running workout is visible everywhere in the shell; the pill stays only where starting something makes sense).
2. A mode chip on Home only (greeting row). Progress is always the whole picture, so it has no chip (finding U4: Progress has no HUD title row, F13).
3. The Workouts tab stays "Workouts" in every mode.

Plain-words consequences:
- Nothing a Phase 1 user already uses moves. The gym QR scan stays one tap. Lowest regression risk for G-5 and for tests that assume five fixed tabs.
- The bar has no Ride, Explore or Body entry; they are reached through the Home chip, the Record pill and cards, one extra tap compared with option B once RIDE exists.
- The Record pill is not in the centre of the bar, so it is less prominent than the film's centre action.
- Reversible: it can later become Option B (5.4).

### 5.2 Rejected within Option A: a mode-named label on the Workouts tab
It needs the tab label, icon and target page to change while the user stays on the tab (F2, F3), and no tab page exists for RIDE/EXPLORE in S03.

### 5.3 Option B: context-sensitive Record replaces Scan
Tabs: Home, Mode tab (label and icon Train/Ride/Explore/Body), Record (centre), Progress, Profile. The `/scan` tab entry is removed; equipment recognition moves under TRAIN (a Train-lens card and an entry in the Record sheet).

Plain-words consequences:
- The bar matches the film's mock, Record is always in the centre.
- The gym QR scan becomes two taps and leaves the bar; risk to G-5; tests that select the third tab by path or index are touched.
- Until S05/S06 the centre button acts only in Train and Body for the whole R2 alpha.
- Mode tab labels change with mode; Russian labels are longer and the bar is one-line ellipsis (F4), so truncation tests are needed.
- `_paths`, `_indexFor`, back-stack and deep links to `/scan` as a tab are touched.

### 5.4 Recommendation and the requirement that keeps both open
RECOMMEND Option A for S03; revisit B in S05-D/S06-D when Record can start a walk, run or ride. PROPOSED build requirement: nav items (icon, label, path, selected-index meaning) come from ONE configuration list read by `MainShell`, with a test that the default list equals today's five tabs. The decision is the operator's (OD-1). Option B deltas are listed in the screens as "Option B delta".

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

### J10. Sign-out with local activity (CONDITIONAL on OD-8)
If the operator assigns the S02 sign-out hooks to S03: signing out with a non-empty journal opens a sheet "You have {n} activities stored only on this device" with "Export first (GPX/FIT)", "Sign out and delete from this device" (destructive, second confirmation), "Cancel". An empty or unavailable journal signs out with no prompt. Account deletion needs no prompt.

## 7. Screens and their states

State vocabulary: LOADING, EMPTY (valid, nothing yet), PARTIAL (missing shown as missing), ERROR, OFFLINE, NOT-AVAILABLE, SUCCESS. Journal-dependent screens use the three availabilities of 4.4. A state that does not apply is stated as n/a with the reason.

Copy strings are English; Russian is authored in the S03 build under the per-key budgets of section 13. Key names are PROPOSED. Test keys (`Key('...')`) are listed per screen and are part of the contract.

### S-1. Mode chooser (full screen route outside the ShellRoute)

Purpose: pick the first mode, or change it. Reached from J1 (while `pending`), the intro card, and the switcher "See all modes".

Layout (phone): `HudScreenTitle` "What do you want to do?" + subtitle; 2x2 grid of Mode cards C-1 (order Train, Ride / Explore, Body; gap 12; gutter 16); under the grid a description area showing the focused/selected card's description (NOT a live region, finding A7; each card carries the same description as its semantic hint); footer: primary `HudButton` "Continue" (enabled only when an available mode is selected) and, while `chooserStatus` is `pending`, text button "Decide later".

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

Option B delta: none.

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

Purpose: switch in two taps from Home (chip). `HudSheet` in a modal bottom sheet, scroll-controlled, safe-area aware, one instance (opening twice is a no-op, same guard as `SyncConflictSheet`).

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
Option B delta: no pill (the centre tab opens S-5); the strip still occupies the dock slot.

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

Option B delta: same sheet from the centre tab; "Scan equipment" stays the first TRAIN row.

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
- AC-PR-1. [flag off] Default providers (journal `notEnabled`): Progress renders `progress.slot.sources`, does not contain `progress.allActivity`, `progress.journalError` or any text equal to an "empty" or "unavailable" string, and the existing blocks are present in the original order.
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

Rows (order): "Recorded in this app" (`app`), "Health Connect" (`health_connect`), "Apple Health" (`healthkit`, listed only on iOS builds; iOS is NOT_RUN under D-12 so not listed in S03), "Bluetooth sensors" (`ble_*`), "Watch" (`wear_os`), "Other services" (`vendor_cloud`). Each row: name, one-line purpose, status chip C-11, and "May provide ..." from `kCapabilityMatrix` for yes/partial levels, "Unknown" otherwise.

Status chip vocabulary (word + icon): "In use", "Ready", "Not connected", plus for S16 the `SourceHealth` map: ok "Connected", permissionMissing "Permission needed", unavailable "Unavailable on this device", stale "Out of date", error "Problem". In S03 no adapter exists, so `healthStatus()` is not called.

App row status by journal availability: `open` with sessions "In use"; `open` empty "Ready"; `notEnabled` "Not active" with the line "Activity history is not active in this build." (no chip colour change, no retry); `failedToOpen` "Problem" with `activityJournalFailed` and "Try again" (once).

Information block: `sourcesDedupNote` "If the same workout comes from two sources, we do not yet merge them automatically." Copy: `sourcesTitle` "Sources"; `sourcesIntro` "Your activity can come from this app, your phone or your devices."; `sourceApp`, `sourceHealthConnect`, `sourceBle`, `sourceWatch`, `sourceOther` as above; status keys `sourceStatus*`; `sourceStatusNotActive` "Not active".

States: LOADING (journal being read: app chip text "Checking" for at most 1 s, plain text); EMPTY n/a (rows are static); PARTIAL n/a; ERROR/NOT-AVAILABLE as above; OFFLINE n/a. Per-source consent and delete controls are the consent-centre scope (OD-8); only an optional link to the existing Health sync card is allowed. No new deletion path.

Keys: `sources.row.<id>`, `sources.dedupNote`, `sources.app.retry`.

Acceptance criteria:
- AC-SRC-1. Journal `open` empty -> `sources.row.app` semantics contains "Ready"; after one fake session -> "In use".
- AC-SRC-2. [flag off] `notEnabled`: the app row contains the not-active line, has no `sources.app.retry`, and no "Problem" text exists on the screen.
- AC-SRC-3. `failedToOpen`: "Problem" + `sources.app.retry`; retry calls the opener once.
- AC-SRC-4. Every non-app row's semantics contains "Not connected" and has no tap action (the optional health-sync link excepted).
- AC-SRC-5. `sources.dedupNote` exists; a text search of all S03 ARB additions finds none of "merged", "deduplicated" or "synced with Health Connect".
- AC-SRC-6. A provenance record with an unknown `sourceId` and each of the five `SourceKind` values renders the label of section 8.1 and never an empty label.
- AC-SRC-7. Each row is one semantics node whose label includes name and status.

### S-9. Tablet mode chooser (design-only, NOT built while U-2 is OPEN)
Breakpoint proposal: shortest side at least 600 dp (INFERENCE; no breakpoints exist, F7). Four cards in one row (a carousel under 900 dp wide) centred in a max width of 960; the description area becomes a right-hand detail panel; Continue bottom end. The film's focus bracket is optional (UI-M). A side rail instead of the floating bar is not decided (U-2). No acceptance criteria in S03; if U-2 is answered "now", add them in a revision.

### S-10. Sign-out warning sheet
Conditional on OD-8 (J10). Not an S03 acceptance item unless assigned.

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

## 10. Responsive behaviour

| Width / condition | Behaviour |
|---|---|
| Phone 320-411 dp (primary) | As specified. Mode cards 2x2, at least 140 dp wide at 320 dp; below 150 dp the blurb is dropped from the card face and stays in the hint/description. |
| Phone landscape / height under 480 dp | No orientation lock exists. Chooser grid becomes 4x1 under 420 dp height; sheets scroll; dock compaction per S-4. Requirement: no overflow. |
| Text scale 2.0 | Cards grow vertically, grid stays 2 columns, blurb wraps to 3 lines then ellipsises (the description area is never truncated); the chooser scrolls. Chips (C-2, C-11) wrap to two lines; chip text is never truncated at 2.0 in Russian or English. The dock strip is two lines (title above time). The nav bar behaviour is unchanged (F4, existing limitation). |
| Tablet / large (S-9, design-only) | Not built. |
| Keyboard open | No text input in these screens. |
| RTL (finding A10) | No RTL locale ships (F20). New code uses start/end (`EdgeInsetsDirectional`, `AlignmentDirectional`), mirrored chevrons via `Directionality`; one widget test pumps S-1 and S-4 with `TextDirection.rtl` and expects no overflow. |

## 11. Data honesty and copy rules
1. Unknown is "No data"; zero only when the source reports zero.
2. Estimates carry "Estimate"; no range is invented in S03.
3. No cross-sport energy; no cross-group total of sessions or time in S03.
4. Sync/cloud words appear only with `ACTIVITY_CLOUD_STREAMS` on.
5. Never say "merged", "deduplicated" or "synced with Health Connect".
6. No body-shaming, medical claim or streak pressure; BODY copy reuses existing strings.
7. Errors are plain sentences with a next step, never exception text; tone models: `errorServiceUnavailable`, `foodDiaryError` + `foodDiaryErrorBody`. "Not available" states are neutral statements, not errors, and never offer a retry that cannot succeed.

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
| Reduced motion | Uses `context.hudMotionDuration`; no looping animation anywhere in S03 and no indeterminate progress indicator (finding A5): loading states are static (outlines, text "Checking"/"Saving"). New full-screen routes (S-1, S-8) are built with a page builder that returns a no-transition page when `disableAnimations` is true, because the router's `_fadeThrough` ignores reduced motion (audit section 8). |
| Text scale | Layouts hold at 2.0 (section 10). Russian is the default locale (F20) so every check below runs in `ru` first. |
| Keyboard | Controls activate with Enter/Space; cards reachable by Tab/arrow; Esc closes sheets. |
| Charts | None introduced; no table alternative needed until S15. |

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
| Nav labels | unchanged (Option A) | existing one-line ellipsis |

- Verification mechanism: a test runs each new screen in `ru` at scale 2.0 and, for each contract key listed in section 7, asserts `RenderParagraph.didExceedMaxLines == false` for status chip words, chip text, button labels and headers; where the budget allows ellipsis (blurb) it asserts the first 24 characters are visible. A pseudo-locale run (every string length x1.6 with accents) is added for keys whose Russian value is not yet authored.
- Number, date, duration formatting through `intl` with the resolved locale (`AppLanguage.resolvedLocaleCode`). Units are metric only in S03; no units setting exists (F20, DQ-4); strings carry no hard-coded "km".
- Mode names are stable product vocabulary; the Russian equivalents are decided in the translation pass and recorded in the ARB.

## 14. Acceptance summary, cross-cutting criteria and test seams

Per-screen criteria are in section 7. Cross-cutting criteria (all observable in widget tests; a test never depends on a real OS dialog):

- AC-SH-1 (Option A). The shell nav configuration list has exactly five entries with paths `/home`, `/workouts`, `/scan`, `/progress`, `/profile` in that order and labels from the keys `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`.
- AC-SH-2. Back from any non-home tab ends at `/home`; Back on `/home` pops out (F3 unchanged; reuse the existing shell test).
- AC-SH-3. The nav bar is built from the configuration list; changing the list changes the bar (test with a 4-item list).
- AC-SH-4. Switching mode changes neither the router location nor `HudNavBar.selectedIndex`.
- AC-SH-5. `shell.dock.recordPill` and `shell.dock.strip` are never in the tree together.
- AC-SH-6. (Rewritten, finding U6.) With `permission_handler`'s method channel mocked to record calls, pumping S-1, S-2, S-3, S-5 (without following a row), S-6, S-7 and S-8 produces zero calls. Static check: no import of a location or permission package under the new S03 files.
- AC-REG-1. The existing scanner and equipment tests pass unchanged; `/scan` still routes as before (G-5).
- AC-REG-2. `isDemoGatedPath` behaviour for `/community`, `/celebrity-plans`, `/contribute`, `/moderate`, `/team/*` is unchanged.
- AC-REG-3. [flag off] Existing Home and Progress widget tests pass unchanged with default providers.
- AC-REG-4. With `ACTIVITY_CLOUD_STREAMS` off no sync wording is present in the S03 widgets (text search of the pumped trees).
- AC-A11Y-1. (Rewritten, findings A1, A3.) For each new interactive control (C-1, C-2, C-8, C-9, sheet buttons, strip) use `tester.getSemantics(find.byKey(...))` and assert with `matchesSemantics`: role (`isButton`), non-empty `label`, expected `hint`, `isSelected`/`isEnabled` where specified, `hasTapAction`, and a size of at least 48x48 from `tester.getSize` of the tappable ancestor (the hit region, not only the painted box).
- AC-A11Y-2. Headers: `isHeader` is true for the titles of S-1, S-3, S-5, S-7b ("All activity"), S-8.
- AC-A11Y-3. Focus: sending Tab key events on S-1 visits the four cards, Continue, Decide later in that order; opening S-3 from `home.modeChip` and closing it returns focus to `home.modeChip`; the first focused node inside a sheet is its header.
- AC-A11Y-4. Announcements: capture messages on the accessibility channel (the transport of `SemanticsService.announce`); a mode change emits one message containing the new mode name; strip transitions started, paused, resumed, ended each emit one; advancing a fake clock by 30 seconds emits none and the strip's semantics label is unchanged until the minute boundary.
- AC-A11Y-5. Text scale 2.0 in `ru` and `en` on a 360x640 surface for every new screen S-1, S-2, S-3, S-4 (strip and pill), S-5, S-6 (chip row, intro card, activity today), S-7a/S-7b, S-8: no `RenderFlex` overflow exception AND `didExceedMaxLines == false` for the keyed status-chip words, chip texts, button labels and headers.
- AC-A11Y-6. Reduced motion: under `MediaQuery(disableAnimations: true)`, `context.hudMotionDuration(d)` as used by the new widgets resolves per `hud_tokens.dart` (the test asserts the documented zero/reduced result), `pumpAndSettle` returns without waiting, and no `CircularProgressIndicator`/`LinearProgressIndicator` indeterminate exists in S03 trees.
- AC-A11Y-7. RTL: S-1 and S-4 pump in `TextDirection.rtl` without overflow.
- AC-A11Y-8. Contrast: the new components use only `HudTokens` text tiers (static test greps new files for `Color(0x` and `Colors.`; none allowed) and no use of `warning`/`danger`/zone colours as a text style.

Test seams the build must provide (contract items, not code): keys listed per screen; `home.section.<name>` keys on existing Home children; an injectable clock for week/today; an injectable journal availability; injectable timer providers (already providers); an in-memory settings store for `selectedMode` and `chooserStatus`.

Real-device checks (focus ring visibility, TalkBack reading order, actual contrast over photographs) are NOT_RUN by the test agents and go to the independent a11y review.

## 15. Open operator decisions

Each states the decision in words, the default, and what each answer does. Owner is the operator unless noted.

OD-1 (open question U-1). Replace the Scan tab with a context-sensitive Record action, or keep five tabs?
- "Keep five tabs, Record as a shell action" (Option A, recommended, default): the gym QR scan stays one tap and nothing moves for Phase 1 users; a running workout is shown in a strip on all five tabs. The bar has no Ride, Explore or Body entry, and Record is a pill above the bar, not the centre button.
- "Replace Scan with Record" (Option B): the bar looks like the film's mock with a centre Record button, but the gym scan becomes two taps and leaves the bar; for the whole R2 alpha the centre button acts only in Train and Body; tests and deep links that assume the third tab are touched.
- Needed before approval of this contract. No answer = Option A.

OD-2 (open question U-2). Tablet and large layouts now or later? Default later: phone only; S-9 stays a drawing. "Now" adds a responsive chooser, a side rail and a large-screen Progress to S03 (estimate UNKNOWN) and a large-screen variant to every later contract.

OD-3 (decision D-9). Are any modes or features paid or gated? Default: no paywall, no lock icons. Any gating needs a locked card state and an upsell path, neither designed here.

OD-4. What happens when a user taps a mode that is not built yet? Recommended: "Coming later" sheet, mode unchanged, nothing collected. Alternative A: allow selecting it (the lens then has nothing to show; looks broken). Alternative B: a "tell me when ready" option (needs a notification consent and storage; privacy-relevant, not designed).

OD-5. (Changed.) How do gym (strength) workouts show on the new dashboard, which reads only the activity store? Recommended: the "All activity" block shows only recorded activity and is not shown at all until a first recorded session exists. A Phase 1 user with five gym workouts sees nothing new on Progress except one quiet "Sources" row whose hint reads "Walks, runs and rides you record will appear on Progress." They never see "No recorded activity yet" above their real gym data, but also never see their gym work inside "This week" until a later sprint bridges the stores. Alternative: add a read-only Gym tile fed by the existing workout readers (needs a verified duration/count reader, UNGROUNDED; extra S03 scope). Alternative: copy gym workouts into the activity store (rejected by S02 3.6 unless reopened).

OD-6. (Changed.) Where does the first-run chooser sit for a brand-new account, and who is spared it? Recommended: after the existing onboarding, shown from Home while a persisted "chooser status" is "pending"; the status is set to "pending" at the end of onboarding only if it was never set, and existing users are marked "migrated" at app start and see only a one-time intro card, never the forced chooser. Consequence: a new user who taps "Decide later" is marked "resolved" and sees no intro card; an upgrader is never forced; a user killed mid-chooser sees it again next start. Alternative: choose before onboarding (first screen "What do you want to do?", feels faster for the 3-minute goal, but changes onboarding and its redirect rules and picks a mode before the app knows the user). Note: the status is stored per device, not per account (DQ-2).

OD-7. (Changed.) A running gym workout lives on its own pushed page (`/workout/:id`), outside the shell. Is it acceptable that the Recording strip is not shown on that page and on other pushed pages (equipment, exercise, settings, body scan, nutrition) in S03? What it means in plain words: while a set or rest timer runs, a user who is on the workout page sees no strip and no mode chip; they have to go Back to a tab, where the strip then shows on all five tabs and returns them to the workout with one tap. Recommended: accept for S03 (the only session is a gym workout with its own screen); the persistent indicator for background GPS is designed in S04-D. Alternative: an app-wide overlay so the strip shows on every page (touches all 50 routes and every page's bottom edge; higher regression risk, not designed).

OD-8. Scope of the consent centre and the sign-out warning. S02 assigned the consent centre UI to S03 and left the sign-out warning UI to a UI story, but the S03 roadmap row lists only EP-1..EP-4. Recommended: S03 builds the Sources panel and, if agreed, the sign-out sheet (J10); the full consent centre becomes its own design sprint before S04. If neither is built, the S02 sign-out hooks stay unused and signing out has no warning for data held only on the device.

OD-9. (NEW, finding U1.) Open the on-device activity history in the default build? Today the journal is opened only when the cloud flag is on (default off), so in the default build the new dashboard has nothing to read. Recommended: add a story S03-0 that opens and recovers the local journal at app start whatever the cloud flag says, keeping every cloud piece behind the flag; needs architect and operator confirmation because it changes the S02 statement that with the flag off no journal is opened. If YES: the default build can show the real empty state and, from S05, recorded sessions; the app does one extra file recovery pass at start. If NO: in the default build the "All activity" block never appears and the Sources panel says "Activity history is not active in this build"; the new dashboard can then only be exercised in builds with the cloud flag on or in tests with overrides, and shipping the alpha without it means the dashboard skeleton is invisible to users.

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

## 16. Known limits of the current app (not fixed by S03)
- Existing HUD controls show no focus indicator; legacy-scaffold pages remain; raw exception text still appears on Home, Settings, Login and Onboarding errors; Progress cannot tell loading from empty for its existing blocks; the router's page transition ignores reduced motion (only the new routes are patched, section 12).
- No global offline indicator; none added.
- Gym timers do not survive process death.
- The set timer and rest timer are global, not keyed by exercise: opening another exercise's page while one runs shows the same timer (existing behaviour).
- The nav bar's one-line labels truncate at large text and in Russian (existing).
- No chart-to-table alternative exists; none is added.

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

## 18. Review handoff
- product-ux-reviewer: re-check J1-J10, S-4 "running" table, S-7 placement and demotion, OD-5/6/7/9 wording.
- a11y-architect: sections 9.1, 12, 13, 14 (AC-A11Y-1..8).
- architect: DQ-2, DQ-10, DQ-11, OD-9 (S03-0), the nav configuration list (5.4), dock inset plumbing (17.5), the primitive extensions (9.1).
- GPT-PM: whole contract after those reviews; OD-1..OD-9 go to the operator in plain Russian, not decided here.
- Build gate: S03 starts only when this contract is approved, OD-1 and OD-9 are answered.

## 19. Review disposition (revision 2)

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
