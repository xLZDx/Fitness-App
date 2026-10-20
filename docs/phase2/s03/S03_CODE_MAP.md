# S03 code map

Author: code-explorer (read-only: Read, Grep and Glob only, no code was run). Saved into the repository by the lead agent from the explorer's final message; the content is the explorer's. Date: 2026-10-17. Worktree base: branch `phase2/s03d-ui-design-contract`. Every item is a FACT with a path and line, or is tagged INFERENCE or UNKNOWN. Paths start at the worktree root `D:\Repo\Fitness_App_Phase2_s01`.

**Summary.** The shell is a `ShellRoute` of five tab routes wrapped in `MainShell`, which has a floating bottom bar and no responsive logic. No mode, sport or activity-kind concept exists. The nearest per-account device-preference pattern is the training-context notifier, which stores one SharedPreferences key per uid. The S02 journal is account-scoped and read through `ActivityJournal.list()`. It opens only when a compile-time flag is set (default off), and no UI or provider reads it yet. Home and Progress are built only from workout logs and workout sessions. No concrete `DeviceSource` exists. `firestore.rules` already lets the owner write any `users/{uid}/<new collection>`, so device-only mode state needs no backend change.

## 1. Shell and navigation

- **Router.** `mobile/lib/core/router/app_router.dart` builds one `GoRouter` in `appRouterProvider` (line 356). It starts at `/splash` (383) and has a `refreshListenable` driven by auth and profile streams (384).
- **Route table.**
  - The non-shell routes are at lines 415-673 and are all pushed on the root navigator, outside the shell: `/splash`, `/login`, `/onboarding`, `/onboarding/edit` (435), `/equipment/:id`, `/exercise/:id`, `/workout-summary`, `/workout/:id?day=&scanId=` (471-485), settings and legal pages, `/nutrition/*`, `/body-scan*`, `/photos*`, `/backup`, `/community`, `/team/:teamId`, `/form-check`, `/posture`, `/coaches`.
  - `ShellRoute` (674-699) has `navigatorKey: _shellKey` and `builder: MainShell(child: child)`. Its children are `/home`, `/scan`, `/workouts`, `/progress`, `/profile`, each through `_fadeThrough` (164).
- **Redirects** (`resolveRedirect` 90-154, `redirectFor` 323-352).
  - A signed-out user goes to `/login` unless the path is in `_publicPaths` (70).
  - Demo-gated paths (83) go to `/home` when demo features are off.
  - A signed-in user who is not onboarded goes to `/onboarding`, except for `/equipment/*`, `/exercise/*`, `/workout/*`, `/delete-account` (77) and public paths.
  - An onboarded user at `/onboarding` goes to `/home`.
  - On a cold start with the profile not yet loaded, the router holds on `/splash` for at most 5 s (385-411).
- **Deep links and notification taps.** UNKNOWN: no such routing code was found in the files read, and `mobile/lib/core/notifications/*` was not read.
- **MainShell** (`mobile/lib/shared/widgets/main_shell.dart`).
  - `_paths` are `/home`, `/workouts`, `/scan`, `/progress`, `/profile` (69-75). The selected index is `location.startsWith` (98-101). Tabs switch with `context.go` (160).
  - `PopScope(canPop: location == '/home')` sends Back to `/home` (111-122). `_AnnounceShellCanPop` (176) exists because of an Android Back bug (129-149) and must be kept.
  - The Scaffold has `extendBody: true`, a transparent background and `HudSkyBackground` as the body (123-127). `bottomNavigationBar` is `HudNavBar` (153-162).
  - There is no `MediaQuery`, `LayoutBuilder` or window-size logic in this file.
  - Attach points: a rail replaces `bottomNavigationBar` at line 153; a Recording strip or a Record button could go in the body or above the nav bar. INFERENCE: the Scaffold has no `floatingActionButton` in use.
- **HudNavBar** (`mobile/lib/shared/widgets/hud/hud_scaffold.dart:233-293`).
  - Inputs are `items`, `selectedIndex`, `onSelect`.
  - It is a floating pill with `left`/`right` 12, `bottom` 14 plus the safe-area inset, height 72, radius `radiusDevice` and a `HudSurface` with `t.navBar` (263-273).
  - Each tab has a `Semantics` wrapper and a 44 px minimum tap target (326-327).
