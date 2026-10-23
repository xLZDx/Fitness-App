# FitnessUp v1: module / route / action matrix (release reachability)

Status: DRAFT, partial trace. Companion to `docs/v1/MODULE_DISPOSITION_MATRIX.md` (46 modules, import-scan only). This file links each disposition to the entry points that reach the module, the gate that closes it in a release build, and the release test that must prove it. It answers review finding M-05 (the disposition matrix is not an executable release-scope gate).

Method: read-only source reading of `D:\tmp\scratch_worktrees\v1design\mobile\lib` (this tree is master). No build, no test run. Paths below are relative to `mobile/`. Evidence tags: FACT (file:line read), INFERENCE (reasoned from facts), UNKNOWN (not traced; the check still owed is named).

Scope limit (stated honestly): the coordinator stopped the trace early. Section 6 lists the modules that were NOT traced. Do not treat any row of those modules as verified.

## 1. Gate mechanisms found

| Gate | What it does | Evidence |
|---|---|---|
| Demo gate (route) | `resolveRedirect` returns `/home` for a demo-gated path when `demoFeaturesEnabled` is false; runs after the sign-in rule. Gated set: `/community`, `/celebrity-plans`, `/contribute`, `/moderate`, `/coaches`, `/team/*`, `/coaches/*`. | FACT `lib/core/router/app_router.dart:90-99,116` |
| Demo flag value | `kDemoFeaturesEnabled = !kReleaseMode \|\| bool.fromEnvironment('DEMO_FEATURES')`; a release build built with `--dart-define=DEMO_FEATURES=true` reopens every gated route and entry. | FACT `lib/core/config/demo_features.dart:22-23` |
| Demo flag provider | Router and Profile read `demoFeaturesEnabledProvider` (defaults to the constant, test-overridable). | FACT `demo_features.dart:29-30`, `app_router.dart:414`, `profile_page.dart:29` |
| Demo flag constant (not provider) | Settings `/moderate` row and exercise reference `/contribute` button read the compile-time constant directly. Two mechanisms for one flag. | FACT `lib/features/settings/settings_page.dart:290-293`, `lib/features/equipment/widgets/exercise_reference.dart:844-849` |
| Auth gate | Signed-out users reach only `/splash /login /about /licences /terms /privacy`. `/donors` is not public. | FACT `app_router.dart:77,112` |
| GPS recorder build flag | `kGpsRecorderBuild = bool.fromEnvironment('GPS_RECORDER')` (default false); recorder wired only if flag, not web, Android, account-scoped journal. Otherwise `gpsRecorderEnabledProvider` stays `false` and `buildS04Routes` returns no routes. | FACT `lib/features/activity/repository/file_activity_journal.dart:111`, `lib/main.dart:198-202,588-590`, `lib/features/workouts/state/active_session_status.dart:527`, `lib/core/router/s04_routes.dart:26` |
| Mode availability table | `/mode-questions/:mode` redirects to `/home` unless the mode is `available`. Default table: Train and Body are `available`; Explore and Ride are `comingLater`. | FACT `lib/core/router/s03_routes.dart:39-49`, `lib/features/modes/data/mode_models.dart:46-51` |
| Day-3 modal provider | `day3WelcomeModalEnabledProvider` defaults to `false`. | FACT `lib/features/moments/state/moment_providers.dart:14`, `lib/features/home/home_page.dart:182` |

