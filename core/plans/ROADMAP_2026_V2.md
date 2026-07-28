# Roadmap 2026 v2 — Implementation Plan + New Game-Changer Features

**Source of truth for what we build next, in what order, why, and at what cost.** Supersedes `IMPLEMENTATION_PLAN.md` for forward planning (that file remains the historical record of completed phases). Driven directly by [`../business/COMPETITIVE_ASSESSMENT.md`](../business/COMPETITIVE_ASSESSMENT.md).

Author signal: this is a planning doc. Anything here is subject to change after a real implementation pass — the per-feature time estimates are realistic but not contractual.

---

## Executive summary

Two parts:

1. **Catch-up plan (Tier 0–4)** — sequenced implementation of every gap surfaced by the top-20 competitor analysis. Aim: ship a credible v1 by 2026Q4 that doesn't lose to Hevy or Fitbod on day-1-of-trial.

2. **Seven new dedicated game-changer features (Tier X)** — features no top-20 incumbent ships, built on our existing stack, designed to create either network effects or non-replicable moats. Each gets a technical sketch (what to build, where to plug it in, what exists today).

12-month effort estimate: **~2 senior FE-leaning full-stack engineers + 1 BD/partnerships lead + ~$50–80k of one-time external costs** (legal, physio review, gym partnership stickers). Realistic v1 launch: **2026Q4** with the catch-up plan; **2027Q2** with the first 3 game-changers integrated.

---

## Glossary of priority labels

- **P0 — must ship before any v1 marketing push.** Day-1-of-trial users churn back to incumbents without these.
- **P1 — closes a gap competitors exploit in reviews.** Ship in the 90 days after launch.
- **P2 — moat-deepening + community.** Defines the second-version product.
- **P3 — long-tail polish.** Don't block earlier work on these.
- **Tier X — new game-changers.** Net-new product surface that defines us in the category.

---

## Part 1 — Catch-up plan (P0–P3)

### Tier 0 — credible v1 (target: 2026Q3)

#### P0.1 — Annual subscription SKUs

**Why it matters:** Every paid competitor offers annual at ~50% effective discount. We have none. Single biggest revenue lever in the assessment.

**Scope:**
- Add `SubscriptionTier` × `SubscriptionPeriod` (`monthly` / `annual` / `lifetime`) to the model
- New Stripe price IDs: `price_standard_annual_5999`, `price_celebrity_annual_11999`, `price_celebrity_lifetime_49900`
- Add `interval` field to `Subscription` model + Firestore + Stripe webhook
- `SubscriptionPage` shows monthly + annual toggle + lifetime CTA
- Feature gates remain unchanged (annual is just a billing cadence)

**Files touched:**
- `mobile/lib/features/subscription/data/subscription_models.dart` — add `SubscriptionPeriod` enum
- `mobile/lib/features/subscription/subscription_page.dart` — add period toggle
- `mobile/lib/features/subscription/data/cloud_functions_stripe_service.dart` — pass `period` to checkout
- `functions/src/index.ts` — `createCheckoutSession` reads `period` arg → maps to right price ID
- 6 new Stripe price IDs created (manual, in Stripe dashboard)
- `core/PHASE_4B_STRIPE_SETUP.md` — record new price IDs

**Effort:** 2 days (1.5 eng + 0.5 you for Stripe dashboard).

**Pricing (locked recommendation):**

| | Monthly | Annual | Lifetime |
|---|---------|--------|----------|
| Free | $0 | — | — |
| Standard | $9.99 | **$59.99** ($5/mo eff.) | — |
| Celebrity | $19.99 | **$119.99** ($9.99/mo eff.) | **$499** |

#### P0.2 — Family plan tier on Standard

**Scope:** $14.99/mo for 2 accounts; $19.99/mo for 4. Implementation via Firebase Auth's child accounts + a `family_owner_uid` field on `Subscription`.

**Files touched:**
- `mobile/lib/features/subscription/data/subscription_models.dart` — add `seats: int` + `seatedUids: List<String>`
- `functions/src/index.ts` — `linkFamilyMember` callable + invite flow
- New `lib/features/family/family_invite_page.dart` (deep link → claim seat)

**Effort:** 5 days (heavier than annual because of the invite + identity flow).

**Marketing line:** *"Apple Fitness+ shares with 6 — only on Apple Watch. We share with 4 — on any phone."*

#### P0.3 — Wear OS companion

**Why it matters:** Strong/Hevy/Fitbod/Centr/NTC/Peloton/Apple all have watch set logging. Phone-out-of-pocket-between-sets is real friction. Without this, $9.99 Standard fails the sniff test vs Hevy.

**Scope:**
- New Flutter Wear OS module (`mobile_wear/`) — separate Flutter target
- Display: current exercise + "Done set" button + rest timer
- Communicates with phone via `wear` package (or `flutter_wear`)
- Logs each tap as a set into the existing `WorkoutLogEntry`

**Files touched:**
- New `mobile/lib/features/wear/` (phone side)
- New `mobile_wear/` Flutter project (watch side)
- `mobile/android/app/build.gradle` — Wear OS feature