- **Scan and Profile tabs.** Both are plain `ShellRoute` children (`ScannerPage` at `app_router.dart:683`, `ProfilePage` at 696) with no special wiring.
- **Bottom-bar assumptions.**
  - `shellBottomObstruction` is `MediaQuery.paddingOf(context).bottom` (`mobile/lib/shared/widgets/shell_insets.dart:34`).
  - `HudScreenBody.bottomClearance` is 14 + 72 + inset + 24 (`hud_scaffold.dart:45-49`).
  - A side rail needs `reserveNavBar: false` (31, 53-55) or a new width-aware clearance.
- **Running-workout state the strip must read.**
  - `setTimerProvider` is a `NotifierProvider<SetTimerController, SetTimerState>` (`mobile/lib/features/workouts/state/set_timer_providers.dart:247`). The state has `phase`, `setNumber`, `secondsLeft`, `totalSets`, `progress`, `running` (103-115).
  - `restTimerProvider` (`mobile/lib/features/workouts/state/rest_timer_providers.dart:209`) starts `idle` (143). `restTimerVisibleProvider` is `!isIdle` (221).
  - Rest is wall-clock based: `endsAt` via `restClockProvider` (145-153).
  - Both are used from `mobile/lib/features/equipment/workout_player_page.dart` (367-375, 735, 976).
  - The doc at `rest_timer_providers.dart:213-220` says a rest survives navigation by design.
  - UNKNOWN: whether these providers are `autoDispose`.
  - UNKNOWN: which provider says that a workout session (not a single timer) is in progress.

## 2. Mode state today

- **Existing mode, sport or kind selection.** There is none. The closest items are:
  - `FitnessGoals.primary` (`ProgrammeGoal`) and `specificSport` (a free String), at `mobile/lib/features/profile/data/profile_models.dart:729-763`.
  - `TrainingContext`, a per-account answer used to filter exercises (`mobile/lib/features/training_context/state/training_context_providers.dart`).
  - `SportType` (`mobile/lib/features/activity/data/sport_type.dart:5-17`), 12 values, a data enum and not a user choice.
- **Persistence in use.**
  - Device settings (theme, language, notifications, tier override) are in `PrefsSettingsRepository` (`mobile/lib/core/settings/settings_repository.dart:18-21`). They are not account-scoped (line 12).
  - They are loaded before the first frame (`mobile/lib/main.dart:364-365`) and passed through `initialSettingsProvider` (610-611).
  - Per-uid SharedPreferences keys:
    - `training_context.v1.$uid` (`training_context_providers.dart:15`)
    - `activity.cloudStreamsConsent.$uid` (`mobile/lib/features/activity/repository/activity_cloud_settings_client.dart:61`)
    - `profile.sensitive.$uid`
    - the `data_notice.`, `body_scan.`, `nutrition.`, `food_diary.` and `weight.` prefixes ending in `.$uid`
  - The profile is Firestore `users/{uid}/profile/*`. The journal key is in secure storage and the journal itself is a file store.
  - UNKNOWN: whether Hive or Drift is used.
- **Pattern to reuse for mode state.** `TrainingContextNotifier` (`training_context_providers.dart:45-84`) is an `AsyncNotifier` that:
  - awaits `authUserProvider`;
  - reads the key for that uid;
  - keeps `_uid` and refuses a write when the signed-in uid differs (68-73);
  - sets state first, then writes the key (73-77);
  - encodes `unanswered`, `skipped` and chosen values, and treats unknown values as unanswered (21-31).
- **Journal account scoping.**
  - `UidScopedActivityJournal` (`mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart:58`) holds no data and delegates to the journal bound to the signed-in uid.
  - The scope id is the first 32 hex characters of sha256(uid) (44-45). The directory is `<app support>/activity_journal/<scopeId>` (49-56).
  - `activityJournalBindingProvider` (`mobile/lib/core/wiring/activity_wiring.dart:101-164`):
    - listens to `authUserProvider` and binds the uid, anonymous users included;
    - retries a failed bind at 5 s, 15 s, 60 s, 5 min and 5 min (190-196);
    - unbinds on sign-out without deleting data (98-99).
  - It is watched from `FitnessApp.build` (`main.dart:675`).