Entry-point classes checked across `lib/`:
- Route table: all `GoRoute` paths in `app_router.dart:428-731`, `s03_routes.dart:104-126`, `s04_routes.dart:28-51`.
- Programmatic navigation: every `context.go/push/pushReplacement`, `GoRouter.of(context).*`, `router.*` call (grep over `lib/`).
- Deep links: `android/app/src/main/AndroidManifest.xml` MainActivity has only MAIN/LAUNCHER and the Health Connect rationale intent filters (lines 73-83) and an activity-alias for permission usage (99-108). No VIEW/BROWSABLE URL filter. FACT. iOS Info.plist and web not checked: UNKNOWN.
- Notifications: `LocalNotificationService` calls `_plugin.initialize(init)` with no tap-response callback (`lib/core/notifications/local_notification_service.dart:59`); payload is the reminder id (`:151`). No `onDidReceiveNotificationResponse` anywhere in `lib/`. FACT. So no notification tap navigates. INFERENCE: a reminder tap only foregrounds the app.
- Keyboard shortcuts: tabs 1-5, Shift+R record sheet, Shift+M mode switcher, `[` back, Cmd+`,` settings (`lib/shared/widgets/app_shortcuts.dart:181-188`). They reach only shell tabs, the Record sheet, the switcher and `/settings`. FACT.
- Quick actions / app widgets / push (FCM): no `quick_actions`, `home_widget`, `firebase_messaging`, `app_links` or `uni_links` found in `pubspec.yaml` (only `flutter_local_notifications`). FACT (grep).
- Persisted preferences that can resurrect an entry: recorded GPS sport (`meta.sport` in `lib/features/recording/journal/file_recording_journal.dart:135,791,1179`), mode answers (`modeStateProvider`), moment counters (`PrefsMomentRepository`). See rows below.

## 2. Per-module table

Columns: Disp = disposition in the disposition matrix. Reachable in release (default build: no `DEMO_FEATURES`, no `GPS_RECORDER`): YES / NO / UNKNOWN. "Test" refers to proposed ids in section 5.

### 2.1 KEEP modules traced

