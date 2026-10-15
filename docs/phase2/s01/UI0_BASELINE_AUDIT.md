# UI-0 baseline audit: `mobile/lib` (read-only)

Sprint S01 part (c). Produced by a read-only code-explorer agent on 2026-10-15 from worktree `D:\Repo\Fitness_App_Phase2_s01` (line `phase2/s00-split-docs` at `6616d2f8`). Saved verbatim by the coordinator. Not reviewed by GPT-PM, product-ux-reviewer or a11y-architect yet.

Evidence labels: FACT(path) means the agent read it. INFERENCE means concluded from what it read.

All paths are relative to the worktree root. Code paths start with `mobile/lib/` and doc paths with `docs/`.

Scope limits:
- The agent did not run git, so branch, HEAD and dirty state are not captured here.
- Theme, router and shell files were read in full. The inventories for the other files come from grep and glob, not line-by-line reads.

## 0. S01 part (c) as the roadmap states it
- FACT(docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md:72): part (c) is "UI-0 baseline audit (verify tokens and implemented HUD, component and screen inventory, state list)". The sprint exit is "UI-0 report; ... no code".
- FACT(docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md:90): UI-0 must verify `app_semantic_colors.dart`, `app_palette.dart` and `hud_tokens.dart`, cover HUD migration status and list the states. It is reviewed by the product-ux and a11y reviewers.
- FACT(docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md:8): the direction document says it did not open the token files, so every token value in its section 3 is UNVERIFIED.

## 1. Design tokens that exist

**Files in `mobile/lib/core/theme/`:** `app_palette.dart`, `app_semantic_colors.dart`, `app_theme.dart`, `hud_tokens.dart`, `hud_typography.dart`. All three files named by the direction document exist.

**Two coexisting token layers.**
- FACT(mobile/lib/core/theme/app_theme.dart:135-147): `AppTheme._build` installs both `AppSemanticColors` and `HudTokens` as `ThemeExtension`s.
- FACT(mobile/lib/core/theme/hud_tokens.dart:1-30): the two layers are intentionally parallel.
- FACT(mobile/lib/core/theme/app_theme.dart:143): "The HUD migration removes the first one screen at a time."

**`AppSemanticColors`** (FACT mobile/lib/core/theme/app_semantic_colors.dart:223-277). It holds 20 roles, resolved per theme.

| Role | Dark | Light |
|---|---|---|
| backgroundPrimary | `#06060F` | `#EDE3F8` |
| backgroundSecondary | `#0D0D1A` | `#E3D7F2` |
| textPrimary | `#F0F0F8` | `#131027` |
| textSecondary | `#B1B1C6` | `#6A647B` |
| accentPrimary | `#C9FF47` | `#5A25D0` (violet) |
| accentSecondary | `#A8D93A` | `#C21E6E` |
| success | `#22E87A` | `#0B6B58` |
| warning | `#FFAA33` | `#9A4A05` |
| danger | `#FF4D70` | `#C0243C` |

- Other roles: `surfacePrimary` (white at 22 percent on dark), `surfaceElevated`, `surfaceInteractive`, `textDisabled`, `onAccent`, `onGradient`, `outline`, `cameraOverlay` and three pose colours.
- The comments cite WCAG ratios (for example, `textSecondary` 9.58:1 on the dark background). The agent did not recompute them.
- FACT(mobile/test/theme/app_semantic_colors_test.dart, mobile/test/support/wcag_contrast.dart): a token test and a contrast helper exist.

**`HudTokens`** (FACT mobile/lib/core/theme/hud_tokens.dart:461-739):
- Dark accent is `#C9FF47` and light accent is `#4B7A00`.
- Text is `#FFFFFF`, with secondary at white 80 percent and tertiary at white 72 percent.
- `base` is `#14182C`.
- Status colours are `success #7BF08A`, `warning #FFB86B` and `danger #FF5A5A`, plus a three-zone `zonePoor`/`zoneMid`/`zoneGood` ramp.
- Glass recipes (`HudGlass`) are `panel`, `subPanel`, `contentPanel`, `button`, `chip`, `navBar`, `scanPrimaryButton` and `scanCta`. The dark `panel` is white at 1.4 percent fill with blur 7, a white-34-percent inner hairline and a glow. `contentPanel` blur is 20. `navBar` blur is 30.
- Geometry (hud_tokens.dart:404-457): radii 16 to 30, `screenGutter` 16, `navBarHeight` 72, `navBarClearance` 158 and `minTapTarget` 44.
- There is a photo veil per time phase, `veilStops`.