- **Sign-out, switch and deletion.**
  - Sign-out never wipes the journal. The code says the sign-out export offer is S03 (`activity_wiring.dart:99-100`). `ActivityWipeCoordinator.onSignOut` and `ActivitySignOutHooks` exist (`mobile/lib/features/activity/repository/activity_journal.dart:102-141`), but the app does not call them.
  - An account switch rebinds the journal. Per-uid prefs stay on disk.
  - Account deletion calls `DeviceLocalDataWipe.wipe(uid)` (`mobile/lib/features/account_deletion/data/local_data_wipe.dart:267`):
    - It removes exact per-uid keys, including `training_context.v1.$uid` (286), and keys with the prefixes in `_perUidFeaturePrefixes` ending in `.$uid`, which include `activity.` (210-223).
    - A new mode key therefore needs either `activity.<name>.<uid>`, a new prefix in that list, or an entry in `personalKeys` (273).
    - It keeps `settings.language`, `settings.theme_mode` and `settings.notifications_enabled` (260-264).
  - `activityAwareLocalDataWipe` wraps it with the journal wipe (`activity_wiring.dart:48-54`, `main.dart:601-602`).
- **Onboarding.**
  - `mobile/lib/features/onboarding/onboarding_page.dart` uses a `PageView.builder` (243) over `kOnboardingOrder`. The steps are Personal, Body, GoalAndLevel, Lifestyle, Equipment, Schedule, Barriers, HealthFlags, Nutrition, Screening and Preview (74-94).
  - It resumes from the saved draft (`_maybeResume`, 117-121) and submits through `profileSubmitProvider` (181).
  - `UserProfile.hasCompletedOnboarding` is `completedAt != null` (`profile_models.dart:1132`).
  - `/onboarding/edit` is the re-entry route for onboarded users (`app_router.dart:435`).
  - Per-mode first-run questions could attach as a new step in `kOnboardingOrder` or as a screen shown after `/home` is reached.
- **Upgrader path (Phase 1 user, first launch after update).**
  - The user is already onboarded, so the router sends them to `/home`.
  - No mode key exists for them, so the mode reads as unanswered.
  - INFERENCE: mode state needs an explicit unanswered value, as `TrainingContextAnswer` has.
  - Home already shows a first-launch modal through `PrefsMomentRepository` (`mobile/lib/features/home/home_page.dart:93-109`).

## 3. Activity data for dashboards

- **`ActivitySession`** (`mobile/lib/features/activity/data/activity_session.dart:65-156`).
  - Fields: `id`, `sport`, `startUtc`, `endUtc`, `utcOffsetMinutes`, `movingTimeS` (nullable), `summary`, `streams`, `laps`, `provenance`, `userEdits`, `privacy`, `schema`, `mergeNotes`, `extras`.
  - v2 fields: `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`, `sourceTermsSnapshot`, `explicitValues`, `summaryOverrides`, `userEditCount` (capped at 64) and `editHistory`.
  - `durationMs` is derived (158), `paceSecPerKm` is derived and null without a speed (173-176), and `isReadOnly` is `schema > kActivitySchema` (162).
  - The id is `act_<sha1>` (50-59).
- **`ActivitySummary`** (`mobile/lib/features/activity/data/activity_summary.dart:6-43`).
  - Every field is a nullable `double?`: `distanceM`, `ascentM`, `descentM`, `avgHrBpm`, `maxHrBpm`, `avgSpeedMps`, `avgCadence`, `avgPowerW`, `normalizedPowerW`, `activeEnergyKcal`, `steps`, `strokeCount`, `poolLengthM`, `lapCount`, `avgSwolf`.
  - `toJson` writes only set fields (84-89), so a missing value reads back as null.
  - The model separates null from zero, so "missing shown as missing" is possible. Every sum or average must skip nulls and report how many sessions lacked the field.
  - The effective value comes from `SummaryProjection.effective(s)` (`mobile/lib/features/activity/data/summary_projection.dart:94`).
  - UNKNOWN: how `effective` treats a field with neither a derived nor an explicit value.
- **Journal read API** (`mobile/lib/features/activity/repository/activity_journal.dart:13-99`).
  - `list()` returns live entries without streams. `read(id)` returns the full entry with streams. `listTombstones()` returns deleted ids.
  - `JournalEntry` (`mobile/lib/features/activity/repository/journal_models.dart:226-243`) has `session`, `state`, `generation`, `streamsLoaded`.
  - `assessSignOut()` returns entry, unsynced and streamLost counts (`journal_models.dart:268-282`).
  - There is no range, sport or date filter, so filtering is client-side after `list()`. There is no push stream; `list()` is a one-shot `Future`.
  - Unbound reads return empty (`uid_scoped_activity_journal.dart:158-169`).