| Module | Disp | Entry points found (file:line) | Closing gate in release | Reachable in release | Required release test |
|---|---|---|---|---|---|
| goal_photo | KEEP | none. Only file `data/goal_photo_request.dart`; no import of `goal_photo` from any other file under `lib/` (grep for `goal_photo\|GoalPhoto` outside the module: 0 hits). FACT | none (not wired) | NO (not compiled into any screen; INFERENCE: not in the import graph from `main.dart`) | FU-AC-130, FU-AC-137 |
| body_comp | KEEP | none. Only `data/body_comp_estimate.dart`; grep outside module finds only unrelated `BodyCompositionEstimator` in `body_scan` (`lib/features/body_scan/data/provisional_estimator.dart:49`). FACT | none | NO | FU-AC-130, FU-AC-137 |
| cycle_aware | KEEP | data enum `CyclePhase` imported by `ai_planner` (`lib/features/ai_planner/data/plan_builder.dart:3`, `data/workout_plan.dart:1`, `plan_reason_text.dart:3`). No page, route or input UI inside the module. FACT. Where `cycle.phase` is supplied is UNKNOWN (owed: trace the `cycle` argument of the plan builder to its provider) | none | UNKNOWN (enum is compiled in; user-facing input not found) | FU-AC-130, FU-AC-137 |
| voice | KEEP | none. Only `data/voice_command.dart`; grep `voice_command\|VoiceCommand` outside the module: 0 hits. The spoken-cue coach is a different thing (`voiceCoachProvider`, `lib/main.dart:671`) and is not this module. FACT | none | NO | FU-AC-130, FU-AC-137 |
| personalisation | KEEP | no page. Providers consumed by `ai_planner` (`state/ai_planner_providers.dart:7`), `workouts_page.dart:20`, `programmes/state/programme_providers.dart:7`, `equipment/state/equipment_providers.dart:20`, `home/data/suggestion_builder.dart:2`, `onboarding/state/plan_preview_provider.dart:8`. FACT | n/a (logic only) | YES, indirect (shapes plan/suggestion output, no screen of its own) | FU-AC-131 |
| training_context | KEEP | selector widget mounted on Home (`home/home_page.dart:27-28`) and AI planner (`ai_planner/ai_planner_page.dart:11-12`); read by `modes/pages/mode_chooser_page.dart:33-34`, `mode_question_page.dart:34-35`, `mode_switcher_sheet.dart:27-28`. FACT | none needed | YES (Home, AI planner, mode screens) | FU-AC-131 |
| recovery | KEEP | `DeloadBanner` imported by Home (`home/home_page.dart:24`); providers used by `ai_planner_providers.dart:9` and `onboarding/state/plan_preview_provider.dart:9`. Banner contains a `/subscription` push (`recovery/widgets/deload_banner.dart:113`). FACT | none needed | YES (banner on Home) | FU-AC-131 |
| safety | KEEP | onboarding screening steps (`onboarding/steps/step_screening.dart:7-8`, `step_health_flags.dart:7-8`, `step_preview.dart:9`), eligibility notice in Home, workouts, AI planner, workout player, exercise reference, machine card (`home_page.dart:25-26`, `workouts_page.dart:28-30`, `ai_planner_page.dart:10`, `equipment/workout_player_page.dart:14-16`, `equipment/widgets/exercise_reference.dart:39`, `visual_equipment/widgets/machine_card_view.dart:12`). FACT | none needed | YES | FU-AC-131 |
| home | KEEP | shell tab `/home` (`app_router.dart:710-713`), post-login/splash target (`splash_page.dart:102`, `login_page.dart:127`). FACT | n/a | YES | FU-AC-132 |
| workouts | KEEP | tab `/workouts` (`app_router.dart:718-721`); routes `/workout/:id`, `/exercise/:id`, `/workout-summary` (`:481-510`); callers `home_page.dart:713,1223,1270,1370`, `workouts_page.dart:635,1128`. FACT | n/a | YES | FU-AC-132 |
| equipment | KEEP | `/equipment/:id`, `/exercise/:id` (`app_router.dart:464-487`); from scanner (`scanner/scanner_page.dart:553`). FACT | n/a | YES | FU-AC-132 |
| scanner | KEEP | tab `/scan` (`app_router.dart:714-717`), `/scan-history`, `/scan-history/:id` (`:455-463`); links `scanner_page.dart:1289`, `scanner/history/scan_history_page.dart:199`, Home `home_page.dart:1036`, Workouts `workouts_page.dart:457`, Record sheet `modes/widgets/record_sheet.dart:157`. FACT | n/a | YES | FU-AC-132 |
| form_check | KEEP | `/form-check` (`app_router.dart:677-680`); callers `workouts/workouts_page.dart:447`, `equipment/widgets/exercise_reference.dart:870`, Record sheet `record_sheet.dart:161`. FACT | n/a | YES | FU-AC-132 |
| posture | KEEP | `/posture` (`app_router.dart:681-686`); caller `home_page.dart:1149`. FACT | n/a | YES | FU-AC-132 |
| ai_planner | KEEP | `/plan` (`app_router.dart:551-554`); callers `home_page.dart:593,1091`. FACT | n/a | YES | FU-AC-132 |
| progress | KEEP | tab `/progress` (`app_router.dart:722-725`). FACT | n/a | YES | FU-AC-132 |
| progress_photos | KEEP | `/photos`, `/photos/scan`, `/photos/compare` (`app_router.dart:559-575`); callers `profile_page.dart:158`, `progress/progress_page.dart:505,538,596`, `body_scan_flow_page.dart:124`. FACT. Photos repo has its own demo flag provider (`progress_photos/state/progress_photos_providers.dart:175`); its effect in release was not traced: UNKNOWN | provider default (demo flag) | YES (route open); data backing UNKNOWN | FU-AC-132, FU-AC-138 |
| body_scan | KEEP | `/body-scan`, `/body-scan/history`, `/body-scan/privacy`, `/body-scan/result/:scanId` (`app_router.dart:577-583,653-662`); entry card widgets `body_scan/widgets/body_scan_entry_card.dart:57-122`; Record sheet `record_sheet.dart:168`. FACT | n/a | YES | FU-AC-132 |
| nutrition_plan | KEEP | `/nutrition`, `/nutrition/profile`, `/nutrition/weight`, `/nutrition/sources`, `/nutrition/how-it-adapts` (`app_router.dart:589-601,644-651`); entry card `nutrition_plan/widgets/nutrition_entry_card.dart:43`. FACT | n/a | YES | FU-AC-132 |
| food_diary | KEEP | `/nutrition/diary`, `/nutrition/add*` (`app_router.dart:603-643`); Record sheet `record_sheet.dart:173-175`. FACT | n/a | YES | FU-AC-132 |
| modes | KEEP | `/mode-chooser`, `/mode-questions/:mode`, `/sources` (`s03_routes.dart:104-126`); Home auto-offers chooser (`home_page.dart:157`); switcher sheet pushes (`modes/widgets/mode_switcher_sheet.dart:191,233`); shortcut Shift+M (`app_shortcuts.dart:184-185`). FACT | mode availability table for `/mode-questions/:mode` | YES; which modes are `available` UNKNOWN | FU-AC-133 |
| recording | KEEP | `/record/gps`, `/record/manual` only when recorder flag on (`s04_routes.dart:26-51`). Entry: Record sheet GPS row (`record_sheet.dart:127-145`), active-session strip destination (`active_session_status.dart:465`), `?mode=resume` link (`s04_routes.dart:22`). FACT | build flag `GPS_RECORDER` (default off) + Android only | NO in default build (route not registered). YES in a `GPS_RECORDER=true` Android build, including hiking/cycling (section 4) | FU-AC-134, FU-AC-135 |
| activity | KEEP | digests refresh on resume (`main.dart:859-866`); journal opened only with `ACTIVITY_CLOUD_STREAMS` (`main.dart:578-580`). Sign-out guard: Profile "Sign out" calls `confirmSignOutWithLocalData` (`profile_page.dart:287-291`), guard in `features/activity/state/sign_out_guard.dart`, sheet `activity/widgets/sign_out_warning_sheet.dart`. FACT (call site read; guard body not read). This affects the queue sign-out design (`LOCAL_QUEUE_DECISION.md`): sign-out is not a plain `signOut()`. Other screen entries not traced: UNKNOWN | cloud flag default off | YES for the sign-out sheet (Profile tab); rest UNKNOWN | FU-AC-132 |
| subscription | KEEP | `/subscription` (`app_router.dart:511-514`); callers `profile_page.dart:231`, `about_page.dart:153`, `body_scan_entry_card.dart:65`, `workouts_page.dart:771`, others. FACT | n/a | YES | FU-AC-132 |
| auth | KEEP | `/login` (public) (`app_router.dart:432-435`); guest link `profile_page.dart:277`. FACT | n/a | YES | FU-AC-132 |
| onboarding | KEEP | `/onboarding`, `/onboarding/edit` (`app_router.dart:436-451`). FACT | n/a | YES | FU-AC-132 |
| profile | KEEP | tab `/profile` (`app_router.dart:726-729`), `/injuries` (`:531-536`). Coaching and Community sections wrapped in `if (demoEnabled)` (`profile_page.dart:166,200`). FACT | demo flag provider | YES (tab); Coaching/Community rows NO | FU-AC-131, FU-AC-136 |
| settings | KEEP | `/settings` (`app_router.dart:537-540`); callers `profile_page.dart:258`, `s04_routes.dart:37`, shortcut `app_shortcuts.dart:161`. `/moderate` row guarded by compile-time constant (`settings_page.dart:290`). GPS consent row only when recorder on (`settings_page.dart:195`). FACT | demo constant; recorder flag | YES | FU-AC-132, FU-AC-136 |
| account_deletion | KEEP | `/delete-account` (`app_router.dart:541-546`); callers `settings_page.dart:314`, `onboarding_page.dart:288`. FACT | n/a | YES | FU-AC-132 |
| data_export | KEEP | `/backup` (`app_router.dart:663-666`); caller `settings_page.dart:242`. FACT | n/a | YES | FU-AC-132 |
| legal | KEEP | `/terms`, `/privacy` (public). FACT | n/a | YES | FU-AC-132 |
| licences | KEEP | `/licences` (public), `settings_page.dart:261`. FACT | n/a | YES | FU-AC-132 |
| about | KEEP | `/about` (public), `settings_page.dart:148`, `profile_page.dart:241`. FACT | n/a | YES | FU-AC-132 |
| splash | KEEP | initial location `/splash` (`app_router.dart:396`). FACT | n/a | YES | FU-AC-132 |