**`AppPalette`** (FACT mobile/lib/core/theme/app_palette.dart): aurora hues, including `auroraLime #C9FF47` and `auroraLimeDeep #A8D93A`; programme goal hues; five tile gradients.

**Typography.**
- FACT(mobile/lib/core/theme/app_theme.dart:14-15, 108-164): `ThemeData` text uses Inter, with Barlow Condensed for display and headline roles. Cyrillic falls back to Inter.
- FACT(mobile/lib/core/theme/hud_typography.dart:48-55): `HudType` uses Archivo, with Inter as the Cyrillic fallback, and Roboto Mono for values. Scale: `screenTitle` 24/800, `heroTitle` 22, `panelHeading` 20, `panelTitle` 14, `rowTitle` 13.5, `rowMeta` 10.5, `body` 11.5, `label` 9.5 (7.5 for `ringLabel`, 8.5 for `navLabel`). `bigNumber` is weight 400 with a glow.
- INFERENCE: three display families are in use (Inter, Barlow Condensed, Archivo), which follows from the two coexisting layers.

**Spacing.** FACT: there is no spacing scale token. Only `screenGutter` 16, `headerGutter` 20 and the nav constants exist (mobile/lib/core/theme/hud_tokens.dart:439-454). Other spacing appears to be literals in widgets (INFERENCE).

**Theme mode and locale.**
- FACT(mobile/lib/main.dart:586-663): theme mode comes from settings (`AppThemeMode` system/light/dark), and the locale is set by `effectiveLanguageCodeProvider`.
- FACT(mobile/lib/l10n/app_en.arb, mobile/lib/l10n/app_ru.arb): there are two ARB files, EN and RU.
- FACT(mobile/lib/main.dart:663): the `MaterialApp.builder` wraps the app in `_InputTraceListener`. No text-scale clamp seen there.

## 2. Implemented HUD and in-session screens

**The HUD design system exists and is the shell.**
- FACT(mobile/lib/shared/widgets/main_shell.dart:124-127): `HudSkyBackground` draws a time-of-day photograph behind all tabs. `HUD_PHASE` and `HUD_PHOTO_SET` override it, ignored in release.
- FACT(mobile/lib/shared/widgets/hud/hud_scaffold.dart:233): `HudNavBar` is a floating glass bar, and selection is shown by ink plus an accent dot.
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart): `HudPanel`, `HudSheet`, `HudButton`, `HudChip` and `HudSurface`.
- FACT(mobile/lib/shared/widgets/hud/hud_metric.dart): `HudRing`, `HudProgressTrack`, `HudZoneBar`, `HudMetricRow`, `HudToggle` and `HudSettingRow`.

**HUD migration status.**
- FACT(grep `HudScreenBody|HudPanel|HudSurface|HudButton|HudChip|HudSheet(` over mobile/lib/features): HUD primitives are used in 54 files, about 210 occurrences.
- FACT(grep `FrostedScaffold(` over mobile/lib): the legacy `FrostedScaffold` is still in 30 feature files plus its definition in `mobile/lib/shared/widgets/glass.dart`. These include `progress_page`, `profile_page`, `settings_page`, `workout_summary_page`, `workout_player_page`, `equipment_detail_page`, `exercise_page`, `form_check_page`, `progress_photos_page`, `posture_page`, `subscription_page`, `login_page`, the legal pages and others.
- FACT: `mobile/lib/features/home/home_page.dart`, `mobile/lib/features/workouts/workouts_page.dart` and `mobile/lib/features/scanner/scanner_page.dart` do not use `FrostedScaffold`. The shell tabs progress and profile do use it.
- FACT(mobile/lib/features/progress/progress_page.dart): the progress page mixes `FrostedScaffold` with `HudPanel`. The same mix holds in the other pages that contain both.
- INFERENCE: the migration is partial and screen-by-screen. Mixed pages are the norm outside Home, Workouts and Scan.