- **Providers.** `activityJournalProvider` is declared at `activity_wiring.dart:93` and defaults to null. The only files that mention it are `mobile/lib/core/wiring/activity_wiring.dart`, `mobile/lib/main.dart` and tests. No screen reads it.
  - No sessions provider, aggregate, or today/week function exists, so all of it must be built.
  - `mobile/lib/features/activity/state/` contains only `sync_conflict_presenter.dart`. `mobile/lib/features/activity/widgets/` contains `activity_sync_entry_card.dart` and `sync_conflict_sheet.dart`.
- **Refresh signal.** `_publishBindingChange` returns early without `cloudSync` (`activity_wiring.dart:180-187`), so a local-only journal has no change notification.
  - INFERENCE: the dashboard provider needs its own invalidation, for example on bind result, on local writes and on app resume.
- **Performance.**
  - `list()` omits streams, which keeps entries small.
  - UNKNOWN: index and read cost at thousands of entries, and whether `list()` decrypts record bodies. `mobile/lib/features/activity/repository/file_activity_journal.dart` was not read.
  - The existing aggregates run on the main isolate (`mobile/lib/features/progress/data/progress_stats.dart`).
- **Home today.**
  - `mobile/lib/features/home/home_page.dart` uses `HudScreenBody` with the greeting, identity row, day panel (`screenedUpcomingSessionsProvider`, `todayDigestProvider`), week section, recovery panel, quick-scan row, `BodyScanEntryCard`, `NutritionEntryCard`, `DeloadBanner`, a summary link card and upcoming cards.
  - `mobile/lib/features/home/state/home_dashboard_providers.dart` has `muscleRecoveryProvider` (26), `weekStripProvider` (54), `weekTotalsProvider` (63), `planProgressProvider` (68) and `homeNowProvider`, a pinned clock for tests (52).
  - All of it derives from `workoutSessionHistoryProvider` and `scheduledSessionsProvider`.
  - The page header states a "no fake data" rule: a value is omitted instead of shown as 0 (`home_page.dart:55-67`).
- **Progress today.**
  - `mobile/lib/features/progress/progress_page.dart` watches `workoutSessionHistoryProvider` and `workoutSessionTotalsProvider` (34-40).
  - It shows `ActivitySyncEntryCard` (55), body-scan and nutrition entry cards, headline stats, photo progress, volume, consistency, records, an 8-week bar chart and recent logs.
  - `deriveProgress` (`progress_stats.dart:61`) returns total, thisWeek, current and longest streak, and `last8Weeks`. It uses local days and Monday week starts (35-47).
  - The history is a window (`kWorkoutHistoryWindow`) and `totals` supplies all-time values (51-64).
  - With an empty window and no totals it returns `ProgressStats.empty`, all zeros (66-78, 24-30).
  - Weight and body scan are reached through entry-card links to `/nutrition/weight` and the body-scan routes.
- **Health daily data.** `HealthSnapshot` (`mobile/lib/core/health/health_models.dart:6-34`) has `dateUtc`, `steps`, `activeMinutes`, `restingHeartRateBpm`, `sleepScore`, `hrvMs` and `activityRingPercent`, all nullable except the date. `todayHealthProvider` and `last7DaysHealthProvider` are at `mobile/lib/core/health/state/health_providers.dart:28,44`. This is separate from `ActivitySession`.
- **Missing for EP-3.**
  - A provider that lists journal sessions.
  - Day and week bucketing (the `progress_stats.dart` helpers for local days and Monday weeks can be reused).
  - Per-sport and per-mode filters.
  - A null-aware sum with a "n of m sessions have this value" count.
  - A decision on how workout-log sessions and journal sessions combine (risk 4).

## 4. Sources

- **Concrete sources.**
  - `DeviceSource` (`mobile/lib/features/activity/data/device_source.dart:126-165`) has `id`, `kind`, `capabilities`, `permission`, `request`, `fetchSessions`, `live`, `disconnect`, `healthStatus` (a `SourceHealth` of `ok`, `permissionMissing`, `unavailable`, `stale`, `error`), `deleteCached` and `streamDuringWorkout`. The file header says no adapter exists.
  - Only `FakeDeviceSource` implements it (`mobile/lib/features/activity/data/fake_device_source.dart:9`), apart from test stubs.
  - The capability matrix is keyed by ids such as `wear_os` and `vendor_cloud` (`device_source.dart:100-106`). The first part of that map was not read.