**Effort:** 12 days (this is the biggest single P0 item; Wear OS development is its own learning curve). Could be parallelised with other work.

**Risk:** First-time Wear OS development — budget +30% for the unknowns. Apple Watch parity is Phase 7+.

#### P0.4 — Exercise videos for every movement (catalog scraper)

**Why it matters:** We ship 12 hand-seeded exercises with maybe 1–2 videos. Hevy 200+, Fitbod 1,000+, Jefit 1,400+. Curated lists without video lose trust.

**Scope:**
- Phase 2E from the original plan — finally schedule it
- Source 1: licensed stock fitness video (BBlearn, Pond5, ~$500–2000 for 200 short clips)
- Source 2: contract one fitness creator to record 200 short demos (~$5–15k)
- Storage: Firebase Storage with public CDN + signed URLs for premium-tier-only content
- Catalog grows from 12 → 200 movements

**Files touched:**
- `mobile/assets/data/exercises.json` — append 200 entries (keep equipment_id mapping)
- `firestore.rules` — already covers
- `lib/features/equipment/data/asset_equipment_repository.dart` — no changes; reads same shape

**Effort:** 10 days eng (catalog + tagging + ingest pipeline) + ~$5–15k content.

**Recommend:** contract route. Stock video tends to look stale; a single fitness creator (find via Upwork or a local CrossFit gym) recording 200 clips in a 3-day shoot is high quality + cheap.

#### P0.5 — Health Connect (Android) + Apple Health sync

**Scope:**
- Read: step count, HR, sleep score, daily activity ring (for "for you" reordering)
- Write: completed workouts (so they show up in Google Fit / Apple Health)
- Package: `health` (Flutter), already 700k+ pub.dev downloads/year, supports both platforms

**Files touched:**
- New `mobile/lib/core/health/health_service.dart` (abstract + impl + mock)
- `mobile/lib/features/workouts/state/workout_log_providers.dart` — `logWorkoutAction.log()` also writes to Health Connect on success
- `AndroidManifest.xml` — Health Connect permission

**Effort:** 4 days.

#### P0.6 — Rest timer with auto-trigger on log

**Scope:** When user marks a set complete, auto-start a 90-second timer with vibration on completion. Configurable per exercise (compound lifts default to 180s).

**Files touched:**
- New `mobile/lib/features/workouts/widgets/rest_timer.dart`
- `WorkoutPlayerPage` shows the timer above the "Mark complete" button when a set has just been logged

**Effort:** 1.5 days. Trivial; unforgivable to ship without.

#### P0.7 — Plate calculator + warm-up calculator

**Scope:**
- Plate calculator: input `total_kg` → output plate-load combo per side
- Warm-up calculator: given working weight, suggests 4-set ramp (40%, 60%, 80%, 90%)

**Files touched:**
- New `mobile/lib/features/workouts/widgets/plate_calculator.dart`
- New `mobile/lib/features/workouts/widgets/warmup_calculator.dart`
- Surfaced as a "quick tools" sheet on `WorkoutPlayerPage`

**Effort:** 1 day each, 2 days total.

#### P0.8 — Offline workout download

**Scope:** Cache `videoUrl` for the next 7 days of scheduled sessions on launch. Background download with `flutter_downloader` or `dio` + filesystem cache. Premium-tier feature.

**Files touched:**
- New `mobile/lib/features/workouts/data/offline_video_cache.dart`
- `WorkoutPlayerPage` checks cache before falling back to network
- Standard+ tier gating via `featureAccessProvider(AppFeature.offlineVideos)` (new feature enum entry)

**Effort:** 4 days.

**Tier 0 total:** ~38 engineering days (one engineer = ~8 weeks; two engineers in parallel = ~5 weeks). Plus $5–15k content + Stripe price ID setup.

---

### Tier 1 — close the personalisation + recovery gaps (target: 2026Q4)

#### P1.1 — Post-workout 1-tap difficulty rating

**Why it matters:** Freeletics' AI Coach reads this signal; nobody else in the top-20 reads perceived exertion at all. Combined with our injury filter, this is the personalisation story Centr/Sweat/Ladder don't have.

**Scope:**
- After "Mark complete", a sheet asks: 😅 too easy / 👍 right / 🥵 too hard
- Stored as `difficultyRating: int (-1, 0, +1)` on `WorkoutLogEntry`
- Recommendation pipeline reads last N ratings per muscle group + adjusts tier-fit ordering

**Files touched:**
- `mobile/lib/features/workouts/data/workout_log.dart` — add field
- `WorkoutPlayerPage` _MarkCompleteButton — show sheet after save
- `lib/features/equipment/data/exercise_filter.dart` — extend `recommended()` to read recent ratings

**Effort:** 3 days.

#### P1.2 — Programmatic progressive overload

**Scope:** Given the user's last N logs of an exercise, suggest the next-session weight (+2.5kg if last 3 sessions hit reps; -5% if last session was rated too hard).

**Files touched:**
- New `lib/features/workouts/data/progression.dart` (pure function)
- `WorkoutPlayerPage` shows a "Suggested: 80kg" hint above the rep input