### 2.2 HIDE / login-only / DEFER modules traced

| Module | Disp | Entry points found | Closing gate in release | Reachable in release | Required release test |
|---|---|---|---|---|---|
| marketplace | HIDE | `/coaches` (`app_router.dart:695-698`), gated incl. `/coaches/*`; Profile row `profile_page.dart:179` inside `if (demoEnabled)`. FACT. Provider wiring stays live: `coachMarketplaceServiceProvider` is overridden with the Cloud service (`main.dart:764-765`); the listing repo stays Mock (`main.dart:754-763`). | demo gate + Profile `demoEnabled` | NO via UI/deep link (given default flag). Provider still constructed lazily; not reachable without a screen. INFERENCE | FU-AC-136, FU-AC-139 |
| community | HIDE | `/community` (`app_router.dart:667-670`), `/team/:teamId` (`:671-676`); Profile row `profile_page.dart:213`. FACT | demo gate (exact + `startsWith('/team/')`) | NO | FU-AC-136 |
| social_feed | HIDE | only importer is the router (`app_router.dart:58`), page mounted at `/community` (`:669`). FACT (resolves the "appears to be" wording in the disposition matrix) | demo gate via `/community` | NO | FU-AC-136 |
| celebrity_plans | HIDE | `/celebrity-plans` (`app_router.dart:555-558`); Profile row `profile_page.dart:192`. FACT | demo gate | NO | FU-AC-136 |
| catalog | HIDE | `/contribute`, `/moderate` (`app_router.dart:687-694`); buttons `equipment/widgets/exercise_reference.dart:849` (guarded by constant `:844`), `settings/settings_page.dart:293` (guarded by constant `:290`). FACT | demo gate + compile-time constant at both buttons | NO | FU-AC-136 |
| moments | HIDE | Home `initState` runs `bumpLaunchCount`, `hasShown`, `launchCount`, `firstLaunchAt` unconditionally (`home_page.dart:169-173`), then returns at `:182` when the provider is off. FACT | provider default `false` | Modal NO. The persisted launch counter is still written in release (see D-08). | FU-AC-139 |
| donor_wall | KEEP login-only | `/donors` not public (`app_router.dart:77`), button on public About page (`about_page.dart:166`); `donorWallRepositoryProvider` is the cloud one (`main.dart:654-655`). FACT | auth redirect to `/login` | YES for signed-in users; NO for signed-out (redirect) | FU-AC-137 (auth case) |
| buddy | DEFER | no import of `buddy` or `buddy_match` anywhere in `lib/` (relative imports included: grep `(features\|\.\.)/buddy/` and `BuddyMatch`: 0 outside module). FACT | none (unwired) | NO | FU-AC-130 |
| sdk_export | DEFER | same: 0 importers by path or `SdkExport` name. FACT | none (unwired) | NO | FU-AC-130 |