**Workout HUD or in-session screen.**
- FACT(mobile/lib/core/router/app_router.dart:447-461): `/workout/:id` opens `WorkoutPlayerPage`, a `ConsumerWidget` (mobile/lib/features/equipment/workout_player_page.dart:134). It is a per-exercise page, not a continuous session HUD.
- FACT(mobile/lib/core/router/app_router.dart:439-442): the router comment says "The app writes one exercise per session".
- FACT(mobile/lib/features/workouts/widgets/): the in-session pieces are:
  - `set_timer_card.dart` (`SetTimerCard`): a `HudPanel` with ring, clock, three controls and voice and mute buttons. Phases are idle, gettingReady, work, rest and done.
  - `rest_timer.dart`, `set_capture_sheet.dart`, `difficulty_rating_sheet.dart`, `plate_calculator.dart`, `warmup_calculator.dart`.
  - `mobile/lib/features/workouts/workout_summary_page.dart` at `/workout-summary`, which summarises the DAY.
- FACT(mobile/lib/features/form_check/widgets/coach_hud.dart): `CoachRingGauge`, `CoachExerciseStrip`, `CoachCueChip` and `CoachCountersPanel` form a live camera overlay for Form Coach. It is the closest thing to a glanceable live HUD.
- FACT: there is no live GPS or ride/run HUD, no recording strip across screens, and no yoga player. A grep of mobile/lib for `ActivitySession|geolocator|TrainingMode|AppMode|recordingStrip` found nothing.
- FACT(mobile/pubspec.yaml): permission_handler, camera, health and ML Kit are present, and there is no location package.

## 3. Reusable component inventory (`mobile/lib/shared/widgets/`)

| Widget (file) | Notes / where seen |
|---|---|
| `GlassCard`, `GlassAppBar`, `FrostedScaffold` (`glass.dart`) | Legacy glass layer; `FrostedScaffold` in 30 feature files; `GlassCard` also used in `mobile/lib/features/equipment/widgets/exercise_reference.dart` |
| `AuroraBackground` (`aurora_background.dart`) | Legacy background |
| `GlassNavBar` (`glass_nav_bar.dart`) | Replaced in the shell by `HudNavBar`; still has a Semantics label and a min-size constraint |
| `AppPrimaryButton`, `AppSecondaryButton`, `AppTertiaryButton`, `AppIconButton` (`app_buttons.dart`) | Imported by `mobile/lib/features/workouts/widgets/set_timer_card.dart` and others |
| `DemoDataBanner`, `ExperimentalBanner` | Banner components with Semantics; `/coaches` has its own demo banner (router comment, mobile/lib/core/router/app_router.dart:64-65) |
| `SmoothScrollList` (`smooth_scroll_list.dart`) | Scroll helper |
| `shell_insets.dart` | `shellBottomObstruction` for bottom-anchored content |
| `HudScreenBody`, `HudScrollFade`, `HudScreenTitle`, `HudSectionHeader`, `HudNavItem`, `HudNavBar` (`hud/hud_scaffold.dart`) | HUD screen scaffolding |
| `HudSurface`, `HudPanel` (with `dense` and `semanticLabel`), `HudSheet`, `HudButton`, `HudChip`, `HudKeyboardActivation`, `HudQuality` (`hud/hud_surface.dart`) | Core HUD primitives |
| `HudRing`, `HudRingLabel`, `HudProgressTrack`, `HudZoneBar`, `HudMetricRow`, `HudToggle`, `HudSettingRow` (`hud/hud_metric.dart`) | Metrics and settings rows |
| `mobile/lib/shared/uncertainty/answer.dart` | Shared "answer with uncertainty" type, not a widget (INFERENCE from name) |

**Feature-level widgets that look reusable (INFERENCE from names):**
- Scanner: `mobile/lib/features/scanner/widgets/` has `scan_frame`, `scan_viewfinder`, `scan_glyph`, `scan_match_card` and `equipment_identity_badge`.
- Safety: `mobile/lib/features/safety/widgets/eligibility_notice` and `safety_refusal_card`, and `mobile/lib/features/equipment/widgets/safety_disclosure`.
- Recovery: `mobile/lib/features/recovery/widgets/deload_banner`.
- Photo consent and delete: `mobile/lib/features/progress_photos/widgets/photo_consent_sheet` and `photo_delete_sheet`.
- Health: `mobile/lib/core/health/widgets/health_sync_card`.
- Onboarding: `mobile/lib/features/onboarding/widgets/inputs` and `ob_shell`.