**Effort:** 4 days.

#### P1.3 — MediaPipe form check on Android (P2 in original — moved up to P1)

**Why downgraded from "12-18 month moat":** Tempo's form check is depth-camera based (Apple TrueDepth on iPhone). Pure RGB form check via MediaPipe BlazePose has been commodity since 2021. Marketing line is *"form feedback on commodity Android, no $2,500 hardware required"*, not "unique AI form check".

**Scope:**
- On-device pose tracking via `google_mlkit_pose_detection` (Flutter wrapper for MediaPipe BlazePose)
- 6 form checks for the highest-injury-risk movements: squat depth, deadlift back angle, push-up scapular stability, overhead press lockout, lunge knee tracking, plank alignment
- Each check is a pure rule-based classifier on the 33 body keypoints (no ML training required for v1)
- UI: phone camera in landscape mode + green/red overlay during the set

**Files touched:**
- New `mobile/lib/features/form_check/` directory
- New `lib/features/form_check/data/form_classifier.dart` (pure rules)
- New `lib/features/form_check/form_check_page.dart`
- Tied into `WorkoutPlayerPage` for the 6 supported exercises
- Premium-tier gated via `featureAccessProvider(AppFeature.formCheck)`

**Effort:** 14 days (the keypoint-to-rule mapping is custom per exercise; each one ~2 days).

**Marketing:** *"Squat depth, deadlift back angle, push-up form. Live feedback on every rep. No $500 device — just your phone."*

#### P1.4 — Wearable HRV/sleep ingestion → recovery score

**Why it matters:** Centr and Hevy reviewers explicitly want this in 2026 reviews. Only Future and SensAI deliver it. White space at $10–20/mo.

**Scope:**
- Read HRV (RMSSD) + sleep score from Health Connect / Apple Health (already wired in P0.5)
- Compute a 0–100 recovery score = (50% sleep + 30% HRV vs 30-day baseline + 20% reported soreness)
- Surface on Home page Today card: *"Recovery 68/100 — go moderate today"*
- "For You" feed re-ranks by recovery: low-recovery days surface mobility + light cardio first

**Files touched:**
- New `lib/features/recovery/data/recovery_score.dart` (pure function)
- `lib/features/home/home_page.dart` — recovery chip on Today card
- `lib/features/equipment/data/exercise_filter.dart` — recovery-aware re-rank

**Effort:** 5 days.

#### P1.5 — Lifetime $499 SKU on Celebrity tier

**Scope:** Standalone Stripe price (one-time charge, not recurring). Webhook handles `payment_intent.succeeded` → marks subscription as `active` with `currentPeriodEndsAt = year 9999`. UI: a "Lifetime" tab next to Annual.

**Files touched:**
- `functions/src/index.ts` — handle `checkout.session.completed` for one-time payments
- `mobile/lib/features/subscription/subscription_page.dart` — third tab

**Effort:** 2 days.

**Marketing:** *"$499 once, no monthly bill ever again. Hevy charges $75 lifetime. Yours is 6.7× the value."*

**Tier 1 total:** ~28 engineering days (~5.5 weeks single eng).

---

### Tier 2 — moat-deepening (target: 2027Q1)

#### P2.1 — Team feed for Celebrity tier

**Scope:** Each signed celebrity gets a feed where they post: workout-of-the-week, motivational notes, technique tips. Subscribers can comment + react. Closest analogue: Ladder's team feeds.

**Files touched:**
- New `mobile/lib/features/community/` directory
- New Firestore subcollection: `users/{trainerUid}/posts/{postId}` + `posts/{postId}/comments/{commentId}`
- New `firestore.rules` — trainers write, all subscribers read

**Effort:** 8 days.

#### P2.2 — Physio-reviewed catalog claim

**Scope:** Pay one DPT (find via local hospital network or ATPT.org) ~$5k for a one-time review of 200 exercises + the contraindication tag mappings. Add reviewer credit to landing page + onboarding.

**Files touched:**
- `mobile/assets/data/exercises.json` — add `reviewedBy` field per exercise
- Marketing site (TBD) — landing-page section "Reviewed by Dr. [X], DPT, [years] years of practice"
- `core/PHYSIO_REVIEW.md` — documents the engagement

**Effort:** 1 day eng + ~$5k contractor cost. Cheapest credibility moat in this whole plan.

#### P2.3 — Progress photos + body composition trend

**Scope:** Camera capture + Firebase Storage with end-to-end encryption (user-controlled key). Side-by-side comparison view with date sliders. v1 is just photos; AI body-comp estimate is Tier X.

**Files touched:**
- New `lib/features/progress/photo_*` files
- New Storage path `users/{uid}/photos/{date}.jpg.enc`

**Effort:** 6 days.

#### P2.4 — Celebrity-led video plans (legal framework)

**Scope:** Sign one celebrity trainer (mid-tier — find via talent agencies or fitness influencer networks). Cost: ~$30–80k for 50 hand-curated workouts + ongoing royalty (5–15%). 4–8 weeks of legal work for the contract.