## 3. Discrepancies

Each: id, claim, evidence, consequence, proposed resolution (document or change; no code was changed here).

- D-01 (KEEP module with no reachable entry): `goal_photo` is classified KEEP ("body") but has no importer; no route, button or provider reaches it. FACT (section 2.1). Resolve by operator decision: re-classify DEFER, or file a wiring story. The disposition matrix already says "confirm it is reachable before claiming v1"; the answer is no.
- D-02 (KEEP without entry): `body_comp` (Navy-formula estimate), same evidence as D-01. The body_scan module has its own unrelated estimator. FACT.
- D-03 (KEEP without entry): `voice` (command parser) has no importer. The disposition matrix already notes "parser only"; there is nothing to reach. FACT.
- D-04 (KEEP with only a data-level link): `cycle_aware` is only the `CyclePhase` enum used inside the AI planner's reasons; no input UI in the module. Whether any phase value is ever supplied in v1 is UNKNOWN. Resolve: trace the plan builder's `cycle` argument source; if constant null, re-classify DEFER.
- D-05 (HIDE gate has a build-time bypass): any release build compiled with `--dart-define=DEMO_FEATURES=true` reopens marketplace, community, social_feed, celebrity_plans and catalog (`demo_features.dart:22-23`). No file in the reviewed tree forbids that define in a release pipeline. Resolve: a release-build check that the define is absent (FU-AC-136).
- D-06 (two mechanisms for one gate): Profile and the router read `demoFeaturesEnabledProvider`; Settings `/moderate` and exercise-reference `/contribute` read the constant `kDemoFeaturesEnabled` (`settings_page.dart:290`, `exercise_reference.dart:844`). A test that overrides the provider cannot prove those two buttons are closed. Resolve: one shared test that builds both widgets and checks the constant value, or move both to the provider (change, out of scope here).
- D-07 (deferred sports still startable): `kGpsStartSports` lists hiking and cycling (section 4). Reachable only with `GPS_RECORDER=true` on Android, but v1 defers outdoor cycling and hiking.
- D-08 (HIDE module still has live side effects): `moments` is hidden by `day3WelcomeModalEnabledProvider=false`, but Home still increments and persists the launch count on every start in release (`home_page.dart:169-173`; store is `PrefsMomentRepository`, `main.dart:535,796`). Not a user-visible entry; it is a persisted preference written by a HIDE module. Decide whether acceptable.
- D-09 (HIDE module with real backend wiring): marketplace's Stripe Connect service is bound to the Cloud implementation in `main.dart:764-765`, while its listings remain Mock. The route is gated, so no UI reaches it. The wiring comment (`main.dart:754-763`) says both should change together; today they do not. INFERENCE: harmless while the route stays gated.
- D-10 (gate edge cases untested in the files read): gated-path matching is exact for five paths plus `/team/` and `/coaches/` prefixes on `state.matchedLocation` (`app_router.dart:90-99,401`). Behavior for a trailing slash (`/community/`) or a bare `/team` is UNKNOWN (owed: go_router normalisation check or a test).
- D-11 (disposition matrix text drift): matrix row for `social_feed` says "appears to be reached only through `/community`"; now FACT (router is the only importer). Matrix rows for `buddy` and `sdk_export` say "relative imports not checked"; now checked: none. Matrix row for the seven "open checks" is answered in sections 2.1 and 6. These are stale statements in `docs/v1/MODULE_DISPOSITION_MATRIX.md`; not changed here.
- D-12 (no deep-link, notification-tap or quick-action surface): this is a finding in favor of release scope, recorded so tests can pin it: the manifest has no URL filter and notification taps have no handler. If either is added later, the demo gate in `resolveRedirect` is the only barrier. FACT for Android manifest; iOS UNKNOWN.