- **`SourceKind`** (`mobile/lib/features/activity/data/source_kind.dart:8-23`) has `platformHealth`, `bleSensor`, `vendorCloud`, `companionApp`, `fileImport`. Unknown names degrade to `fileImport`.
- **`SourceRecord`** (`mobile/lib/features/activity/data/source_record.dart:7-50`) has `sourceId`, `sourceKind`, `importedAt`, `deviceModel`, `appPackage`, `externalId`, `fieldsContributed`, `rawRef`.
- **`primarySourceId`.**
  - It exists only in the cloud summary, as `provenance.first.sourceId` plus `primarySourceKind` (`mobile/lib/features/activity/data/activity_cloud_summary.dart:51-57`).
  - The merger sorts by `(priority, startUtc, id)` using `MergePolicy` ranks (`mobile/lib/features/activity/data/activity_merger.dart:42-72`) and is order-independent.
  - UNKNOWN: whether `provenance.first` is always the highest-priority source after a merge.
- **Health Connect.**
  - `HealthService` (`mobile/lib/core/health/health_service.dart:12`) offers `readSnapshots`, `readTodaySnapshot`, `writeWorkout` and auth status. `PlatformHealthService` is bound in `main.dart:444-445`.
  - Its output is `HealthSnapshot` daily aggregates, not `ActivitySession`. Its UI is `mobile/lib/core/health/widgets/health_sync_card.dart`.
  - Manual workout logs are a separate store, not the journal.
  - UNKNOWN: whether any code writes Health Connect workouts into the journal.
- **What the sources panel (EP-4) can read.**
  - `healthAuthStatusProvider` and `healthSetupRequiredProvider` (`health_providers.dart:12,24`).
  - Provenance aggregated over `journal.list()`: sources seen, session counts, last `importedAt`.
  - `ActivityFlags`, to show whether the journal is on.
  - Per-source `SourceHealth` only if a `DeviceSource` is registered. No registry or provider for sources exists.

## 5. Flags and config

- **`ActivityFlags`** (`mobile/lib/core/config/activity_flags.dart`).
  - `cloudSync` and `localJournal` default to false (21). `journalEnabled` is `localJournal || cloudSync` (30).
  - `compileTime` reads `bool.fromEnvironment('ACTIVITY_CLOUD_STREAMS')` and `bool.fromEnvironment('ACTIVITY_LOCAL_JOURNAL')` (33-36). `activityFlagsProvider` defaults to `compileTime` (53-54).
  - For S03-0 (journal open by default), the options are to change the `localJournal` default, add a `defaultValue: true`, or make `journalEnabled` always true. Tests that assert the default-off matrix will need changing, for example `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart`.
- **Where the flags are read.**

  | Location | Behaviour |
  |---|---|
  | `mobile/lib/core/wiring/activity_wiring.dart:41` (`openActivityJournal`) | returns null if not `journalEnabled` |
  | `activity_wiring.dart:63` (`activityRootOverrides`) | returns no overrides if not `journalEnabled` |
  | `activity_wiring.dart:102` (`activityJournalBindingProvider`) | does nothing if not `journalEnabled` |
  | `activity_wiring.dart:182,293,301,331` | cloud paths, gated by `cloudSync` |
  | `mobile/lib/features/activity/widgets/activity_sync_entry_card.dart:21` | hidden unless `cloudSync` |

  - `main.dart:377` calls `openActivityJournal()` once before `runApp`. With the flag on, this only creates an unbound scoped journal and does no I/O (`activity_wiring.dart:32-43`).
- **Other mechanisms.**
  - `--dart-define` values `HUD_PHASE`, `HUD_PHOTO_SET` (`main_shell.dart:21,36`), `APP_VERSION` and others.
  - `kDemoFeaturesEnabled` and `demoFeaturesEnabledProvider` (`mobile/lib/core/config/demo_features.dart`).
  - `BodyScanFlags`, the pattern the activity flags copy.
  - `ALLOW_TIER_OVERRIDE`.
  - UNKNOWN: whether Remote Config is used.

## 6. Responsive and theme

- **Existing layout queries.** `MediaQuery`, `LayoutBuilder`, `SafeArea` and similar names appear 86 times in 51 files under `mobile/lib`. In shell-related files:
  - `mobile/lib/shared/widgets/shell_insets.dart` has 6 uses, all bottom-padding arithmetic.
  - `hud_scaffold.dart` has 5 uses, all `paddingOf` for top and bottom.
  - `mobile/lib/core/theme/hud_tokens.dart` has 3 uses, including `disableAnimations` (985).
  - `mobile/lib/core/background/hud_sky.dart` has 4 uses.
  - Other uses are scattered across the scanner, food diary and progress photo capture screens.
  - No breakpoint, window-size class, `NavigationRail` or orientation handling was found in the files read.
