# CODEMAP — where everything lives

**Purpose: answer "which file do I open?" in one read, instead of several Glob/Grep rounds.**
Paths are relative to `mobile/` unless stated. Counts verified against the working tree 2026-07-28.

Descriptions marked **[doc]** are quoted from the module's own doc-comment (the code carries ticket
IDs like `MK.6` / `TX.3`). Unmarked ones are derived from the route + entry filename.

---

## Start here

| You want to... | Open |
|---|---|
| Understand app startup, DI, Firebase init | `lib/main.dart` |
| Find which page a URL renders | `lib/core/router/app_router.dart` (296 lines, all routes) |
| Find a feature's code | the feature table below, then `lib/features/<name>/` |
| Change global look/colour | `lib/core/theme/app_theme.dart`, `lib/core/theme/app_palette.dart` |
| Change bottom nav / shell chrome | `lib/shared/widgets/main_shell.dart`, `lib/shared/widgets/glass_nav_bar.dart` |
| Touch health / wearable sync | `lib/core/health/`, `lib/core/wear/` |
| Add or modify a Cloud Function | `functions/src/index.ts` (Stripe bridge) |

**Layout convention** — every feature follows the same shape, so guessing is safe:

```
lib/features/<name>/
    <name>_page.dart      UI entry point (only if the feature has a screen)
    data/                 models, repositories, pure logic  <- unit-testable, no Flutter
    state/                Riverpod providers
    widgets/              feature-local widgets
```

---

## Routes to feature

Declared in `lib/core/router/app_router.dart`. Five routes sit inside `MainShell` (bottom nav); the
rest are pushed full-screen.

| Route | Feature | Entry file |
|---|---|---|
| `/splash` | splash | `lib/features/splash/splash_page.dart` |
| `/login` | auth | `lib/features/auth/login_page.dart` |
| `/onboarding` | onboarding | `lib/features/onboarding/onboarding_page.dart` |
| `/home` *(shell)* | home | `lib/features/home/home_page.dart` |
| `/scan` *(shell)* | scanner | `lib/features/scanner/scanner_page.dart` |
| `/workouts` *(shell)* | workouts | `lib/features/workouts/workouts_page.dart` |
| `/progress` *(shell)* | progress | `lib/features/progress/progress_page.dart` |
| `/profile` *(shell)* | profile | `lib/features/profile/profile_page.dart` |
| `/equipment/:id` | equipment | `lib/features/equipment/equipment_detail_page.dart` |
| `/workout/:id` | equipment | `lib/features/equipment/workout_player_page.dart` |
| `/subscription` | subscription | `lib/features/subscription/subscription_page.dart` |
| `/about` | about | `lib/features/about/about_page.dart` |
| `/donors` | donor_wall | `lib/features/donor_wall/donor_wall_page.dart` |
| `/plan` | ai_planner | `lib/features/ai_planner/ai_planner_page.dart` |
| `/celebrity-plans` | celebrity_plans | `lib/features/celebrity_plans/celebrity_plans_page.dart` |
| `/photos` | progress_photos | `lib/features/progress_photos/progress_photos_page.dart` |
| `/team/:teamId` | community | `lib/features/community/team_feed_page.dart` |
| `/form-check` | form_check | `lib/features/form_check/form_check_page.dart` |
| `/contribute` | catalog | `lib/features/catalog/contribute_video_page.dart` |
| `/moderate` | catalog | `lib/features/catalog/moderation_page.dart` |
| `/coaches` | marketplace | `lib/features/marketplace/marketplace_page.dart` |

---

## Features with a screen

| Feature | Files | Lines | What it does |
|---|---:|---:|---|
| `workouts` | 22 | 3,385 | Workout browsing + logging. `lib/features/workouts/data/offline/` handles prefetch; `widgets/` holds the plate, rest and warm-up calculators plus `set_timer_card.dart`. The timed set lives in `data/set_session.dart` (pure, clock-free) driven by `state/set_timer_providers.dart` (owns the only clock) with `data/cue_player.dart` for the three synthesised sounds |
| `equipment` | 18 | 3,449 | Equipment detail + workout player. `data/exercise_filter.dart` is the injury-aware filter that gates exercises; `widgets/exercise_thumb.dart` is the one tile every list renders an exercise as (bundled poster, gradient fallback) |
| `subscription` | 10 | 1,834 | Tiers, paywall, Stripe checkout. `subscription_page.dart` is the biggest file in the repo. `effectiveTierProvider` is the single point that decides the tier — including the Settings test-access override |
| `onboarding` | 10 | 1,209 | Multi-step intake incl. the injury questionnaire. `lib/features/onboarding/steps/` = one file per step |
| `profile` | 6 | 1,024 | Profile + settings. `lib/features/profile/data/firestore_profile_repository.dart` is the Firestore boundary |
| `form_check` | 16 | 4,799 | On-device pose/form checking. `data/mlkit_pose_detector_service.dart` + `data/form_classifier.dart`; `data/pose_silhouette.dart` builds the two-sided outline (drawn only — scoring still reads the six authored side-view joints) and `data/pose_projection.dart` maps measured landmarks onto the preview |
| `home` | 1 | 594 | Landing dashboard, single file |
| `progress_photos` | 5 | 519 | Progress photo capture + timeline |
| `donor_wall` | 5 | 501 | Public donor recognition (ties to the nonprofit model) |
| `catalog` | 5 | 498 | Community video contribution + moderation queue |
| `auth` | 6 | 479 | Firebase email / social sign-in |
| `community` | 4 | 454 | Teams and team feeds |
| `marketplace` | 4 | 405 | Coach marketplace |
| `progress` | 2 | 400 | Charts + stats over logged workouts |
| `visual_equipment` | 13 | ~1,300 | Equipment recognition data layer: Gemini cloud recogniser (`gemini_equipment_service.dart`, Firebase AI Logic) with on-device TFLite fallback, live smoother, recognition history. Rendered by `scanner` |
| `ai_coach` | 4 | ~600 | Gemini-backed technique advice sheet (opened from every equipment page) + AI exercise generator with a per-(user, machine, language) Firestore cache, used only for machines the vendored catalog has nothing for |
| `social_feed` | 4 | 333 | Social activity feed |
| `ai_planner` | 4 | 326 | AI-generated training plan (`/plan`) |
| `about` | 1 | 287 | About / info page |
| `celebrity_plans` | 4 | 228 | Celebrity-authored plans |
| `scanner` | 1 | ~700 | Photo-recognition tab (the core moat feature): live viewfinder at min zoom, centre-crop capture, honest confidences, "My machines" history. QR was removed 2026-07-30 (operator request) |
| `splash` | 1 | 106 | Launch / routing gate |