**Nearest capture-frame precedent.** `scan_frame.dart` and `scan_viewfinder.dart` (both under `mobile/lib/features/scanner/widgets/`) are the existing capture-frame widgets. They were not read, so whether they draw corner brackets is UNKNOWN.

## 4. Screen inventory and router paths

FACT(mobile/lib/core/router/app_router.dart): go_router, initial location `/splash`, with `resolveRedirect` (:74) deciding access. There are 30 top-level `GoRoute`s plus 5 shell children, 35 in total.

**Public paths** (:54): `/splash`, `/login`, `/about`, `/donors`, `/licences`, `/terms`, `/privacy`. `/delete-account` is allowed before onboarding (:61).

**Shell tabs (ShellRoute -> `MainShell`)** (:561-586):

| Path | Page |
|---|---|
| `/home` | `HomePage` |
| `/workouts` | `WorkoutsPage` |
| `/scan` | `ScannerPage` |
| `/progress` | `ProgressPage` |
| `/profile` | `ProfilePage` |

**Outside the shell** (:391-560):

| Path | Page |
|---|---|
| `/splash` | `SplashPage` |
| `/login` | `LoginPage` |
| `/onboarding`, `/onboarding/edit` | `OnboardingPage` |
| `/equipment/:id?scanId` | `EquipmentDetailPage` |
| `/exercise/:id?scanId` | `ExercisePage` |
| `/workout/:id?day&scanId` | `WorkoutPlayerPage` |
| `/workout-summary` | `WorkoutSummaryPage` |
| `/subscription` | `SubscriptionPage` |
| `/about`, `/licences`, `/terms`, `/privacy` | about and legal pages |
| `/injuries` | `InjuriesPage` |
| `/settings` | `SettingsPage` |
| `/delete-account` | `AccountDeletionPage` |
| `/donors` | `DonorWallPage` |
| `/plan` | `AiPlannerPage` |
| `/celebrity-plans` | `CelebrityPlansPage` |
| `/photos`, `/photos/scan`, `/photos/compare` | `ProgressPhotosPage`, `ScanCaptureScreen`, `ScanCompareScreen` |
| `/backup` | `BackupPage` |
| `/community` | `SocialFeedPage` |
| `/team/:teamId` | `TeamFeedPage` |
| `/form-check` | `FormCheckPage` |
| `/posture` | `PosturePage` |
| `/contribute`, `/moderate` | `ContributeVideoPage`, `CatalogModerationPage` |
| `/coaches` | `MarketplacePage` |

**Demo-gated paths** (:68-70): `/community`, `/celebrity-plans`, `/contribute`, `/moderate`, `/team/*`. They redirect to `/home` when `kDemoFeaturesEnabled` is off.

**Feature folders with no router path** (INFERENCE from the glob), all under `mobile/lib/features/`:
- `ai_coach`: `ai_coach_sheet`, opened as a sheet.
- `moments`: `day3_welcome_modal`.
- `recovery`, `safety`, `training_context`, `visual_equipment`.
- `body_comp`, `buddy`, `cycle_aware`: only `data` files were found.

Other `mobile/lib/core/` services: `health`, `notifications`, `wear`, `camera`, `settings`.

## 5. State inventory per main screen

FACT = found by grep for `when(`, `isEmpty`, `CircularProgressIndicator`, retry, permission and offline terms in the file. Full widget trees were not read, so "not found" below means "not found by that grep".

| Screen | Loading | Empty | Error | Offline | Permission denied | Success |
|---|---|---|---|---|---|---|
| Home (`mobile/lib/features/home/home_page.dart`) | FACT :1214 suggestions placeholder | FACT :135, :279, :320, :689 | FACT `suggestionsProvider.when` :178 with `_SuggestionsMessage` | not found | n/a | main content |
| Workouts (`mobile/lib/features/workouts/workouts_page.dart`) | FACT `list.when` :460 | FACT :517 | FACT :469, with `errorRetry` retry button :484 | FACT `_OfflinePrefetchCard` :554 and offline-prefetch outcomes :702-735 (offline videos, not network state) | n/a | main content |
| Scanner (`mobile/lib/features/scanner/scanner_page.dart`) | `_retrying` flag :111 | not found | FACT: camera or classify failure with reason and retry :105-287 | not found | FACT: denied, permanently denied and no-camera cases, `openSettings` :304, retry re-asks :281 | match card |
| Progress (`mobile/lib/features/progress/progress_page.dart`) | not found | FACT :63, :95 | not found | not found | n/a | main content |
| Progress photos (`mobile/lib/features/progress_photos/progress_photos_page.dart`) | FACT `photosAsync.when` :72 | FACT :348 | FACT :77 and :609 | not found | camera permission gate noted at :134 | main content |
| Workout player (`mobile/lib/features/equipment/workout_player_page.dart`) | FACT `exercise.when` :207 | FACT :1093 (picker) | FACT :209, :1236, :1340 | offline video states live in `mobile/lib/features/workouts/state/offline_video_providers.dart` | n/a | main content |
| Form check (`mobile/lib/features/form_check/form_check_page.dart`) | not found | n/a | camera-failure card (:100, :183-185 comments) | not found | FACT: permission asked on the intro card, failure card retry asks again (:169-192, :483-489) | |