## 4. Deferred GPS sports (hiking, cycling)

Where they can still be started (only in a build with `GPS_RECORDER=true` on Android; otherwise the whole recorder route is absent):

1. Start screen sport chips: `kGpsStartSports = [walking, running, hiking, cycling]` (`lib/features/recording/widgets/gps_format.dart:76-81`), rendered by `GpsSportRow` (`lib/features/recording/widgets/gps_start_panels.dart:32`). FACT.
2. Selected sport goes straight to the recorder: `recorder.requestStart(sport: _sport, ...)` (`lib/features/recording/widgets/gps_start_flow.dart:438`); the page default is `walking` (`gps_start_flow.dart:204`, `pages/gps_recording_page.dart:207`). No allow-list check was found between the chip and `requestStart`: INFERENCE. `requestStart` (`recorder_controller.dart:174-209`) was read only in part; owed: read the `_preconditions` body to confirm no sport is validated.
3. Entry to the Start screen: Record sheet GPS row. In Train and Body it is the last row; in Ride and Explore it is the only row (`record_sheet.dart:127-145`). Ride and Explore are `comingLater` (`mode_models.dart:46-51`), so the recorder is reachable only through Train and Body in a `GPS_RECORDER=true` Android build. FACT for the table; that a `comingLater` mode can never be the selected mode is INFERENCE (chooser/switcher refusal not traced). The modes disposition says cycling and hiking "stay closed by the capability policy"; the Record sheet code shows no such check for the sport, only for the mode.
4. Direct route `/record/gps` and `/record/gps?mode=resume` (`s04_routes.dart:22,29`). The route is behind the sign-in rule only.
5. Persisted recording: the sport is stored in the recording meta (`recording/journal/file_recording_journal.dart:135,791,1179`) and restored by recovery (`recorder_controller.dart:259,762`). A recording of a deferred sport made on an earlier build would resume. INFERENCE for the cross-build case.
6. Cycling-specific logic exists in the pipeline (`recording/pipeline/recording_constants.dart:121`) and the page shows speed instead of pace for cycling (`gps_format.dart:96-99`), so the sports are implemented, not stubs. FACT.