- **Tokens.** `HudTokens` (`hud_tokens.dart:228`) is a `ThemeExtension`, reached through `context.hud`.
  - `referenceViewport` is 390x844 (435). `screenGutter` 16 and `headerGutter` 20 (439-440).
  - `navBarHeight` 72, `navBarInset` 12, `navBarBottom` 14, `navBarClearance` 158 (443-450). `minTapTarget` 44 (457).
  - Radii: device 26, panel 30, sub-panel 28, sheet 26, button 22, chip 20, tile 16 (406-412).
  - Related files: `app_theme.dart`, `app_palette.dart`, `app_semantic_colors.dart`, `hud_typography.dart` (all under `mobile/lib/core/theme/`).
  - UNKNOWN: fonts and text-scale handling, since `hud_typography.dart` was not read.
- **Components.**
  - `HudScreenBody` (`hud_scaffold.dart:26`) is a `ListView` with a top inset and the bottom clearance, inside `HudScrollFade`.
  - Also `HudScreenTitle`, `HudSectionHeader`, `HudNavItem`, `HudNavBar`, `mobile/lib/shared/widgets/hud/hud_surface.dart` and `hud_metric.dart`.
  - Older: `glass.dart`, `glass_nav_bar.dart` (replaced by `HudNavBar`), `aurora_background.dart`.
  - The app root wraps the router in `AuroraBackground` (`main.dart:703-706`).
- **What new components should wrap or extend.**
  - Side rail: replaces `HudNavBar` in `MainShell`. Reuse `HudNavItem`, `HudSurface`, `context.hud` and the 44 px tap target.
  - Window-size class provider: none exists. It could be derived from `MediaQuery.sizeOf` at the shell level.
  - Adaptive surface: `HudScreenBody` and the bottom-clearance functions need a width-aware variant.

## 7. Localization

- **Workflow.** `mobile/l10n.yaml` sets `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-class: AppLocalizations`, `nullable-getter: false`. Code imports `package:flutter_gen/gen_l10n/app_localizations.dart`.
- **Files and size.** `mobile/lib/l10n/app_en.arb` has about 3,017 key lines. `mobile/lib/l10n/app_ru.arb` is in the same folder. Line numbers for the same key differ between the two files (`restTimerTitle` at 2190 in the English file, 1276 in the Russian one).
  - UNKNOWN: whether the two files have the same key set.
- **Locale selection** (`mobile/lib/core/settings/app_settings.dart`).
  - `kSupportedLocaleCodes = ['ru','en']`, and the first entry is the fallback for unsupported device locales (9).
  - `AppSettings.language` defaults to `AppLanguage.ru` (90). `AppLanguage.system` resolves to the first supported device locale (43-52).
  - `MaterialApp.router` takes `locale: Locale(localeCode)` (`main.dart:693`).
- **Key naming.** camelCase with a feature prefix: `homeThisWeek`, `homeHome`, `progressProgress`, `navWorkouts`, `navScan`, `workoutsTrain`, `restTimer*`. Placeholders are `{arg0}`, `{arg1}`.
- **Reusable keys.**

  | Need | Existing key |
  |---|---|
  | Home tab | `homeHome` |
  | Progress tab | `progressProgress` |
  | Workouts tab | `navWorkouts` |
  | Scan tab | `navScan` |
  | Profile tab | `profileProfile` |
  | "This week" | `homeThisWeek` |
  | Streak | `homeStreak`, `progressCurrentStreak` |
  | Rest strip | `restTimerTitle` and related keys |

  - There is no key for a "Today" dashboard heading (`homeToday0700` and `homeTodaySAdaptivePlan` are not reusable), nor for mode, source, Record or Recording.
  - INFERENCE: most S03 strings are new, apart from the tab labels.

## 8. Tests

- **Layout.**
  - `mobile/test/` has `features/`, `router/`, `shared/widgets/`, `golden/`, `support/`, `widgets/`, `core/architecture`, `android/`, `adversarial/`, plus loose files such as `_mockups.dart` and `_g12b_board.dart`.
  - S02 tests are under `mobile/test/features/activity/{data,repository,e2e,config}`.
