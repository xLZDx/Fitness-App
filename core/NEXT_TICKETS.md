# Next implementation tickets

**As of 2026-05-10.** What's left of the v2 roadmap (`ROADMAP_2026_V2.md`)
that I couldn't ship in the catch-up sprint, with concrete enough
detail that any future session can pick up the highest-leverage one
and start work.

Sequenced by leverage / blockers, not roadmap tier. Mark items
done by editing this file.

---

## Ready to ship right now (eng-only)

### 1. Wire `progression.suggestNextWeight` into `WorkoutPlayerPage`

**Estimate:** 2 days.

**What:** The pure helper exists (`lib/features/workouts/data/progression.dart`)
+ tests. Need to surface it in the player page above the rep input
field as a "Suggested: 80kg" caption with a tap-to-fill action. Should
read from `workoutLogsProvider.future` filtered by `exerciseId`.

**Files:** `mobile/lib/features/equipment/workout_player_page.dart`
+ a small new `_SuggestedWeightChip` widget.

### 2. Wire `detectDeload` into Home page banner

**Estimate:** 2 days.

**What:** Pure helper exists; surface verdict on `home_page.dart` as a
dismissable banner above the Today card. Gate to Standard+ tier via
`featureAccessProvider`. Tap "Accept deload" → call a yet-to-write
`scheduledSessionRepository.deloadNext7Days()` that reduces the next
week's volume to 50%.

**Files:** `mobile/lib/features/home/home_page.dart`,
`mobile/lib/features/recovery/state/recovery_providers.dart` (new),
`mobile/lib/features/workouts/data/mock_scheduled_session_repository.dart`
extension.

### 3. P0.5 Health Connect / Apple Health sync

**Estimate:** 4 days.

**What:** Read step count, HR, sleep score, daily activity ring; write
completed workouts. Package: `health: ^11.0.0` (works on both Android
+ iOS). Wire reads into `HealthService` abstraction (mock + real),
hook writes into `logWorkoutAction.log()` so completed workouts also
land in system rings.

**Files:** new `mobile/lib/core/health/` directory with the abstraction,
+ `AndroidManifest.xml` permissions, + a small `HealthSyncCard` on
`home_page.dart` Today section showing today's steps + ring %.

### 4. P0.8 Offline workout download

**Estimate:** 4 days.

**What:** Cache `videoUrl` for the next 7 days of scheduled sessions.
Background download with `dio` + `path_provider` to filesystem cache.
Premium-tier feature gated via `featureAccessProvider`.

**Files:** new `mobile/lib/features/workouts/data/offline_video_cache.dart`,
`WorkoutPlayerPage` checks cache before falling back to network.

### 5. P0.6+ Surface plate calculator + warm-up calculator on `EquipmentDetailPage`

**Estimate:** 0.5 days.

**What:** They're already on `WorkoutPlayerPage` via the `_ToolsRow`
chips. Add the same sheet to the equipment detail page so users can
hit the calculators before starting a workout. Trivial — copy
`_ToolsRow`, link to existing widgets.

---

## Stripe-dashboard blocked (needs user action then ~1d eng each)

### 6. P0.1 Annual subscription SKUs

**You do** (Stripe dashboard, 5 min):
1. Add monthly recurring price + annual recurring price to Standard
   product. Recommended: $9.99/mo + $59.99/yr (= $5/mo effective).
2. Add monthly recurring + annual recurring + one-time lifetime price
   to Celebrity product. Recommended: $19.99/mo + $119.99/yr + $499
   lifetime.
3. Send the four new price IDs back so I can drop them into Functions
   Secret Manager.

**I do** (1.5 days):
- Add `SubscriptionPeriod` enum (`monthly`/`annual`/`lifetime`) to the
  model + Firestore mapping.
- Update `createCheckoutSession` Cloud Function to accept a `period`
  arg and look up the right price ID from secrets.
- Update `SubscriptionPage` with monthly/annual/lifetime toggle.
- Update tests + redeploy functions.

### 7. P0.2 Family plan tier

**You do:** Add a "Family" recurring price ($14.99/mo for 2 seats;
$19.99/mo for 4 seats). One product, two prices.

**I do** (5 days):
- Add `seats: int` + `seatedUids: List<String>` fields on
  `Subscription`.
- New Cloud Function `linkFamilyMember` (callable) handles the invite
  flow: owner sends email → invitee signs in → claims a seat.
- New `lib/features/family/family_invite_page.dart` for the deep-link
  claim flow.
- `SubscriptionPage` shows seat occupancy on the Manage card.

### 8. P1.5 Lifetime $499 SKU on Celebrity

**You do:** Already covered by ticket #6's "lifetime price" step.

**I do** (2 days):
- Cloud Function handles `checkout.session.completed` for one-time
  payments; marks subscription active with `currentPeriodEndsAt =
  year 9999`.
- `SubscriptionPage` adds "Lifetime" tab next to Annual.

---

## Big eng (multi-week, schedule explicitly)

### 9. P0.3 Wear OS companion

**Estimate:** 12 days (first-time Wear OS dev — budget +30%).

**What:** New Flutter target under `mobile_wear/`. Display: current
exercise + "Done set" button + rest timer (reuse `RestTimerController`
from `lib/features/workouts/widgets/rest_timer.dart`). Communicates
with phone via `flutter_wear` or `wear` package.

**Risks:** Custom Wear OS Flutter is its own learning curve. If this
takes >15 days, consider Kotlin native module + platform channel
instead. Apple Watch parity is Phase 7 — not a P0 for Android-first
launch.