- FACT(mobile/pubspec.yaml grep): there is no connectivity package. INFERENCE: no global offline indicator exists. The "offline" states found are about video or prefetch caches.
- FACT(mobile/lib/features/equipment/data/video_failure.dart, mobile/lib/features/visual_equipment/data/scan_outcome.dart): typed failure outcomes exist.
- UNKNOWN: whether Home, Progress and Profile show a connectivity-loss or sync state.

## 6. Accessibility basics

**Present.**
- FACT(mobile/lib/shared/widgets/hud/hud_surface.dart:700-736, 836-856; mobile/lib/shared/widgets/hud/hud_scaffold.dart:317-337; mobile/lib/shared/widgets/hud/hud_metric.dart:137, 358, 432, 582, 687): HUD components (nav tab, `HudButton`, `HudChip`, `HudRing`, `HudToggle`, `HudSettingRow`) use `Semantics` with an `ExcludeSemantics` child to avoid double announcements. `HudPanel` takes an optional `semanticLabel` (hud_surface.dart:333-361, 439-448). `HudToggle` takes a `semanticLabel`.
- FACT(mobile/lib/core/theme/hud_tokens.dart:456; mobile/lib/shared/widgets/hud/hud_scaffold.dart:327; hud_surface.dart:728, :848; hud_metric.dart:593, :687): `minTapTarget = 44` is applied as a minimum height. This is 44, not the 48 dp the direction document requires.
- FACT(mobile/lib/core/theme/hud_tokens.dart:983-1003): `reduceMotion` reads `MediaQuery.disableAnimations`, and `hudMotionDuration` is the one helper for it. The comment says there is no in-app toggle.
- FACT(mobile/test/support/wcag_contrast.dart, mobile/test/theme/app_semantic_colors_test.dart): a contrast test helper exists, so colour contrast is tested for `AppSemanticColors` tokens.
- FACT(mobile/lib/main.dart:586-616): the app reacts to device locale changes.
- FACT(mobile/test/): semantics or contrast are mentioned in at least 25 test files, including `mobile/test/shared/widgets/hud/hud_components_test.dart`. Only the first 25 were listed and none was opened to see how deep the coverage goes.

**Gaps.**
- FACT(grep `textScaler|TextScaler|textScaleFactor` over mobile/lib): the only text-scale handling is `TextScaler.noScaling` in `mobile/lib/features/scanner/widgets/scan_viewfinder.dart:155`, `scan_match_card.dart:104` and `scan_glyph.dart:92` (same folder). These deliberately stop scaling for text on a fixed overlay. No app-level 200 percent policy, clamp or test was found.
- FACT(mobile/lib/core/theme/hud_typography.dart): many HUD sizes are 7.5 to 12.5 px (`rowMeta` 10.5, `label` 9.5, `ringLabel` 7.5, `navLabel` 8.5). INFERENCE: these are high-risk at 200 percent scale and for 4.5:1 contrast on photos.
- FACT(mobile/lib/core/theme/hud_tokens.dart:107-109, 490-506): the dark `panel` fill is white at 1.4 percent. `contentPanel` was added because `panel` gives no separation over bright photos. The comment says the nav bar was the only surface whose body copy measured above 4.5:1 before this.
- FACT(mobile/lib/core/theme/hud_tokens.dart:278-283): secondary text is a range, white at .62 to .80, with the top at .80 and the bottom (`textTertiary`) at .72.
- FACT: only 37 files carry Semantics or tap-target terms (118 grep hits), against 54 files using HUD primitives. INFERENCE: many screens rely on default widget semantics.
- FACT: no chart-to-data-table alternative found. The progress `_BarChart` is custom (mobile/lib/features/progress/progress_page.dart:663); its Semantics were not opened.
- FACT: `AppSemanticColors.light` accent is violet `#5A25D0` while `HudTokens.light` accent is `#4B7A00`. Two light accents coexist during the migration.