**Effort:** 0 eng (this is content + legal). Required for Celebrity tier credibility.

**Tier 2 total:** ~15 engineering days + ~$35–85k content/legal.

---

### Tier 3 — polish + retention (target: 2027Q2)

P3 items are smaller and accelerate as the team matures. Quick list:

- **Social feed** (Hevy-style): friends + activity. ~10 days.
- **Trial-end transparency** (auto-cancel reminders 48h before billing): ~1 day. Defensive — cheap.
- **Account deletion + data export** (GDPR): ~5 days. Phase 5 in original plan.
- **WCAG 2.2 AA accessibility audit**: ~10 days + ~$3k external audit.

---

## Part 2 — Seven new dedicated game-changer features (Tier X)

These are features **no top-20 incumbent ships**, built on our existing stack, designed to create network effects, B2B leverage, or non-replicable moats. Each has a technical sketch + rationale + effort.

### TX.1 — AI Injury Recovery Coach

**Status quo:** Our injury intake (34 questions) collects injury body parts + types and our filter removes incompatible exercises. That's reactive.

**Game-changer:** Active rehab progressions. When a user reports a knee injury at intake, rather than only hiding squats, we surface a 6-week guided progression: isometrics → bodyweight squats → goblet squats → return to full barbell. Tracks compliance and graduates them.

**Why no one else has this:** Freeletics literally tells users "consult your doctor." Future has 1:1 coaches but at $149/mo. Caliber has live human PTs at $200+/mo. Nobody at the $10–20/mo tier touches recovery actively because liability scares them.

**Why we can ship it:**
- We already have the injury intake + the filter
- Rehab protocols are public (Mike Boyle, NSCA, ACE) and well-documented
- Shipping with a "Reviewed by Dr. [X], DPT" disclaimer (P2.2) covers the liability angle

**Technical sketch:**
- New `lib/features/rehab/` module
- New Firestore: `users/{uid}/rehab_programs/{injuryId}` documents
- New `RehabProtocol` model: phase × duration × exercise list × success criteria
- Tied into `currentProfileProvider` — when a new injury is added, prompt: "Want a guided recovery plan?"
- Each rehab session feeds into existing `workoutLogsProvider` so streaks count

**Defensibility:** Once the user is 4 weeks into a 6-week rehab program, they don't switch apps. Switching cost = restart from week 1. **Strongest user-lock-in feature in the whole roadmap.**

**Effort:** 12 days eng + $5–10k for protocol design contractor (DPT, can be the same person doing the catalog review in P2.2).

**B2B angle:** Sell to physical therapy chains as a patient-facing companion app. PTs prescribe routines; patient logs at home; PT sees compliance.

---

### TX.2 — Photo-based equipment recognition (no-QR fallback)

**Status quo:** Our QR scan only works on machines we've stickered. The cold-start problem: a new user at a non-partnered gym has no QR codes.

**Game-changer:** Phone camera + on-device ML recognises the equipment by sight. Treadmill, rower, lat pulldown, cable column, leg press → identified in <1s. No internet round-trip, no privacy concerns.

**Why no one else has this:**
- Technogym's Mywellness ties to specific machine serial numbers (no general vision)
- iFIT pairs to NordicTrack hardware (no general vision)
- Weightplan uses stickers (no general vision)
- Tempo recognises its own dumbbells via depth camera (only its own gear)

**Why we can ship it:** Equipment recognition is a much narrower vision problem than general object detection. We need to distinguish ~30 common gym machines. A small custom MobileNet model (~5MB) trained on a few thousand labelled images per machine reaches >90% top-1 accuracy. On-device inference via `tflite_flutter`.

**Technical sketch:**
- New `lib/features/scanner/data/visual_classifier.dart`
- TFLite model: 30 classes, MobileNetV3-small backbone, ~5MB on-device
- `ScannerPage` adds a "Use camera (no QR)" mode
- Falls back to manual selection if confidence < 0.7
- Ground-truth training set: ~3,000 photos crowd-sourced from beta users + our own gym visits (or scraped from public images, ~$2k for labelling via Mechanical Turk)

**Defensibility:** Solves the cold-start problem at non-partnered gyms. Combined with QR (where partnered) and manual (always), we're equipment-aware **everywhere**. Nobody else can claim that.

**Effort:** 25 days eng + ~$5k for training data labelling. The biggest single Tier X investment but the highest moat-expansion.

---

### TX.3 — Workout Buddy Matching (in-gym network effects)

**Status quo:** Hevy has the strongest social moat in the top-20 (friends + feed). But it's asynchronous — see what your friends did *after the fact*.

**Game-changer:** Real-time, location-aware. "Two other Standard subscribers are at LifeTime Westwood right now and want a spotter for bench press." Match consent + match → in-app chat → meet at the rack.

**Why no one else has this:**
- Hevy has friends but no presence
- Strava has presence but it's GPS-only (running/cycling) and post-hoc
- Nobody has *bench-press-spotter-needed-now* as a primitive

