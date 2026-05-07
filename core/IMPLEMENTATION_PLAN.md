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
- All file I/O on D: drive to spare C:
- Tests must stay green at every commit (no skipped, no xfail without justification)
- Approval gate: present a plan before non-trivial work, wait for explicit OK

---

## Phase 0 — Foundations & design system ✅ committed (`76ddda4`)

- Tooling installed end-to-end (JDK, Flutter SDK, Android SDK, AVD)
- Flutter project scaffolded under `mobile/` with 5-tab bottom shell
- Splash → Login → Home flow rendering on emulator
- **Design system:** aurora gradient backdrop with two soft radial blooms; `GlassCard` with diagonal sheen + two-layer drop shadow + no borders; `GlassNavBar` floating frosted bar; `GlassAppBar` with backdrop blur; `ScrollDimList` (vertical list that blurs/dims non-focused cards only while user is actively scrolling)
- Test library: 44 tests across theme, widgets, pages, router (all green)

## Phase 1A — Auth + onboarding questionnaire (local-first) 🔄 in flight

**Goal:** every screen and flow that depends on a signed-in user with a profile, working end-to-end against an in-memory backend so we can iterate without waiting on Firebase.

- [x] Auth repository pattern (abstract + mock) — `AuthRepository`, `MockAuthRepository`, Riverpod providers (`authRepositoryProvider`, `authUserProvider`, `authActionProvider`)
- [x] Wire `LoginPage` to call the auth provider with loading + error states
- [x] Auth-aware router redirect: `/splash` → `/home` → (if no user) `/login` → (after sign-in) `/home`
- [x] Tests for auth repo, providers, redirect (added 15 tests on top of the 44 from Phase 0)
- [ ] Profile / questionnaire repository (abstract + mock) — `UserProfile`, `ProfileRepository`, `MockProfileRepository`, Riverpod state
- [ ] **34-question onboarding questionnaire** as a multi-step form, grouped by section (Personal · Health · Goals · Fitness level · Lifestyle · Equipment · Motivation), with progress indicator and field validation. Persists to the profile repository on submit.
- [ ] Router redirect: authed but no profile → `/onboarding`
- [ ] Profile tab: show questionnaire summary, edit shortcut, sign-out
- [ ] Tests for the questionnaire flow

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

## Phase 2 — Equipment scanner + curated workout videos (queued)

**Maps to master tasks 1, 6, 8, 9.** First half of the actual product surface.

- Camera + QR scanner via `mobile_scanner`
- Equipment catalog (manufacturer, model, exercise mappings) seeded from `content/equipment.json`
- Equipment detail screen: machine info → recommended exercises filtered by user profile
- Video player (Cloudflare Stream / Mux) with offline-friendly controls
- Hand-curated seed library of ~50 exercises (scraper deferred to a later phase)

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