## 7. Where the four-mode selector and global dashboard would plug in

- **Router entry.**
  - FACT(mobile/lib/core/router/app_router.dart:565-584): the shell has five `GoRoute`s under `ShellRoute`.
  - FACT(mobile/lib/shared/widgets/main_shell.dart:69-75, 98-101): `MainShell._paths` is a hard-coded list of five paths, and `_indexFor` picks the selected one.
  - FACT(mobile/lib/core/router/app_router.dart:299-328): `redirectFor` and `resolveRedirect` decide placement, and onboarded users are sent to `/home`.
  - INFERENCE: a mode chooser route would be a new `GoRoute` in app_router.dart or an in-shell overlay. A new path must be allowed in `resolveRedirect` and in the onboarding exemptions if it is meant to be reachable before onboarding.
- **Home shell.**
  - FACT(mobile/lib/shared/widgets/main_shell.dart:64-166): `MainShell` owns the scaffold, `HudSkyBackground`, `PopScope` and `HudNavBar` (label list from `AppLocalizations`).
  - FACT(main_shell.dart:80-96): nav items are built per build from l10n (`homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile`). U-1's centre Record action would replace the `/scan` item here (INFERENCE).
  - FACT(main_shell.dart:111-122): Back on any non-home tab goes to `/home`.
  - INFERENCE: a "recording in progress" strip would sit in `MainShell` between the body and the nav bar. This needs `mobile/lib/shared/widgets/shell_insets.dart` (`shellBottomObstruction`) to account for it.
- **Existing dashboard.**
  - FACT(mobile/lib/features/home/home_page.dart:78-1230): `HomePage` is today's dashboard. Its widgets are `_HudGreeting`, `_HudIdentityRow`, `_HudDayPanel`, `_HudWeekSection`, `_HudRecoveryPanel`, `_HudQuickScanRow`, `_AiPlanCard`, `_PostureCheckCard`, `_UpcomingCard` and `_SuggestionCard`.
  - FACT(mobile/lib/features/progress/progress_page.dart): the Progress tab has `_HeadlineStats`, `_VolumeSection`, `_ConsistencySection`, `_RecordsSection` and photo progress, drawn as `_BarChart`. All of these are gym-only (INFERENCE from the section names; data sources were not read).
  - INFERENCE: the future "global dashboard" maps to `/progress`, per the direction document, which says the Progress tab is the global dashboard.
- **Mode state.** FACT: no mode enum or provider exists anywhere in `mobile/lib`. Persistence would go through `mobile/lib/core/settings/` (`app_settings.dart`, `settings_repository.dart`, `state/settings_providers.dart`) or the profile repository. Which of the two is right is UNKNOWN.
- **Nearest reusable patterns.**
  - `HudPanel` and `HudSurface` for mode cards. They already take `onTap` and `semanticLabel`.
  - `_HudQuickScanRow` in home_page.dart (:766) for a row of entry cards.
  - `mobile/lib/features/onboarding/` (`ob_shell`, `inputs`) for first-run questions.
  - `mobile/lib/features/scanner/scanner_page.dart` for a permission-denial path.

## 8. Discrepancies: UI direction document vs code

1. **Token values (section 3 of the direction document).**
   - Doc: panel is `#0D0D1A` with glass. Code: `#0D0D1A` is only `AppSemanticColors.dark.backgroundSecondary`. The HUD panel is a near-transparent white fill over a photograph, not a dark solid.
   - Doc: background `#06060F` is "main dark surface". Code: it is `backgroundPrimary`, but the scaffold is transparent (mobile/lib/core/theme/app_theme.dart:148) and `HudSkyBackground` paints a photograph over it. `HudTokens.base` is `#14182C`.
   - Doc: text `#F0F0F8`, secondary `#B1B1C6`. Code: those are `AppSemanticColors` values only. `HudTokens` uses `#FFFFFF` and white at .80 / .72. Both are live, split by screen.
   - Doc: accent `#C9FF47`, secondary `#A8D93A`. Code: these match in `AppSemanticColors` dark. `HudTokens` has no secondary accent.
   - Doc is dark only. Code has a full light theme with different accents: violet `#5A25D0` (semantic) vs `#4B7A00` (HUD).