**Why we can ship it:**
- We already know your gym (QR scan or visual recognition)
- We already have your subscription (verified user, not random)
- Anonymous Bluetooth beacon broadcast (BLE) for in-gym presence detection without GPS

**Technical sketch:**
- New `lib/features/buddy/` module
- BLE scan + advertise via `flutter_blue_plus`
- Privacy: opt-in only, ephemeral IDs that rotate every 15 min, no persisted location data
- Matchmaking: Firestore-side function `findBuddiesNearby` filters by gymId + opted-in + active in last 30 min
- Chat: Firestore subcollection, auto-deletes 24h after match

**Defensibility:** **Network effect.** Once 10% of a gym's regulars use the app, the buddy feature becomes the reason new members install. Sticky. Hard to bootstrap individually but exponentially valuable per gym we hit critical mass at.

**Effort:** 15 days eng. Privacy review is the biggest risk — needs a careful threat model + opt-in flows.

---

### TX.4 — Auto-deload detection (overtraining prevention)

**Status quo:** Fitbod's algorithm balances muscle groups by recovery but doesn't prescribe a deload. Hevy Trainer auto-progresses weight but doesn't decelerate.

**Game-changer:** When the user's last 7 difficulty ratings are mostly 🥵 + missed sessions + dropping HRV, the app suggests a deload week (50% volume + form-only sets) **before** the user gets injured.

**Why no one else has this:** Programmatic overtraining detection requires combining 3 signals: difficulty rating (Freeletics has it but doesn't use it for deloads), wearable HRV (only Future has it well-integrated), session compliance (everyone tracks it but doesn't act on it). Combined detection is unique to anyone willing to write a small Bayesian model.

**Why we can ship it:**
- P1.1 ships difficulty rating
- P1.4 ships HRV ingestion
- We already track session compliance (`scheduledSessionsProvider`)

**Technical sketch:**
- New `lib/features/recovery/data/deload_detector.dart` (pure function)
- Rules-based v1: if (avg difficulty > 0.5 over last 7 sessions) AND (HRV trending down) AND (missed > 30% of scheduled sessions) → recommend deload
- Surface: dismissable banner on Home page + auto-substitute next 3 sessions to mobility/light variants if accepted
- Logged as `DeloadEvent` for retention analysis

**Defensibility:** This is the single feature that differentiates "the app that prevents your next injury" from "the app that adapts your weights." Marketing line: *"Other apps push you harder. We're the only one that knows when to pull you back."*

**Effort:** 5 days eng (depends on P1.1 + P1.4 shipping first).

---

### TX.5 — Coach Marketplace (B2B + content scaling)

**Status quo:** Centr has Hemsworth + a roster. BODi has its instructors. We can't out-content them by hiring 50 trainers.

**Game-changer:** Trainers create their own programs in our app, set their own price (revenue share 70/30 or 80/20), and our subscriber base finds them. We become Spotify, not Universal Music.

**Why no one else has this:** Centr/Sweat/Peloton/Apple all gatekeep their trainer rosters because that's their content moat. They literally can't open it without diluting their brand. **We have no celebrity content moat to defend, so we can be the platform.**

**Why we can ship it:**
- Stripe Connect supports the revenue-share split natively
- Cloud Functions can host trainer onboarding + program creation tools
- Existing `WorkoutLogEntry` + `ScheduledSession` models extend to "trainer-prescribed programs"

**Technical sketch:**
- New `lib/features/marketplace/` module
- New `Trainer` model: profile, certifications, programs[], earnings
- New web app `web_trainer_studio/` for trainers to create programs (likely separate React app — Flutter web can do it but the editing UX is heavier)
- Stripe Connect: `account_id` per trainer, automatic payout split
- Browse + subscribe surface in main app: "Find a coach for your goal"

**Defensibility:** **Two-sided network effect.** More trainers → more program variety → more users → more trainers earning. The bigger we get, the harder we are to dislodge. **This is the single most valuable Tier X feature long-term, and the riskiest to bet on early.**

**Effort:** 30 days eng for v1 + Stripe Connect integration is a 2-week task itself + ~$10k legal (1099 contractor agreements, payout flows). Don't ship before Tier 1 is done.

---

### TX.6 — Voice-only hands-free workout mode

**Status quo:** Every workout app makes you tap a screen mid-set. Phones go in pockets between sets. Bluetooth earbuds are universal.

**Game-changer:** Set the phone down, log entire workout by voice. *"Bench press, 80 kilos, 8 reps." → app logs it, plays a beep, starts rest timer. "Done." → moves to next exercise.*

**Why no one else has this:**
- Aaptiv is audio-first but for cardio classes (no logging)
- Strong has Apple Watch for wrist tap (still requires touch)
- Nobody offers fully voice-driven set logging

**Why we can ship it:**
- On-device speech recognition is mature (Android `SpeechRecognizer`, iOS `SFSpeechRecognizer`)
- Domain vocabulary is small (~100 exercise names + numbers)
- Custom keyword spotting (Vosk, Picovoice) is free and on-device