- **Helpers in `mobile/test/support/`.** `journal_harness.dart`, `scoped_journal_world.dart`, `two_device_world.dart`, `stale_view_world.dart`, `stream_upload_world.dart`, `gated_prefs.dart`, `fake_summary_backend.dart`, `journal_fault_fs.dart`, `journal_crash_matrix.dart`, `s02_fixtures.dart`, `s02_paths.dart`, `synthetic_activity_corpus.dart`, `synthetic_hostile_corpus.dart`, `firestore_rules_parser.dart`, `golden_fonts.dart`, `golden_override_scenarios.dart`, `wcag_contrast.dart`, and others.
  - UNKNOWN: whether a shared widget-test app wrapper exists. None was found by name; `mobile/test/features/home_page_test.dart` and `mobile/test/features/workouts_page_test.dart` build their own.
  - No shared fake journal or fake auth wrapper for widget tests was found beyond `scoped_journal_world.dart` and `journal_harness.dart`.
- **Window size and text scale.**
  - Tests set the size inline: `tester.view.physicalSize = const Size(800, 1600); tester.view.devicePixelRatio = 1.0;` (`mobile/test/features/home_page_test.dart:42-43`), and `Size(320, 800)` (479-480). There is no shared window-size setter.
  - UNKNOWN: whether a text-scale helper exists.
  - Shell-related tests: `mobile/test/shared/widgets/shell_insets_test.dart`, `mobile/test/router/back_navigation_test.dart`, `mobile/test/shared/widgets/hud/hud_components_test.dart`, `mobile/test/features/scanner_page_test.dart`, `mobile/test/features/home_page_test.dart`, `mobile/test/golden/hud_golden_test.dart`.
- **Goldens.** `mobile/test/golden/*` with `README.md` and `mobile/test/support/golden_fonts.dart`. The comment at `home_dashboard_providers.dart:38-51` says the composed-screen golden was clock-dependent until `homeNowProvider` was added.
- **Keys.** Dotted string keys, mainly `const Key('<feature>.<thing>')`, for example `Key('train.blocked')`, `Key('workouts.currentProgramme')`, `Key('programme.template.${id}')`, `Key('summary.home')` (`mobile/lib/features/workouts/workouts_page.dart:509,1078,1527`, `mobile/lib/features/workouts/workout_summary_page.dart:68`).
- **Commands.**
  - From `docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md:80-107`: `flutter test --timeout 60s <paths>`, for example `flutter test --timeout 60s test/features/activity`, run in `mobile/`.
  - A wipe-related run also covered `test/features/account_deletion test/core/architecture test/android/backup_rules_test.dart test/features/safety/health_rules_parity_test.dart test/adversarial/n07_team_activation_test.dart` (line 107).
  - Per the workspace rules, the test-writing agents run these and the coordinator does not.

## 9. Server side