What must change (description only, for the release-scope story):
- The sport list must be derived from the capability policy (one source), not a fixed constant, so v1 offers walking and running only. A single function `startableGpsSports(policy)` replacing the constant at `gps_start_panels.dart:32` would do.
- `requestStart` (or the flow in `gps_start_flow.dart:438`) must reject a sport the policy closes, so a crafted call or a restored default cannot start it.
- Recovery of a stored recording must keep working for any sport (data is not deleted), but must not offer to start a new one. Decide the product behavior for a hiking/cycling recording found on disk.
- `/record/gps` must apply the same check when `?mode=` or a future `?sport=` is supplied.
- The disposition matrix row for `recording` and package rows FU-AC-084/085 should state the resulting sport list.

## 5. Proposed release-policy tests (shared, not per directory)

All tests are Flutter tests that run a table of cases from one source. Ids start at FU-AC-130. Test-writing agents decide file placement; these are acceptance definitions only.

- FU-AC-130 Disposition manifest completeness. A machine-readable manifest (one row per directory under `lib/features/`, with disposition) is compared to the real directory list: every directory has exactly one row; every DEFER module has zero importers outside itself (path form and relative form); every module marked "no entry" has no route/provider consumer. Fails if a module appears or an importer is added without a manifest edit.
- FU-AC-131 Logic-only modules are consumed. For `personalisation`, `training_context`, `recovery`, `safety`: at least one non-test importer outside the module exists (guards against silently orphaning a KEEP module).
- FU-AC-132 KEEP route reachability table. Using the live router with a signed-in, onboarded fake user and `demoFeaturesEnabled=false`, every route of every KEEP module in section 2.1 resolves (no redirect to `/home`). Uses `resolveRedirect` plus a route-table walk, so a path missing from the router fails.
- FU-AC-133 Mode gate table. For each `AppMode`, `/mode-questions/<mode>` and the Record sheet rows follow the mode availability table; modes the policy closes produce `/home` and no GPS row beyond the allowed sports.
- FU-AC-134 Recorder-off build. With `gpsRecorderEnabledProvider=false`, `/record/gps` and `/record/manual` do not resolve to a page (redirect or not-found) and the Record sheet has no GPS row.
- FU-AC-135 Recorder-on sport list. With the recorder on, the Start screen renders chips only for the policy-allowed sports; a request to start a closed sport is rejected by the recorder; `kGpsStartSports` is not a free-standing constant (or equals the policy list). Must fail today (hiking and cycling present).
- FU-AC-136 HIDE route/button closure. With `demoFeaturesEnabled=false`: all gated paths (including `/team/x`, `/coaches/x`, and the edge cases from D-10) redirect to `/home`; Profile shows no Coaching/Community section; Settings shows no moderation row; exercise reference shows no contribute button. The last two are built with the real constant, plus an assertion that `kDemoFeaturesEnabled` equals `demoFeaturesEnabledFor(isRelease: true, definedFlag: false)`. A release-pipeline check (script or CI-less local check) asserts the build command contains no `DEMO_FEATURES=true`.
- FU-AC-137 Auth boundary. Signed-out: `/donors`, `/plan`, and every KEEP route redirect to `/login`; public paths stay open. KEEP-with-no-entry modules (goal_photo, body_comp, voice) are listed as `NOT_WIRED` in the manifest until a story wires them, so a claim "reachable in v1" cannot be made for them.
- FU-AC-138 Deferred data-backing flags. For progress_photos and other modules with an `*AreDemoProvider` (`progress_photos_providers.dart:175`, `marketplace_providers.dart:87-89`): in a release configuration the provider values match the disposition (documents what is demo-backed and still visible).
- FU-AC-139 Hidden-module side effects. With the Day-3 provider off, Home does not show the modal; a documented assertion records the launch-counter write (D-08) so a change in that behavior is deliberate.
- FU-AC-140 Entry-surface inventory. A static check over `lib/` for string route targets: every literal route used in `go/push/replace` exists in the route table, and every route in the table appears in the manifest. Also asserts no `onDidReceiveNotificationResponse`, and no URL intent filter in `AndroidManifest.xml`, unless the manifest lists them (D-12).