2. **Doc "do not introduce new blur radii; approved blur tier".** Code has many radii: 6, 7, 12, 14, 16, 18, 20, 22 and 30 across the recipes in hud_tokens.dart. No single "approved tier" was identified in the file.
3. **Doc "about 45 routes".** Code has 35 routes (30 top-level plus 5 shell).
4. **Doc "large sans-serif headings".** Code uses three display families with Cyrillic fallbacks.
5. **Doc "touch targets at least 48 dp".** Code `minTapTarget` is 44.
6. **Doc "200 percent text scale".** No app-level scale handling or test, and three `noScaling` exceptions on the scanner.
7. **Doc "corner brackets as a capture/live device".** Unverified in code. Scanner frame widgets exist, but whether they draw brackets is UNKNOWN.
8. **Doc idea 8.8, a design-token parity test.** The document lists it as a proposal. Related tests already exist (`mobile/test/theme/app_semantic_colors_test.dart`, `mobile/test/shared/widgets/hud/hud_components_test.dart`, and `scan_glass_recipes_test.dart`, which is referenced from mobile/lib/core/theme/hud_tokens.dart:345). Their exact coverage is not checked.
9. **Doc assumes new shell concepts not in code:** a mode switcher, a recording strip, a context-sensitive centre Record action, a tablet/side-rail layout, a Consent centre, a "how this is calculated" sheet and source chips. None exist today.
10. **Doc "the film's lime corner wedges".** No wedge or bracket tokens exist in `HudTokens`.
11. **Doc says Scan flows move into BODY.** Today `/scan` is equipment recognition (gym), `/photos/scan` is the body scan and `/form-check` is the form coach, so "Scan" means several things in code.

## 9. Unknowns that need more evidence

- Git branch, HEAD and dirty state for the worktree (git was not run by the agent).
- Whether the scanner frame widgets draw corner brackets, and how the lime accent is used on live screens.
- Per-screen use of semantic vs HUD tokens beyond file counts. A hard-coded colour audit (`Colors.white`, `Color(0x...)`) was not run in this pass; mobile/lib/core/theme/app_semantic_colors.dart:1-42 records an earlier count of 339 references at 2026-08-06.
- Actual contrast on `panel` and `subPanel` fills over each time-of-day photo. The tests found cover `AppSemanticColors`, and `HudTokens` coverage is unconfirmed.
- Depth of the 25 test files that mention semantics or contrast (only the first 25 matches were listed, so more may exist).
- Behaviour at 200 percent text scale (no run was made).
- Offline or connectivity indication on Home, Progress and Profile.
- Whether `/scan` and the centre Record action are intended to merge (U-1 is open in the direction document).
- How settings storage would carry a mode choice (`AppSettings` vs profile).
- Whether the legacy `FrostedScaffold` screens are scheduled for migration and in what order (the `docs/Redisign/` documents may say; they were not read).
- Whether `docs/Redisign/DEV_SINGLE_FILE_MASTER_PROMPT_v2.0_EN.md`, cited by the blueprint, matches what `hud_tokens.dart` transcribes. `mobile/lib/core/theme/hud_tokens.dart:22-27` instead names `design_handoff_fitness_hud/CLAUDE.md` and `README.md` as its source of record, and that folder was not located.

## 10. Key files for the report

`mobile/lib/core/theme/app_semantic_colors.dart`, `hud_tokens.dart`, `hud_typography.dart`, `app_theme.dart`, `app_palette.dart`; `mobile/lib/core/router/app_router.dart`; `mobile/lib/shared/widgets/main_shell.dart`; `mobile/lib/shared/widgets/hud/hud_scaffold.dart`, `hud_surface.dart`, `hud_metric.dart`; `mobile/lib/features/home/home_page.dart`; `mobile/lib/features/progress/progress_page.dart`; `mobile/lib/features/workouts/widgets/set_timer_card.dart`; `mobile/lib/features/form_check/widgets/coach_hud.dart`; `mobile/lib/features/scanner/scanner_page.dart`.