**Technical sketch:**
- New `lib/features/voice/voice_logger.dart`
- Custom intent grammar: `EXERCISE WEIGHT REPS` triplets
- Confirmation TTS: *"Logged 80 kilos for 8."*
- Bluetooth headphone-aware: pauses on call, ducks music

**Defensibility:** UX moat. Once a user trains hands-free for 3 sessions, going back to tap-typing feels archaic. Especially powerful for gym contexts where hands are sweaty/chalked.

**Effort:** 10 days eng for v1 + needs a 5-day discovery phase to pick the right speech library + on-device vs cloud trade-off. Privacy is a non-issue if on-device.

---

### TX.7 — Equipment Failure Reporting (B2B value-add)

**Status quo:** Gym members complain about broken equipment by hunting down a staff member or filling out a paper form. Gym chains have no real-time data on which machines are broken.

**Game-changer:** Mid-workout, scan a machine's QR, tap "Report broken" + photo + voice note. Routes to gym's maintenance team via webhook. **For free for the user. For paid for the gym chain.**

**Why no one else has this:** Equipment-aware apps (Technogym, iFIT) are tied to specific OEMs and report only their own brand. Generic gym apps (Fitbod, Hevy) don't know what equipment is at the gym. Only we do.

**Why we can ship it:**
- We already have the QR-scan flow
- Trivial Firestore write + email/Slack webhook
- Adds zero cost to the user; high value to our gym partners

**Technical sketch:**
- New `lib/features/scanner/equipment_report_page.dart`
- "Report broken equipment" CTA on `EquipmentDetailPage`
- Cloud Function: `reportEquipmentIssue` writes to Firestore + dispatches webhook
- B2B partnership track (P2.5): gym chain integration via Slack/Email/Teams webhook

**Defensibility:** **B2B leverage point.** Gym chains see real-time equipment health as a feature they pay for. Combined with the QR-scan partnership (TX-adjacent), we become operationally embedded in the gym's day-to-day. Not just a fitness app — a gym-operations tool.

**Effort:** 6 days eng + 10 days of BD/product work for the first chain partnership.

---

## Part 3 — Sequenced 12-month roadmap

| Quarter | Tier 0 / P0 | Tier 1 / P1 | Tier 2 / P2 | Tier X game-changers |
|---------|-------------|-------------|-------------|----------------------|
| **2026Q3** | Annual SKUs · Family · Wear OS · Catalog scraper · Health Connect · Rest timer · Plate calc · Offline | | | |
| **2026Q4** | (catch-up tail) | Difficulty rating · Progressive overload · Form check · HRV/recovery · Lifetime SKU | | TX.4 Auto-deload (depends on P1.1+P1.4) |
| **2027Q1** | | (P1 tail) | Team feed · Physio review · Progress photos | TX.1 Injury Recovery · TX.6 Voice-only |
| **2027Q2** | | | Celebrity-led plans (legal track) | TX.2 Visual recognition · TX.7 Equipment reporting |
| **2027Q3** | | | (P2 tail) | TX.3 Buddy Matching · TX.5 Coach Marketplace v1 |
| **2027Q4** | Phase 5 compliance (GDPR + WCAG) | | | |

**Resource implications:**
- 2 senior FE-leaning full-stack engineers (Flutter + TypeScript Cloud Functions)
- 1 ML engineer part-time from 2027Q1 (TX.2 visual recognition; TX.6 voice)
- 1 BD/partnerships lead from 2026Q4 (gym chain pilots; coach marketplace recruitment)
- ~$50–80k one-time external costs:
  - Catalog scraper content creator: $5–15k
  - Physio review: $5k
  - Visual recognition labelling: $5k
  - Celebrity trainer signing: $30–50k
  - Legal (Stripe Connect contracts, gym chain MSAs): $10k
  - Provisional patent (injury-aware QR path): $2k

---

## Part 4 — Decision points / approval gates

These are points where the roadmap should pause for an explicit user
decision before proceeding:

1. **After P0 ships (end of 2026Q3):** v1 marketing push? Beta to existing waitlist? Or keep building before any external launch? My recommendation: closed beta to ~500 users on Tier 0 alone; don't open to public until P1 (form check + recovery) lands.

2. **Before TX.5 Coach Marketplace work:** is Stripe Connect + 1099 contractor management worth a 30-day eng investment + $10k legal? Alternative: hire 5 in-house trainers (~$200k/yr) and skip marketplace entirely. Marketplace bets on volume; in-house bets on curation.

3. **Before TX.2 Visual recognition labelling:** ~3,000 labelled images at ~$2/image via Mechanical Turk = $6k. Cheaper alternative: crowd-source from beta users (slower, lower quality). Not blocked but the spend should be approved.

4. **Before TX.3 Buddy Matching:** privacy review + a clear answer to "what happens if a creep uses our matchmaker to harass another user?". The threat model is non-trivial and could nuke the whole feature if mishandled.

5. **2027Q1 quarterly review:** are we differentiating successfully or following Hevy/Fitbod into commodity territory? If our churn looks like Hevy's, we've failed at the moat strategy and need to reconsider Tier X priorities.

---

