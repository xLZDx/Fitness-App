# S03 Technical Design: shell, mode chooser, dashboard skeleton

Status: DRAFT part 1 (contract-derived sections only). Written 2026-10-17. Branch: `phase2/s03d-ui-design-contract`. No code is changed by this document.

All ten sections are written. Sections 2, 3, 4, 5, 7 and 9 were completed after the code map `docs/phase2/s03/S03_CODE_MAP.md` arrived; facts from it carry its path and line. Items the map lists as UNKNOWN are tagged UNGROUNDED or avoided.

Tags used for every claim: FACT (path, section or line), INFERENCE, PROPOSED (design choice made here), OPEN (needs an owner's answer), UNGROUNDED (could not be verified in the repository). In this part the only FACT source is the contract `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` (called "the contract" below; "contract 4.2" means its section 4.2) and the roadmap `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`. Nothing here was checked against the Dart code.

Plain-words glossary of ids used (each is also explained where first used):
- AC-xx-n = an "acceptance criterion": one observable pass/fail check written in the contract (xx is the family, for example CH = chooser, WS = window size).
- S03-nn = a story (a unit of build work) of this sprint. S03-0 is the first one: the local activity history opens in the default build.
- EP-n = an epic (a group of stories). OD-n = an open operator decision. DQ-n = a design question from the contract. DD-n = a decision or question raised by this design.
- D-9 = roadmap decision on monetisation per mode; its default is "all new modes behind flags, no new paywall".
- S-n = a screen of the contract (S-1 mode chooser ... S-10 sign-out sheet). C-n = a component of the contract (C-1 ... C-15).
- T1 to T4 and R-classes are NOT used in this file; risk is written as low, medium or high with the reason.

## 1. Scope, non-goals, entry conditions, definition of done

### 1.1 Scope

Source of scope (FACT): roadmap row S03 "Shell, chooser, dashboard skeleton (EP-1 mode state, EP-2 chooser and per-mode first-run questions, EP-3 Today/This week/Progress from `ActivitySession`, EP-4 sources panel)", gate text "Existing five-tab flows unchanged; mode switch never resets a running session; missing shown as missing" (roadmap line 82). The contract (approved by GPT-PM on 45b9184b, per the lead agent's brief) is implemented exactly; where it is silent this design decides and tags the decision PROPOSED.

Operator decisions that bind this design (FACT, contract header and section 15, answered 2026-10-16, GO for S03 on 2026-10-17):
1. One app, one application id (contract F26). Phase 2 is an update of the same app.
2. Five tabs stay; Record is a button over the screen (pill above the bar, or the Record slot of the side rail).
3. Layouts for Android phone, iPhone, iPad, Android tablet and MacBook are designed and built NOW as one responsive UI.
4. Only the Android platform folder exists. S03 builds and tests on Android and, for Apple behaviour, with a faked `TargetPlatform` in widget tests. No iOS, iPadOS or macOS build target is created.
5. The local activity journal opens in the default build whatever the cloud flag says (story S03-0).
6. Cloud retention for GPS history offers 90, 365 or 730 days; default 730 days; "never" is not offered (S03 has no retention control; only copy and fixtures are checked, AC-RET-1).
7. All new modes stay behind flags and there is no new paywall (decision D-9 default).

Epics (FACT: names from the roadmap; EP-5 and EP-0 are the contract's additions, contract header and 4.4):

| Epic | Plain words | Stories |
|---|---|---|
| EP-0 | The local journal opens in the default build | S03-0 |
| EP-1 | Mode state: which mode is selected, whether the chooser still has to be shown, saved on the device per account | S03-01 |
| EP-2 | Mode chooser, per-mode first-run questions, mode switcher, Record sheet | S03-08, S03-09, S03-10, S03-11 |
| EP-3 | Today, This week and Progress built from `ActivitySession` | S03-12, S03-13, S03-14 |
| EP-4 | Sources panel (and the sign-out warning that belongs to local-only data) | S03-15, S03-16 |
| EP-5 | Responsive shell: window-size class, bottom bar versus side rail, Record button and strip, adaptive surfaces, keyboard and pointer, conformance | S03-02 to S03-07, S03-17, S03-18, and conditional S03-19, S03-20 |

### 1.2 Non-goals (nothing below is built in S03)

- Any recorder, GPS, location permission, foreground service (S04 to S06). S03 requests no permission anywhere (AC-SH-6, AC-CH-7).
- Any new network call and any new server code or Firestore rule change (PROPOSED: none needed; INFERENCE from the contract, which designs only local UI and reads the existing journal; the code map must confirm, section 7).
- iOS, iPadOS and macOS build targets, store accounts, signing, the macOS menu bar, a Cupertino swipe-back transition (contract 10, OD-12).
- Retention control, consent centre UI, per-source consent and delete controls (consent-centre sprint; contract S-8, OD-8).
- Dedup against external sources and any wording that promises it (contract 11 rule 5).
- Health Connect, HealthKit, BLE or watch adapters; `healthStatus()` is not called (contract S-8).
- Photography on mode cards, lime corner wedges, a units setting (metric only), "See all" history, "How this is calculated", a chart table alternative (contract DQ-5, DQ-9, DQ-4, section 16).
- A paywall, lock icons or any gating of modes (D-9 default; contract OD-3).
- Retrofit of focus rings and 44 dp targets on legacy HUD controls and redesign of the roughly 45 pushed pages (contract section 16).
- Bridging gym `strength` workouts into the activity dashboard (contract OD-5): `strength` never appears in S03 tiles or rows.

### 1.3 Entry conditions

| # | Condition | State |
|---|---|---|
| E1 | Contract approved (GPT-PM, 45b9184b) | FACT per brief |
| E2 | Operator GO for S03 | FACT per brief, 2026-10-17 |
| E3 | S02 merged: `ActivitySession`, local journal, merger exist | FACT contract header ("after the S02 merge", HEAD da3279f7) |
| E4 | Code map `S03_CODE_MAP.md` delivered | FACT: delivered 2026-10-17; sections 2 to 5, 7, 9 are written from it |
| E5 | Privacy wording stays untouched (source `scripts/legal/legal_text.py`) | FACT contract 15 (OD-11); S03 adds no privacy copy |

### 1.4 Definition of done (sprint level)

1. Every story of 1.5 is merged into the single S03 branch with its change-record file (operator rule: every commit carries its own change record) and a lessons-log entry.
2. All 124 contract acceptance criteria listed in 1.7 are implemented as automated tests and green, run by the test-writing agents (`functional-test-reviewer`, `e2e-runner`), complete sets per epic and once more after the last epic. The coordinator runs no tests.
3. No valid BLOCKER or MAJOR finding remains from the specialist reviews (accessibility, architecture, reliability, security as routed); GPT-PM approves the exact final head before push and PR.
4. Existing five-tab flows are unchanged: existing scanner, equipment, Home and Progress tests pass unchanged (AC-REG-1 to AC-REG-3).
5. A mode switch never resets, pauses or edits a running timer (AC-SW-2, AC-ST-4).
6. Missing is shown as missing: no zero for unknown, no cross-sport energy (AC-PR-4, AC-PR-5).
7. The default build has the journal open, every cloud piece still behind `ACTIVITY_CLOUD_STREAMS`, and no sync wording when that flag is off (AC-REG-4, story S03-0).
8. Every item the contract marks "real-device only" is recorded as NOT_RUN with the reason (1.8), never as passed.
9. The nine ARB key groups of section 6 (6.1 to 6.9) exist in both `en` and `ru` and pass the length and word-ban checks.

Story-level DoD is the common rule "code merged, listed ACs green, no new BLOCKER/MAJOR, change record and lessons entry committed" plus the specific line in table 1.6.

### 1.5 Story overview

Risk class here means: low = additive pure code or copy; medium = touches shared shell, router or Home/Progress; high = changes startup behaviour, persistence of user state or the shell for every tab. Test estimate is the designer's INFERENCE (number of widget, unit and integration tests, counting each contract AC as at least one test and parametrised size/locale cases separately); the test agents own the real count.

| Id | Title | Epic | Depends on | Risk | Est. tests |
|---|---|---|---|---|---|
| S03-0 | Open and recover the local journal at app start in the default build; one availability value (`open`, `notEnabled`, `failedToOpen`) | EP-0 | none | high (changes S02 statement "flag off: no journal is opened", contract 4.4) | 6 |
| S03-01 | Mode state: `selectedMode`, `chooserStatus`, per-mode answers, availability table, account-scoped store, start-up migration, onboarding-finish hook, `modeChanged` event | EP-1 | none | high (persistence, startup, per-account) | 14 |
| S03-02 | Window-size class provider and `ShellLayout` (C-14) | EP-5 | none | medium | 8 |
| S03-03 | HUD primitive extensions: semantics, `minHeight`, `maxLines`, hover style, cursor, focus ring (9.1) | EP-5 | none | medium (shared widgets; defaults must equal today) | 14 |
| S03-04 | Navigation configuration list and the bottom bar built from it, "Main navigation" container | EP-5 | S03-03 | medium | 6 |
| S03-05 | Side rail (C-13) and presentation swap bar versus rail, rail forms, vertical fit, bottom clearance | EP-5 | S03-02, S03-03, S03-04 | high (shell for every tab) | 30 |
| S03-06 | Adaptive surface (C-15): bottom sheet, centred dialog, anchored popover; reduced-motion routes | EP-5 | S03-02, S03-03 | medium | 10 |
| S03-07 | Dock: Record pill, Recording strip, `ActiveSessionStatus`, destination provider, rail Record slot, padding and compaction | EP-5 | S03-02, S03-03, S03-04 (needs only the `ShellLayout` API of S03-05, not the rail) | high | 34 |
| S03-08 | Mode chooser S-1 as one responsive screen (incl. the S-9 large layouts) | EP-2 | S03-01, S03-02, S03-03, S03-06 | medium | 30 |
| S03-09 | Per-mode first-run questions S-2 | EP-2 | S03-01, S03-08 | medium | 12 |
| S03-10 | Mode switcher S-3 and Coming-later sheet | EP-2 | S03-01, S03-06, S03-07 | medium | 12 |
| S03-11 | Record sheet S-5 | EP-2 | S03-01, S03-06, S03-07 | medium | 10 |
| S03-12 | Home: mode chip, section keys, lens ordering, "Activity today", upgrader intro card, two-pane layout | EP-3 | S03-0, S03-01, S03-02, S03-03, S03-05, S03-10, S03-13 | high (Home is about 20 children) | 20 |
| S03-13 | Activity aggregates (today, this week, recent), sport groups, source labels, formatters; pure and testable | EP-3 | S03-0 | medium | 18 |
| S03-14 | Progress dashboard: quiet Sources slot, "All activity" block, journal error panel, dock padding, two-column layout | EP-3 | S03-0, S03-02, S03-07, S03-13, S03-15 (row target) | high | 22 |
| S03-15 | Sources panel S-8 and its large layout | EP-4 | S03-0, S03-13 | low | 14 |
| S03-16 | Sign-out warning sheet S-10 (ASSUMED in scope, see OD-8) | EP-4 | S03-0, S03-06 | medium (touches sign-out) | 6 |
| S03-17 | Keyboard shortcuts, scroll behaviour, visible Back on Apple desktop, touch-only regression | EP-5 | S03-04, S03-05, S03-07, S03-10, S03-11 | medium | 16 |
| S03-18 | Cross-cutting conformance suite (accessibility, text scale, platform family, regression, narrow-pane fallback, static checks) | all | all above | medium (tests only, no product code except fixes) | 60 |
| S03-19 | CONDITIONAL: shared width-cap frame for pushed pages (contract DQ-12) | EP-5 | S03-02 | medium | 6 |
| S03-20 | CONDITIONAL: reminder-notification tap routing (contract J6) | EP-1 | S03-01 | medium | 4 |

The "Est. tests" column above is the designer's estimate from before the review batch (about 340 tests in total, INFERENCE) and is NOT current: the test plan (plan 9.1) holds the counts, now 456 tests without the two conditional stories and 468 with them, which is 33 percent above these estimates (the story estimates sum to 342). Number of stories: 21 (S03-0, S03-01 to S03-20), of which 2 are conditional (S03-19, S03-20) and 19 are unconditional. Roadmap sizes S03 at 4 (unit not stated in the rows read, INFERENCE: sprint units); the contract itself says the large-screen decision grew the sprint and the effort is UNKNOWN (contract OD-2). This is raised as DD-1 in section 10.

### 1.6 Story details: files, contract sections, acceptance criteria, definition of done

File paths: paths that exist today come from the contract (FACT, contract section 1 table; the `hud/` files are under `mobile/lib/shared/widgets/hud/`, INFERENCE from `main_shell.dart` living in `mobile/lib/shared/widgets/`). Paths of NEW files are PROPOSED names; the folder for each is given in section 2 and must follow the architecture guards that the S02 design records (for example `activity/data` is pure Dart, FACT S02_DESIGN section 2).

| Id | Files to add (PROPOSED) / change (existing) | Contract sections | ACs (exactly one owner each) | Story DoD |
|---|---|---|---|---|
| S03-0 | Change `mobile/lib/core/wiring/activity_wiring.dart`, `mobile/lib/core/config/activity_flags.dart`; add `mobile/lib/features/activity/state/journal_availability.dart`, the companion bind-status Notifier and the bind retry controller class (refactored out of the closure in `activityJournalBindingProvider`, behaviour-preserving, 2.1 item 3) in `activity_wiring.dart`; the existing `activity_journal_binding_retry_test.dart` stays valid unchanged; UNCONDITIONALLY (RV-13, verified FACT) the backup fix: `mobile/android/app/src/main/res/xml/backup_rules.xml`, `mobile/android/app/src/main/res/xml/data_extraction_rules.xml`, `mobile/lib/features/activity/repository/journal_layout.dart` (one constant for the scoped root `activity_journal`, corrected header claim at lines 4-7), the file that holds `fileActivityJournalFactory` (path read in the story's first step), and the tests `mobile/test/android/backup_rules_test.dart` and `backup_exclusion_test.dart` | 4.4, principle 6, J10 | none in the contract (GAP, see 1.8); tests: see the plan, epic table and section 10; this story's decisions are guarded by DT-0-1 (default build opens the journal), DT-0-2 (cloud pieces unwired), DT-0-3 (open failure), DT-0-4 (`notEnabled` override), DT-0-5 (single flight), DT-0-11 to DT-0-14 (retry state machine), DT-0-6 to DT-0-8 (backup exclusion, RV-13); `binding`, `gaveUp` and uid reset are guarded under RV-3 (DT-13-8 to DT-13-15), recovery counts under RV-10 (DT-13-16, DT-14-5, DT-15-4) and the sign-out guard under RV-12 (DT-16-4 to DT-16-7) | Backup fix lands BEFORE the default flip of `ACTIVITY_LOCAL_JOURNAL` (order in the story and in the commit sequence); manual and automatic bind attempts follow the single retry state machine of 2.1 item 3 (DT-0-5, DT-0-11 to DT-0-14) and `activity_journal_binding_retry_test.dart` passes unchanged; default build holds an open journal; cloud wiring unchanged; the changed S02 statement is recorded in this story's change record |
| S03-01 | New `mobile/lib/features/modes/{data,state}/` (2.2); NOT `app_settings.dart` (settings are device-wide, map risk 3); change `mobile/lib/features/onboarding/onboarding_page.dart` (one awaited call before `context.go('/home')`) and `mobile/lib/main.dart` (`FitnessApp.build` watches only) | 4.1, 4.2, 4.3, J1, J4, OD-6, DQ-2 | AC-CH-8 | Migration table of contract 4.2 holds; key `activity.mode.v1.<uid>`; account switch, sign-out and deletion rules of section 5 implemented; `modeChanged` emitted only on a real change |
| S03-02 | New `mobile/lib/shared/widgets/window_size.dart` (`WindowSizeInfo`, override provider); `ShellLayout` is created in S03-05 (lane L4a) | 10.1, WS-1 to WS-5, C-14 | AC-WS-1 | Provider overridable in tests; boundaries 600 and 840 inclusive at the lower end; short flag below 480 dp height; no screen reads raw widths |
| S03-03 | Change `hud/hud_surface.dart` (HudChip, HudButton, HudPanel), `hud/hud_metric.dart` (HudSettingRow); the focus ring lives in the primitives and `HudKeyboardActivation` (`hud_surface.dart`); `hud/hud_scaffold.dart` is NOT touched (lane L4a owns it) | 9.1, 12, 10.9 | AC-KB-3, AC-KB-4 | Every new parameter optional; defaults reproduce today exactly; the existing HUD tests pass unchanged |
| S03-04 | Change `mobile/lib/shared/widgets/main_shell.dart`; add `mobile/lib/shared/widgets/shell_destinations.dart` (`kShellDestinations`); `HudNavBar` API (`items`, `selectedIndex`, `onSelect`) stays, its items are built from the list | 5.1, 5.3, F2, F3 | AC-SH-1, AC-SH-2, AC-SH-3 | Bar identical to today for the five tabs; bar wrapped in container Semantics "Main navigation"; Back behaviour unchanged |
| S03-05 | Add `hud/hud_side_rail.dart` and `shell_layout.dart` (which also declares `RailLabelMeasurer` and `railLabelMeasurerProvider`, the only way the rail reads label widths); change `main_shell.dart`, `hud/hud_scaffold.dart` (`HudScreenBody` reads `ShellLayout`, falls back to today's behaviour when absent) and `shell_insets.dart`; the `ShellRoute` child keeps one `GlobalKey` slot (RV-6); NO edit to `app_router.dart`, `home_page.dart`, `progress_page.dart` or any Workouts file: Home, Workouts and Progress adopt the insets through `HudScreenBody` and `ShellLayout` (Progress in its own story S03-14) | 10.4, 10.1 | AC-WS-2, AC-WS-3, AC-WS-4, AC-WS-5, AC-WS-6, AC-WS-8, AC-WS-9, AC-WS-10, AC-WS-11, AC-KB-2, AC-KB-9 | Rail and bar come from one list; rail form by measured label width; no overflow at 640x360 and 800x360; presentation swap keeps route, selection, timers, focus |
| S03-06 | Add `mobile/lib/shared/widgets/adaptive_surface.dart` and `mobile/lib/core/router/s03_routes.dart` (no-transition page builder, route list spliced once into `app_router.dart`, three stub pages); new routes use the builder (contract 12, audit: `_fadeThrough` ignores reduced motion) | 10.6, 12 (reduced motion), C-15 | AC-LS-8, AC-WS-14, AC-A11Y-6 | One component picks placement by class; Esc, Back, scrim close it; focus returns to opener; no indeterminate progress indicator |
| S03-07 | Add `features/workouts/state/active_session_status.dart` (status from `setTimerProvider`, `restTimerProvider`, `ActiveSessionOwner{uid, destination}`, driven one-shot timers) and `shared/widgets/dock_widgets.dart` (pill, strip, rail Record slot content); change the timer start paths in `features/equipment/workout_player_page.dart` to write the owner; NO edit to `main_shell.dart` (lane L4a mounts the widgets after L4b's interface commit) | S-4, 5.1, J2, J3, R-S1 to R-S5, 10.4 (Record slot) | AC-ST-1 to AC-ST-9, AC-SH-5, AC-WS-7, AC-WS-12, AC-WS-13 | Table of "running" states exactly as the contract; strip never on pushed routes; process death clears (no recovery claim); mode switch does not touch the timers |
| S03-08 | Add `mobile/lib/features/modes/pages/mode_chooser_page.dart` on route `/mode-chooser` (PROPOSED) outside the `ShellRoute`; the route is registered through `s03_routes.dart` | S-1, S-9, J1, J9, 10.5 chooser row | AC-CH-1 to AC-CH-7, AC-CH-9 to AC-CH-14, AC-LS-7, AC-LS-11 | One screen, three layouts; grid rule by available grid width; chooser pushed once per app start while `pending`; no permission call |
| S03-09 | Add `mobile/lib/features/modes/pages/mode_question_page.dart` on route `/mode-questions/:mode`, reusing `ob_shell` and `inputs` (paths UNGROUNDED, read in the story's first step); read and write the `TrainingContext` answer through `training_context_providers.dart` | S-2, C-10, DQ-6 | AC-Q-1 to AC-Q-6 | At most 3 questions; every question skippable; a refused option disabled with reason |
| S03-10 | Add switcher sheet and Coming-later sheet; add `home.modeChip` hook point (Home change itself is S03-12) | S-3, J2, J5, J9 | AC-SW-1 to AC-SW-5, AC-SH-4 | Two taps from Home; single instance guard; unavailable rows never write |
| S03-11 | Add Record sheet; read Home day-panel start target and `ScanAccess`, `FOOD_AI`, `FOOD_LOOKUP` rules (`screenedUpcomingSessionsProvider`, `todayDigestProvider`, map 123; the `ScanAccess` path is UNGROUNDED); new `mobile/lib/features/modes/widgets/record_sheet.dart` | S-5, 10.6 | AC-RC-1 to AC-RC-5 | Every row navigates into an existing flow; creates no capability; no write on open/close |
| S03-12 | Change `mobile/lib/features/home/home_page.dart` (stable `home.section.<name>` keys, chip, lens, activity today, intro card, panes) | S-6, 10.5 Home, J4 | AC-HM-1 to AC-HM-6, AC-LS-1, AC-LS-2, AC-LS-3 | Pre-S03 section order preserved under TRAIN; no new error text on Home; intro never beside Day-3 modal |
| S03-13 | Add pure aggregation and label code (week and today windows, sport groups, source labels 8.1, formatters) in `mobile/lib/features/activity/data/activity_aggregates.dart` (pure layer) and providers in `mobile/lib/features/activity/state/activity_dashboard_providers.dart`; reuse the day and Monday-week helpers of `progress_stats.dart:35-47` | 8.1 to 8.4, 11, S-7b (week definition OPEN-1), DQ-10 | AC-PR-5, AC-PR-7, AC-PR-11, AC-SRC-6 | Week starts Monday in the device zone, injectable clock and zone; no session counted in two groups; `strength` excluded |
| S03-14 | Change `mobile/lib/features/progress/progress_page.dart` (insert S-7a/S-7b, padding by dock, columns) | S-7, 10.5 Progress, 11 | AC-PR-1, AC-PR-2, AC-PR-3, AC-PR-4, AC-PR-6, AC-PR-8, AC-PR-9, AC-PR-10, AC-LS-4, AC-LS-5 | Existing children and their order unchanged except inserted children; demotion rule: empty or loading shows only the Sources row |
| S03-15 | Add Sources screen and route outside the shell; read `kCapabilityMatrix` and `SourceKind` | S-8, 8.1, 10.5 Sources | AC-SRC-1, AC-SRC-2, AC-SRC-3, AC-SRC-4, AC-SRC-5, AC-SRC-7, AC-LS-6 | Rows are information only; no adapter called; app row states by availability |
| S03-16 | Add sign-out warning sheet; guard `confirmSignOutWithLocalData` called by every sign-out call site (call sites UNGROUNDED, enumerated in the story's first step); read counts via `assessSignOut()` (`journal_models.dart:268-282`) | J10, S-10 | AC-SO-1, AC-SO-2 | Nothing deleted before the second confirmation; empty journal signs out with no prompt; export reuses `activity_local_export.dart` (exists); deletion reuses `ActivityWipeCoordinator.onSignOut` |
| S03-17 | Add shortcut map (`Shortcuts`/`Actions`), scrollbar, Back control on Apple desktop; touch-only regression | 10.9, 10.8, DQ-15 | AC-KB-1, AC-KB-5, AC-KB-7, AC-KB-8 | No shortcut fires in a text field or a modal; Esc never navigates back |
| S03-18 | Tests and static checks only (and fixes they force); ARB word-ban and budget tests | 12, 13, 14, 11 | AC-SH-6, AC-REG-1, AC-REG-2, AC-REG-3, AC-REG-4, AC-A11Y-1, AC-A11Y-2, AC-A11Y-3, AC-A11Y-4, AC-A11Y-5, AC-A11Y-7, AC-A11Y-8, AC-KB-6, AC-FAM-1 to AC-FAM-6, AC-LS-9, AC-LS-10, AC-RET-1 | Every listed AC green; no overflow at text scale 2.0 in `ru` and `en`; NOT_RUN items recorded |
| S03-19 | Add a frame for pushed pages (excluding camera pages); wire in the router | 10.5 (pushed pages), DQ-12 | none in the contract (tests: see plan, DT-19-1 to DT-19-6) | Only if DQ-12 is answered yes (contract assumes yes) |
| S03-20 | Add notification tap callback and payload-to-route mapping (UNGROUNDED, contract 17.6) | J6, DQ-8 | none in the contract (tests: see plan, DT-20-1 to DT-20-5) | Only if confirmed in scope; mode never changes on a tap (R-M4) |

### 1.7 Coverage table: every contract acceptance criterion maps to exactly one story

The contract has 124 acceptance-criterion ids in 17 families (the brief named ten families; the contract also defines Q, SW, ST, RC, HM, SO and REG, which are included so none is left without an owner). Counts below add up to 124.

| Family | Ids | Count | Story |
|---|---|---|---|
| AC-CH (chooser) | CH-8 | 1 | S03-01 |
| | CH-1, CH-2, CH-3, CH-4, CH-5, CH-6, CH-7, CH-9, CH-10, CH-11, CH-12, CH-13, CH-14 | 13 | S03-08 |
| AC-Q (questions) | Q-1 to Q-6 | 6 | S03-09 |
| AC-SW (switcher) | SW-1 to SW-5 | 5 | S03-10 |
| AC-ST (strip and pill) | ST-1 to ST-9 | 9 | S03-07 |
| AC-RC (Record sheet) | RC-1 to RC-5 | 5 | S03-11 |
| AC-HM (Home) | HM-1 to HM-6 | 6 | S03-12 |
| AC-PR (Progress) | PR-5, PR-7, PR-11 | 3 | S03-13 |
| | PR-1, PR-2, PR-3, PR-4, PR-6, PR-8, PR-9, PR-10 | 8 | S03-14 |
| AC-SRC (sources) | SRC-6 | 1 | S03-13 |
| | SRC-1, SRC-2, SRC-3, SRC-4, SRC-5, SRC-7 | 6 | S03-15 |
| AC-SO (sign-out) | SO-1, SO-2 | 2 | S03-16 |
| AC-SH (shell) | SH-1, SH-2, SH-3 | 3 | S03-04 |
| | SH-4 | 1 | S03-10 |
| | SH-5 | 1 | S03-07 |
| | SH-6 | 1 | S03-18 |
| AC-REG | REG-1 to REG-4 | 4 | S03-18 |
| AC-A11Y | A11Y-6 | 1 | S03-06 |
| | A11Y-1, A11Y-2, A11Y-3, A11Y-4, A11Y-5, A11Y-7, A11Y-8 | 7 | S03-18 |
| AC-WS (window size, rail) | WS-1 | 1 | S03-02 |
| | WS-2, WS-3, WS-4, WS-5, WS-6, WS-8, WS-9, WS-10, WS-11 | 9 | S03-05 |
| | WS-7, WS-12, WS-13 | 3 | S03-07 |
| | WS-14 | 1 | S03-06 |
| AC-LS (large screens) | LS-1, LS-2, LS-3 | 3 | S03-12 |
| | LS-4, LS-5 | 2 | S03-14 |
| | LS-6 | 1 | S03-15 |
| | LS-7 (pointer to CH-9 to CH-14), LS-11 | 2 | S03-08 |
| | LS-8 | 1 | S03-06 |
| | LS-9, LS-10 | 2 | S03-18 |
| AC-KB (keyboard, pointer) | KB-3, KB-4 | 2 | S03-03 |
| | KB-2, KB-9 | 2 | S03-05 |
| | KB-1, KB-5, KB-7, KB-8 | 4 | S03-17 |
| | KB-6 | 1 | S03-18 |
| AC-FAM (platform family) | FAM-1 to FAM-6 | 6 | S03-18 |
| AC-RET | RET-1 | 1 | S03-18 |

Arithmetic check: CH 14 + Q 6 + SW 5 + ST 9 + RC 5 + HM 6 + PR 11 + SRC 7 + SO 2 + SH 6 + REG 4 + A11Y 8 + WS 14 + LS 11 + KB 9 + FAM 6 + RET 1 = 124. Per story: S03-01: 1; S03-02: 1; S03-03: 2; S03-04: 3; S03-05: 11; S03-06: 3; S03-07: 13; S03-08: 15; S03-09: 6; S03-10: 6; S03-11: 5; S03-12: 9; S03-13: 4; S03-14: 10; S03-15: 7; S03-16: 2; S03-17: 4; S03-18: 22; S03-0, S03-19, S03-20: 0. Sum 124.

Notes on the mapping (PROPOSED choices where an AC spans more than one story):
- An AC is owned by the story whose behaviour it mainly checks; other stories need not duplicate it but must not break it. For example AC-LS-8 (surfaces by class) is owned by S03-06 even though S-3 (S03-10) and S-10 (S03-16) use the surfaces; those stories pass it by using the S03-06 component.
- AC-A11Y-1 to AC-A11Y-5, AC-A11Y-7, AC-A11Y-8 and AC-FAM-4 cross every screen; they live in S03-18 so that one agent writes one conformance suite, while each earlier story's DoD requires its own screens to be keyed and measurable. The test agents still write per-epic accessibility cases early (operator rule: all tests of the epic after each epic) and S03-18 consolidates and runs them.
- AC-LS-7 only points at AC-CH-9 to AC-CH-14; it is kept as a separate id with the same owner.

### 1.8 Contract gaps and criteria with limits in S03

Criteria that no S03 test can fully prove (none is wholly untestable; each has a limit that must be recorded as NOT_RUN or "faked", never as passed):

| Criteria | Limit | Reason |
|---|---|---|
| AC-FAM-1 to AC-FAM-6 (Apple cases), AC-KB-8, AC-KB-1 Apple part | Faked `TargetPlatform` only | No Apple build target exists (contract F26, OD-12) |
| AC-A11Y-3, AC-A11Y-4, AC-A11Y-1 | Flutter semantics tree only; TalkBack, VoiceOver reading order NOT_RUN | Real-device checks go to the independent a11y review (contract 14, last paragraph) |
| AC-KB-3 | Ring is checked as a painted decoration, not as visible contrast on a device | Contract 14 |
| AC-KB-9 | Token-level contrast, not pixels over the photo | Panel-over-photo contrast unmeasured (contract 17.8) |
| AC-LS-9, AC-LS-4 | Russian pixel widths measured in the test, not from a design drawing | Contract 17.19 |
| AC-WS-9 | Asserts the app sets no orientation lock; manifest resizability on Android 16 is not tested | Contract 17.16 |

Gaps found while mapping (reported to the lead, no ownership decision taken silently):
1. S03-0 has no acceptance criterion in the contract although the contract says it is in scope (contract 4.4). The plan adds design tests DT-0-1 to DT-0-8 for it and this design proposes that the contract owner add AC ids. OPEN (DD-2).
2. Journey J6 (notification tap) and DQ-12 (width-cap frame) have requirements but no AC. They are conditional stories S03-19 and S03-20 with design tests only. OPEN (DD-3).
3. AC-ST-3 lists nine rows of the "running" table but the table itself (contract S-4) has a row "set timer `phase == done`" and "idle"; the test must cover both (INFERENCE, no change needed).

### 1.9 Design decisions that tests must guard (test ids belong to the plan)

Tests: see the plan (`docs/phase2/s03/S03_TEST_PLAN.md`), epic table and section 10. The plan OWNS every test id (`DT-<story>-<seq>` and `AC-...`); this design only cites them. The table says WHAT each story's design decisions require a test to guard, with the plan ids from plan 8.7 (review decisions RV) and section 10. A decision with no plan id is reported to the plan author.

| Story | What must be guarded (design decision) | Plan ids |
|---|---|---|
| S03-0 | default build opens the journal with the cloud flag off and cloud pieces stay unwired; open failure gives `failedToOpen`; override forces `notEnabled`; Try again runs one attempt; backup exclusion covers the real journal tree and lands before the flag flip (RV-13) | DT-0-1 to DT-0-5; DT-0-6, DT-0-7, DT-0-8 |
| S03-01 | atomic `initIfAbsent`, migration from the first profile value only (RV-1); unreadable stored mode never overwritten, newer version read-only, corrupt replaced only by an explicit action (RV-2); wiped-uid guard (RV-14); one warm-up provider (RV-18a); account scoping, restore before first frame | DT-01-12 to DT-01-15; DT-01-1, DT-01-2, DT-01-3, DT-01-16 to DT-01-19; DT-01-20; DT-01-21; DT-01-6, DT-01-9 |
| S03-05 | bar to rail swap keeps the element tree (RV-6); rail label measurement memoised (RV-18c); reactive window size (RV-18b) | DT-05-3; DT-05-5; DT-02-3 |
| S03-06 | surface is a route: live re-placement while open, Back closes it, depth counter reset (RV-9) | DT-06-2, DT-06-3, DT-06-4 |
| S03-07 | strip hidden on provider exception; owner uid captured at start and strip hidden for another account (RV-4); driven transitions at `endsAt` and `endsAt + 10 min`, re-armed and cancelled (RV-8); animated dock padding (RV-18e) | DT-07-1; DT-07-8, DT-01-7; DT-07-9, DT-07-10, DT-07-3; DT-07-11 |
| S03-08, S03-09 | chooser Back equals Decide later, one offer per run, Home waits for the Day-3 decision (RV-7); invalid `:mode` redirects Home with no write (RV-15) | DT-08-7, DT-08-8, DT-08-9; DT-09-6 |
| S03-13 | digests discard a completion for another uid or generation, reset on uid change, binding shows LOADING (RV-3); recovery counts (RV-10); stale marker and unreadable sessions (RV-11); content-free logging (RV-16); labels (RV-19) | DT-13-8 to DT-13-15; DT-13-16; DT-13-12, DT-13-17; DT-13-18; DT-13-19 |
| S03-14, S03-15 | recovery notice and "may be incomplete" marker; stale line with Try again; source labels | DT-14-5, DT-15-4; DT-14-6, DT-15-5; DT-15-6 |
| S03-16 | cannot-check sheet for `binding`, `gaveUp`, `failedToOpen`; export or wipe failure keeps the user signed in and never shows "deleted"; export location outside backup (RV-12, RV-16) | DT-16-4 to DT-16-7, DT-16-2; DT-16-8 |
| S03-17 | tab shortcuts only on shell routes, `CallbackShortcuts` under an autofocus root (RV-18d) | DT-17-3, DT-17-4 |
| S03-20 | notification payloads through a fixed allow-list, session must be the user's own, tap ignored while signed out or onboarding (RV-15) | DT-20-5; DT-20-4 |

Every decision above has a plan id. Ids the plan author added for decisions that first had no test: DT-07-12 and DT-07-13 (timers are not auto-dispose, and a real timer survives rebuilds of all shell pages), DT-13-14 and DT-13-20 (load coalescing), DT-14-9 (`refreshIfStale` not called from `build`), DT-16-9 (sign-out call sites against the guard), DT-08-10 and DT-10-5 (account switch with the chooser or switcher open), DT-01-24 (the wipe removes the mode key), DT-01-25 (mode key only in SharedPreferences), DT-14-7 (deleted entry stale only until refresh), DT-13-24 (first-record label pinned), DT-13-23 and DT-14-8 (journal load cost, measure-only), DT-0-10 (no I/O while the journal is unbound).

## 2. Architecture per epic

Facts in this section come from `docs/phase2/s03/S03_CODE_MAP.md` (called "the map"; "map 4.1" = its section 1 line or item as cited, written `map <line>` where the map's own line numbers are meant) and carry the code path and line the map gives. Code paths are under `D:\Repo\Fitness_App_Phase2_s01`. Every new file name is PROPOSED. The ten risks of the map (map section 10) are resolved with PROPOSED decisions in the table of 9.3; this section says where each decision is applied. Two more risks found while writing are R11 and R12 in 9.3.

Conventions:
- Folders: the activity feature already has `data/` (pure Dart, may not import Flutter or Riverpod, FACT S02_DESIGN section 2), `repository/`, `state/` and `widgets/` (map 3, `mobile/lib/features/activity/`). Mode state is a new sibling feature `mobile/lib/features/modes/` with `data/`, `state/`, `widgets/`, `pages/` (PROPOSED). The architecture guards `mobile/test/core/architecture/pure_data_layer_guard_test.dart` and `import_graph_guard_test.dart` (FACT S02_DESIGN section 2) must be re-run when the folder is added; whether a new top-level feature folder needs an entry in the import graph allow-list is UNGROUNDED, and S03-01's first step is to read that test.
- Shell-level widgets live next to `main_shell.dart` in `mobile/lib/shared/widgets/` (map 20) and the HUD primitives stay in `mobile/lib/shared/widgets/hud/` (map 26).
- Providers follow the repository pattern: `Notifier`/`AsyncNotifier` with Riverpod (FACT map 36, 60); tests override providers.

### 2.0 Existing code each epic attaches to

| Attach point | Fact | Used by |
|---|---|---|
| `MainShell` (`mobile/lib/shared/widgets/main_shell.dart`) | `_paths` list lines 69-75; selected index by `location.startsWith` lines 98-101; `PopScope(canPop: location == '/home')` lines 111-122; `_AnnounceShellCanPop` line 176, kept because of an Android first-Back bug (129-149); Scaffold `extendBody: true`, transparent, `HudSkyBackground` body (123-127), `HudNavBar` as `bottomNavigationBar` (153-162); no `MediaQuery` or `LayoutBuilder` | S03-04, S03-05, S03-07, S03-17 |
| `HudNavBar` (`hud/hud_scaffold.dart:233-293`) | inputs `items`, `selectedIndex`, `onSelect`; pill at left/right 12, bottom 14 plus inset, height 72, `t.navBar` surface; each tab `Semantics` and 44 px minimum | S03-04, S03-05 |
| Clearance | `shellBottomObstruction` = bottom inset (`shell_insets.dart:34`); `HudScreenBody.bottomClearance` = 14 + 72 + inset + 24 (`hud_scaffold.dart:45-49`) with a `reserveNavBar` switch (31, 53-55) | S03-05, S03-07 |
| Router | `appRouterProvider` `app_router.dart:356`; non-shell routes 415-673; `ShellRoute` 674-699 with `_shellKey`; `_fadeThrough` 164; redirects 90-154; `_publicPaths` 70; onboarding exceptions 77 | S03-08, S03-09, S03-15, S03-06 |
| Home | `home_page.dart` `HudScreenBody` with about 20 children; Day-3 modal through `PrefsMomentRepository` lines 93-109; `homeNowProvider` pinned clock (`home_dashboard_providers.dart:52`) | S03-12 |
| Progress | `progress_page.dart` watches workout history (34-40); `ActivitySyncEntryCard` at line 55; `deriveProgress` in `progress_stats.dart:61` with local days and Monday weeks (35-47) | S03-14 |
| Timers | `setTimerProvider` (`set_timer_providers.dart:247`, state at 103-115); `restTimerProvider` (`rest_timer_providers.dart:209`, starts idle 143, wall-clock `endsAt` via `restClockProvider` 145-153, `restTimerVisibleProvider` 221); used by `mobile/lib/features/equipment/workout_player_page.dart` (367-375, 735, 976) | S03-07 |
| Journal | `ActivityJournal.list()` live entries without streams, `read(id)`, `listTombstones()`, `assessSignOut()` (`activity_journal.dart:13-99`, `journal_models.dart:226-243, 268-282`); `UidScopedActivityJournal` (`uid_scoped_activity_journal.dart:58`); wiring (`activity_wiring.dart:93-164`); watched from `FitnessApp.build` (`main.dart:675`) | S03-0, S03-13 to S03-16 |
| Per-uid prefs | `TrainingContextNotifier` (`training_context_providers.dart:45-84`), key `training_context.v1.$uid` (line 15) | S03-01 |
| Wipe | `DeviceLocalDataWipe.wipe(uid)` (`local_data_wipe.dart:267`), per-uid prefixes include `activity.` (210-223), exact keys list `personalKeys` (273) | S03-01 |

Map-to-contract timer note: the map lists "whether the timers are `autoDispose`" as UNKNOWN. The contract states the set timer is a plain, not auto-dispose, provider and the rest timer is app-scoped by design (FACT contract F23; map 40 for the rest-timer doc comment at `rest_timer_providers.dart:213-220`). This design relies on the contract statement and guards it with DT-07-12 (declaration check: fails if either becomes auto-dispose) and DT-07-13 (a real timer survives rebuilds of all shell pages).

### 2.1 EP-0 journal always open (S03-0)

Goal (FACT contract 4.4): the default build opens and recovers the local journal whatever the cloud flag says; cloud pieces stay behind `cloudSync`.

Changes (all PROPOSED, resolving map risk 1):
1. `mobile/lib/core/config/activity_flags.dart`: in `ActivityFlags.compileTime` (lines 33-36) the `ACTIVITY_LOCAL_JOURNAL` read gets `defaultValue: true`. The `const ActivityFlags(...)` constructor defaults (line 21) stay false, so every test that builds explicit flags keeps its meaning. `cloudSync` default stays false. `journalEnabled` stays `localJournal || cloudSync` (line 30). Effect: `activityFlagsProvider` (lines 53-54) defaults to a journal-on configuration; a build can still switch it off with `--dart-define=ACTIVITY_LOCAL_JOURNAL=false` and tests switch it off by overriding the provider. Details and the affected tests are in section 4.
2. `mobile/lib/core/wiring/activity_wiring.dart`: no logic change to `openActivityJournal` (line 41), `activityRootOverrides` (63) or the binding provider (101-164) beyond publishing the bind outcome (next item). `main.dart:377` already calls `openActivityJournal()` once before `runApp`; with the flag on this only creates the unbound scoped journal and does no I/O (map 181), so start-up cost does not change measurably (INFERENCE; guarded by DT-0-10).
3. New `journalAvailabilityProvider` (Notifier, app lifetime, file `mobile/lib/features/activity/state/journal_availability.dart`). Value (RV-3): sealed `JournalAvailability` = `notEnabled`, `binding`, `open`, `gaveUp`, `failedToOpen`. Derivation: flags say `!journalEnabled` -> `notEnabled`; a bind in progress or not yet started for the current uid -> `binding`; the journal is bound AND `boundUid == authUid` -> `open` (never `open` merely because a journal object exists: the old rule "otherwise open" is withdrawn); the retry schedule is exhausted -> `gaveUp`; a failed open or recovery -> `failedToOpen`. The binding provider (`activityJournalBindingProvider`, today a `Provider<void>`, lines 101-164) already retries a failed bind at 5 s, 15 s, 60 s, 5 min, 5 min (190-196, map) and its retry behaviour is unchanged. S03 adds an additive companion status Notifier in `core/wiring/activity_wiring.dart` (owned by lane L1) that publishes `binding(uid)`, `bound(uid)`, `gaveUp(uid)` and the recovery counts `recoveredAbsentCount` and `streamLostCount` taken from the journal recovery report (RV-10), and a `retryNow()` entry used by the "Try again" button. `journalAvailabilityProvider` also resets on sign-out. "Try again" is `retryNow()` and is disabled while busy (FACT contract 4.4, AC-PR-2). It does not replace the automatic schedule: ONE retry state machine serves automatic and manual attempts (GPT-PM round 1, MAJOR-01; FACT for the existing code, `activity_wiring.dart:101-164, 189-204`: one pending timer, `attempt(uid, generation, retryIndex)`, delays `kActivityBindRetryDelays` = 5 s, 15 s, 60 s, 5 min, 5 min, then only a 'gave up' log, a generation bump on every new auth value, the timer factory is the overridable `activityBindRetryTimerFactoryProvider`).

   States per generation (a generation is one auth value; a new auth value resets everything exactly as today): `Idle/Bound(uid)` (bound, no timer); `Attempting(source)` (exactly one `bindUid` in flight, source `automatic` or `manual`); `WaitingRetry(i, deadline)` (the last attempt failed, the automatic timer for index i is armed, availability `binding`); `GaveUp` (index reached 5 and the last automatic retry failed, no timer, availability `gaveUp(uid)`).

   Rules: (1) Single flight shared by both sources: at most one `bindUid` in flight; `retryNow()` while `Attempting` is a no-op that returns the busy state (a double tap makes one attempt); a due automatic timer that finds an attempt in flight does nothing and re-arms itself with the SAME index and delay (not consumed, not doubled). (2) A manual attempt never disables the automatic schedule: when `retryNow()` runs from `WaitingRetry(i, deadline)` and fails, the state returns to `WaitingRetry(i, deadline)` with the ORIGINAL deadline and index intact; the automatic attempt runs at the original deadline. (3) Success, manual or automatic: `Bound(uid)`, the pending timer is cancelled and the retry index resets; availability becomes `open` only when `boundUid == authUid` (RV-3). (4) `GaveUp` stops automatic attempts; `retryNow()` from `GaveUp` runs exactly one attempt; if it fails the state stays `GaveUp` and no new automatic loop starts; if it succeeds the state is `Bound(uid)`. (5) A new auth value (generation bump), sign-out or provider disposal cancels the pending timer and invalidates any in-flight attempt exactly as today, and a stale completion is discarded. (6) Every completion publishes the binding change (as today) and the bind status (`binding(uid)`, `bound(uid)`, `gaveUp(uid)`, recovery counts); `retryNow()` is exposed by the companion bind-status Notifier and implemented by the same controller object that owns the timer. (7) `failedToOpen` (the journal object could not be opened at all) has no automatic loop; it is left only by `retryNow()`, which re-runs one open plus one bind attempt under rule 1.

   Implementation: the closure inside `activityJournalBindingProvider` is refactored into a small controller class in `core/wiring/activity_wiring.dart` (lane L1) with behaviour-preserving automatic retries. The existing test file `mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart` stays valid UNCHANGED and is a regression guard of the refactor. Tests (ids owned by the plan): DT-0-5 (single flight), DT-0-11 (manual failure leaves the original automatic deadline), DT-0-12 (manual success cancels the timer and resets the index), DT-0-13 (`GaveUp`: no automatic attempts, one tap one attempt, no loop), DT-0-14 (a due automatic timer during an in-flight manual attempt is re-armed with the same index).
4. Unbound reads return empty (FACT `uid_scoped_activity_journal.dart:158-169`), so an empty list is also what an unbound journal returns. For that reason an empty list is NEVER read as "no activity" unless the availability is `open` (bound AND `boundUid == authUid`); while the availability is `binding` the dashboards show LOADING (RV-3). Signed-out users never reach the shell (INFERENCE from the redirects, map 14).
5. Everything cloud stays gated exactly as today: `activity_wiring.dart:182, 293, 301, 331` and `activity_sync_entry_card.dart:21` read `cloudSync` (map 178-179). No cloud code is touched.
6. Backup (new risk R11 in 9.3): with the journal opened in every build, the Android backup exclusions must cover the real journal directory. The rules exclude `journal`, `sources` and `quarantine` "directly under `getFilesDir()`" in both `backup_rules.xml` (lines 35-40, 46-52) and `data_extraction_rules.xml` (lines 28-43), and the constant is `kActivityBackupExcludedDirs` in `journal_layout.dart:28-32` (FACT). The map says the journal directory is `<app support>/activity_journal/<scopeId>` (map 68, `uid_scoped_activity_journal.dart:49-56`). VERIFIED FACT (RV-13, checked by the coordinator): the production journal root is `<support>/activity_journal/<scopeId>` (`uid_scoped_activity_journal.dart:47-55`; the generation writer is in `journal_generation_writer.dart:35-37`) and its children are `journal`, `sources` and `quarantine`, while the XML files exclude only `files/journal`, `files/sources` and `files/quarantine` (`backup_rules.xml:50-52`; `data_extraction_rules.xml:32-34` and `41-43`). The real tree is therefore NOT excluded today. The existing tests compare the XML with the constants only, so they could not see it. The fix is UNCONDITIONAL and lands before the default flip of `ACTIVITY_LOCAL_JOURNAL` (order inside S03-0 and in the commit sequence): (a) one constant for the scoped root (`activity_journal`) used by `fileActivityJournalFactory` AND by `kActivityBackupExcludedDirs`; (b) `<exclude domain="file" path="activity_journal" />` added to `backup_rules.xml` and to both sections of `data_extraction_rules.xml` (an excluded directory excludes its subtree, so every scope id is covered), with the three legacy names kept for `FileActivityJournal.openDefault`; (c) the exact-count assertions in `backup_rules_test.dart` and `backup_exclusion_test.dart` updated, and the claim at `journal_layout.dart:4-7` corrected; (d) DT-0-6 rewritten: in a temp directory with a faked `PathProviderPlatform.getApplicationSupportPath`, call `fileActivityJournalFactory()(activityJournalScopeId('u1'))`, start it, put one session, list every top-level entry of the support directory and assert that each has a `domain="file"` exclude with exactly that name in all three XML sections; it fails if the XML names `journal` while the code writes `activity_journal/...`; (e) accepted rollback model: the journal kill switch is build-time only (`--dart-define=ACTIVITY_LOCAL_JOURNAL=false`), and any journal-writing story (S04 and later) must not merge before DT-0-6 is green. The stream key is in the excluded secure-storage files, so a restored copy would not be decryptable (FACT `backup_rules.xml:38`), which limits but does not remove the issue.

Data flow: app start -> `FitnessApp.build` watches the binding provider (`main.dart:675`) -> auth user known -> bind `UidScopedActivityJournal` to the uid -> `journalAvailabilityProvider` = `open` -> dashboards `list()`.

### 2.2 EP-1 mode state (S03-01)

New files (PROPOSED), all under `mobile/lib/features/modes/`:

| File | Content | Layer |
|---|---|---|
| `data/mode_models.dart` | `AppMode` (train, ride, explore, body); `ChooserStatus` (absent, pending, migrated, resolved); `ModeAnswer` (unanswered, skipped, answered with a short value); `ModeState` value class (`selectedMode`, `chooserStatus`, `answers` map); `ModeAvailability` (a pure function from `AppMode` and flags to available or comingLater) | pure Dart |
| `data/mode_codec.dart` | Tolerant encode and decode of `ModeState` to one string; unknown or corrupt values decode to the default state and never throw (the `TrainingContextAnswer` precedent, map 65: unknown values count as unanswered) | pure Dart |
| `data/mode_store.dart` | Abstract `ModeStore`: `read(uid)` returns `ModeState?` (null = key absent) and `write(uid, ModeState)`; `PrefsModeStore` over SharedPreferences | store |
| `state/mode_providers.dart` | `modeStoreProvider`; `modeFlagsProvider` (section 4); `modeStateProvider` (`AsyncNotifier<ModeState>`); `modeChangedProvider` (event stream, one event per real change) | state |
| `state/mode_migration.dart` | Start-up migration provider (below) | state |

Public API in prose:
- `ModeStore.read(uid)` returns a three-way result (RV-2): `missing` (key absent), `value(state)`, or `unreadable(reason)` with reason `corrupt`, `newerVersion` or `unknownShape`.
- `ModeNotifier.build()` awaits `authUserProvider` (as `TrainingContextNotifier` does, map 60-65), remembers the uid and reads the store. `missing` gives `ModeState(selectedMode: train, chooserStatus: absent, answers: {})`. `unreadable` gives the same default state in memory with NO write at start, no chooser push, and a content-free reason code in the log. A `newerVersion` value makes the notifier READ-ONLY for the whole run: user choices are kept in memory and never written. A `corrupt` value is replaced only by an explicit user action (choosing a mode or answering a question). A stored mode that is currently unavailable (a flag rolled back) is coerced to `train` in memory and is NOT rewritten. An `AsyncError` while loading yields the default state, no chooser push and no writes (all RV-2).
- `selectMode(mode)`: refuses (returns a failed result) if the mode is not available or if the signed-in uid differs from the remembered uid (the guard at `training_context_providers.dart:68-73`); a change to the same mode does nothing and emits no event; otherwise it sets state first, emits `modeChanged(from, to)` and then awaits the write (the pattern at lines 73-77). A write that throws leaves the new mode active for the session and returns `saveFailed` (FACT contract AC-CH-6, S-3 error row).
- `resolveChooser(mode)`: sets `selectedMode` and `chooserStatus = resolved`; on a write failure the in-memory `selectedMode` is kept and `chooserStatus` stays `pending` in memory and on disk (AC-CH-6).
- `decideLater()`: `selectedMode = train`, `chooserStatus = resolved` (AC-CH-4).
- `answerQuestion(mode, answer)` and `skipQuestion(mode)`: write the per-mode answer.
- `initIfAbsent(InitSource source)`: the ONLY writer of the first chooser status, an atomic check-and-set inside the notifier (RV-1). Source `migration` writes `migrated`; source `onboarding` writes `pending`. It acts only on a `missing` store result, never on `unreadable`, and refuses a uid that is being or was wiped (RV-14). Whichever source arrives second finds the status already set and does nothing (AC-CH-8).
- `markResolved()`: used by the intro card "Not now" and "Choose a mode".

Lifecycle: `modeStateProvider` is app-scoped (not auto-dispose) and rebuilds when the auth uid changes (it watches `authUserProvider`). It is warmed during splash by ONE `Provider<void>` warm-up provider (`modeWarmUpProvider`) that `FitnessApp.build` watches next to the journal binding watch at `main.dart:675`; the warm-up provider starts mode state, the migration and the dashboard refresher listeners internally, so `FitnessApp.build` never `ref.watch`es an `AsyncNotifier` value and `MaterialApp` is not rebuilt on each mode choice (RV-18a). The value exists before the first Home frame (FACT contract 4.2: restore before the first Home frame; the router holds `/splash` up to 5 s while the profile loads, `app_router.dart:385-411`, so the warm-up has time). While the value is still loading, Home shows its pre-S03 content in the TRAIN order without a chip and does not push the chooser (no flash of a wrong lens beyond one frame; INFERENCE).

Start-up migration (`mode_migration.dart`, RV-1): started by the warm-up provider. It runs ONCE per process per uid and decides from a snapshot: the FIRST profile value loaded for that uid in this process. If that first value already has `hasCompletedOnboarding` true (`profile_models.dart:1132`, map 85) and the store result is `missing`, it calls `initIfAbsent(migration)`, which writes `migrated`. If the first value is not onboarded, the migration never runs for that uid in this process, even when the profile flips to onboarded later: that transition belongs to the onboarding hook, which writes `pending`. Result for the two interleavings (migration event first, hook first): a new user ends in `pending`; a cold start with an already-onboarded profile ends in `migrated`. This is AC-CH-8 (first half). A migration failure is logged with a fixed message, a content-free reason code and the exception type only, and never blocks start-up (RV-16).

Onboarding finish hook: `onboarding_page.dart` submits through `profileSubmitProvider` (line 181) and then navigates to `/home` (contract F24, lines 179-193). S03 adds one call between the successful submit and `context.go('/home')` (RV-1): the hook awaits `modeStateProvider.future`, checks `context.mounted` after the await, then calls `initIfAbsent(onboarding)` inside a try/catch. A failure is logged with a fixed message, a content-free reason code and the exception type only, and never blocks `context.go('/home')` (RV-16). For `/onboarding/edit` (an onboarded user, `app_router.dart:435`) the stored status is already set, so the call is a no-op (AC-CH-8, last clause).

Output event: `modeChangedProvider` emits only on a real change. Nobody on the timer side listens to it (R-M1, risk R8 in 9.3).

Offline: the whole epic is local (SharedPreferences); no network.

### 2.3 EP-2 chooser, questions, switcher, Record sheet (S03-08 to S03-11)

Routes (added through a separate file, see 9.2, spliced once into `app_router.dart`): `/mode-chooser`, `/mode-questions/:mode` and, for EP-4, `/sources` (names PROPOSED). All sit in the non-shell list (map 11) so no rail or bar shows on them (contract S-1, S-8). They are not in `_publicPaths` (line 70), so a signed-out user is redirected to `/login` and a not-onboarded user to `/onboarding` by the existing redirects (map 14-16): no new redirect rule (FACT contract 4.2: "no router redirect rule is added").

First-run chooser trigger (RV-7): `HomePage` listens to `modeStateProvider`. An `offeredThisRun` set (per uid) lives in a keep-alive provider and is set when the chooser is opened, so a Home to Profile to Home round trip never offers it again in the same run (a kill still leaves `pending`, so the next start offers it). Home first waits for the asynchronous Day-3 modal decision (`PrefsMomentRepository`, `home_page.dart:93-109`) to settle: no chooser is opened while that modal is pending or shown. Then, when the status is `pending`, it calls `context.go('/mode-chooser')` after the first frame; the contract (J1 step 2) specifies replace, which is kept over the review's `push` suggestion (see the disposition). System Back on the chooser behaves exactly like "Decide later": it writes `selectedMode = train` and `chooserStatus = resolved` (AC-CH-4), through a `PopScope` on the chooser; if that write fails the status stays `pending` (F-1). "Switcher: See all modes" uses `context.push` and pops back.

Route parameter validation (RV-15): `/mode-questions/:mode` must parse to an AVAILABLE `AppMode`; otherwise the route redirects to `/home` and nothing is written (test: DT-09-6).

Chooser screen (`pages/mode_chooser_page.dart`): one responsive screen built from `ShellLayout`-independent window info (section 2.6: pushed routes read the window size class through `WindowSizeInfo.of(context)`, which does not need the shell). Cards are `HudPanel` with the 9.1 extensions. Selection is local widget state until Continue; Continue calls `resolveChooser`. The grid rule and the 2x2 versus 4x1 choice are a pure function `chooserGridColumns(gridWidth, isShort)` in `data/`-free layout code (`widgets/mode_grid_layout.dart`) so AC-CH-10 boundary cases are unit-testable.

Questions (`pages/mode_question_page.dart`): a separate route, NOT a new step of `kOnboardingOrder` (map 83: the onboarding `PageView` is Phase 1 and resumes from a saved draft; adding a step would affect every onboarding user and the draft resume). It reuses the onboarding shell and input widgets that the contract names `ob_shell` and `inputs` (FACT contract F11, S-2); their exact file paths are UNGROUNDED here and are read in S03-09's first step. TRAIN question "Where do you train most?" writes the existing `TrainingContext` answer through `TrainingContextNotifier` (`training_context_providers.dart:45-84`) and is skipped when that answer is already answered or skipped (AC-Q-1). BODY question writes `answers[body]`. Refused options come from `ScanAccess` (contract S-2 and F21), disabled with the existing reason text.

Switcher and Coming-later: `widgets/mode_switcher_sheet.dart`, `widgets/coming_later_sheet.dart`, opened through the adaptive surface (2.6). A static guard keeps one instance (the `SyncConflictSheet` precedent in `mobile/lib/features/activity/widgets/sync_conflict_sheet.dart`, map 115).

Record sheet (`widgets/record_sheet.dart`): rows are built by a pure function `recordRowsFor(mode, context)` returning row descriptors (id, label key, destination, enabled, reason). Destinations are the existing routes: `/scan`, `/workouts`, `/form-check`, `/body-scan`, `/nutrition/add`, `/nutrition/weight` (contract S-5; the router has `/nutrition/*`, `/body-scan*`, `/form-check` as non-shell routes, map 11; the exact `/nutrition/add` and `/nutrition/weight` paths are UNGROUNDED and are asserted by AC-RC-3 against `app_router.dart`). "Today's workout" is present only when the existing scheduled-session provider has a session today (`screenedUpcomingSessionsProvider`, `todayDigestProvider`, map 123); the destination is the Home start target `/workout/:id?day=...` (`app_router.dart` lines 471-485); the exact provider item shape is UNGROUNDED and read in S03-11. Rows for body access and flags reuse the existing tile rules of the food and body-scan entry points (AC-RC-3).

Mode switch never resets a session: `modeStateProvider` is read only by Home, the switcher, the Record sheet, the chooser and the dock (for the pill label). No timer provider reads it, and `ActiveSessionStatus.mode` belongs to the session (a gym timer is always `train`), not to the selected mode, so the strip text cannot change on a switch (AC-ST-4, AC-SW-2).

### 2.4 EP-3 Today, This week, Progress (S03-12 to S03-14)

Detailed definitions are in section 3. Attach points:
- Pure aggregation: `mobile/lib/features/activity/data/activity_aggregates.dart` (pure Dart, allowed in `data/` because it imports only `ActivitySession`, `SportType`, `SourceRecord`), holding `SportGroup`, `groupOf(SportType)`, `SessionDigest`, `WeekTile`, `aggregateWeek(...)`, `todaySessions(...)`, `recentSessions(...)` and `sourceLabelOf(...)`.
- State: `mobile/lib/features/activity/state/activity_dashboard_providers.dart`: `activityDigestsProvider` (AsyncNotifier, reads the journal once, converts entries to digests), `activityWeekTilesProvider`, `activityTodayProvider`, `activityRecentProvider` (derived Providers), and `activityJournalRevisionProvider` (the refresh signal, section 3).
- Home: `home_page.dart` keeps `HudScreenBody` and gets stable keys `home.section.<name>` on its existing children, a chip in the greeting row, a lens that reorders children by key, and the "Activity today" card inserted under the day panel only when the digests exist for today. The reordering is a pure function `homeSectionOrder(lens)` over the key list so AC-HM-1/2 compare lists, not pixels.
- Progress: `progress_page.dart` keeps `FrostedScaffold`, `GlassAppBar` and its `ListView`; the new children are inserted at the positions in contract S-7 (after `ActivitySyncEntryCard` at line 55; the quiet slot after `NutritionEntryCard`'s gap). The list's fixed bottom padding 120 becomes `120 + ShellLayout.dockHeight` (2.6).
- Two stores (risk R4): the new widgets read only the journal; the existing tabs keep reading workout history. No number mixes the two (decision in 9.3).

### 2.5 EP-4 sources panel and sign-out warning (S03-15, S03-16)

Sources (`pages/sources_page.dart`, route `/sources`): `HudScreenBody` with `HudPanel` rows. Data: `sourcesSummaryProvider` derives from the digests (distinct `sourceId`, session counts, last `importedAt`; map 161) and from `journalAvailabilityProvider` for the app row; the capability text comes from `kCapabilityMatrix` (`device_source.dart:100-106`; the first part of the map was not read by the explorer, UNGROUNDED). No `DeviceSource` is called: only `FakeDeviceSource` exists (map 146) and `healthStatus()` is not used (FACT contract S-8). `provenance.first` as "primary source" is not guaranteed to be the highest-priority source after a merge (map UNKNOWN, `activity_merger.dart:42-72`); the label of a row uses the first record as the contract says (8.1) and the order issue is recorded as UNGROUNDED, (current behaviour pinned by DT-13-24).

Map-versus-contract note on Health Connect: `HealthService` and `HealthSyncCard` exist and can be authorised today (map 155-156), but their output is daily `HealthSnapshot` aggregates, not `ActivitySession` rows, and nothing is known to write Health Connect workouts into the journal (map UNKNOWN). AC-SRC-4 requires the Health Connect row to say "Not connected". Read literally, a Phase 1 user who has authorised Health Connect for daily steps would see "Not connected" on the sessions list. This design follows the contract text (the row describes workout-session import, which does not exist) and raises it as DD-7 (section 10).

Sign-out warning (`widgets/sign_out_warning_sheet.dart`, story S03-16): `assessSignOut()` gives entry, unsynced and stream-lost counts (`journal_models.dart:268-282`); `ActivityWipeCoordinator.onSignOut` and `ActivitySignOutHooks` exist but the app never calls them (`activity_journal.dart:102-141`, `activity_wiring.dart:99-100`, map risk 9). The contract assumes S03 builds the sheet (OD-8) while the map proposes leaving sign-out untouched; this design follows the contract assumption and records the conflict as DD-8. A GPX/FIT export already exists in `mobile/lib/features/activity/repository/activity_local_export.dart` (`ActivityExportFormat`, found by search, path and line 22); "Export first" calls it. The sign-out call sites are not in the map (UNGROUNDED); the first step of S03-16 is to enumerate every call to the auth sign-out method, and the sheet is invoked through one guard function `confirmSignOutWithLocalData(context, ref)` that every call site awaits. When the journal cannot be checked (availability `binding`, `gaveUp`, `failedToOpen`) the sheet offers Try again and the explicit "Sign out anyway" path, which GPT-PM round 1 asked to retain (F-42). "Sign out and delete from this device" uses `ActivityWipeCoordinator.onSignOut` after a second confirmation; its exact semantics must be read in the story's first step, and if it does not delete the journal of the departing uid the story stops and reports instead of inventing a deletion path.

### 2.6 EP-5 responsive shell (S03-02 to S03-07, S03-17)

New shared files (PROPOSED), in `mobile/lib/shared/widgets/` unless noted:

| File | Content |
|---|---|
| `window_size.dart` | Pure `classifyWindow(Size, {textScale})` returning `WindowSizeInfo{sizeClass (compact, medium, expanded), isShort, usesRail}`; `WindowSizeInfo.of(BuildContext)` is reactive (an `InheritedModel` or a `ConsumerWidget` path that depends on `MediaQuery.sizeOf` and the override provider), not a static lookup, so a resize rebuilds only dependants (RV-18b, DT-02-3); `windowSizeOverrideProvider` (null by default, set by tests) |
| `shell_layout.dart` | `ShellLayout` inherited object: `info`, `navigation` (bar or rail), `railWidth`, `contentStartInset`, `bottomClearance`, `dockHeight`; `ShellLayout.maybeOf(context)` is null on pushed routes. Also the rail measurement seam: `typedef RailLabelMeasurer = double Function(String label, TextStyle style, TextScaler scaler);` and `final railLabelMeasurerProvider = Provider<RailLabelMeasurer>(...)` (see "Rail label measurer" below) |
| `shell_destinations.dart` | `kShellDestinations`: ordered list of `ShellDestination{path, icon, labelOf(AppLocalizations)}` for `/home`, `/workouts`, `/scan`, `/progress`, `/profile`; replaces `_paths` (`main_shell.dart:69-75`) and builds both the `HudNavItem` list for the bar and the rail |
| `hud/hud_side_rail.dart` | `HudSideRail` (C-13) built from `HudSurface` with `t.navBar`, `HudNavItem`, 48/56 dp destinations, a pinned Record slot child, the "Main navigation" container semantics, form selection through `railLabelMeasurerProvider` only |
| `shell_dock.dart` | `ShellDock` (pill or strip) used by the bar presentation; the same strip and pill widgets are given to the rail slot |
| `adaptive_surface.dart` | `AdaptiveSurface.show<T>(context, builder, {anchorKey})` (C-15) |
| `mobile/lib/core/router/s03_routes.dart` | `List<RouteBase> s03Routes` for the new non-shell routes and a `noTransitionIfReduced` page builder helper |

Window-size class provider (C-14): the class is computed from the window width that `MediaQuery.sizeOf` reports (FACT contract 10.1). `MainShell` evaluates `WindowSizeInfo.of(context)` once per build and publishes `ShellLayout` with an `InheritedWidget`; pushed routes (chooser, Sources) call `WindowSizeInfo.of(context)` themselves because they are outside the shell (map 11). Boundaries are 600 and 840 inclusive at the lower end, short means height under 480, and the rail override applies at width 600 or more when short (contract 10.1, WS-1). The text scale does not enter the class; it enters only the rail form (`HudSideRail` measures the labels, contract WS-4). The override provider is the test seam; the real window size is set by `tester.view`.

MainShell structure (risk R7, resolved): the outer wrappers do not change. `PopScope(canPop: location == '/home')`, `_AnnounceShellCanPop` and the `context.go` tab switch stay exactly as in `main_shell.dart:111-162` and stay OUTSIDE the presentation swap; `back_navigation_test.dart` (map 251) must pass unchanged and green (AC-SH-2). The `ShellRoute` child sits under one `GlobalKey` (or a structurally identical slot) so a bar-to-rail or rail-to-bar swap reuses the same element and its state instead of rebuilding the tab page (RV-6, DT-05-3). The dock does not make content jump: the bottom clearance changes through `AnimatedPadding`, and the ticking strip and the rail Record slot sit in `RepaintBoundary` (RV-18e, DT-07-11). The rail label measurement (`TextPainter`) is memoised by locale, text scale, font family and label set, not re-run per pixel of a resize (RV-18c, DT-05-5). Inside the `Scaffold`:
- Bar presentation (Compact, Medium of height 480 dp or more): `bottomNavigationBar` remains `HudNavBar` built from `kShellDestinations`, wrapped in a container `Semantics` labelled "Main navigation"; bar width capped at 560 dp on Medium. The dock is NOT put inside `bottomNavigationBar` (the nav bar draws itself with fixed insets, `hud_scaffold.dart:263-273`, and its behaviour inside a column is unknown); it is a `Positioned`/`Align` child of a `Stack` around the body, bottom offset 14 + 72 + inset + 12 (PROPOSED).
- Rail presentation (width 840 or more, or width 600 or more with height under 480): no `bottomNavigationBar`; `extendBody` is false (risk R6); the body is a `Stack` of the background and a directional row `[rail footprint, content pane]` (12 inset + rail width + 12, start side, mirrored in RTL).
- Dock visibility is computed in `MainShell` from `activeSessionStatusProvider` and the location: strip on all five tabs when a session is active; pill on `/home`, `/workouts`, `/progress` otherwise (bar presentation); rail: the Record slot is always mounted (contract 10.4). `MainShell` reads a coarse selected value (kind and state only, `select`) so the seconds tick does not rebuild the whole shell.

Rail label measurer (seam added after the plan review, TP-1): `mobile/lib/shared/widgets/shell_layout.dart` (lane L4a) declares `typedef RailLabelMeasurer = double Function(String label, TextStyle style, TextScaler scaler);` and `final railLabelMeasurerProvider = Provider<RailLabelMeasurer>(...)`. The default implementation measures with `TextPainter` and is memoised by (locale, text scale, font family, label set) (RV-18c). The rule "the rail is extended (240 dp) when the window is 1200 dp or wider, or when the widest measured label plus 16 dp is more than 96 dp" reads the widest label ONLY through this provider; no other code measures the labels. Tests override the provider with a fixed-width stub: 70 dp gives the 96 dp rail and 90 dp gives the 240 dp rail. Reason: the project loads no real font in tests (default test font Ahem, no `loadFont`, `FontLoader`, `flutter_test_config` or `google_fonts` in `mobile/test`), so a font-measured label is wider than 96 dp and font-measured expectations alone are vacuous for the 96 dp form (TP-1). Plan ids that use it: AC-WS-3b, DT-05-2, DT-05-5.

Clearance functions (risk R6, resolved; also answers contract UNGROUNDED 17.5 and 17.18): `ShellLayout` carries `bottomClearance` and `contentStartInset`.
- Bar presentation: `bottomClearance = 14 + 72 + bottomInset + 24` plus `dockHeight + 12` while the dock shows. This equals today's value when the dock is empty (`hud_scaffold.dart:45-49`).
- Rail presentation: `bottomClearance = bottomInset + 24`, `contentStartInset = 12 + railWidth + 12 + 16` (contract 10.4, AC-WS-8).
- `HudScreenBody` (map 205) reads `ShellLayout.maybeOf(context)`: if null (pushed routes) it behaves exactly as today including the `reserveNavBar` switch (31, 53-55); if present it uses the layout's values. `shellBottomObstruction` (`shell_insets.dart:34`) keeps returning the plain bottom inset and is not used for shell clearance. Progress uses `ShellLayout` explicitly because its `ListView` has fixed padding (contract F13). Before editing, S03-05 enumerates every user of `bottomClearance`, `shellBottomObstruction` and `reserveNavBar` (map 192: six uses in `shell_insets.dart`) and records the list in its change record; AC-ST-6 and AC-WS-8 then assert the result on every tab.

Record strip and pill reading the timers: `activeSessionStatusProvider` (Provider, app lifetime, file `mobile/lib/features/workouts/state/active_session_status.dart`) watches `setTimerProvider`, `restTimerProvider` and `restClockProvider` and applies the table of contract S-4: set timer phase gettingReady, work or rest -> running or paused; rest timer not idle and (running now, paused, or finished less than 10 minutes ago) -> resting, paused or rest finished; set timer wins when both apply; `done`, `idle` and rest finished more than 10 minutes ago hide the strip. Fields: kind, title, mode (always `train` for these two sources), state, elapsed or remaining, `destination`, `ownerUid`. A second provider `activeSessionOwnerProvider` (Notifier of `ActiveSessionOwner?`, value `{uid, destination}`) is written by `workout_player_page.dart` where a set or rest timer is started (call sites near lines 367-375, 735, 976, map 39): the owner uid is captured at that moment from the signed-in user, in the same place that writes the destination route, stored together with it, and never recomputed from the current auth (RV-4). Empty owner or empty destination means `/workouts` (AC-ST-5). `ActiveSessionStatus` hides the strip and the pill when `owner.uid` differs from the current uid, and the owner is cleared by an explicit `ref.listen` on the status; no provider writes to another provider from inside `build`. The timers themselves are not touched by S03. Another account therefore never sees the previous account's workout (F-11 in section 7).

Driven time transitions (RV-8): `ActiveSessionStatus` owns one-shot timers created through an injectable timer-factory seam: one at `endsAt` (resting becomes "rest finished") and one at `endsAt + 10 minutes` (the strip hides). They are cancelled with `ref.onDispose` and re-armed whenever a timer state changes, so the table of contract S-4 holds without any widget polling (DT-07-9, DT-07-10, DT-07-3). The map UNKNOWN "which provider marks a workout session in progress" is avoided: the status depends only on the two timers, as the contract defines it. The visible seconds tick is a widget-local ticker inside the strip, wrapped in a `RepaintBoundary` (not a provider), and the semantics label changes only at minute boundaries (contract R-S4, AC-A11Y-4).

Adaptive surface (C-15): `AdaptiveSurface.show` picks, from `WindowSizeInfo` only (never the input device): modal bottom sheet (Compact), bottom sheet capped at 560 dp (Medium), anchored popover (Expanded) for the switcher and Record sheet; centred dialog capped at 480 dp for Coming-later, sign-out and Day-3 on Medium and Expanded (contract 10.6). Every placement (bottom sheet, popover, side sheet, dialog) is a ROUTE (`ModalBottomSheetRoute`, `PopupRoute` or `RawDialogRoute`) whose builder reads `WindowSizeInfo` live, so the placement is re-evaluated while the surface is open (RV-9, DT-06-2); system Back and `PopScope` close it (DT-06-3). It records an open-surface depth in a small provider so the shortcut layer knows a modal is open; the depth is decremented in `route.completed.whenComplete` inside try/finally and is also reset on account change (DT-06-4). Reduced motion: surfaces use the no-animation style when `disableAnimations` is true; the Flutter SDK version, and therefore whether `showModalBottomSheet` accepts an animation style, is UNGROUNDED (not in the map) and S03-06's first step reads `mobile/pubspec.yaml`; if unsupported the surface is a custom route with a zero-duration transition. New full-screen routes use `noTransitionIfReduced` instead of `_fadeThrough` (`app_router.dart:164`), because `_fadeThrough` ignores reduced motion (FACT contract 12, audit).

Keyboard and pointer (S03-17): an `AppShortcuts` widget supplied in the `builder:` of `MaterialApp.router` (`main.dart` near line 693) reads `appRouterProvider` through Riverpod, so it needs no router context. It uses `CallbackShortcuts` under an autofocus root `Focus` (RV-18d, DT-17-3) and binds the contract set (modifier + 1 to 5, + Shift + R, + Shift + M, + `[`, + `,` on Apple platforms, Esc handled by the surfaces themselves). The tab shortcuts (modifier + 1 to 5) act only when the current route is a shell route; on pushed pages such as the workout player or the scanner they do nothing (DT-17-4). Shortcuts are inactive when an editable text has focus or when the open-surface depth is above zero. Limit: legacy modal dialogs that do not go through `AdaptiveSurface` are not tracked, so a shortcut can still fire beneath them (recorded as a known limit; contract section 16 lists the legacy HUD limits). The Mac menu bar is not built (no macOS target).

## 3. Dashboards: Today, This week, Progress

Contract-derived rules that already bind this section (FACT, contract S-6, S-7, 8, 11): the week starts on Monday in the device time zone, injected as a function so tests control it (OPEN-1, DQ-10 to align with the existing Home week rule); `strength` never appears; sport groups are Walk and hike, Run, Ride, Swim, Row, Other; unknown is shown as "No data"; estimates carry "Estimate"; no energy and no cross-group total; units are metric; the merger already de-duplicates by session id, so the dashboard never merges.

Facts used (map section 3): `ActivitySession` fields and the nullable `ActivitySummary` doubles (`activity_session.dart:65-156`, `activity_summary.dart:6-43`; a missing value reads back as null, `toJson` writes only set fields lines 84-89); the effective value of a field comes from `SummaryProjection.effective(s)` (`summary_projection.dart:94`); the journal read API is a one-shot `list()` returning live entries without streams and without range or sport filters (`activity_journal.dart:13-99`); existing aggregates use local days and Monday week starts (`progress_stats.dart:35-47`) and run on the main isolate; `ProgressStats.empty` is all zeros (`progress_stats.dart:24-30`); no sessions provider or day or week function exists, so all of it is built.

### 3.1 Inputs and the digest

One read path: `activityDigestsProvider` (AsyncNotifier, file `mobile/lib/features/activity/state/activity_dashboard_providers.dart`) watches the auth uid and the bind status and calls the bound journal's `list()` once per refresh (section 3.7). Every load carries the `ownerUid` and a generation counter; a completion whose uid or generation differs from the current ones is DISCARDED (RV-3). The cached value is a `DigestSnapshot{ownerUid, loadedAt, lastLoadFailedAt, digests, unreadableSessions, recoveredAbsent, streamLost}`. On a uid change or sign-out the provider resets SYNCHRONOUSLY to loading before the first frame under the new uid, and a previous value is reused only when its `ownerUid` equals the current uid. Each `JournalEntry` is converted into a `SessionDigest`, a small immutable record: `id`, `startUtc`, `sportGroup`, `movingTimeS?`, `distanceM?`, `primarySourceId?`, `primarySourceKind?`, `syncState`, `streamLost`. Metric values are taken from `SummaryProjection.effective(session)`, never from raw `summary` fields, so explicit user values and adopted cloud values apply (PROPOSED). How `effective` treats a field with neither a derived nor an explicit value is UNKNOWN (map); the digest builder wraps the call: a null or missing result is "missing" (never zero; AC-PR-4 pins this with a walk that has no distance), while a call that THROWS makes the session an `unreadableSession` (RV-11): it is counted separately in the snapshot, added to the recovery notice (3.6), and never enters the "k of n sessions have a value" counts as an ordinary missing value (DT-13-12, DT-13-17). Streams are never loaded (`list()` omits them). Entries with `session.sport == strength` are dropped at this step (FACT contract OD-5, AC-PR-5). Entries deleted by the user are not in `list()` (live entries only, map 108), so tombstoned sessions never reach the dashboard. Read-only sessions (`isReadOnly`, `schema > kActivitySchema`, map 99) are included in counts and metrics like any other.

No merge happens here: de-duplication is already done at ingest by the merger and by the journal upsert on `act_<sha1>` ids (FACT S02_DESIGN section 2, map 100); a session id appears once in `list()` (AC-PR-6 tests the journal fake upsert).

### 3.2 Time rules

- Zone: the device local zone. A session belongs to the local day or week of `startUtc.toLocal()` in the device zone, NOT of its own recorded `utcOffsetMinutes` (FACT contract AC-HM-3 and AC-PR-7: "converted to the device zone"). The recorded offset is used only to display the local start time of the session on a row, if at all (PROPOSED: rows show the date in the device zone, to stay consistent with the grouping).
- Clock: injectable. Home already has a pinned clock, `homeNowProvider` (`home_dashboard_providers.dart:52`, introduced because a golden was clock-dependent). Progress and Home use that one provider so both tabs agree and no third clock exists. The time zone is read from `DateTime.toLocal()`; tests set the zone through a small `ZoneFn` parameter of the pure functions (a function from UTC `DateTime` to local `DateTime`), because the VM test zone cannot be changed per test (AC-PR-7 needs two offsets).
- Day: `[00:00, 24:00)` local on the day of `now`.
- Week: Monday 00:00 local (inclusive) to the next Monday 00:00 (exclusive). This is the rule of `progress_stats.dart:35-47` (map 130); the S03-13 first step reads the helper names there; if they are private they are extracted to a shared pure file with no behaviour change, so Progress's existing `deriveProgress` and the new code share one definition (resolves contract DQ-10 and OPEN-1 for Progress). The Home week section (`weekStripProvider`, `home_dashboard_providers.dart:54`) was not read by the map; its week-start rule is UNGROUNDED and S03-12's first step compares it. If it is not Monday, the new "Activity today" card is unaffected (it is a day, not a week) and the mismatch is reported as a new OPEN decision (DD-9); no third rule is introduced.
- Daylight-saving days have 23 or 25 hours; local-date comparison uses calendar dates, not 24-hour arithmetic (PROPOSED). A session at 23:30 Sunday belongs to the week starting the preceding Monday; 00:10 Monday belongs to the new week (AC-PR-7).

### 3.3 Today (Home, S-6)

`activityTodayProvider` returns the digests whose local start date equals the local date of `now`, sorted by `startUtc` descending, ties by `id`. The card shows at most 3 rows and a non-interactive "+n more" line (contract C-5). The card exists only when the list is non-empty and the availability is `open` (AC-HM-3); it is absent in every other state, silently (contract S-6). No zero card.

### 3.4 This week (Progress S-7b)

For the week window W and each sport group g (groups: Walk and hike = walking, hiking; Run = running, trailRunning; Ride = cycling, indoorCycling, mountainBiking; Swim = swimmingPool, swimmingOpenWater; Row = rowing; Other = other; `strength` excluded; the 12 `SportType` values are all handled, map 49, and the mapping is an exhaustive `switch` so a new sport fails to compile until it is placed in a group):
- `sessions(g)` = number of digests in W with group g. Each session is counted in exactly one group (AC-PR-11).
- `time(g)` = sum of `movingTimeS` over digests in W and g where the value is not null; `timeContributing(g)` = how many of those digests had a value. The tile shows the sum and, when `timeContributing < sessions`, the hint "Time from {k} of {n} sessions" with k = `timeContributing`, n = `sessions` (FACT contract S-7b, `activityTimeFrom`). When `timeContributing == 0` the tile shows "No data" for time.
- `distance(g)` = the same rule over `distanceM`, with the same "k of n" count; walks without a distance show "No data" for distance (AC-PR-4). A reported value of zero is a value and is summed and shown as zero; only null means missing.
- No energy, no heart-rate figure, no cross-group total of sessions, time or distance (FACT contract 11 rule 3). Units: metric only, formatted by `intl` with the resolved locale (AC-PR-10).
- Tiles appear only for groups with at least one session in W. If W has none but older sessions exist, the panel shows `progressThisWeekEmpty`. The selected mode sorts its groups first (EXPLORE: Walk and hike, Run; RIDE: Ride; others in the fixed order above) and never hides one (contract 8.4).
- "Estimate" marker: no value shown in S03 is classified as an estimate (time and distance come from recorded sessions; explicit user edits are values, not estimates). The marker is a component capability fed by a predicate `isEstimate(field, session)` that returns false in S03; how a source marks a derived value is UNGROUNDED (map UNKNOWN on `effective`), so the marker is built but never shown until a later sprint defines estimates (PROPOSED; plan DT-14-4 covers the Estimate marker).

### 3.5 Recent activity and sources

`activityRecentProvider`: the 5 latest digests by `startUtc` descending (ties by id). "See all" is not built (contract DQ-5). A row's source label follows contract 8.1: `app` -> "Recorded in this app", `health_connect`, `healthkit`, `wear_os`, `ble_*`, otherwise by `SourceKind`, a record whose kind is missing or not one of the five values -> "Unknown source" (RV-19); a parsed `fileImport` -> "File import" (contract 8.1, kept: the contract says the parser maps unknown names to `fileImport`, so the label for that value stays "File import"); empty provenance -> "Unknown source"; with several provenance records "+{k} sources". Because the map could not establish that `provenance.first` is the highest-priority source after a merge, the label shows the first record as the contract states and DT-13-24 records the current behaviour; a wrong-priority label is a known limit (UNGROUNDED).

### 3.6 State matrix

| State | Condition | Home "Activity today" | Progress | Sources app row |
|---|---|---|---|---|
| LOADING | availability `binding`, or `open` but digests not yet loaded (never shown as EMPTY while `binding`, RV-3) | nothing (inserted later without moving the viewport) | Sources row only | chip text "Checking" (at most 1 s) |
| EMPTY | `open`, zero digests | absent | Sources row only | "Ready" |
| PARTIAL | some digests lack time or distance | rows show "No data" for the missing metric | tile shows "No data" or the "k of n" hint | "In use" |
| SUCCESS | `open`, at least one digest ever | card if any today | "All activity" block | "In use" |
| ERROR | `failedToOpen`, `gaveUp`, or `list()` throws with no earlier value for this uid | absent, no new error text | Sources row plus error panel and one Try again | "Problem" plus Try again |
| NOT-AVAILABLE | `notEnabled` (tests and opt-out builds only) | absent | Sources row only | "Not active" line, no retry |
| STALE (internal) | a refresh is running over an existing value of the SAME uid (a value is reused only when its `ownerUid` equals the current uid) | the same-uid value is shown until the new one arrives | same | same |

Stale marker (RV-11, replaces the earlier keep-the-old-value rule): when a refresh fails after a success for the SAME uid, the value is kept, `lastLoadFailedAt` is set, Progress shows one line "Showing data from <time>" (`activityStaleNotice`) with Try again, and the Sources app row shows a "Problem" chip. A previous value of ANOTHER uid is never kept (test: DT-13-10, another account's data is never shown). The error panel is shown only when there has never been a value for this uid. The notifier catches errors inside its own load method, so a failed refresh does not turn the state into `AsyncError` when a same-uid value exists. The failure is logged with a fixed message, a content-free reason code and the exception type only (RV-16).

Recovery notice (RV-10, RV-11): when `recoveredAbsent + streamLost + unreadableSessions` is above zero, Sources and Progress show one plain line "n activities could not be restored on this device" (`activityRecoveryNotice`), and the "All activity" block and tiles carry a "Totals may be incomplete" marker (`activityMayBeIncomplete`) while the count is above zero. Aggregates never claim completeness in that state. The existing `activityStreamLost` chip ("Route not available on this device") stays for the per-row stream-lost state.

An offline device changes nothing: nothing here uses the network.

### 3.7 Refresh signal

A local-only journal publishes no change notification (`_publishBindingChange` returns early without `cloudSync`, `activity_wiring.dart:180-187`, and `list()` is a one-shot future, `activity_journal.dart:35`; map risk 2). `activityDigestsProvider` therefore reloads on (RV-3): (1) the bind completing for the current uid (the `bound(uid)` event, including after Try again); (2) app resume, reusing the existing `_FitnessAppState` lifecycle callback in `main.dart` (NO second `WidgetsBindingObserver`); (3) the Home or Progress tab becoming visible after more than 60 seconds since the last load, checked in the page `initState` or `didChangeDependencies` through `ref.read(...).refreshIfStale()`, never in `build`; (4) pull-to-refresh or the Try again button; (5) a bump of `activityJournalRevisionProvider`, a counter that every future writer (recorder, import, delete, sync conflict resolution) increments; S03 has no writer, so the counter is only the seam and has a unit test. A uid change is not a reload trigger but a reset (3.1). Coalescing is owned by the notifier itself: one in-flight future plus one dirty flag, not `ref.invalidate`; while a load runs, further requests set the dirty flag and trigger exactly one more load (DT-13-14, DT-13-20).

### 3.8 Computation location and the measured-budget argument

Decision (PROPOSED): `list()` and the digest conversion run on the UI isolate (the journal object holds file handles and keys in the main isolate, so it cannot be passed to another isolate without redesign); the aggregation functions are pure and take only plain data (`SessionDigest` lists, `now`, a zone function), so they can be moved to a background isolate without code change if the gate below fails.

Argument, with what is known and what is not:
- Expected sizes (INFERENCE, not measured): one active user logs about 300 sessions a year, so a five-year journal holds about 1,500; a heavy outlier 10,000. The synthetic corpus in `mobile/test/support/synthetic_activity_corpus.dart` (map 245) can generate these sizes.
- Aggregation is one pass over n digests with constant work per digest (a date comparison, a group lookup, two additions). For n = 10,000 that is on the order of 10^4 simple operations, far below one 16.7 ms frame on any phone this app supports (INFERENCE; no measurement exists in the repository).
- The dominant cost is not the aggregation but `list()` (file reads, JSON decode, possibly decryption). Its cost at thousands of entries and whether it decrypts record bodies are UNKNOWN (map 120; `file_activity_journal.dart` was not read). `list()` is asynchronous, so waiting on file I/O does not block the UI, but JSON decode and decryption between awaits do. This is the S02 open item "heavy work off the UI isolate" (S02_DESIGN section 17, item 20) and is not closed by S03.
- Existing aggregates (`progress_stats.dart`) already run on the main isolate (map 121), which is the precedent for the aggregation.

Release gate for heavy work (the test agents, `performance-optimizer` or `e2e-runner`, measure; the coordinator does not run it; thresholds are PROPOSED, not measured):
- G1: aggregation over 5,000 digests takes at most 2 ms and over 20,000 digests at most 10 ms in the Dart VM test harness, median of 20 runs. The harness is faster than a phone, so G1 is a regression tripwire, not a device claim.
- G2: `list()` plus digest conversion on a real temporary journal directory (the fixtures in `scoped_journal_world.dart` and `journal_harness.dart`) with 5,000 sessions takes at most 250 ms end to end in the harness and does not exceed 16 ms of continuous synchronous work between awaits (measured with a timeline of await points).
- G3: loading never happens inside a widget `build`; it only runs from providers.
- If G1 fails, the aggregation moves behind `Isolate.run` in S03-13 (the data is plain, so this is an additive change). If G2 fails, S03 still ships (the first Home or Progress paint does not wait for the list), but the finding is recorded as an S02 carry-over with the measured numbers and reported to the operator as a new OPEN decision (DD-10: accept the cost for launch, or schedule the journal-side fix before S05, when real sessions arrive). Until S05 the journal is empty for nearly every user (INFERENCE I1 of the contract), so the practical exposure in S03 is small.
- Evidence format: exact head revision, command, corpus size, median and worst values, recorded in the test findings file.

## 4. Flags and configuration

### 4.1 Current state (FACT, map section 5)

`ActivityFlags` (`mobile/lib/core/config/activity_flags.dart`): `cloudSync` and `localJournal` default to false in the constructor (line 21); `journalEnabled = localJournal || cloudSync` (line 30); `compileTime` reads `bool.fromEnvironment('ACTIVITY_CLOUD_STREAMS')` and `bool.fromEnvironment('ACTIVITY_LOCAL_JOURNAL')` (lines 33-36); `activityFlagsProvider` defaults to `compileTime` (lines 53-54). Readers: `activity_wiring.dart:41` (`openActivityJournal` returns null if not `journalEnabled`), `:63` (`activityRootOverrides` returns none), `:102` (the binding provider does nothing), `:182, 293, 301, 331` (cloud paths, gated by `cloudSync`), and `activity_sync_entry_card.dart:21` (hidden unless `cloudSync`). `main.dart:377` calls `openActivityJournal()` once before `runApp`.

### 4.2 Values after S03

| Flag | Before | After S03 | Where |
|---|---|---|---|
| `ACTIVITY_LOCAL_JOURNAL` (`localJournal`) | false | true by default in `compileTime` (`defaultValue: true`); `--dart-define=ACTIVITY_LOCAL_JOURNAL=false` still switches it off | `activity_flags.dart:33-36` |
| `ACTIVITY_CLOUD_STREAMS` (`cloudSync`) | false | false (unchanged) | same |
| `ActivityFlags(...)` constructor defaults | false, false | unchanged, so explicit flag objects in tests keep their meaning | line 21 |
| `MODE_RIDE`, `MODE_EXPLORE` (new, `ModeFlags.rideEnabled`, `exploreEnabled`) | n/a | false (Ride and Explore are "coming later"; S05 and S06 flip them) | new `mobile/lib/features/modes/state/mode_flags.dart` |
| Train and Body availability | n/a | always available; the inner Body features keep their own `BodyScanFlags`, `FOOD_AI`, `FOOD_LOOKUP` (map 185, contract F21) | no new flag |
| Responsive shell, rail, large-screen layouts | n/a | always on (operator decision: NOW); no flag | none |
| Paywall or entitlement gates | none | none; no entitlement check is added (D-9 default, contract OD-3) | none |

Why `defaultValue: true` and not a constant `journalEnabled`: the opt-out stays possible for a build or a test without code change, the cloud path remains independent, and explicit `ActivityFlags(...)` objects keep their meaning. The map listed three options (change the `localJournal` default, add `defaultValue: true`, make `journalEnabled` always true); the second is chosen because it changes one expression and keeps the flag matrix meaningful (risk R1, PROPOSED).

### 4.3 How flags are read and tested

- Reading: `ref.watch(activityFlagsProvider)` for journal and cloud state; `ref.watch(modeFlagsProvider)` for mode availability; `ModeFlags` follows the `BodyScanFlags` pattern (compile-time `bool.fromEnvironment`, a Provider with the compile-time default, map 185). Widgets never call `bool.fromEnvironment` themselves.
- Compile-time constants cannot change inside one test run, so tests set flags by overriding `activityFlagsProvider` and `modeFlagsProvider` with explicit objects. The one thing a test cannot do is read a different `--dart-define`; `compileTime` is therefore covered by a single unit test that asserts the default values of the unmodified environment (journal on, cloud off, ride and explore off).
- Cloud wording: every sync chip and sentence is built only when `activityFlagsProvider.cloudSync` is true (AC-REG-4, contract 8.5). `ActivitySyncEntryCard` already hides itself without `cloudSync` and is left alone.
- `notEnabled` is derived from `!journalEnabled` and is reachable only by override or the opt-out define.

### 4.4 Tests that change or are added (named exactly)

| Test file | Change | Story |
|---|---|---|
| `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart` (map 170) | The row "compile-time default => journal off" becomes "compile-time default => journal enabled, cloud off"; the explicit `ActivityFlags()` row stays "all off" | S03-0 |
| Any other test that reads `ActivityFlags.compileTime`, `activityFlagsProvider` without override, or pumps `FitnessApp` | UNGROUNDED which ones exist; S03-0's first step searches `mobile/test` for these three names and lists them in its change record; each is updated to override the flags explicitly rather than rely on the default | S03-0 |
| `mobile/test/features/activity/` (new file `journal_availability_test.dart`) | DT-0-1 to DT-0-5 (default open, cloud flag false and true, open failure, `notEnabled` override, retry once) | S03-0 |
| `mobile/test/android/backup_rules_test.dart` (exists, map 256) | DT-0-6 (rewritten, RV-13): every top-level entry the real journal factory creates in the support directory has an exact `domain="file"` exclude in all three XML sections; exact-count assertions updated; also `backup_exclusion_test.dart` | S03-0 |
| `mobile/test/features/modes/mode_flags_test.dart` (new) | defaults and availability table | S03-01 |

Forbidden by the operator rules and not done: running the whole test tree to find affected tests; the search above is a text search, and only the named files are run.

## 5. Persistence, account scoping and Phase 1 upgrader

Contract-derived requirements already fixed (FACT, contract 4.2): fields `selectedMode`, `chooserStatus` (`absent`, `pending`, `migrated`, `resolved`), `answers[mode]` (unanswered, skipped, answered); writes are awaited before the navigation they precede; state is restored before the first Home frame. The contract stores state per device and leaves per-account behaviour to DQ-2. The operator's brief for this design requires an account-scoped format with the same pattern as the S02 journal binding, sign-out, account switch, account deletion and backup exclusion rules.

### 5.1 Storage

- Store: SharedPreferences (the same mechanism as `training_context.v1.$uid`, `activity.cloudStreamsConsent.$uid` and the other per-uid keys, map 53-57). Not `AppSettings`: those settings are device-wide and not account-scoped (`settings_repository.dart:12`), so using them would leak the mode across accounts (risk R3).
- Key: `activity.mode.v1.<uid>` (PROPOSED). It starts with `activity.` and ends with `.<uid>`, which is the shape the account-deletion wipe already removes (`local_data_wipe.dart:210-223`, `_perUidFeaturePrefixes` includes `activity.`, map 78).
- Value: one string (PROPOSED), a compact JSON object: `{"v":1,"mode":"train","chooser":"pending","answers":{"train":"a:gym","body":"s"}}`. `mode` is an `AppMode` name; `chooser` is one of `pending`, `migrated`, `resolved`; `answers` values are `u` (unanswered), `s` (skipped) or `a:<value>`. A missing key means chooser status `absent`. Unknown or corrupt content is reported as `unreadable` and the in-memory state is the default (never written, see the read result below); unknown mode names fall back to `train` in memory only; unknown answer values count as unanswered (the tolerance of `TrainingContextAnswer`, map 65). A newer `v` is read tolerantly and never rewritten by an older reader (the S02 forward-compatibility rule, FACT S02_DESIGN 3.3).
- Why a single value: one atomic write per change, no partial state between `mode` and `chooser`.
- Read result (RV-2): the store returns `missing`, `value` or `unreadable(corrupt | newerVersion | unknownShape)`. Only `missing` is treated as "no key"; `unreadable` is never overwritten at start (2.2). A newer `v` is read-only for the whole run. This replaces the earlier rule that corrupt content decodes to `absent` and may be rewritten.
- Explicit unanswered value for Phase 1 upgraders (map risk 3): the upgrader has no key (`missing`); the start-up migration then WRITES `chooser = migrated` immediately through `initIfAbsent(migration)` (AC-CH-8), so "upgrader" is an explicit stored state and not an absence that later code could mistake for a new account. Question answers start as `u` (not present in the map means `u`).
- Write order: state first, then the awaited write (the pattern at `training_context_providers.dart:73-77`); navigation that depends on the write waits for it (FACT contract 4.2).

### 5.2 Account scoping

- The notifier watches `authUserProvider`, remembers the uid it loaded for and refuses a write when the signed-in uid differs (`training_context_providers.dart:68-73`). A sign-in as another account rebuilds the provider from that account's key.
- Account switch on one device: each account has its own key, so a second account that has never used S03 has no key. If its profile is onboarded the migration writes `migrated` for it (it sees the intro card once); if not onboarded it stays `absent` until its own onboarding finishes and writes `pending`. This is the behaviour the brief asked for (account-scoped) and differs from the contract's per-device wording (contract 4.2, DQ-2); decision DD-6 stands.
- A mode change in flight while the account switches: the write is refused (uid mismatch), the result is `saveFailed`, nothing is written under the wrong uid (F-9, F-10 in section 7).
- Running session and mode: unaffected (section 2.3).

### 5.3 Sign-out, account switch, account deletion

| Event | Behaviour | Evidence |
|---|---|---|
| Sign-out | Nothing is written or deleted. The key stays on disk like the other per-uid keys. In-memory state is dropped when the auth user becomes null | map 76 (per-uid prefs stay on disk), pattern map 60-65 |
| Account switch | New uid, new key (5.2) | as above |
| Account deletion | `DeviceLocalDataWipe.wipe(uid)` removes keys with the `activity.` prefix ending in `.<uid>`, which includes `activity.mode.v1.<uid>` with no change to the wipe (`local_data_wipe.dart:267, 210-223`); the activity-aware wrapper also wipes the journal (`activity_wiring.dart:48-54`, `main.dart:601-602`). A test adds the mode key to the existing wipe test and asserts removal. Wiped-uid guard (RV-14): `ModeStore.write` and `initIfAbsent` refuse a uid that is being or has been wiped (the same fail-closed idea as `_wipedUid` in the journal), or the wipe sequence invalidates the mode providers before deleting; a `selectMode` write in flight, then `wipe(uid)`, then a migration re-run leaves the key absent | DT-01-20 (wiped-uid guard); the assertion that the wipe removes the mode key in `mobile/test/features/account_deletion/` is DT-01-24 |
| Wipe keeps | `settings.language`, `settings.theme_mode`, `settings.notifications_enabled` (`local_data_wipe.dart:260-264`); the mode key is NOT kept | map 80 |
| Sign-out with local-only sessions | The warning sheet of S03-16 (section 2.5) | contract J10 |

The wipe prefix list is not edited, which avoids touching a security-sensitive file; if a reviewer prefers an explicit entry in `personalKeys` (`local_data_wipe.dart:273`), that is a one-line addition (R3 alternative, not chosen).

### 5.4 Backup exclusion

SharedPreferences are stored in `FlutterSharedPreferences.xml`, which both Android backup files exclude (`backup_rules.xml:47` and `data_extraction_rules.xml:29` and `:38`, FACT from the files). The mode key is therefore excluded from Android backup and device transfer with no change. iOS is not built in S03 (the layout of `journal_layout.dart:49` onward concerns iCloud; not applicable until OD-12). A static test asserts that the mode key does not live in any other storage (DT-01-25).

### 5.5 Data classification

The mode state is a device-local preference: the selected product mode, the chooser status and at most three short question answers. It is personal data (it is tied to an account) of low sensitivity: it carries no health, body, location or contact data and is not sent anywhere. It is never written to Firestore, never logged with its content, never included in debug telemetry and not exported. The privacy wording is unchanged (source `scripts/legal/legal_text.py`). The data-lifecycle matrix (`docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`) has no row for it; adding one is a documentation follow-up for the `doc-updater` and is listed in section 10 as a stale document not changed here.

### 5.6 Phase 1 upgrader path

1. The user updates the app; they are already onboarded, so the router sends them to `/home` (map 89).
2. `FitnessApp.build` watches the single warm-up provider, which starts mode state and the migration. No key exists (`missing`) and the first profile value loaded in this process is onboarded, so `initIfAbsent(migration)` writes `chooser = migrated`, `mode = train`. If the key is `unreadable`, nothing is written and no chooser or intro card is shown (RV-2).
3. Home shows the five tabs as before plus the mode chip and, in a Home build where `Day3WelcomeModal` is not shown (it is launch-count based, `home_page.dart:93-109`), the one-time intro card.
4. "Choose a mode" opens the chooser; "Not now" and any chooser exit write `resolved`.
5. No question, permission or network call happens (AC-CH-7, AC-SH-6).
If the profile has not loaded when the migration runs (cold start), the migration waits for it: the router already holds `/splash` for at most 5 s (`app_router.dart:385-411`); if the profile never loads the status stays `absent`, Home shows no chip logic change, and the migration runs on the next start (F-4).

### 5.7 Offline behaviour

Everything in this section works without a network. The only network-dependent S03-adjacent piece is the profile load that the migration waits on, and that is an existing Phase 1 dependency.

## 6. Localization

Source: contract 13 and the copy tables of contract sections 7 to 10 (FACT). Russian is the first supported locale and the fallback (FACT contract F20: `kSupportedLocaleCodes = ['ru', 'en']`), so every key ships with a Russian value and is tested in `ru` first. The ARB files are `mobile/lib/l10n/app_en.arb` (template, about 3,017 key lines) and `mobile/lib/l10n/app_ru.arb`, generated with `mobile/l10n.yaml` (`arb-dir: lib/l10n`, `output-class: AppLocalizations`, `nullable-getter: false`; FACT map 216-217). Existing key style is camelCase with a feature prefix (FACT map 223: `homeThisWeek`, `homeHome`, `progressProgress`, `navWorkouts`, `navScan`, `restTimer*`; also `profileProfile`, `legalPrivacyBody`); existing placeholders are written `{arg0}`, `{arg1}` (map 223), while the S03 keys below use named placeholders (`{n}`, `{k}`, `{minutes}`), which ARB supports; whether named placeholders are used elsewhere in the files is UNGROUNDED, and a localization test checks that `en` and `ru` carry the same placeholders. The map could not establish whether the two ARB files have the same key set (UNKNOWN), so S03-18 adds the parity test for the new keys only. Reusable existing keys are the five tab labels and `homeThisWeek`; almost every other string is new (map 224-238).

The privacy wording is NOT touched: its source stays `scripts/legal/legal_text.py` and the ARB key `legalPrivacyBody` is not edited (FACT contract 15, OD-11). S03 adds no privacy or retention sentence.

Rules that apply to every new key (FACT contract 13 and 11):
1. Mode names are never interpolated into a sentence (Russian declension). A sentence that mentions a mode is an ICU `select` on the mode or four full-sentence keys.
2. Counts use ICU plural with Russian forms one, few, many, other.
3. Numbers, dates and durations use `intl` with the resolved locale; no hard-coded "km"; metric only.
4. No key contains "merged", "deduplicated", "synced with Health Connect", "never keep", "forever" or "indefinitely" (AC-SRC-5, AC-RET-1). Cloud and sync wording exists only behind `ACTIVITY_CLOUD_STREAMS` (AC-REG-4).
5. Errors are plain sentences with a next step, never exception text.
6. Russian values below are PROPOSED first drafts by the designer for the translation pass; every length budget is enforced by test (AC-A11Y-5, AC-FAM-4), not by this table. English values are the contract's text (FACT).

Budgets (FACT, contract 13), in Russian characters: mode name 14; card blurb 40; mode chip 16; status chip word 22; button label 18; sheet row title 28 and description 60; strip title 24; section header 28; rail label (compact form) 11 and (extended form) 18; side-pane section title 28; chooser detail panel description 60; rail running state word 8.

Contract inconsistency noted (INFERENCE, to fix in the translation pass, not by editing the contract): the English `modeBodyDesc` is about 79 characters while the chooser description and detail-panel budget is 60; the Russian text must wrap in 320 dp and never be ellipsised, so the budget test for that single key allows wrapping to 3 lines. OPEN (DD-4).

### 6.1 Mode chooser S-1 and large layout (S-9 part)

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `modeChooserTitle` | What do you want to do? | Что вы хотите делать? |
| `modeChooserSubtitle` | You can change this any time in two taps. | Это можно изменить в любой момент в два нажатия. |
| `modeTrainName` | Train | Тренировка |
| `modeRideName` | Ride | Велосипед |
| `modeExploreName` | Explore | Прогулки |
| `modeBodyName` | Body | Тело |
| `modeTrainBlurb` | Gym, plans and technique | Зал, планы и техника |
| `modeRideBlurb` | Routes and rides | Маршруты и поездки |
| `modeExploreBlurb` | Walk, run and hike | Ходьба, бег и походы |
| `modeBodyBlurb` | Progress, food and weight | Прогресс, питание и вес |
| `modeTrainDesc` | Follow your plan, scan equipment, and check your form. | Следуйте плану, сканируйте тренажёры, проверяйте технику. |
| `modeRideDesc` | Record rides and follow routes. | Записывайте поездки и следуйте маршрутам. |
| `modeExploreDesc` | Record walks, runs and hikes. | Записывайте прогулки, пробежки и походы. |
| `modeBodyDesc` | See your progress, log food and track weight. Estimates are shown as estimates. | Смотрите прогресс, ведите дневник питания и веса. Оценки помечены как оценки. |
| `modeDetailIdle` | Pick a mode to see what it does | Выберите режим, чтобы узнать, что он делает |
| `modeComingLater` | Coming later | Скоро |
| `modeSelected` | Selected | Выбрано |
| `modeContinue` | Continue | Продолжить |
| `modeDecideLater` | Decide later | Решить позже |
| `modeSaveError` | We could not save your choice on this device. You can continue; we will ask again next time. | Не удалось сохранить выбор на этом устройстве. Можно продолжить; мы спросим снова в следующий раз. |

### 6.2 Coming-later sheet and mode switcher S-3

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `modeComingLaterSheetTitle` (select by mode) | Ride is coming later / Explore is coming later | Режим «Велосипед» появится позже / Режим «Прогулки» появится позже |
| `modeComingLaterSheetBody` | You cannot start this yet. Everything else works as before. | Начать это пока нельзя. Всё остальное работает как раньше. |
| `modeComingLaterSheetAction` | Choose Train for now | Пока выбрать «Тренировку» |
| `modeSwitcherTitle` | Choose a mode | Выберите режим |
| `modeSwitcherSeeAll` | See all modes | Все режимы |
| `modeSwitcherQuestions` (plural) | {n} quick questions | {n, plural, one{{n} быстрый вопрос} few{{n} быстрых вопроса} many{{n} быстрых вопросов} other{{n} быстрого вопроса}} |
| `modeSwitcherCurrent` (select by mode) | Current mode: {mode} (key named by the contract, text PROPOSED here) | Текущий режим: {mode} |
| `homeModeChipLabel` (select by mode) | Mode: Train. Change mode | Режим: Тренировка. Сменить режим |
| `modeSwitchSaveError` (snackbar, PROPOSED key name) | We could not save this choice on this device. | Не удалось сохранить этот выбор на устройстве. |
| `modeChangedAnnouncement` (select by mode, PROPOSED key name) | Mode changed to {mode} | Режим изменён: {mode} |

The mode name inside `modeChangedAnnouncement` and `homeModeChipLabel` is chosen by `select`, not concatenated, to avoid declension errors.

### 6.3 Per-mode questions S-2

| Key | EN | RU (PROPOSED) |
|---|---|---|
| `modeQuestionTrainWhere` (PROPOSED name) | Where do you train most? | Где вы тренируетесь чаще всего? |
| `modeQuestionTrainOptionGym` / `AtHome` / `Outdoors` / `Yoga` | Gym / At home / Outdoors / Yoga | Зал / Дома / На улице / Йога |
| `modeQuestionBodyStart` (PROPOSED name) | What do you want to start with? | С чего вы хотите начать? |
| `modeQuestionBodyOptionPhotos` / `Food` / `Weight` | Progress photos / Food diary / Weight trend | Фото прогресса / Дневник питания / Динамика веса |
| `modeQuestionSkip` | Skip (key `modeQuestion.skip`) | Пропустить |
| `modeQuestionProgress` (plural/placeholders) | Question {n} of {total} | Вопрос {n} из {total} |
| `modeQuestionWhatChanges` (per question, PROPOSED) | Train: "This sets which cards come first on Home." Body: "This sets which Body card comes first on Home and in Record." (PROPOSED) | Тренировка: «Это определит, какие карточки будут первыми на главном экране.» Тело: «Это определит, какая карточка «Тела» будет первой на главном экране и в «Записи».» |
| `modeQuestionSaving` | Saving | Сохранение |
| `modeQuestionSaveError` | We could not save this. Try again or skip. | Не удалось сохранить. Повторите или пропустите. |
| `modeQuestionRetry` | Try again | Повторить |

Refused options reuse the existing access-gate reason text (FACT contract S-2: `ScanAccess`); no new reason string is added.

### 6.4 Shell dock, strip, rail

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `recordPill` | Record | Запись |
| `stripWorkout` | Workout in progress | Тренировка идёт |
| `stripPaused` | Paused | Пауза |
| `stripResting` | Resting | Отдых |
| `stripRestDone` | Rest finished | Отдых закончен |
| `stripResumeHint` | Tap to resume | Нажмите, чтобы вернуться |
| `stripModeLabel` (select by mode) | the mode name of the session, chosen by select: Train / Ride / Explore / Body (key named by the contract, text PROPOSED; a gym timer is always Train) | Тренировка / Велосипед / Прогулки / Тело |
| `stripSpokenMinutes` (plural, PROPOSED name) | {minutes} minutes (spoken, plural-aware) | {minutes, plural, one{{minutes} минута} few{{minutes} минуты} many{{minutes} минут} other{{minutes} минуты}} |
| `railStateRunning` | Active | Идёт |
| `railStatePaused` | Paused | Пауза |
| `railStateResting` | Rest | Отдых |
| `railStateRestDone` | Done | Готово |
| `railMinutes` (plural, PROPOSED name) | {minutes} min | {minutes} мин |
| `navMainLabel` (PROPOSED name) | Main navigation | Основная навигация |
| `shellBack` (label of `shell.back`, may already exist) | Back | Назад |

Existing nav labels are reused unchanged and not edited: `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`. Russian values (FACT per lead agent, contract 13): Главная, Тренировки, Скан, Прогресс, Профиль; the longest is 10 characters against the compact-rail budget of 11. The map's list of reusable keys (map 226-235) has no "Back" key; S03 adds `shellBack` unless a text search of `app_en.arb` at build time finds an existing generic one (UNGROUNDED).

### 6.5 Record sheet S-5

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `recordSheetTitle` (select by mode) | Record: Train / Record: Body | Запись: Тренировка / Запись: Тело |
| `recordTrainScan` | Scan equipment | Сканировать тренажёр |
| `recordTrainToday` | Today's workout | Тренировка на сегодня |
| `recordTrainChoose` | Choose a workout | Выбрать тренировку |
| `recordTrainForm` | Check my form | Проверить технику |
| `recordBodyScan` | Body scan | Скан тела |
| `recordBodyMeal` | Add a meal | Добавить приём пищи |
| `recordBodyWeight` | Log weight | Записать вес |
| `recordNothingHere` | Nothing to start in this mode yet. | В этом режиме пока нечего начинать. |
| `recordOpenTrain` (PROPOSED name; button "Open Train") | Open Train | Открыть «Тренировку» |

### 6.6 Home

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `homeActivityToday` | Activity today | Активность сегодня |
| `modeIntroTitle` | New: choose what you want to do | Новое: выберите, что вы хотите делать |
| `modeIntroBody` | Train, Ride, Explore and Body now share one history. Pick the one you use most. | Тренировка, Велосипед, Прогулки и Тело теперь делят одну историю. Выберите то, чем пользуетесь чаще. |
| `modeIntroChoose` | Choose a mode | Выбрать режим |
| `modeIntroDismiss` | Not now | Не сейчас |
| `homeScheduledGone` (J6 snackbar, only if S03-20 is built; PROPOSED name) | That workout is no longer scheduled | Эта тренировка больше не запланирована |

### 6.7 Progress

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `progressAllActivity` | All activity | Вся активность |
| `progressThisWeek` | This week | Эта неделя |
| `progressThisWeekEmpty` | No recorded activity this week. | На этой неделе записанной активности нет. |
| `progressRecent` | Recent activity | Недавняя активность |
| `progressSourcesRow` | Sources | Источники |
| `progressSourcesHint` | Walks, runs and rides you record will appear on Progress. | Записанные вами прогулки, пробежки и поездки появятся в «Прогрессе». |
| `activityJournalFailed` | Activity history on this device could not be opened. | Историю активности на этом устройстве не удалось открыть. |
| `activityJournalRetry` | Try again | Повторить |
| `activityNoData` | No data | Нет данных |
| `activityEstimate` | Estimate | Оценка |
| `activityStreamLost` | Route not available on this device | Маршрут недоступен на этом устройстве |
| `activityTimeFrom` (plural) | Time from {k} of {n} sessions | Время по {k} из {n} тренировок (plural forms one/few/many/other required; text PROPOSED) |
| Group names (PROPOSED keys `sportGroupWalkHike`, `sportGroupRun`, `sportGroupRide`, `sportGroupSwim`, `sportGroupRow`, `sportGroupOther`) | Walk and hike / Run / Ride / Swim / Row / Other | Ходьба и походы / Бег / Велосипед / Плавание / Гребля / Другое |
| `activitySourcesMore` (plural, PROPOSED name) | +{k} sources | +{k} источников (plural forms required) |
| `activitySourceUnknown` and source labels of 8.1 (PROPOSED keys `sourceLabelApp`, `sourceLabelHealthPlatform`, `sourceLabelSensor`, `sourceLabelService`, `sourceLabelCompanionApp`, `sourceLabelFileImport`, `sourceLabelUnknown`) | Recorded in this app / Health platform / Sensor / Service / App / File import / Unknown source | Записано в приложении / Платформа здоровья / Датчик / Сервис / Приложение / Импорт файла / Неизвестный источник |
| Sync chips (cloud flag on only; PROPOSED keys `syncChipPending`, `syncChipFailed`, `syncChipConflict`) | Waiting to sync / Could not sync, will retry / Needs your decision | Ожидает синхронизации / Не удалось синхронизировать, повторим / Нужно ваше решение |

### 6.8 Sources S-8

| Key | EN (FACT) | RU (PROPOSED) |
|---|---|---|
| `sourcesTitle` | Sources | Источники |
| `sourcesIntro` | Your activity can come from this app, your phone or your devices. | Ваша активность может приходить из этого приложения, телефона или устройств. |
| `sourceApp` | Recorded in this app | Записано в приложении |
| `sourceHealthConnect` | Health Connect | Health Connect |
| `sourceBle` | Bluetooth sensors | Bluetooth-датчики |
| `sourceWatch` | Watch | Часы |
| `sourceOther` | Other services | Другие сервисы |
| `sourceStatusInUse` / `Ready` / `NotConnected` / `NotActive` | In use / Ready / Not connected / Not active | Используется / Готово / Не подключено / Не активно |
| `sourceStatusPermission`, `Unavailable`, `Stale`, `Error`, `Connected` (S16 values, defined now, shown later) | Permission needed / Unavailable on this device / Out of date / Problem / Connected | Нужно разрешение / Недоступно на этом устройстве / Устарело / Проблема / Подключено |
| `sourcesNotActiveLine` (PROPOSED name) | Activity history is not active in this build. | История активности в этой сборке не активна. |
| `sourcesDedupNote` | If the same workout comes from two sources, we do not yet merge them automatically. | Если одна тренировка пришла из двух источников, мы пока не объединяем их автоматически. |
| `sourceStatusChecking` (PROPOSED name) | Checking | Проверка |

Note on AC-SRC-5: the English text of `sourcesDedupNote` contains the word "merge"; AC-SRC-5 bans "merged", "deduplicated" and "synced with Health Connect" (inflected forms), so the test must match those exact phrases, not the stem "merge". INFERENCE; confirm in the test plan.

The Apple Health row (`sourceHealthKit` "Apple Health") is NOT added in S03: no Apple build exists, so it is listed in no S03 build (FACT contract S-8).

### 6.9 Sign-out warning S-10 (if S03-16 is built)

| Key | EN (FACT where quoted, otherwise PROPOSED) | RU (PROPOSED) |
|---|---|---|
| `signOutWarningTitle` (plural, n = count) | You have {n} activities stored only on this device | {n, plural, one{У вас {n} активность хранится только на этом устройстве} few{У вас {n} активности хранятся только на этом устройстве} many{У вас {n} активностей хранятся только на этом устройстве} other{У вас {n} активности хранятся только на этом устройстве}} |
| `signOutExportFirst` | Export first (GPX/FIT) | Сначала экспортировать (GPX/FIT) |
| `signOutAndDelete` | Sign out and delete from this device | Выйти и удалить с этого устройства |
| `signOutCancel` | Cancel | Отмена |
| `signOutConfirmDelete` (second confirmation, text PROPOSED) | Delete {n} activities from this device? This cannot be undone. | Удалить с этого устройства активности: {n}? Это нельзя отменить. |

The map lists no shared `Cancel` key (UNGROUNDED); S03-16 searches `app_en.arb` first and reuses an existing one if found.

### 6.10 Counting and tests

The new key groups are 6.1 to 6.9, that is nine groups; an earlier draft of the DoD said ten and was corrected to nine (DD-5). Tests owned by S03-18: ARB parity (every `en` key has a `ru` key and the same placeholders), plural forms present in `ru` (one, few, many, other), word-ban search (AC-SRC-5, AC-RET-1), budget and `didExceedMaxLines` checks (AC-A11Y-5, AC-FAM-4), pseudo-locale run for keys whose Russian is not yet reviewed.

## 7. Failure and security analysis

### 7.1 Failure table

Test ids: a contract AC id where the contract already has the check; otherwise a design test `DT-<story>-<n>` (section 8.2). "Handling" is the PROPOSED design response.

| # | Cause | Effect | Handling | Test |
|---|---|---|---|---|
| F-1 | Mode write throws (disk full, prefs error) | Choice not persisted | Mode stays active for the session; `modeChooser.saveError`; `chooserStatus` stays `pending` on disk and in memory; Continue still works; asked again next start | AC-CH-6 |
| F-2 | Mode write throws in the switcher | Same, no chooser involved | Lens changes for the session; snackbar `modeSwitchSaveError` | DT-10-1 |
| F-3 | Stored value corrupt, unknown shape or newer version | Read is `unreadable` | Default state in memory only; no write at start; newer version read-only for the run; corrupt replaced only by an explicit user action; never throw (RV-2; see F-36) | DT-01-1 to DT-01-3, DT-01-16 to DT-01-19 |
| F-4 | Profile not loaded at start (slow or offline) | Migration cannot decide | The migration decides from the first profile value loaded in this process; while none has loaded it waits within the router's 5 s splash hold; if it never loads, status stays `absent` and the decision is taken at the next start; no chooser is pushed while `absent` (RV-1) | DT-01-13, DT-01-14, DT-01-22 |
| F-5 | App killed during the chooser | `pending` persists | Chooser offered again on the next app start (not again within the same run, F-39) | AC-CH-5 |
| F-6 | Onboarding finish write fails, throws, or the page is unmounted during the await | Status remains `absent` | The hook awaits the provider future, checks `mounted`, wraps the call in try/catch, logs a fixed message with a content-free code and the exception type only, and never blocks `context.go('/home')`; the next start finds an onboarded first profile value and the migration writes `migrated` (intro card instead of the chooser; accepted) | DT-01-15 |
| F-7 | `/onboarding/edit` finishes for an onboarded user | Would re-mark pending | `markPendingIfAbsent` is a no-op when the status is not `absent` | AC-CH-8 |
| F-8 | Mode changed while a gym timer runs | Timers could reset if mode state invalidated the shell | Timers never watch mode state; `ActiveSessionStatus.mode` is the session's own; states compared by equality before and after | AC-SW-2, AC-ST-4 |
| F-9 | Account switches while a mode write is in flight | Write could land under the wrong uid | Uid guard refuses the write (`training_context_providers.dart:68-73` pattern) and so does the wiped-uid guard (RV-14); returns `saveFailed` | DT-01-6, DT-01-20, DT-01-23 |
| F-10 | Account switches while the chooser or switcher is open | Surface shows the old account's mode | `modeStateProvider` rebuilds for the new uid; the open surface re-reads it; a pending selection is discarded and no write is made | DT-08-10, DT-10-5 |
| F-11 | Account switches while a timer runs | New account would see the other account's strip | The owner uid is captured when the timer starts, in the same place that writes the destination, stored with it as one `ActiveSessionOwner{uid, destination}` and never recomputed from the current auth; strip and pill are hidden when `owner.uid` differs from the current uid and the owner is cleared by an explicit `ref.listen` on the status (no provider writes to another provider inside `build`); timers themselves are untouched by S03 (RV-4) | DT-07-8 |
| F-12 | Process killed while a timer ran | Both timers are gone (map 40, contract F23) | No strip, no recovery claim | AC-ST-8 |
| F-13 | Either timer provider becomes auto-dispose | The strip could keep or lose timers unexpectedly | A test asserting both providers are not auto-dispose is needed (the map had this as UNKNOWN) | DT-07-12, DT-07-13 |
| F-14 | Strip or pill provider throws | Shell could break | Strip hidden, no blocking error, shell unaffected; the existing timers stay reachable (the Workouts tab and the workout page are untouched) and a content-free error code with the exception type is logged (RV-16) | S-4 ERROR row; DT-07-1 |
| F-15 | Journal `list()` throws or the bind fails | No dashboard data | Home card absent with no new text; Progress error panel with one Try again when no value ever loaded for this uid; a same-uid previous value is kept with the stale line (F-41); a previous value of another uid is never kept; Sources "Problem" | AC-HM-5, AC-PR-2, AC-SRC-3, DT-14-1, DT-13-10 |
| F-16 | Try again tapped repeatedly, or tapped while an automatic retry is armed or due | Duplicate or concurrent binds, or a lost automatic retry | Single flight shared by both sources; a double tap makes one attempt; a failed manual attempt leaves the original automatic deadline and index intact; a due automatic timer during a manual attempt is re-armed with the same index; no loop is started from `gaveUp` (2.1 item 3, GPT-PM MAJOR-01) | AC-PR-2, AC-SRC-3, DT-0-5, DT-0-11, DT-0-13, DT-0-14 |
| F-17 | Journal deleted entry still on screen | Stale view of a deleted session | `list()` returns live entries only; refresh signals of 3.7 re-read it; a bump of `activityJournalRevisionProvider` on delete is the seam for S04+ | DT-14-7 |
| F-18 | Account deletion | Mode key and journal must go | Existing wipe removes `activity.mode.v1.<uid>` and the activity-aware wrapper wipes the journal | DT-01-24 |
| F-19 | Sign-out with local-only sessions | Data loss risk | Warning sheet; export first; second confirmation for delete; nothing deleted before it; empty or unavailable journal signs out with no prompt | AC-SO-1, AC-SO-2 |
| F-20 | Sign-out call site misses the guard | Warning skipped | S03-16 enumerates all call sites; a static test lists them against the guard | DT-16-9 |
| F-21 | Live window resize across a boundary | Layout swap could lose state | Route, selection, mode, timers, focus and open surface kept; first visible section anchored. The `ShellRoute` child stays under one `GlobalKey` slot so a bar-to-rail or rail-to-bar swap reuses the same element and its state; the open surface route re-reads `WindowSizeInfo` live and re-evaluates its placement while open (RV-6, RV-9) | AC-WS-5, AC-WS-14, AC-CH-14, AC-LS-10, DT-05-3, DT-06-2 |
| F-22 | Text scale 2.0 in Russian | Overflow or truncated status words | Wrap rules and rail extended form by measurement | AC-A11Y-5, AC-WS-3, AC-FAM-4 |
| F-23 | Very short window (landscape phone) | Rail does not fit | 48 dp items, scrollable destinations, pinned Record slot | AC-WS-10 |
| F-24 | Shell restructure breaks Android first-Back | App exits on first Back | `PopScope` and `_AnnounceShellCanPop` untouched; existing test unchanged | AC-SH-2 (`back_navigation_test.dart`) |
| F-25 | Dock padding double-counted or missing | Content hidden behind strip, or dead space | Single `ShellLayout` source; assertions on every tab | AC-ST-6, AC-WS-8, AC-PR-9 |
| F-26 | Question save fails | User blocked | Skip and Back stay enabled | AC-Q-5 |
| F-27 | Unknown sport or kind in a stored session | Wrong group or crash | Exhaustive group mapping (compile-time); unknown names already degrade to `other`; unknown `SourceKind` degrades to `fileImport` | AC-SRC-6, DT-13-7, DT-13-21 |
| F-28 | Session lacks time or distance | Zero shown for unknown | Null-aware sums with "k of n" counts; "No data" | AC-PR-4, DT-13-5, DT-13-22 |
| F-29 | Clock or zone changes (travel, DST) | Week assignment shifts | Calendar-date comparison in the device zone; injectable clock and zone | AC-PR-7, DT-13-1, DT-13-2 |
| F-30 | Large journal | Slow load | Release gate G1 and G2 of 3.8 | DT-13-23, DT-14-8 (measure-only, run once by the test agents at the end) |
| F-31 | Journal opens in every build now | Backup includes routes and laps because the exclusion paths do not match the real tree (verified FACT, RV-13) | Unconditional fix in S03-0 before the default flip: scoped root excluded in all three XML sections, one shared constant; DT-0-6 reads the real tree | DT-0-6 |
| F-32 | A shortcut fires under a modal or in a text field | Unwanted navigation | Open-surface depth and editable-focus guards; limit for legacy modals recorded | AC-KB-1 |
| F-33 | Reminder tap during sign-in or onboarding | Wrong route | Dropped (DQ-8); S03-20 only if confirmed | DT-20-4 |
| F-34 | Cloud flag off but sync text shown | Misleading wording | Sync chips built only under `cloudSync` | AC-REG-4 |
| F-35 | Mode state read before the profile or auth is ready | Flash of wrong lens | Provider warmed during splash; Home renders pre-S03 content without a chip while loading | DT-01-9, DT-12-4 |
| F-36 | Stored mode unreadable (corrupt, unknown shape, newer version), or mode state fails to load | Silent overwrite of a user's choice, or a chooser on a healthy account | Default state in memory; no write at start; no chooser push; newer version read-only for the run; corrupt replaced only by an explicit user action; a stored but unavailable mode is coerced to `train` in memory and not rewritten; `AsyncError` gives default state, no chooser, no writes; content-free reason code logged (RV-2) | DT-01-1 to DT-01-3, DT-01-16 to DT-01-19 |
| F-37 | Journal still binding, or the bind gave up | "No activity" shown for a journal that is merely not ready | Availability `binding` shows LOADING, never EMPTY; `gaveUp` (the automatic schedule is exhausted, no timer) shows the error panel with Try again, and one tap runs exactly one attempt without starting a loop; `open` only when bound for the current uid (RV-3) | DT-13-8 to DT-13-15, DT-0-12, DT-0-13 |
| F-38 | A load for the previous account completes after an account switch | Previous account's activity shown to the new account | Every load carries `ownerUid` and a generation; a completion with another uid or generation is discarded; the provider resets synchronously to loading on uid change or sign-out; a previous value is reused only for the same uid (RV-3); a generation bump also cancels the pending bind timer and invalidates an in-flight bind, so a stale bind completion is discarded (retry rule 5) | DT-13-9, DT-13-10 |
| F-39 | Chooser offered again after a Home to Profile to Home round trip, or while the Day-3 modal is pending | Repeated or stacked prompts | `offeredThisRun` keep-alive set per uid, set when the chooser is opened; Home waits for the asynchronous Day-3 decision before offering; system Back on the chooser behaves like "Decide later" (writes `selectedMode = train`, `chooserStatus = resolved`, as AC-CH-4); a kill still leaves `pending` (RV-7) | DT-08-7, DT-08-8, DT-08-9 |
| F-40 | Journal recovery lost activities (recovered-absent or stream-lost counts above zero) | Silent loss, aggregates look complete | The bind status carries both counts; Sources and Progress show one plain line (`activityRecoveryNotice`); aggregates carry a "may be incomplete" marker while the count is above zero (RV-10) | DT-0-9, DT-13-16, DT-14-5, DT-15-4 |
| F-41 | A refresh fails after an earlier success | Stale numbers look current, or the value is lost | Same-uid value kept; `lastLoadFailedAt` set; Progress shows "Showing data from <time>" with Try again; Sources app row shows a "Problem" chip; sessions whose effective summary throws are counted as `unreadableSessions`, added to the notice, never counted as ordinary "no data" (RV-11) | DT-13-12, DT-13-17, DT-14-6, DT-15-5 |
| F-42 | Sign-out guard cannot check the journal (availability `binding`, `gaveUp`, `failedToOpen`) | Silent sign-out could hide data loss | Sheet "We could not check the activity stored on this device" with Try again and Sign out anyway; never a silent pass; `notEnabled` and an `open` empty journal sign out with no prompt (contract J10 reading, see disposition) (RV-12) | DT-16-4, DT-16-2 |
| F-43 | A mode write or the migration runs for a uid that is being or was wiped | Key re-created after account deletion | Wiped-uid guard in the store and in `initIfAbsent` (RV-14) | DT-01-20 |
| F-44 | `/mode-questions/:mode` with an unknown or unavailable mode, or a notification payload outside the allow-list | Wrong screen or a write for an invalid mode | Redirect to Home with no write; notification payloads map through fixed route templates, never `go(payload)`; the session id must exist among the signed-in user's own sessions; the tap is ignored while signed out or in onboarding (RV-15) | DT-09-6, DT-20-5, DT-20-6 |
| F-45 | Export or wipe fails during sign-out | Data lost or "deleted" claimed falsely | Export or delete runs FIRST and sign-out only after success; on failure the user stays signed in with an error sheet and Retry; the UI never says "deleted" unless the wipe returned normally; the export file lives in a cache location outside backup, is deleted after the share and is bound to the departing uid (RV-12, RV-16) | DT-16-5, DT-16-6, DT-16-8 |

### 7.2 Security and privacy analysis

- Network: none added. Dashboards read the local journal; mode state is local. No Firestore rule, Cloud Function or storage rule changes: the owner wildcard in `firestore.rules:83-127` already permits any non-excluded collection, and no mode data is written to it (map 261-263). INFERENCE from the map and the contract; the account-deletion Cloud Function was not read (map UNKNOWN) and is not involved because nothing is stored server-side.
- Permissions: none requested. Static test: no import of a location or permission package under the new S03 files (AC-SH-6); the mocked permission channel records zero calls on all S03 screens.
- Authorization and routes: new routes are not in `_publicPaths`; the existing redirects send signed-out users to `/login` and not-onboarded users to `/onboarding` (map 14-16). A cold deep link to `/mode-chooser`, `/mode-questions/:mode` or `/sources` before onboarding is redirected; a notification tap that targets a new route does not exist (no tap routing in the map, UNGROUNDED).
- Tenant isolation: the mode key and the journal are per uid; a uid mismatch refuses writes; the strip is bound to its owner uid (F-9, F-11).
- Data minimisation: no location, heart-rate, route or health value enters any new store; the dashboard digest carries only id, start, group, two metrics and source ids; digests are in memory only and are not persisted or logged.
- Deletion and tombstones: dashboards show only live journal entries (`list()` excludes tombstones, map 108); account deletion removes the mode key and the journal (5.3). The dashboards never call `listTombstones()`.
- Sign-out: no automatic wipe; the warning sheet only informs and exports; deleting from the device requires a second confirmation. A user-initiated deletion of the user's own local data is not an operator-only action; the code that deletes is the existing S02 `ActivityWipeCoordinator.onSignOut`, not new deletion logic.
- Backup: mode key excluded by the existing SharedPreferences exclusion; the journal exclusion needs the layout check of R11 (F-31).
- Logging: no mode value, activity value or source id is written to logs or debug telemetry; error panels show plain sentences, never exception text (contract 11 rule 8).
- Keyboard shortcuts: additive, no destructive action is bound to a key (Record only opens a sheet in S03).

## 8. Test strategy and seams

Operator rules that bind this section (FACT, global contract section 5): the test-writing agents (`functional-test-reviewer`, `e2e-runner`; `tdd-guide` as test engineer where a unit seam needs it) write detailed functional scripts for every epic and run the COMPLETE set they wrote after each epic and once more after the last epic. The coordinator never runs tests. No full suite, no CI, no mutation runs. A test must fail if the guarded behaviour breaks.

### 8.1 Test levels

| Level | What | Where it applies |
|---|---|---|
| Unit (U) | Pure Dart, no widgets: mode state transitions and migration table (contract 4.2), week and today windows, sport groups, source labels, formatters, availability value, nav list equality, window-size class function, contrast function for token pairs, ARB parity and word-ban | S03-01, S03-02, S03-13, S03-04 (list), S03-18 |
| Widget (W) | One screen or component pumped with fakes, a set window size, text scale, locale and `TargetPlatform` | Almost every AC (the contract states "widget tests" for all of them, FACT contract 14) |
| Integration (I) | Router plus shell plus providers with in-memory fakes, no device: onboarding finish writes `pending` before `/home`; app restart simulated by a new `ProviderScope` over the same fake store; live resize across the rail boundary; journal fake with sessions | AC-CH-5, AC-CH-8, AC-ST-8, AC-WS-5, AC-FAM-1, AC-SH-2 |
| Static check (K) | File scans: no import of a location or permission package in new S03 files (AC-SH-6), no `Color(0x`, `Colors.` or warning/danger colours as text in new files (AC-A11Y-8), no gesture-only handlers (AC-KB-6), no `Cupertino*` widget (AC-FAM-2), ARB word-ban (AC-SRC-5, AC-RET-1) | S03-18 |
| Not run (N) | Real device or simulator checks | 1.8 |

Estimated split of the roughly 340 tests (INFERENCE): about 15 percent unit, about 75 percent widget, about 7 percent integration, about 3 percent static.

### 8.2 Test id scheme

- Tests that realise a contract criterion use the contract id as the test name prefix: `AC-CH-4`, plus a suffix for parametrised cases, for example `AC-WS-3/ru/1100x800/scale1.15`. This keeps one id per criterion in every report.
- Design-added tests (not in the contract) use `DT-<story number>-<seq>`: for example `DT-0-1` (S03-0), `DT-01-n` (mode state), `DT-13-n` (aggregates). The plan owns every id and its meaning; the design only cites plan ids.
- Test file location: mirror the library path under `mobile/test/` (FACT: existing guards live in `mobile/test/core/architecture/`, S02_DESIGN section 2); for the new code: `mobile/test/features/modes/`, `mobile/test/features/activity/{data,state,config}/`, `mobile/test/shared/widgets/` and `mobile/test/router/` (the existing layout, map 243-244, 251).
- Findings from test runs go to the test-findings files in the S02 style (`docs/phase2/s03/S03_TEST_FINDINGS_EPICn.md`), written by the test agents, not by this design.

### 8.3 Seams the build must provide (so the test agents can write tests without touching production code)

Taken from the contract list (FACT, contract 14, last "Test seams" paragraph) and completed by the designer (PROPOSED):

| Seam | Purpose | Story that provides it |
|---|---|---|
| Overridable `windowSizeClass` provider plus the real `tester.view` physical size (device pixel ratio 1.0) | Class, short flag, presentation and layout tests | S03-02 |
| Injectable text scale | Scale 1.0, 1.15, 1.29, 1.3, 2.0 cases | test harness (uses `MediaQuery`), no production code |
| Locale setter (`ru` first, then `en`) and a pseudo-locale | Budgets and plurals | test harness plus S03-18 |
| Injectable `TargetPlatform` | Cmd versus Ctrl, Apple versus Android back, haptics | S03-17, test harness |
| In-memory fake store for `selectedMode`, `chooserStatus`, answers, with a switch that makes writes throw and a write spy | AC-CH-2, CH-4, CH-5, CH-6, CH-8, SW-3, SW-5, Q-5, RC-4 | S03-01 (store interface with a fake) |
| Injectable journal availability (`open`, `notEnabled`, `failedToOpen`) and a fake journal with `list()`, `put` (upsert by session id), a throwing `list()`, and an opener spy counting calls | AC-PR-1 to PR-6, SRC-1 to SRC-3, HM-3, HM-5 | S03-0 |
| Injectable clock and time zone (functions, not globals), two offsets | AC-PR-7, AC-HM-3, strip minute boundary | S03-13 |
| Fake timer providers: `setTimerProvider` and `restTimerProvider` can be overridden with chosen states (already providers, FACT contract F23); a fake clock for `endsAt` rules | AC-ST-1 to ST-9, SW-2 | S03-07 (no change needed to the providers themselves) |
| Provider for the strip destination route string | AC-ST-5 | S03-07 |
| Router test harness that reports the current location | AC-RC-1, RC-5, SH-2, SH-4, WS-5, KB-1 | existing router, test harness |
| Mocked permission method channel counting calls; mocked accessibility (announce) channel; mocked `SystemChrome` channel; mocked haptic channel | AC-SH-6, CH-7, A11Y-4, WS-9, FAM-5 | test harness |
| Fixed widget keys: `shell.bottomBar`, `shell.rail`, `shell.rail.record`, `shell.back`, `shell.dock`, `shell.dock.recordPill`, `shell.dock.strip`, `home.pane.main`, `home.pane.side`, `home.section.<name>`, `home.modeChip`, `home.activityToday`, `home.modeIntro`, `modeChooser.*`, `modeSwitcher.*`, `recordSheet*`, `progress.*`, `sources.*`, `signOut.warningSheet`, `modeDetailIdle` text | Every locator in the contract | each owning story |
| `railLabelMeasurerProvider` (`RailLabelMeasurer = double Function(String label, TextStyle style, TextScaler scaler)` in `shared/widgets/shell_layout.dart`); tests override it with a fixed-width stub (70 dp gives the 96 dp rail, 90 dp gives the 240 dp rail); the default measures with `TextPainter`, memoised (RV-18c) | AC-WS-3b, DT-05-2, DT-05-5 | S03-05 |
| Flag override: `ACTIVITY_CLOUD_STREAMS` readable and overridable in tests (how: override `activityFlagsProvider` with an explicit `ActivityFlags(...)`, FACT map 53-54, section 4.3; the compile-time constant itself cannot change inside a run) | AC-REG-4, AC-PR-1 | S03-0 |

Seams NOT to build: no test-only code paths that change product behaviour; overrides use providers only.

### 8.4 Fakes the test agents write (test code, not product code)

`FakeModeStore`, `FakeJournal`, `FakeClock`, `FakeZone`, `FakeSetTimer`, `FakeRestTimer`, `FakeScheduleProvider` (for the "Today's workout" row, AC-RC-2), `FakeScanAccess` (for refused options, AC-Q-6 and AC-RC-3), `MockPermissionChannel`, `MockAccessibilityChannel`. Names are PROPOSED; the test agents may rename.

### 8.5 Focused commands

The command form used by the S02 test agents (FACT map 255, from `docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md:80-107`) is `flutter test --timeout 60s <paths>` run in `mobile/`, for example `flutter test --timeout 60s test/features/activity`. S03 uses the same form with the files the test agents wrote, for example `flutter test --timeout 60s test/features/modes`. A wipe-related run also names `test/features/account_deletion`, `test/core/architecture` and `test/android/backup_rules_test.dart` (map 256). The project-pinned Flutter executable path is not in the map (UNGROUNDED; the test agents use whatever the S02 findings record). Static checks are written as Dart tests that read the source files, so they run with the same command. Forbidden: running the whole `mobile/test` tree, CI-mimicking containers, analyzers as a gate for the epic, mutation runs.

### 8.6 Test order per epic (for the test agents)

1. After EP-0 and EP-1 (S03-0, S03-01): unit and integration (availability, migration table, onboarding hook).
2. After EP-5 foundations (S03-02 to S03-06): window class, nav list, rail geometry and semantics, surfaces.
3. After dock and EP-2 (S03-07 to S03-11): strip table, chooser sizes, questions, switcher, Record sheet.
4. After EP-3 and EP-4 (S03-12 to S03-16): Home, aggregates, Progress, Sources, sign-out.
5. After S03-17: keyboard and pointer.
6. After S03-18: the full set the agents wrote, run once more; results recorded with the exact head revision.

### 8.7 What would make a green run misleading (guards against weak tests)

- Rail form tests must compute the expectation from the rule and print the measured width on failure (FACT contract AC-WS-3); a hard-coded 96 dp assertion is a defect.
- "No write" assertions need a write spy that would record a write if one happened (AC-CH-2, AC-SW-3, AC-SW-5, AC-RC-4, AC-WS-14, AC-CH-14).
- Order assertions compare real `Rect` positions or semantics traversal, not widget list order.
- The `notEnabled` tests force the state by override; they must not be satisfied by the default build, which is `open` after S03-0.

## 9. Build plan

### 9.1 Build order (epics and stories)

Order follows the dependencies of table 1.5 and the file-ownership rule of 9.2:

1. Foundations, no dependencies: S03-0 (EP-0), S03-01 (EP-1), S03-02 and S03-03 (EP-5).
2. Pure and shell skeleton: S03-13 (needs S03-0 only for its tests), S03-04, then S03-06 (needs S03-02 and S03-03).
3. Shell body: S03-05 (rail, lane L4a) and S03-07 (dock and strip, lane L4b) in parallel; S03-07 depends on the `ShellLayout` API, not on the finished rail. Critical path (RV-5): S03-03/S03-02, then S03-07, then S03-10, then S03-12 (Home also needs S03-13 and S03-05).
4. EP-2 screens: S03-08 (chooser), S03-09, S03-10, S03-11.
5. EP-3 and EP-4 screens: S03-15 (Sources), S03-12 (Home), S03-14 (Progress), S03-16 (sign-out).
6. Input and conditional: S03-17, then S03-19 and S03-20 if confirmed.
7. Conformance: S03-18.

### 9.2 Parallel groups for implementation agents without file collisions

Rule (RV-5): a path appears in at most one lane. One lane owns a file for the whole sprint; a second lane never edits it, not even serially. Where a story needs something from a file owned by another lane, it uses a public API of that lane's file, created in that lane's "interface commit" (a first commit with the final signatures, possibly with stub bodies) before the dependent lane mounts it. Inset adoption for Home, Workouts and Progress happens ONLY through `HudScreenBody` and `ShellLayout`: S03-05 (lane L4a) provides the API, and L7 and L8 adopt it in their own page edits. Implementation agents use the allowed model policy; they never approve their own change (global rule) and the coordinator runs no tests. Test files are written by the test agents, one owner per test file (the test plan lists them); they are not implementation-lane paths.

#### File-ownership table (path to lane)

| Lane | Paths owned (all under `mobile/lib/` unless stated) |
|---|---|
| L1 | `core/config/activity_flags.dart`, `core/wiring/activity_wiring.dart` (including the bind retry controller class and the bind-status Notifier), `mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart` (regression guard, unchanged), `features/activity/state/journal_availability.dart`, `features/activity/data/activity_aggregates.dart`, `features/activity/state/activity_dashboard_providers.dart`, `features/activity/repository/journal_layout.dart`, the file defining `fileActivityJournalFactory` and the scoped-root constant (path read in the S03-0 first step), `features/progress/data/progress_stats.dart` (only if the day and week helpers are extracted), `android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml` (both under `mobile/`), tests `mobile/test/android/backup_rules_test.dart`, `backup_exclusion_test.dart`, `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart` |
| L2 | `features/modes/data/**`, `features/modes/state/**` (mode models, codec, store, providers, migration, flags, warm-up), `features/onboarding/onboarding_page.dart`, `main.dart` (the `FitnessApp.build` warm-up watch, the existing `_FitnessAppState` resume callback calling the L1 refresher entry, and, after L10's interface commit, the `AppShortcuts` splice in the `MaterialApp.router` builder) |
| L3 | `shared/widgets/hud/hud_surface.dart`, `shared/widgets/hud/hud_metric.dart`, `shared/widgets/window_size.dart` |
| L4a | `shared/widgets/main_shell.dart`, `shared/widgets/hud/hud_scaffold.dart`, `shared/widgets/shell_insets.dart`, `shared/widgets/shell_layout.dart` (including `RailLabelMeasurer` and `railLabelMeasurerProvider`), `shared/widgets/shell_destinations.dart`, `shared/widgets/hud/hud_side_rail.dart`, `shared/widgets/shell_dock.dart` (host: position, animated padding, `RepaintBoundary`) |
| L4b | `features/workouts/state/active_session_status.dart` (status, owner, destination, driven timers), `shared/widgets/dock_widgets.dart` (`RecordPill`, `RecordingStrip`, `RailRecordSlot`), `features/equipment/workout_player_page.dart` (timer start paths only) |
| L5 | `shared/widgets/adaptive_surface.dart`, `core/router/s03_routes.dart`, `core/router/app_router.dart` (the one splice, the S03-19 pushed-page frame wiring), the pushed-page frame widget `shared/widgets/pushed_page_frame.dart` |
| L6 | `features/modes/pages/mode_chooser_page.dart`, `features/modes/pages/mode_question_page.dart`, `features/modes/widgets/**` (grid layout, switcher sheet, Coming-later sheet, Record sheet) |
| L7 | `features/home/home_page.dart`, new files under `features/home/widgets/` |
| L8 | `features/progress/progress_page.dart`, new files under `features/progress/widgets/` |
| L9 | `features/modes/pages/sources_page.dart`, `features/activity/widgets/sign_out_warning_sheet.dart`, `features/activity/state/sign_out_guard.dart`, the sign-out call-site files (named in the S03-16 first step and added to this table before any edit; a call-site file already owned by another lane makes S03-16 wait until that lane closes) |
| L10 | `shared/widgets/app_shortcuts.dart`, `shared/widgets/shell_back_button.dart` (pages of L6 and L9 mount it from their first version), scroll and scrollbar helpers |
| L11 (conditional) | the notification files found by search for S03-20 (`core/notifications/*`, UNKNOWN), no router file |
| L12 | fixes forced by S03-18, see below; no path is claimed in advance |

Pre-agreed interface commits (so lanes do not wait on each other's whole stories): L4b's first commit creates `active_session_status.dart` and `dock_widgets.dart` with the final public signatures; L6 creates the two page files and L9 the Sources page with their final constructors; L10 creates `AppShortcuts({child})`; L5 wires `s03_routes.dart` only after those page files exist. L4a mounts the L4b widgets only after the interface commit.

#### Lanes

| Lane | Stories, in order | Waits for |
|---|---|---|
| L1 journal and aggregates | S03-0 (backup fix first, then the flag flip), S03-13 | nothing |
| L2 mode state | S03-01, then the `AppShortcuts` splice of S03-17 | nothing; the splice waits for L10's interface commit |
| L3 HUD primitives and window class | S03-03, then S03-02 | nothing |
| L4a shell frame | S03-04, S03-05 | L3 (S03-03 semantics, S03-02), L4b interface commit for the mount |
| L4b dock and status | S03-07 | L3 (S03-02, S03-03) and the `ShellLayout` API from L4a's interface commit; it does not wait for the rail |
| L5 surfaces and routes | S03-06, then the router part of S03-19 (serial, after S03-06) | L3; L6 and L9 interface commits for the routes |
| L6 mode screens | S03-08, S03-09, S03-10, S03-11 | L2, L5, L10 (back button interface), and for S03-10 and S03-11 the strip from L4b |
| L7 Home | S03-12 | L1 (S03-13), L6 (S03-10), L4a (S03-05 for panes and insets) |
| L8 Progress | S03-14 | L1, L4a (S03-05 for insets), L4b (S03-07 for the dock height), L3 |
| L9 Sources and sign-out | S03-15, S03-16 | L1 (S03-13), L5 |
| L10 input | S03-17 (shortcut and back-button files) | L4a, L6 for the tab and surface targets |
| L11 conditional | S03-20 | L5, L2 and the J6 decision |
| L12 fixes | the fixes forced by S03-18 | all other lanes closed |

L12 (RV-5): one implementation-engineer, one file set at a time, started only after the other lanes close; each fix is listed by file in a short fix list BEFORE it starts, and a file is never claimed by two fixes at once. Fixes found while other lanes are still open are reported to the owning lane instead.

Parallelism: lanes L1, L2, L3 start together. L4b, L5 and L4a start when L3 has merged `window_size.dart` and the primitive extensions; L4a and L4b run in parallel because they own different files and meet only through the interface commits. L6, L7, L8 and L9 run in parallel once their waits are met. Critical path (RV-5): L3 (S03-03, S03-02) then L4b (S03-07, strip) then L6 (S03-10, switcher) then L7 (S03-12, Home), together with L1 (S03-13, aggregates) which S03-12 also needs; L4a (S03-05) is needed by L7 and L8 for insets and panes. Collision points and how they are removed: `main.dart` is owned by L2 alone; `app_router.dart` by L5 alone (L6 and L9 supply page files, not router edits); `hud_scaffold.dart` by L4a alone (S03-03 does not touch it: the focus ring lives in `hud_surface.dart` and `HudKeyboardActivation`); `home_page.dart` by L7; `progress_page.dart` by L8; `main_shell.dart` by L4a.

Test agents: after each epic the test-writing agents write and run the complete set for that epic (global rule): EP-0 and EP-1 after lanes L1 and L2; EP-5 foundations after L3, L4a, L4b and L5; EP-2 after L6; EP-3 and EP-4 after L7, L8 and L9; a final complete run of everything they wrote after S03-18. Test findings go to `docs/phase2/s03/S03_TEST_FINDINGS_EPICn.md`.

### 9.3 Risks and decisions (map risks 1 to 10 resolved, plus R11 and R12)

All decisions are PROPOSED.

| Risk | Map evidence | Decision | Applied in |
|---|---|---|---|
| R1 Journal default-off | `activity_flags.dart:21`; `activity_wiring.dart:41, 63, 102` | `compileTime` gets `defaultValue: true` for `ACTIVITY_LOCAL_JOURNAL`; cloud stays off; constructor defaults unchanged; flag-matrix test updated | 2.1, 4.2, S03-0 |
| R2 No change signal for a local-only journal | `activity_wiring.dart:180-187`; `activity_journal.dart:35` | Dashboard provider refreshes on bind, resume, revision bump, uid change and tab visibility after 60 s; coalesced loads | 3.7, S03-13 |
| R3 Account-scoped mode state | `settings_repository.dart:12`; `training_context_providers.dart:45-84` | Per-uid key `activity.mode.v1.<uid>` covered by the existing wipe prefix; explicit `migrated` for upgraders; uid-guarded notifier | 2.2, 5.1 to 5.3 |
| R4 Two activity stores | `home_dashboard_providers.dart:26-73`; `progress_page.dart:34-40` | New dashboards read only the journal; existing tabs unchanged; no number mixes the stores; Progress shows no "No activity" message above gym data while empty (contract demotion rule) | 2.4, 3.1 |
| R5 Missing versus zero | `activity_summary.dart:29-43`; `progress_stats.dart:24-30` | New null-aware aggregates with contributing counts; `ProgressStats` zeros are not reused for the new block | 3.4 |
| R6 Bottom-bar assumptions | `hud_scaffold.dart:45-49`; `shell_insets.dart:34` | `ShellLayout` supplies clearance and start inset; `HudScreenBody` reads it and falls back to today's behaviour when absent; `extendBody` false for the rail | 2.6 |
| R7 Back handling | `main_shell.dart:111-150` | `PopScope` and `_AnnounceShellCanPop` untouched; restructure only inside the Scaffold; existing back test must pass unchanged | 2.6, F-24 |
| R8 Running session survives a mode switch | `set_timer_providers.dart:247`; `rest_timer_providers.dart:209` | Mode state is a separate provider no timer watches; session mode belongs to the session; test with a running fake timer; auto-dispose question answered by the contract (pinned by DT-07-12, DT-07-13) | 2.3, F-8, F-13 |
| R9 Sign-out data | `activity_wiring.dart:99-100`; `activity_journal.dart:102-141` | Contract assumption OD-8 followed: S03-16 builds the sheet using the existing coordinator and export; conflict with the map's "leave as is" recorded as DD-8 | 2.5, S03-16 |
| R10 Sources panel has little to read | only `FakeDeviceSource`; `primarySourceId` only in the cloud summary | Panel built from journal provenance counts and availability plus static rows; no `healthStatus()` call; Health Connect row follows AC-SRC-4 (DD-7) | 2.5 |
| R11 Backup exclusion path versus real journal layout (new) | `backup_rules.xml:35-40`; `journal_layout.dart:28-32`; map 68 | Verified FACT, unconditional: the fix lands in S03-0 before the flag flip (`activity_journal` excluded in all three XML sections, one shared constant); DT-0-6 reads the real tree | 2.1 item 6, F-31 |
| R13 Manual retry versus automatic schedule (GPT-PM MAJOR-01) | `activity_wiring.dart:101-164, 189-204` | One retry state machine for both sources (2.1 item 3): single flight, a manual failure keeps the original automatic deadline and index, a manual success cancels the timer and resets the index, `GaveUp` stops automatic attempts and a manual retry runs one attempt without a loop, `failedToOpen` has no automatic loop; the closure is refactored into a controller class in lane L1 and the existing retry test stays valid unchanged | 2.1 item 3, F-16, F-37, S03-0; DT-0-5, DT-0-11 to DT-0-14 |
| R12 Unknown build facts (new) | Flutter SDK version, import-graph allow-list, helper names in `progress_stats.dart`, sign-out call sites, `ob_shell` and `inputs` paths are not in the map | Each is a named "first step" of its story (S03-06, S03-01, S03-13, S03-16, S03-09); the design does not depend on the answer except where a fallback is stated | 2.1 to 2.6 |

### 9.4 Delivery risks

| Risk | Effect | Mitigation |
|---|---|---|
| Sprint size (DD-1): 19 unconditional stories, about 340 tests | Long sprint, late feedback | Lanes of 9.2; per-epic test runs; stories small and independently verifiable; operator may split (DD-1) |
| Shell restructure touches every tab | Regression on Back, padding, scanner | Existing tests unchanged as gates (AC-REG-1 to AC-REG-3, `back_navigation_test.dart`, `shell_insets_test.dart`); lanes L4a and L4b are sequential (L4b starts after the `ShellLayout` API of L4a) |
| HUD primitive extensions touch shared widgets | Golden or semantics regressions | Optional parameters with today's defaults; `hud_components_test.dart` and `hud_golden_test.dart` (map 251) run unchanged; CI-only golden failures are a known limit, not work (operator rule) |
| Russian text lengths | Overflow | Budget tests in `ru` first (AC-A11Y-5, AC-FAM-4) |
| Journal cost unknown | Slow dashboards | Gate G1 and G2 (3.8) |
| Apple behaviour only faked | False confidence | NOT_RUN entries recorded (1.8) |

### 9.5 Estimated number of tests

Designer's estimate before the review batch, about 340 in total (table 1.5; the plan counts 456, or 468 with the conditional stories, see plan 9.1): EP-0 and EP-1 about 20; EP-5 foundations (S03-02 to S03-07) about 102; EP-2 (S03-08 to S03-11) about 64; EP-3 and EP-4 (S03-12 to S03-16) about 80; input and conditional (S03-17, S03-19, S03-20) about 26; conformance (S03-18) about 60. The totals are the designer's INFERENCE; the test agents set the real count.

## 10. Open decisions, ungrounded items, inherited assumptions

### 10.1 Open operator decisions (in plain words, with what each option changes)

Contract decisions still open (FACT, contract 15). Each is restated with its default; the designer takes the default so the build can start, and the operator may overrule.

| Id | Question in words | Default taken | What changes if answered differently |
|---|---|---|---|
| OD-3 (roadmap decision D-9) | Is any mode or feature paid or gated? | No paywall, no lock icons | Gating needs a locked card state and an upsell path; neither is designed; add a story and a design sprint |
| OD-4 | What happens when a user taps a mode that is not built yet (Ride, Explore)? | "Coming later" sheet, mode unchanged, nothing collected | Allowing selection gives an empty lens that looks broken; a "tell me when ready" option needs a notification consent and storage |
| OD-5 | How do gym (strength) workouts appear on the new dashboard? | Not at all in S03: the dashboard shows recorded activity only | A read-only Gym tile needs a verified reader for gym duration and count and extra scope; copying gym workouts into the activity store was rejected in S02 |
| OD-6 | When does a brand-new account see the chooser, and who is spared it? | After onboarding, from Home, while status is `pending`; existing users see only a one-time intro card | Choosing before onboarding changes onboarding and its redirects |
| OD-7 | May the Recording strip be absent on pushed pages, including the workout page itself? | Yes; user leaves the workout page to see it | An app-wide overlay touches all 50 routes and raises regression risk |
| OD-8 | Is the sign-out warning (S03-16) built in S03, and who builds the consent centre? | Sign-out sheet in S03; consent centre is its own sprint before S04 | If not built, signing out gives no warning for data held only on the device |
| OD-10 | In which countries or stores does the first Phase 2 release ship? | No assumption; copy is Russian-first | A narrower list reduces languages, legal pages and listings |
| OD-11 | Who approves the privacy wording as a whole? | Wording is DRAFT, untouched by S03 | Release blocker for the privacy page only, not for S03 code |
| OD-12 | When are the iOS, iPadOS and macOS targets created? | Not in S03 | Earlier makes Apple criteria runnable on devices; layouts need no redesign either way |
| OD-13 | Does the main branch keep its name? | Keep | Only branch and release-note wording |
| OD-14 | May the third-party dossier be used or quoted? | S03 copy refers to no third-party source | Allows source references in the Sources panel wording |

Design-level questions raised by this document:

- DD-1 (scope size). The contract added responsive layouts, the rail, keyboard and pointer input to S03; the roadmap sizes S03 at 4 (unit not stated in the rows read) and this design has 19 unconditional stories. The test plan now counts 456 tests without the two conditional stories and 468 with them (plan 9.1; the design's earlier story estimates sum to 342, about 340 as a headline, so the plan is 33 percent higher). Operator decision, in plain words. Option A (default): keep ONE sprint and ONE pull request (rule: one PR per sprint). Consequence: a longer sprint, but one review, and the app is never half-changed in the middle (the new shell, the mode chooser and the dashboards arrive together). Option B: split into two sprints, for example shell and large-screen layouts (S03-02 to S03-07, S03-17, the two-pane parts of S03-12, S03-14, S03-15) in one and the mode state, chooser, dashboards and Sources in the other. Consequence: shorter gates and earlier feedback, but the shell and the dashboards would ship separately and the app would need a defined interim state (for example the old five-tab bar with the new mode screens, or the new shell with an empty dashboard slot), which adds work and its own tests, and the tablet and Mac layouts the operator asked for NOW would arrive later. Default: A (the operator said NOW and one PR per sprint).
- DD-2 (S03-0 acceptance). The contract has no AC for the journal-always-open story. Default: the plan's design tests DT-0-1 to DT-0-8 (1.6). Ask the contract owner to add AC ids if a stricter gate is wanted.
- DD-3 (conditional stories). S03-19 (width-cap frame for about 45 pushed pages) and S03-20 (reminder-tap routing, UNGROUNDED) have requirements but no AC. Default: S03-19 included, S03-20 included only if the code map shows a small, safe change; otherwise recorded as a known limit.
- DD-4 (one key above its budget). `modeBodyDesc` exceeds the 60-character description budget in English (section 6). Default: allow three lines in the 320 dp panel for that key.
- DD-5 (DoD wording). The sprint DoD refers to nine ARB key groups (6.10), not ten; corrected here.
- DD-6 (mode state scope). The contract keeps mode state per device (DQ-2); the operator brief asks for account-scoped state like the S02 journal binding. Default: account-scoped (the brief wins); effect on a shared device: a second account starts with `absent`, so an onboarded second account becomes `migrated` and sees the intro card once. Details: section 5.2. Storage is `activity.mode.v1.<uid>` in SharedPreferences (FACT pattern map 53-65).
- DD-7 (Health Connect row). Contract AC-SRC-4 makes the Health Connect row say "Not connected", but Phase 1 already has a Health Connect daily-data sync that a user may have authorised (`health_sync_card.dart`, `HealthService`, map 155-156). A Phase 1 user could see "Not connected" next to a sync that works. Option A (default): follow the contract; the row means workout-session import, which does not exist yet. Option B: show the real permission state from `healthAuthStatusProvider` (needs a contract change and an extra test). Option B is more truthful but means the Sources row reports daily data, not sessions.
- DD-8 (sign-out warning). The map proposes leaving sign-out as it is (`ActivityWipeCoordinator.onSignOut` is never called); the contract assumes S03 builds the warning sheet (OD-8). Default: build it (story S03-16). If the operator says no, S03-16 is dropped, AC-SO-1 and AC-SO-2 move to "not built", and signing out stays silent about local-only sessions.
- DD-9 (Home week rule). The Home week strip may use a different week start than the Monday rule of `progress_stats.dart`; this is not known (the map did not read `weekStripProvider`). Default: no change to Home's existing week section; the new blocks use Monday. If the rules differ the operator decides whether to align Home (changes an existing Phase 1 screen).
- DD-10 (journal read cost). If gate G2 of section 3.8 fails, S03 ships with a slower journal read and the fix is scheduled before S05; the operator decides whether to accept that or hold the release.
- DD-11 (backup exclusion). Turning the journal on in every build makes the Android backup exclusion paths matter in the default build (R11). The paths DO NOT match today (verified FACT, 2.1 item 6), so S03-0 unconditionally edits `backup_rules.xml` and `data_extraction_rules.xml` and lands that fix before the default flip; this is a privacy-relevant change and is listed so the operator and the security reviewer see it.

### 10.2 Items that could not be grounded (UNGROUNDED)

From the contract (FACT, contract 17, carried over; the number is the contract's item number): 1 whether `/onboarding/edit` is the only second entry into the finish code; 3 the existing Home week rule and whether a reader exposes gym workout duration and count; 4 the journal has no change stream, so refresh after `put` or `delete` is an architect question; 5 and 18 how the dock height and the rail insets reach `HudScreenBody` and the Progress list without double padding; 6 the notification payload-to-route mapping; 7 real Russian widths; 8 contrast over photographs; 13 whether another app-level "workout in progress" flag exists beyond the two timers (DQ-11); 14 the 600 and 840 dp breakpoints follow guidance that is not in the repository; 15 Apple specifics; 16 manifest resizability on Android 16; 17 hover and press tokens; 20 wallpaper crop on wide windows; 21 whether HUD pages show a visible Back control.

Added from the code map UNKNOWN list and the design: the paths of `ob_shell` and `inputs`; the sign-out call sites; the Flutter SDK version (sheet animation style); the names of the `progress_stats.dart` helpers; the Home week rule; the exact `/nutrition/add` and `/nutrition/weight` paths and the scheduled-session provider item shape; whether `Back` and `Cancel` keys exist; whether the import-graph guard needs an entry for the new `features/modes` folder; notification-tap routing; journal read cost; whether `provenance.first` is the top-priority source after a merge; how `SummaryProjection.effective` treats a field with no value; the real journal directory versus the backup exclusion paths. Each has a named first step in its story (9.3, R12) or a stated fallback.

### 10.3 Contradictions between the contract and the code

Between the map and the contract: (1) the map's UNKNOWN on whether the timers are auto-dispose is answered by contract F23 (plain provider, app-scoped rest timer); the design relies on the contract (pinned by DT-07-12, DT-07-13); (2) the map suggests leaving sign-out unchanged while the contract assumes S03 builds the warning sheet (DD-8); (3) the contract calls mode state per device (DQ-2) and the map's pattern is per uid; the operator brief and this design use per uid (DD-6); (4) the Health Connect row of AC-SRC-4 against the existing Phase 1 Health Connect sync (DD-7); (5) the map's journal path `activity_journal/<scopeId>` against backup rules that exclude `journal`, `sources`, `quarantine` directly under the files directory (R11, UNGROUNDED which is right); (6) the contract's trigger "chooser from Home" and the map's note that per-mode questions could join `kOnboardingOrder`: the design keeps them out of onboarding (2.3). Contradictions inside the contract (not code): the 60-character budget versus the English `modeBodyDesc` (DD-4); S03-0 without an AC (DD-2); the brief names ten AC families, the contract has seventeen (1.7).

### 10.4 Assumptions inherited from the contract: the designer's five assumptions DQ-16 (accepted by default)

FACT: contract 15, DQ-16 lists these as "assumptions added after the review of revision 3" for the operator. This design accepts them by default; any change is an operator decision and the affected stories are named.

| Assumption | In plain words | If the operator says otherwise | Stories affected |
|---|---|---|---|
| (a) | The rail shows an enabled Record button on all five tabs, including Scan and Profile, where the bottom bar shows no pill; chosen so the rail does not jump | A disabled slot with a reason wastes the space; the pill rule would then match the bar | S03-07, S03-05 (AC-WS-7, AC-WS-12) |
| (b) | Esc never means Back; it only closes the top-most surface | Esc-as-Back would conflict with closing popovers | S03-17 (AC-KB-1) |
| (c) | Two-pane layouts need a content pane of at least 880 dp, so a 1100 dp window with large text shows one column | A lower threshold would squeeze panes below their minimum widths | S03-12, S03-14, S03-15, S03-18 (AC-LS-9) |
| (d) | The rail form (96 dp or 240 dp) switches by measured label width, not by a fixed text scale | A fixed scale breaks with longer translations | S03-05 (AC-WS-3) |
| (e) | The compact rail shows a short state word and minutes while a session runs, not the full strip text | The extended form takes more width | S03-05, S03-07 (AC-WS-13) |

Other contract defaults taken as accepted (FACT contract 15): DQ-3 48 dp for new controls with 44 dp as the HUD exception; DQ-4 metric only; DQ-5 no "See all" and no "How this is calculated"; DQ-6 at most three questions per mode; DQ-8 a notification tap during sign-in is dropped; DQ-9 no photographs on cards; DQ-12 the width-cap frame is included for non-camera pages (S03-19); DQ-13 bundled fonts kept; DQ-14 rail and window thresholds as proposed; DQ-15 shortcut set as proposed pending the accessibility and Mac check. Answered by this design: DQ-2 (per-uid SharedPreferences key, 5.1), DQ-10 (Monday rule shared with `progress_stats.dart`, Home rule open as DD-9), DQ-11 (`ActiveSessionStatus` from the two timer providers, 2.6). Still open: DQ-7 (where a skipped question can be revisited; the contract does not specify it, S03 offers no revisit entry except the switcher line "{n} quick questions").

### 10.5 Documentation follow-up (RV-17)

Not done by this design (stale documents found, not changed). A `doc-updater` pass is needed, in the S03 closing commit or earlier:
1. `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`: add a row for the mode state (`activity.mode.v1.<uid>`: device-local preference, SharedPreferences, excluded from backup, removed by the account-deletion wipe) and a row or note "local journal on by default + backup exclusion" (journal root `activity_journal/<scopeId>`, excluded in `backup_rules.xml` and both sections of `data_extraction_rules.xml`).
2. `core/DATA_INVENTORY_2026-08-11.md`: record the local journal being on by default and name the `activity_journal` directory and its backup exclusion.
3. OD-12 (Apple targets) note: creating an Apple target requires implementing the `isExcludedFromBackup` marking of the journal before release, because the journal is on by default (the Android exclusion rules do not cover Apple platforms; `journal_layout.dart` already documents the iCloud/iTunes inclusion of Application Support).

## Review disposition (internal review, batch 1)

Five independent reviewers (architect, flutter-reviewer, silent-failure-hunter, security-reviewer, tdd-guide) reviewed the design and the test plan: 0 BLOCKER and 21 distinct MAJOR or MINOR root causes after merging duplicates. The decisions are FINAL for this batch and were applied as written, with the three contract interactions listed after the table. Source of the decisions: the coordinator's remediation file (`s03_remediation_batch1.md` in the session scratchpad). Test ids are owned by `S03_TEST_PLAN.md`: its section 8.7 maps every RV to tests, section 8.1 maps every failure row to tests and section 10 maps stories to tests. The ids in the last column below are copied from plan section 8.7.

| RV id | Reviewers | Severity | Decision (short) | Where applied in the design |
|---|---|---|---|---|
| RV-1 | architect, flutter-reviewer, silent-failure-hunter | MAJOR | One writer for the chooser status: atomic `ModeNotifier.initIfAbsent(source)`; the migration runs once per process per uid and only when the first profile value loaded in this process is already onboarded; the onboarding hook owns the later transition and writes `pending`; the hook awaits the provider future, checks `mounted`, never blocks `/home` | 2.2, 5.6, F-4, F-6, F-36; tests DT-01-12 to DT-01-15, AC-CH-8a to 8d |
| RV-2 | silent-failure-hunter | MAJOR | `ModeStore.read` returns `missing`, `value` or `unreadable`; unreadable is never overwritten at start; newer version read-only for the run; corrupt replaced only by an explicit user action; unavailable stored mode coerced in memory only; `AsyncError` gives default state, no chooser, no writes | 2.2, 5.1, F-3, F-36; tests DT-01-1 to DT-01-3, DT-01-16 to DT-01-19 |
| RV-3 | architect, flutter-reviewer, silent-failure-hunter, security-reviewer | MAJOR | `JournalAvailability` = `notEnabled`, `binding`, `open`, `gaveUp`, `failedToOpen`; `open` only when bound for the current uid; digests carry `ownerUid` and a generation and stale completions are discarded; synchronous reset on uid change; `binding` shows LOADING never EMPTY; refresh triggers and coalescing owned by the notifier | 2.1, 3.1, 3.6, 3.7, F-15, F-37, F-38; tests DT-13-8 to DT-13-15 |
| RV-4 | architect, security-reviewer, flutter-reviewer | MAJOR | `ActiveSessionOwner{uid, destination}` captured when the timer starts, never recomputed; strip and pill hidden when the owner differs from the current uid; owner cleared by an explicit `ref.listen` | 2.6, F-11; tests DT-07-8, DT-01-7 |
| RV-5 | architect | MAJOR | File-ownership table (path to lane), "a path appears in at most one lane"; inset adoption only through `HudScreenBody` and `ShellLayout`; `app_router.dart` owned by lane L5 alone; L4 split into L4a and L4b; S03-18 fixes owned by lane L12; critical path re-checked | 9.2, 9.1, 1.5, 1.6 |
| RV-6 | flutter-reviewer, architect | MAJOR | The `ShellRoute` child keeps one `GlobalKey` slot across bar and rail swaps; `PopScope` and `_AnnounceShellCanPop` stay outside the swap; `back_navigation_test.dart` unchanged and green | 2.6, F-21; tests DT-05-3 and back_navigation_test.dart unchanged |
| RV-7 | flutter-reviewer, architect | MAJOR | Chooser Back equals "Decide later"; `offeredThisRun` keep-alive provider per uid; Home waits for the Day-3 decision before offering the chooser. The `push` part conflicts with the contract (see below): the contract's replace is kept | 2.3, 5.6, F-5, F-39; tests DT-08-7 to DT-08-9 |
| RV-8 | flutter-reviewer | MAJOR | `ActiveSessionStatus` owns one-shot timers at `endsAt` and `endsAt + 10 min` with an injectable factory, cancelled on dispose, re-armed on change; the seconds tick stays widget-local in a `RepaintBoundary` | 2.6; tests DT-07-9, DT-07-10, DT-07-3 |
| RV-9 | flutter-reviewer | MAJOR | Every `AdaptiveSurface` placement is a route that reads `WindowSizeInfo` live; Back closes it; the depth counter is decremented in `try/finally` and reset on account change | 2.6; tests DT-06-2 to DT-06-4, AC-WS-14b |
| RV-10 | silent-failure-hunter | MAJOR | The bind status carries `recoveredAbsentCount` and `streamLostCount`; one plain notice on Sources and Progress above zero; aggregates carry a "may be incomplete" marker | 2.1, 3.6, 6.7, F-40; tests DT-13-16, DT-14-5, DT-15-4 |
| RV-11 | silent-failure-hunter | MAJOR | `lastLoadFailedAt`; after a failed refresh the same-uid value is kept with "Showing data from <time>" and Try again, and a "Problem" chip on Sources; `unreadableSessions` counted apart from "no data" | 3.1, 3.6, 6.7, F-41; tests DT-13-12, DT-13-17, DT-14-6, DT-15-5 |
| RV-12 | silent-failure-hunter | MAJOR | Sign-out guard: any availability other than `open` means "cannot check" (sheet with Try again and Sign out anyway); export or delete first, sign out after success; a failing export or wipe keeps the user signed in; "deleted" never shown unless the wipe returned. Interacts with contract J10 (see below) | 2.5, 6.9, F-19, F-42, F-45; tests DT-16-2, DT-16-4 to DT-16-7 |
| RV-13 | silent-failure-hunter, security-reviewer, architect | MAJOR | Android backup exclusion is wrong today (verified) and is fixed unconditionally in S03-0, before the default flip: one constant for the scoped root, `activity_journal` excluded in all three XML sections, tests updated, `journal_layout.dart` claim corrected, DT-0-6 rewritten against the real tree; accepted rollback model recorded | 1.6 (S03-0), 2.1 item 6, 4.4, 9.3 (R11), 10 (DD-11), F-31; tests DT-0-6 to DT-0-8 |
| RV-14 | security-reviewer | MINOR | The mode store refuses a uid that is being or was wiped, extending DT-01-7 | 5.3, F-43; tests DT-01-20 |
| RV-15 | security-reviewer | MINOR | `/mode-questions/:mode` must parse to an available mode or redirect Home with no write; S03-20 maps payloads through a fixed allow-list, requires an existing own session, ignores the tap while signed out or onboarding | 2.3, 7.2, F-33, F-44; tests DT-09-6, DT-20-5 |
| RV-16 | security-reviewer, silent-failure-hunter | MINOR | S03-16 first step records where the export writes (cache location outside backup, deleted after share, bound to the departing uid); every swallowed failure logs a fixed message, a content-free code and the exception type only | 2.5, 7.2, F-14, F-45; tests DT-16-8, DT-13-18, DT-01-15 |
| RV-17 | security-reviewer | MINOR | Documentation follow-up for the doc-updater (matrix rows, data inventory, Apple note) | 10.5 (Documentation follow-up) |
| RV-18 | flutter-reviewer | MINOR | (a) one warm-up `Provider<void>`; (b) reactive `WindowSizeInfo`; (c) memoised rail measurement; (d) `CallbackShortcuts` with an autofocus root, tab shortcuts only on shell routes; (e) animated dock padding and `RepaintBoundary` | 2.2, 2.6; tests DT-01-21 (a), AC-WS-3 and DT-02-3 (b), DT-05-5 (c), DT-17-3 and DT-17-4 (d), DT-07-11 (e) |
| RV-19 | silent-failure-hunter | MINOR | A missing or unmapped source kind is labelled "Unknown source" (a parsed `fileImport` keeps "File import" per contract 8.1); the Health Connect row keeps the contract wording, with the false-status risk recorded in DD-7 | 3.5, 6.7, DD-7; tests DT-13-19, DT-15-6 |

Contract interactions (the contract stays authoritative):
1. RV-7 says Home opens the chooser with `push`. Contract J1 step 2 says the chooser is opened once "(replace, so Back does not return to the empty Home behind it)". Kept: the contract. Home still uses `go('/mode-chooser')` on the first run; the remaining RV-7 rules (Back equals Decide later, `offeredThisRun`, wait for the Day-3 decision) are applied. The switcher's "See all modes" still uses `push`.
2. RV-12 says availability other than `open` means "cannot check". Contract J10 says "an empty or unavailable journal signs out with no prompt" and AC-SO-2 covers the empty journal. Interpretation (PROPOSED): `notEnabled` (no journal exists, opt-out build or test override) and an `open` empty journal sign out with no prompt, as the contract says; `binding`, `gaveUp` and `failedToOpen` (a journal that exists but cannot be read) get the "cannot check" sheet, because silent sign-out could hide data loss. Accepted by the coordinator as a refinement of J10 and ACCEPTED by the GPT-PM documentation gate round 1 ("retain the explicit Sign out anyway path"), which the design keeps (2.5, F-42). The reason for the refinement: a journal that exists but cannot be read (`binding`, `gaveUp`, `failedToOpen`) may hold activity that a silent sign-out would hide or lose, whereas a build with no journal (`notEnabled`) or an empty open journal has nothing to lose.
3. RV-19, Health Connect: the contract fixes the row to "Not connected" (AC-SRC-4), so the wording stays and DD-7 records the false-status risk.
4. RV-19, labels: contract 8.1 states that the parser maps an unknown stored kind to `fileImport` and that its label is "File import", and AC-SRC-6 tests that label. Kept: the contract. RV-19 is applied to what the contract does not fix: a missing or unmapped kind shows "Unknown source".

### GPT-PM round 1 disposition (documentation gate on 3bedcba4: MODIFY, 1 MAJOR, 0 BLOCKER)

| Finding | Decision | Where applied |
|---|---|---|
| MAJOR-01 The design kept the automatic journal-bind retry schedule (5 s, 15 s, 60 s, 5 min, 5 min, then gave up) and added a manual `retryNow()` without defining the combined behaviour; plan DT-0-5 required "no automatic loop", which contradicted the retained schedule (verified FACT against `activity_wiring.dart:101-164, 189-204`) | ONE retry state machine for automatic and manual attempts: states `Idle/Bound`, `Attempting(source)`, `WaitingRetry(i, deadline)`, `GaveUp`; rules 1 to 7 (single flight, a manual failure leaves the original deadline and index intact, a manual success cancels the timer and resets the index, `GaveUp` stops automatic attempts and a manual retry runs one attempt without a loop, a due timer during an in-flight manual attempt is re-armed with the same index, a generation bump resets everything, `failedToOpen` has no automatic loop). The closure in `activityJournalBindingProvider` is refactored into a controller class in `activity_wiring.dart` (lane L1) with behaviour-preserving automatic retries; `activity_journal_binding_retry_test.dart` stays valid unchanged. DT-0-5 is rewritten as single flight; DT-0-11 to DT-0-14 are new (plan ids) | 2.1 item 3, F-16, F-37, F-38, S03-0 story and DoD, lane L1 file table (9.2), R13 (9.3); tests DT-0-5, DT-0-11 to DT-0-14 |
| Sign-out guard refinement (RV-12 against contract J10): ACCEPTED by GPT-PM, "retain the explicit Sign out anyway path" | Kept: `binding`, `gaveUp` and `failedToOpen` get the "cannot check" sheet with Try again and Sign out anyway; `notEnabled` and an open empty journal sign out with no prompt | 2.5, F-42, contract interaction 2 of the batch 1 disposition; tests DT-16-4, DT-16-2 |

Test counts: the test plan owns them (section 9.1: 456 planned tests without the two conditional stories, 468 with them). The per-story figures in design 1.5 are estimates made before the review batch.