- **Device-only mode state needs no backend change.**
  - The wildcard `match /users/{uid}/{coll}/{document=**}` (`firestore.rules:83-127`) lets the owner read and write any collection not on its exclusion list.
  - The excluded collections are `usage`, `receipts`, `profile`, `recognised_models`, the three `equipment_identity_*`, `body_scans`, `body_scan_settings`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`, `activities`, `activity_streams`, `activity_settings` and `activity_tombstones`. `subscription` is excluded from writes only.
- **If mode state were cloud-stored.**
  - A field in `users/{uid}/profile/*` goes through the profile rule (`firestore.rules:281-301`). That rule restricts only `health`, `nutrition` and `lifestyle.smoking/alcohol`, so a new top-level field would be accepted.
  - A new `users/{uid}/<collection>` would match the wildcard with no rule change, at the cost of an unchecked shape.
  - UNKNOWN: whether `mobile/lib/features/profile/data/firestore_profile_repository.dart` drops unknown fields on write.
  - UNKNOWN: what the account-deletion Cloud Function deletes. `functions/` was not read.
- **Activity paths.** The S02 activity collections have their own rules (`firestore.rules:881-1020`). Dashboards read only the local journal, so they need no rule change.

## 10. Risks and open technical questions

1. **Journal default-off.**
   - Evidence: `mobile/lib/core/config/activity_flags.dart:21`, `activity_wiring.dart:41,63,102`.
   - Consequence: dashboards are empty and the binding never runs until S03-0 flips the default.
   - Proposed default: set `localJournal` true by default in `compileTime`, keep `cloudSync` false, and update the flag-matrix test.
2. **No change signal for a local-only journal.**
   - Evidence: `_publishBindingChange` returns early without `cloudSync` (`activity_wiring.dart:180-187`), and `list()` is a one-shot future (`activity_journal.dart:35`).
   - Consequence: dashboards go stale after a bind or a write.
   - Proposed default: a dashboard provider that watches the binding and refreshes on resume and after local writes.
3. **Account-scoped mode state.**
   - Evidence: `AppSettings` is device-wide (`settings_repository.dart:12`); the account-scoped precedent is `training_context_providers.dart:45-84`.
   - Consequence: storing the mode in `AppSettings` would leak it across accounts.
   - Proposed default: a per-uid SharedPreferences key such as `activity.mode.v1.<uid>`, which the existing `activity.` wipe prefix covers (`local_data_wipe.dart:216-223`), with an explicit unanswered value for Phase 1 upgraders.
4. **Two activity stores.**
   - Evidence: Home and Progress read only workout logs and sessions (`home_dashboard_providers.dart:26-73`, `progress_page.dart:34-40`); the journal is read by no screen.
   - Consequence: the new dashboards can disagree with the existing tabs, or double-count if both feed one number.
   - Proposed default: dashboards show journal sessions for the active mode, and the five existing tabs stay unchanged.
5. **Missing versus zero.**
   - Evidence: `ActivitySummary` fields are nullable (`activity_summary.dart:29-43`), while `ProgressStats.empty` is zeros (`progress_stats.dart:24-30`).
   - Consequence: reusing the old aggregates shows 0 for missing data.
   - Proposed default: a null-aware aggregate that also returns the contributing count.
6. **Bottom-bar assumptions.**
   - Evidence: `hud_scaffold.dart:45-49` and `shell_insets.dart:34`, with every tab page using `HudScreenBody`.
   - Consequence: a rail leaves dead bottom space on every tab, and `extendBody: true` is wrong for a rail.
   - Proposed default: a window-size class provider set by the shell, and a clearance function that returns no bottom bar space when the rail is shown.
7. **Back handling.**
   - Evidence: `main_shell.dart:111-150`.
   - Consequence: restructuring `MainShell` can reintroduce the Android first-Back exit bug.
   - Proposed default: keep `PopScope` and `_AnnounceShellCanPop` unchanged, covered by `mobile/test/router/back_navigation_test.dart`.
8. **A running session must survive a mode switch.**
   - Evidence: the timers are notifier providers (`set_timer_providers.dart:247`, `rest_timer_providers.dart:209`). UNKNOWN: whether they are `autoDispose`.
   - Consequence: if mode state rebuilds or invalidates the shell, a running set could reset.
   - Proposed default: mode state is a separate provider that no timer watches, plus a test that switches mode while a timer runs.
9. **Sign-out data.**
   - Evidence: the sign-out export offer is described as S03 (`activity_wiring.dart:99-100`), and `ActivityWipeCoordinator.onSignOut` is never called.
   - Consequence: unclear whether S03 adds the sign-out export UI.
   - Proposed default: leave sign-out as it is unless the sprint scope says otherwise, and record it as out of scope.
10. **Sources panel has little to read.**
    - Evidence: only `FakeDeviceSource` exists, and `primarySourceId` exists only in the cloud summary.
    - Consequence: EP-4 can show only the health permission status and provenance counts.
    - Proposed default: build the panel from `healthAuthStatusProvider` plus provenance from `journal.list()`, with an explicit "no sources connected" state.

## UNKNOWN list

- Deep-link and notification-tap routing code.
- Whether the set and rest timer providers are `autoDispose`, and which provider marks a running workout session.
- Whether Hive or Drift is used.
- How `SummaryProjection.effective` treats a field with no value.
- Journal index size and read cost, and whether `list()` decrypts bodies.
- Whether `provenance.first` is the highest-priority source after a merge.
- Whether anything writes Health Connect workouts into the journal.
- Fonts and text-scale handling in `hud_typography.dart`.
- Whether the two ARB files have the same key set.
- A shared widget-test app wrapper, and any text-scale test helper.
- Whether `FirestoreProfileRepository` drops unknown profile fields.
- What the account-deletion Cloud Function deletes.
- Whether Remote Config is used.

## Three most important risks

1. Journal default-off (risk 1) together with no change signal for a local-only journal (risk 2): dashboards would show nothing or stale data.
2. Two activity stores (risk 4) together with missing versus zero (risk 5): dashboards could contradict the existing tabs or show 0 for missing data.
3. Bottom-bar assumptions and the Back-handling fix (risks 6 and 7): the responsive shell change touches code that every tab and the Android Back fix depend on.