## 6. Not yet traced

These items were not traced because the trace stopped early. Nothing below is verified.

Release gate (pre-implementation review PI-M08): until FU-AC-130 to 140 have run against real release build defines, direct routes, resume paths, keyboard actions and the recorder port, no document may claim that every KEEP module is reachable and every HIDE module is closed. Build-time bypasses (`DEMO_FEATURES`, recorder-enabled builds that expose hiking and cycling) are release gates.

Modules with no row, or a partial row, in section 2 (check owed in parentheses):
- programmes (12 files): only known wiring is `programmeRepositoryProvider` in `main.dart:646`; UI entry points UNKNOWN (grep for importers by pages and routes).
- ai_coach (5): imported by? no route found; UNKNOWN (grep `ai_coach/` imports, check `AiCoachSheet` callers).
- visual_equipment (35): providers wired in `main.dart:685-742`; entry through scanner presumed, not traced.
- activity (57): partial; the sign-out warning sheet is now traced (section 2.1). Still untraced: other user-facing screens and `sync_conflict_sheet` callers.
- recording (53): internals other than the sport list not traced (battery, permissions, consent row).
- progress_photos scan sub-module and its `scanAccessProvider` gates (Supporter, age, consent).

Other open checks:
- RESOLVED: `kDefaultModeAvailability` is Train and Body `available`, Explore and Ride `comingLater` (`mode_models.dart:46-51`). Still owed: whether the Record sheet GPS row is hidden for a `comingLater` mode (the sheet code shows rows per selected mode; the selected mode cannot be Ride/Explore only if the chooser and switcher refuse it, not traced).
- `requestStart` (`recorder_controller.dart:174-209`) was read only in part. That it has no sport allow-list stays INFERENCE; check owed: read the `_preconditions` body and confirm no sport argument is validated.
- Source of `cycle` input to the plan builder (`plan_builder.dart:228`).
- `requestStart` allow-list behavior in `recorder_controller.dart`.
- iOS `Info.plist` URL schemes and web entry; Android `build.gradle` release flags other than `GPS_RECORDER`.
- Tests already present for gating: `test/router/app_router_gating_test.dart:279-303`, `test/core/config/demo_features_test.dart`, `test/features/profile/profile_page_test.dart:224-232` exist (FACT, headers only read); their assertions were not reviewed.
- Whether a `core/router` consumer outside `lib/` (integration_test) opens a hidden route.

## 7. Stale documents (not changed)

- `docs/v1/MODULE_DISPOSITION_MATRIX.md`: statements listed in D-11 are now resolved; row `goal_photo` should not read KEEP-reachable. Left unchanged because the operator decides dispositions.