## Part 4.5 — Seven market-killer features (Tier MK)

These are the **absolute strongest** ideas — features that, if shipped
well, would make this app the category leader rather than just a
solid alternative. They're harder than Tier X (more eng, more
partnerships, more risk) but each one would meaningfully *kill* a
subset of competitors. Sequenced so the easiest two ship inside
2027Q2 and the harder three are 2027Q3+ bets.

### MK.1 — Live Form Coach with Voice (combines TX.3 + TX.6)

**What it is:** During a working set, phone in stand or paired with
Bluetooth earbuds, the app *speaks* form corrections in real-time.
*"Go deeper. Three more reps. Slow on the eccentric."* Hands-free,
eyes-forward. The form check (TX.3 / P1.3) reads pose keypoints; the
voice engine (TX.6) does set logging *and* TTS feedback.

**Why it kills:**
- **Tempo** can't compete — hardware-locked, $2,495 device, iOS-only
  on Move. We do it on a $200 Android phone.
- **Future** at $149/mo gives a human coach text feedback. Ours does
  it live, mid-rep, for $19.99/mo.
- **Fitbod / Hevy / Centr** have nothing close.
- Marketing line writes itself: *"The first AI personal trainer that
  watches your form and coaches your reps. No $2,500 device. Just
  your phone."*

**Effort:** 18 days (extends TX.3 form check + TX.6 voice with a
shared real-time loop + TTS via `flutter_tts`).

**Revenue impact:** This is the feature that justifies the $19.99
Celebrity tier without needing a celebrity. Pricing power → can push
to $24.99.

---

### MK.2 — Goal-Photo → Personalised Program (Vision-LLM)

**What it is:** User uploads a photo of their goal physique (a
fitness model, an athlete, themselves N years younger). On-device
+ cloud LLM analyses the goal vs the user's current state (height,
weight, body comp from MK.6 below) and generates a 12-week tailored
program. Updates monthly as progress photos come in.

**Why it kills:**
- **Centr / Sweat / Ladder** sell pre-baked programs. Theirs are made
  for everyone; ours is made for *one person*.
- **Fitbod** generates programs but not from goal images.
- **Future** has a human coach interpret your goals. Ours does it in
  10 seconds.