## Logic-only modules (no screen)

No UI; other features consume their models and providers. All carry doc-comments with ticket IDs,
quoted here.

| Feature | Files | Lines | What it does |
|---|---:|---:|---|
| `moments` | 6 | 433 | **[doc]** In-app "moments" — one-shot celebration / nurture prompts |
| `recovery` | 3 | 323 | **[doc]** Auto-deload signal, pure function on recent history (`lib/features/recovery/data/deload_detector.dart`) + `lib/features/recovery/widgets/deload_banner.dart` |
| `injury_coach` | 2 | 201 | **[doc]** TX.1 Injury Recovery Coach — multi-week, day-by-day rehab plans tagged to injuries |
| `personalisation` | 3 | 199 | **[doc]** Re-ranks the For-You feed from the user's `FitnessProfile` |
| `voice` | 1 | 137 | **[doc]** TX.6 / MK.1 voice-only hands-free workout control; restricted command grammar |
| `cycle_aware` | 1 | 80 | **[doc]** MK.3 Cycle-Aware Programming — 4-phase model, pure |
| `buddy` | 1 | 75 | **[doc]** TX.3 Buddy Matching — in-gym presence via BLE |
| `sdk_export` | 1 | 66 | **[doc]** MK.5 White-label gym-chain SDK foundations |
| `goal_photo` | 1 | 60 | **[doc]** MK.2 Goal-photo to personalised program |
| `body_comp` | 1 | 58 | **[doc]** MK.6 Body composition from phone camera + height/weight |
| `insurance` | 1 | 54 | **[doc]** MK.4 Insurance discount partnerships (attestation endpoint) |
| `recovery_workout` | 1 | 46 | **[doc]** MK.7 Recovery as a first-class workout |

> The previous version of this file called these "single-file stubs". They are not stubs — each is a
> documented domain module with a ticket ID.

---

## Cross-cutting — `lib/core/` (15 files)

| Path | Role |
|---|---|
| `lib/core/router/app_router.dart` | All routes + `MainShell` wiring (296 lines) |
| `lib/core/theme/` | `app_theme.dart`, `app_palette.dart` — global theme + colours |
| `lib/core/health/` | Health Connect / HealthKit abstraction. `health_service.dart` is the interface, `platform_health_service.dart` the impl — **this is the iOS-portability seam** |
| `lib/core/wear/` | Wear OS phone-side sync (`wear_sync_service.dart`) |
| `lib/core/notifications/` | Notification service + a mock impl for tests |
| `lib/core/assets/asset_bootstrap.dart` | Bundled asset loading |

## Shared UI — `lib/shared/widgets/` (5 files)

`main_shell.dart` (bottom-nav scaffold), `glass_nav_bar.dart`, `glass.dart`,
`aurora_background.dart`, `smooth_scroll_list.dart` — the glass/aurora visual language.
(`scroll_dim_list.dart` was deleted: it blurred and dimmed every off-centre card on
every scroll tick, which cost the frame budget for decoration.)

---

## Outside `mobile/lib`

| Path | Files | Role |
|---|---:|---|
| `mobile/test/` | 103 | Unit + widget tests, 721 of them. Runs on the host via `flutter test` |
| `mobile/integration_test/` | 1 | `app_test.dart` — drives the real app on a device; the only place the native ML Kit bridge and the actual APK contents are visible. Needs hardware |
| `mobile/android/` | 19 | Android host + Gradle |
| `mobile/assets/` | 4 | Bundled data, ML models, demo frames, and the CC BY 4.0 anatomy chart |
| `functions/src/index.ts` | 1 | Cloud Functions — Stripe bridge |
| `wear/src/` | 5 | Wear OS companion (Kotlin) |
| `scripts/dev/` | 7 | `debug_daemon.ps1`, `run_app.ps1`, `run_tests.ps1`, `run_with_debug.ps1`, `build_wear.ps1`, `measure_context.ps1`, `audit_doc_links.ps1` |
| `scripts/ops/` | 1 | `setup_stripe_secrets.ps1` |
| `scripts/catalog/` | 1 | `seed_stock_videos.ps1` |
| `docs/` | 67 | Emulator screenshots — see `docs/README.md` |

---

## Keeping this file honest

Hand-maintained; nothing regenerates it. When you add or remove a feature, update the tables above
in the same commit. `scripts/dev/audit_doc_links.ps1` fails the moment a path here stops resolving,
which catches deletions and renames — but **not** a feature you forgot to add.