### 10. P0.4 Catalog scraper (Phase 2E)

**Estimate:** 10 days eng + ~$5–15k content cost.

**What:** Grow `assets/data/exercises.json` from 12 hand-seeded to
~200 movements with `videoUrl` populated for each.

**You do:**
- Decide on content path:
  - **Stock video:** $500–2000 for 200 short clips (Pond5, BBlearn) —
    quick but visually generic.
  - **Contract a fitness creator:** ~$5–15k for 200 hand-recorded
    demos in a 3-day shoot. Way better quality.
- I lean strongly toward contract. Find a CrossFit gym owner or
  fitness influencer with their own studio space.

**I do:**
- Build the ingest pipeline + tagging tool.
- Update `AssetEquipmentRepository` to handle the larger catalog
  efficiently.
- Move videos to Firebase Storage (current 12 use external CDN URLs).

### 11. P1.3 MediaPipe form check on Android

**Estimate:** 14 days.

**What:** On-device pose detection via `google_mlkit_pose_detection`
(Flutter wrapper for MediaPipe BlazePose). Six rule-based form
classifiers for the highest-injury-risk movements: squat depth,
deadlift back angle, push-up scapular stability, overhead press
lockout, lunge knee tracking, plank alignment.

**Files:** new `mobile/lib/features/form_check/` directory.

**Marketing:** *"Form feedback on commodity Android — no $2,500
hardware required."* Direct shot at Tempo (which is depth-camera-only,
iOS-only on Move).

### 12. P2.1 Team feed for Celebrity tier

**Estimate:** 8 days.

**What:** Each signed celebrity gets a Firestore-backed feed where
they post workouts, motivation notes, technique tips. Subscribers
can comment + react. Closest analogue: Ladder's team feeds.

**Files:** new `mobile/lib/features/community/`, new Firestore
subcollections, new rules for trainer-write/subscriber-read.

### 13. P2.3 Progress photos

**Estimate:** 6 days.

**What:** Camera capture + Firebase Storage with end-to-end
encryption (user-controlled key). Side-by-side comparison view with
date sliders. v1 is just photos; AI body-comp estimate (MK.6) is
later.

---

## External-resource blocked

### 14. P2.2 Physio-reviewed catalog

**You do:** Hire one DPT (~$5k for one-time review of 200 exercises +
contraindication tag mappings). ATPT.org has a directory; local
hospital networks also work.

**I do** (1 day):
- Add `reviewedBy` field per exercise.
- Update landing page (when one exists) with "Reviewed by Dr. [X],
  DPT" credit.
- Document the engagement at `core/PHYSIO_REVIEW.md`.

**Marketing:** *"Other apps tell you to consult your doctor. We built
our exercise library with one."* This is Freeletics' explicit
disclaimer flipped.

### 15. P2.4 Celebrity-led video plans

**You do:** ~$30–80k contract negotiation with a mid-tier celebrity
trainer (find via talent agencies or fitness influencer networks +
4–8 weeks of legal work).

**I do** (0 eng — this is content + legal).

---

## Tier X game-changers (post-v1 launch)

Already covered in `ROADMAP_2026_V2.md` Tier X + Tier MK sections.
Five remain (TX.4 + TX.7 are now shipped):

- **TX.1 AI Injury Recovery Coach** — 12d + $5–10k. Strongest
  user-lock-in feature in the plan.
- **TX.2 Photo-based equipment recognition** — 25d + $5k labelling.
  Solves cold-start at non-partnered gyms.
- **TX.3 Workout Buddy Matching** — 15d. BLE in-gym presence.
- **TX.5 Coach Marketplace** — 30d + $10k legal. Largest long-term
  bet; needs Stripe Connect setup first.
- **TX.6 Voice-only hands-free workout mode** — 10d + 5d discovery.

## Tier MK market-killers (2027+)

Seven from `ROADMAP_2026_V2.md`:

- **MK.1 Live Form Coach with Voice** (combines TX.3 + TX.6) — 18d.
  *The* killer Celebrity-tier feature.
- **MK.2 Goal-Photo → Personalised Program** (Vision-LLM) — 25d +
  $5–10k. PR moment.
- **MK.3 Cycle-Aware Programming for Women** — 12d + $3k consultant.
  Doubles TAM. Easiest big win; ship first.
- **MK.4 Insurance Premium Discount Partnerships** — 8d eng + 6–18mo
  BD.
- **MK.5 White-Label Gym Chain SDK** — 60d + dedicated devrel
  headcount.
- **MK.6 Continuous Body Comp via Phone Camera** — 20d + $10–15k.
- **MK.7 Recovery as a First-Class Workout** — 25d + $10k content.
  Reframes the brand entirely.

---

## What's already shipped

(Cross-reference for context — see `IMPLEMENTATION_PLAN.md` for the
historical Phase 0–4B record.)

- **Wave 1 (commit `bd9aa34`-prev):** Rest timer + plate calculator +
  warm-up calculator. ✓ P0.6 + P0.7.
- **Wave 2 (commit `bd9aa34`):** Post-workout difficulty rating sheet
  + `WorkoutLogEntry.{weightKg, repsCompleted, difficulty}` +
  `progression.suggestNextWeight()` pure helper. ✓ P1.1 + P1.2 (data
  + logic; UI surfacing remains in ticket #1 above).
- **Wave 3 (commit current):** `detectDeload()` pure helper + full
  Equipment Failure Reporting (model + service + sheet + Cloud
  Function + rules). ✓ TX.4 + TX.7 (UI surfacing for TX.4 in ticket
  #2).
