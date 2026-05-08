# Fitness App — Roadmap

**Source of truth for multi-phase plans, sequencing, and progress.** Update as phases complete or scope shifts. Master feature list lives in [`../FITNESS_APP_TASK_LIST.md`](../FITNESS_APP_TASK_LIST.md) (75 features); this file describes *how* and *in what order* we build them.

---

## Stack (locked-in)

- **App:** Flutter 3.27.1, Dart, Riverpod (state), go_router (nav), google_fonts (Inter)
- **Backend (planned):** Firebase Auth + Firestore + Storage + Cloud Functions (TS)
- **Payments (planned):** Stripe via `flutter_stripe`
- **Video (planned):** Cloudflare Stream or Mux for adaptive bitrate
- **CI/CD:** Codemagic for iOS, GitHub Actions for everything else
- **Dev environment:** Windows + Android Studio + Android emulator (`Pixel_API_34`); SDK at `D:\android-sdk`, Flutter at `D:\flutter`

## Tooling baseline

- JDK 17 (`C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot`) — pinned via `gradle.properties` to avoid AGP/Java-21 incompat
- **Strict D:-drive policy** (2026-05-08): every cache, temp file, install, AVD, build artefact, screenshot lives on D:. C: is reserved for the OS and pre-existing system tooling.
  - Env vars (set in user environment): `PUB_CACHE=D:\.pub-cache`, `GRADLE_USER_HOME=D:\.gradle`, `TEMP=D:\Temp`, `TMP=D:\Temp`, `ANDROID_AVD_HOME=D:\android-avd`, `ANDROID_SDK_ROOT=D:\android-sdk`
  - Flutter SDK at `D:\flutter`, Android SDK at `D:\android-sdk`, AVD at `D:\android-avd\Pixel_API_34.avd`, project root at `D:\test 2\Fitness App\`.
- Tests must stay green at every commit (no skipped, no xfail without justification)
- Approval gate: present a plan before non-trivial work, wait for explicit OK

---

## Phase 0 — Foundations & design system ✅ committed (`76ddda4`)

- Tooling installed end-to-end (JDK, Flutter SDK, Android SDK, AVD)
- Flutter project scaffolded under `mobile/` with 5-tab bottom shell
- Splash → Login → Home flow rendering on emulator
- **Design system:** aurora gradient backdrop with two soft radial blooms; `GlassCard` with diagonal sheen + two-layer drop shadow + no borders; `GlassNavBar` floating frosted bar; `GlassAppBar` with backdrop blur; `ScrollDimList` (vertical list that blurs/dims non-focused cards only while user is actively scrolling)
- Test library: 44 tests across theme, widgets, pages, router (all green)

## Phase 1A — Auth + onboarding questionnaire (local-first) ✅ complete

**Goal:** every screen and flow that depends on a signed-in user with a profile, working end-to-end against an in-memory backend so we can iterate without waiting on Firebase.

- [x] Auth repository pattern (abstract + mock) — `AuthRepository`, `MockAuthRepository`, Riverpod providers (`authRepositoryProvider`, `authUserProvider`, `authActionProvider`)
- [x] Wire `LoginPage` to call the auth provider with loading + error states
- [x] Auth-aware router redirect: `/splash` → `/home` → (if no user) `/login` → (after sign-in) `/home`
- [x] Profile repository (abstract + mock) — `UserProfile` + 7 sub-objects, `ProfileRepository`, `MockProfileRepository`, Riverpod (`profileRepositoryProvider`, `currentProfileProvider`, `isOnboardedProvider`, `profileSubmitProvider`)
- [x] **34-question onboarding questionnaire** — 7-step PageView with gradient progress bar:
  - Step 1 — Personal (age · gender · height · current weight · target weight · activity level)
  - Step 2 — Health history (conditions · allergies · meds · injuries · limitations · surgeries · BP · other)
  - Step 3 — Goals (multi-select + specific sport)
  - Step 4 — Fitness level (frequency · current exercises · self-rated tier · basic ability)
  - Step 5 — Lifestyle (diet multi · smoking · alcohol · sleep · stress slider · occupation)
  - Step 6 — Equipment (gym y/n · home equipment list)
  - Step 7 — Motivation (free text · environment multi · preferred duration)
  - Submission stamps `completedAt` and bounces to `/home`
- [x] Router redirect tightened: signed-in & not onboarded → `/onboarding`; onboarded → `/onboarding` redirects back to `/home`
- [x] Profile tab: pulls real user + profile, shows "At a glance" summary card (age/height/weight/activity/goals) when onboarded, "Complete questionnaire" CTA when not, and the sign-out tile actually signs out via `authActionProvider`

## Phase 1B — Firebase wiring 🔒 blocked on user

**Goal:** swap the in-memory mocks for the real backend with zero UI changes.

User actions required:
1. Create Firebase project at <https://console.firebase.google.com>
2. Enable Auth (Email/Password + Google providers) and Firestore (production mode)
3. Add an Android app, download `google-services.json` to `mobile/android/app/`
4. Install Firebase CLI; run `flutterfire configure` to generate `firebase_options.dart`

Implementation:
- Add `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`
- `FirebaseAuthRepository` and `FirestoreProfileRepository` — Phase 1A interfaces, real backend
- Override the existing Riverpod providers in `main.dart` to point at the Firebase implementations
- `firestore.rules`: locked-down per-user reads/writes against `users/{uid}/...`
- Tests against the Firebase emulator suite (no live network in CI)

## Phase 2 — Equipment scanner + curated workout videos ✅ A+B shipped

**Maps to master tasks 1, 6, 8, 9.** First half of the actual product surface.

- [x] **Phase 2A** — Live QR scanner via `mobile_scanner`, equipment catalog (`assets/data/equipment.json` + `assets/data/exercises.json` shipped with the app), `AssetEquipmentRepository`, `/equipment/:id` route with `EquipmentDetailPage` listing all curated exercises for that machine.
- [x] **Phase 2B** — `video_player`-backed `WorkoutPlayerPage` at `/workout/:id`. Plays remote MP4 when an exercise has `videoUrl`; falls back to step-by-step instructions when not. Caution card surfaces contraindications based on the exercise's hidden injury tags.
- [x] AGP bumped 8.1 → 8.7 + Kotlin 1.8.22 → 2.0.21 + Gradle 8.3 → 8.10.2 + minSdk 21 → 23 to satisfy `mobile_scanner` and Firebase requirements.
- [ ] **Phase 2C** — recommendation filter (hide contraindications based on the user's actual injury list, surface tier-appropriate exercises). Today the catalog ships everything for an equipment id.
- [ ] **Phase 2D** — Train tab integration (currently still using stubbed workout cards; needs to pull live data from the equipment catalog).
- [ ] **Phase 2E** — scraper + content pipeline to grow the catalog beyond the 12 hand-seeded exercises.

## Phase 3 — Workout calendar, logging, basic progress (queued)

**Maps to master tasks 10, 26 (subset).**

- Schedule + reminders via local notifications
- Workout log model + writes
- Progress tab: real charts (workouts/week, weight trend) backed by logs

## Phase 4 — Subscriptions, billing, free trial (queued)

**Maps to master tasks 13, 17.** First monetisation surface.

- Stripe integration via `flutter_stripe`
- Tiered plans (free / standard / celebrity-trainer)
- Free trial gating
- Subscription state in profile

## Phase 5 — Compliance, accessibility, data export (queued)

**Maps to master tasks 64, 65, 68, 73.** Required before any real launch.

- GDPR / HIPAA-aware data model
- Account deletion + data export
- Age verification (COPPA)
- WCAG 2.2 AA pass on all screens

## Phase 6+ — High-value differentiators (queued, sequenced later)

Sequence depends on user appetite and Phase 1–5 outcomes:

- AI workout generator + AI coach (master tasks 40, 41)
- Real-time pose / form-risk detection (20, 38)
- Social network + workout buddy matching (19, 50)
- Live-streamed group classes (47)
- User-generated workout marketplace (48, 49)
- Deep-fake celebrity trainers — *legal framework first* (12, 67)
- Sports event ticketing + travel mode (23, 34)

---

## Decisions captured along the way

- **Android-first.** iOS deferred until after Phase 2; Codemagic for cloud builds when we get there.
- **Mock-first repositories.** Lets us build full flows without waiting on Firebase setup; Phase 1B is a flip-the-DI exercise, not a rewrite.
- **No carousel for browsing.** Replaced the original PageView carousel with `ScrollDimList`: every card visible at rest, blurred/dimmed only while actively scrolling, snaps back to clarity on release.
- **GoogleFonts in tests.** `allowRuntimeFetching = false` + `tester.takeException()` per theme test — the proper fix is bundling the Inter font as an asset, deferred.
- **Single git history at the project root.** No nested repos. `mobile/`, `docs/`, `content/`, etc., all live in the same repo.

## Open questions to revisit

- Will we bundle the Inter font as an asset to remove the network dependency at runtime?
- Branding (name, colors, logo) — currently using "Fitness App" + dumbbell icon as placeholders.
- Where do equipment videos live initially — Firebase Storage or Cloudflare Stream from day one?
- Multi-language story (master task 33): Crowdin / Phrase / hand-rolled ARB files?