- Massive PR + viral moment — every fitness influencer will demo it
  in a TikTok ("I uploaded my 22-year-old self and the app gave me a
  comeback plan").

**Effort:** 25 days eng + ~$5–10k for goal-physique tagged training
data + ongoing Anthropic / OpenAI inference cost (~$0.05/program
generation, profitable at any tier).

**Revenue impact:** Premium-tier-defining. Lifts Standard → Celebrity
upgrade rate measurably (we'd gate this to Celebrity).

---

### MK.3 — Cycle-Aware Programming for Women (huge underserved market)

**What it is:** Reads menstrual cycle data from Health Connect / Apple
Health / Clue / Flo. Adjusts programming through the month:
follicular phase = strength + intensity push; luteal = endurance
+ steady-state; menstrual = recovery + mobility. Includes a
postnatal track (3-12 months postpartum progression).

**Why it kills:**
- **Sweat** owns the female-fitness brand and has a postnatal track
  but **does not adjust within the month**. They re-skin the same
  programs.
- **Fitbod / Hevy / Centr** ignore cycle entirely.
- **Apple Fitness+ / NTC** have no awareness.
- Real performance benefit (peer-reviewed: women's strength capacity
  varies 5-15% across the cycle).
- 50% of the addressable market is currently treated as "men minus
  some weight."

**Effort:** 12 days eng + ~$3k consultant fee (sports physiologist
specialising in women's training). Cycle integration via Health
Connect is well-documented.

**Revenue impact:** Opens the ~$2B women's-fitness segment without
us being a women's-only brand. Could double TAM if marketed correctly.

---

### MK.4 — Insurance Premium Discount Partnerships

**What it is:** Partner with health insurers (Aetna, Cigna, Vitality,
Anthem). Users who maintain a workout-streak get measurable health-
insurance premium discounts. App displays *"Maintaining 12-week
streak — saving $34/mo on Cigna."*

**Why it kills:**
- No fitness app currently routes the user's value back into real
  $$ savings on a non-fitness bill. Garmin Connect / Apple Watch
  feed insurer programs *but the user has to manually opt in via the
  insurer.* We bridge it.
- Real value-add. Customer LTV soars because cancelling = losing
  insurance discount.
- Network effect with insurers: once one signs, others follow.

**Effort:** 8 days eng (API integrations, attestation flows) + 6–18
months of BD work (insurance partnerships move slowly). Heavy legal
review (HIPAA, state-by-state insurance regs).

**Revenue impact:** Indirect — drives retention 2-3× through insurance
discount lock-in. Plus possible direct revenue share with insurers
(per-user-per-month fee for verified active subscribers).

---

### MK.5 — White-Label Gym Chain SDK (B2B distribution play)

**What it is:** Open Flutter SDK + REST API. Any gym chain or fitness
brand can embed our QR-scan + injury filter + workout log + form check
into their *own* member app, with their own branding. We charge
per-subscriber per-month ($1–3/MAU). They keep their UX; we power the
features.

**Why it kills:**
- **Technogym Mywellness** is closed-source — only their hardware.
- **iFIT** is hardware-locked.
- **Centr / BODi** are content businesses, not platforms.
- **No fitness platform in 2026 sells the underlying tech.**
- Distribution multiplier: every gym member of every chain we sign
  becomes a user. One chain = 50k–500k users overnight.
- Coach Marketplace (TX.5) becomes more powerful when all the
  white-labelled gyms feed into it.

**Effort:** 60 days eng (it's a whole SDK + admin console + analytics
+ docs site) + ongoing maintenance + dedicated devrel headcount.
Massive but transformational.

**Revenue impact:** Long-term, **larger than the consumer subscription
business.** SaaS-style ARR per chain, retention >95%, unit economics
better than B2C.

---

### MK.6 — Continuous Body Composition via Phone Camera

**What it is:** Front-camera selfie photos with on-device ML estimate
body fat %, lean mass distribution, posture. Tracks every 2 weeks
automatically. Replaces $200 InBody scales and $300 DEXA scans with
something free, private, on-device.

**Why it kills:**
- **Made Health** and similar standalone apps do this but aren't
  integrated into a workout flow. Switching cost = user has to
  manually transcribe results.
- **Centr** has a "before-and-after" gallery feature. Ours has actual
  measurements feeding into the program.
- Privacy moat: on-device, no photos leave the phone. Big
  differentiator vs cloud-based alternatives.
- Combined with MK.2 goal-photo + cycle-aware programming = a
  closed personalisation loop unlike anything else on the market.

**Effort:** 20 days eng + ~$10–15k for training data (volunteers with
DEXA + photo pairs at multiple body fat %s) + ML eng help.

**Revenue impact:** Premium-tier feature. Drives Standard → Celebrity
upgrade because seeing your body comp trend monthly is sticky.

---

### MK.7 — Recovery as a First-Class Workout (24h cycle product)

**What it is:** Reframe what "the app is for" entirely. Most apps
optimise *training*; we optimise the entire 24-hour cycle —
sleep, nutrition, mobility, contrast therapy, breath-work, meditation.
Each of these is a scheduled "workout" with completion tracking,
streak counting, and progression. *Recovery isn't a rest day; it's a
practice.*

**Why it kills:**
- **WHOOP** measures recovery but doesn't prescribe practices.
- **Centr** has meditation but not as part of program scheduling.
- **Fitbod / Hevy / Strong** literally do nothing for recovery.
- **Apple Fitness+** has cooldowns and meditation but they're
  separate libraries.
- Broadens the addressable use case from "active gym-goers" to "anyone
  who cares about wellbeing." 5-10× larger market.
- Shifts the brand from "workout app" → "performance OS."

**Effort:** 25 days eng (new feature surface, content authoring tools,
calendar integration) + ~$10k content creation (mobility flows,
breath-work guides, scripted meditations).

**Revenue impact:** Brand-defining. Repositions us from "Fitbod
competitor" to a different category entirely. Marketing line: *"The
first fitness app that treats sleep as a workout."*

---

### MK feature priority for first execution

Not all 7 ship at once. Recommended order based on effort vs revenue
impact:

| Order | MK | Effort | Impact | Notes |
|-------|----|--------|--------|-------|
| 1 | **MK.3 Cycle-aware programming** | 12d + $3k | Doubles TAM | Easiest big win; ship 2027Q2 |
| 2 | **MK.1 Live Form Coach with Voice** | 18d | Pricing power for Celebrity | Builds on TX.3 + TX.6; ship 2027Q3 |
| 3 | **MK.7 Recovery as workout** | 25d + $10k | Brand reposition | Ship 2027Q3-Q4 |
| 4 | **MK.2 Goal-Photo → Program** | 25d + $5–10k | PR moment | Cloud LLM cost manageable; ship 2028Q1 |
| 5 | **MK.6 Body comp via camera** | 20d + $10–15k | Premium upgrade driver | Needs good training data; ship 2028Q1 |
| 6 | **MK.4 Insurance partnerships** | 8d eng + 6-18mo BD | LTV multiplier | Start BD work 2027Q1, eng follows partner |
| 7 | **MK.5 Gym Chain SDK** | 60d + devrel headcount | Larger than B2C long-term | Needs dedicated team; 2028H2 |

---

## Part 5 — Cross-references

- Existing roadmap of completed phases: [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)
- Competitive landscape this plan responds to: [`../business/COMPETITIVE_ASSESSMENT.md`](../business/COMPETITIVE_ASSESSMENT.md)
- Phase 4B Stripe operational runbook: [`PHASE_4B_STRIPE_SETUP.md`](PHASE_4B_STRIPE_SETUP.md)
- Debugging discipline: [`DEBUGGING.md`](DEBUGGING.md)
- Master 75-feature task list (long-tail product features): [`../FITNESS_APP_TASK_LIST.md`](../FITNESS_APP_TASK_LIST.md)
