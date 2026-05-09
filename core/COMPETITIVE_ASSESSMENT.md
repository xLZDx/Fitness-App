# Competitive Assessment — Fitness App

**As of 2026-05-09.** Snapshot of how this app stacks up against the
15 most-shipped consumer fitness apps in 2026, what we already do
better, what we're missing at table stakes, and a prioritised feature
backlog. Source data: 40+ vendor pages, App Store listings, and
2026-dated reviews captured by a research pass on the same day. See
`core/COMPETITIVE_ASSESSMENT_RAW.md` if you want the per-vendor
breakdown.

## Executive summary

Three things to take away.

1. **The QR-scan equipment hook is genuinely defensible.** Zero major
   incumbents do it. Fitbod and Jefit are equipment-aware via manual
   toggles; only Tecnogym/PlanetFitness use QR for static instructional
   videos, none tied to a personal injury profile. This is the wedge
   — defend it with a patent filing and one mid-tier gym chain
   exclusive.

2. **Our 34-question onboarding + injury-aware filtering is materially
   deeper than every competitor.** Fitbod requires manual exclusions
   *per session*; Centr is fully static; everyone else relies on a
   human or doesn't ask. This is a real product moat — but only if
   marketing surfaces it ("we don't show exercises that conflict with
   your injuries — others make you skip them manually").

3. **We're 9 features short of $10/month table stakes.** The big one
   is **Wear OS companion** (Standard tier sub-$10/mo without a watch
   app fails the Hevy/Strong/Fitbod sniff test on day 1). Then
   exercise videos for every move (we ship 12 hand-seeded), Health
   Connect / Apple Health sync, rest timer, plate calculator, offline
   downloads, progress photos, programmatic progressive overload,
   wearable HRV/sleep ingestion. None are individually hard; the
   collection adds up.

## Market landscape — four lanes

| Lane | Players | Price band | Battle |
| ---- | ------- | ---------- | ------ |
| Ultra-cheap loggers | Hevy, Strong | $3–5/mo | Brutal commodity floor |
| AI program generators | Fitbod, Jefit, Hevy Trainer (new) | $10–16/mo | Where Standard tier lives |
| Celebrity / studio content | Centr, NTC, Apple Fitness+, Peloton, BODi, Ladder, Les Mills | $10–30/mo | Where Celebrity tier lives |
| 1:1 human coaching | Future, Caliber | $149–300+/mo | Different segment, not direct |

Total 2026 market sized at ~$9.22B and growing ~15% YoY. The two lanes
we straddle (AI generators + celebrity content) are the most
competitive but also the highest-growth.

## Where we win

### 1. QR-scan equipment recognition (unique)

No one else does it. Fitbod's "multi-profile" toggle is the closest
analogue — user-configured, not scanned. The user's mental cost of
"which gym am I at right now" remains; we eliminate it. Especially
strong in commercial gym partnerships.

**Defend with:**
- Provisional patent on the QR-tag → equipment-id → personalised
  exercise filter pipeline.
- One mid-tier gym chain exclusive (Anytime Fitness, Crunch, EOS,
  regional chains in Europe). Free QR stickers + branded co-marketing.

### 2. Injury-aware filtering (unique at the recommendation layer)

`exercise_filter.dart` removes exercises whose contraindication tags
overlap the user's reported injuries *before* they're shown. Fitbod
makes the user skip-and-swap manually each session. Centr ignores
injuries entirely. Caliber/Future rely on a human asking. **None
auto-filter from a structured intake at runtime.**

The 34-question intake is what makes this work — most competitors ask
3–5 questions (goal, level, equipment, body stats). Going from 5 to
34 questions is the kind of thing they can't easily copy because it
hurts their conversion rate; we already paid that onboarding price
and shipped it.

### 3. Android-first premium

Apple Fitness+ requires an Apple Watch. Future is iOS-only at
$149/mo. Centr/Peloton/NTC are cross-platform but iOS-leaning. **The
Android premium-fitness market is genuinely under-served.** Focus
remains correct.

### 4. Pricing structure

| Plan | Our price | Closest comp | Verdict |
| ---- | --------- | ------------ | ------- |
| Free | $0 | NTC ($0), FitOn ($0), Hevy free tier | Competitive — the body-weight library is real value |
| Standard | $9.99/mo | Apple Fitness+ ($9.99 + family of 6), Sworkit ($9.99) | Tight but defensible if Wear OS + injury-filter clear |
| Celebrity | $19.99/mo | Les Mills ($19.99), Centr ($29.99), Peloton App+ ($28.99), Future ($149) | **Strong** — undercuts Centr by 33%; matches Les Mills exactly |
| Trial | 14 days | Fitbod 7d, Centr 7d, Aaptiv 7d, Sworkit 7d | **Best-in-class** outside Apple's hardware bundle |

The 14-day trial is the longest credible trial in category. Lead
with it.

### 5. Architecture quality

This is a stealth advantage that won't show in marketing but will
show in shipping speed:
- Mock-first repository pattern means we can rebuild any data source
  (auth, profile, logs, sessions, subscription) in a few hours.
- Webhook-driven Stripe state means the subscription doc is server-
  controlled, which matters the moment we ship App Store In-App
  Purchase (Apple/Google forbid client writes).
- Test suite at 207/207 green lets us refactor confidently.
- Debug daemon + DEBUGGING.md means incident → root cause → fix in
  hours, not days. Nobody else has this.

## Where we lose (table-stakes gaps)

Items every $10+/mo competitor has that we currently don't:

| Gap | Priority | Notes |
| --- | -------- | ----- |
| **Wear OS companion** | P0 | Strong/Hevy/Fitbod/Apple Fitness+/NTC/Peloton/Centr all have watch set-logging or class controls. Phone-out-of-pocket-between-sets is real friction; Android-first means Wear OS first. |
| **Exercise video for every movement** | P0 | We ship 12 hand-seeded exercises with one or two `videoUrl`s. Hevy 200+, Fitbod 1,000+, Jefit 1,400+. Curated lists without video lose trust. Phase 2E (catalog scraper) was already queued. |
| **Health Connect / Apple Health sync** | P1 | Write completed workouts back to system rings; read steps + HR. Every $10+/mo app has this. |
| **Rest timer with auto-trigger on set logged** | P1 | Strong, Hevy, Fitbod. Trivial to ship; unforgivable to ship without. |
| **Plate calculator + warm-up calculator** | P1 | Strong, Hevy, Fitbod. Days of work. |
| **Offline workout download** | P1 | FitOn, Centr, Peloton. Gym wifi is hostile. Our `WorkoutPlayerPage` streams `videoUrl` over network today. |
| **Progress photos** | P2 | Strong, Hevy, Centr. Camera + Firestore Storage; feature itself is one screen. |
| **Programmatic progressive overload** | P2 | Fitbod and Hevy Trainer auto-suggest next-session weight from prior log. We only display history. |
| **Wearable HRV/sleep ingestion → recovery score** | P2 | Aspirational; only Future and SensAI deliver. *Reviewers now penalise apps that don't* — Centr, Fitbod, Hevy all eat that complaint in 2026 reviews. There's white space at $10–20/mo. |
| **Family plan** | P3 | Apple Fitness+ family-of-6 included. None of our 3 tiers offers it; potential up-sell on Standard ("share with 1 partner for +$3"). |
| **Social feed** | P3 | Hevy's strongest moat. Phase 6 territory. |
| **AI coach / form check** | P3 | Phase 6+ in roadmap. **12–18 month moat opportunity** if shipped before incumbents — Form Fix, Gymscore, FormCheck AI exist as standalones but none of the major loggers/program-generators have integrated form-check yet. |

## Top 3 threats

### 1. Fitbod — closest equipment-aware analogue

- **Pricing:** $15.99/mo or $95.99/yr (~$8/mo). 7-day trial.
- **Threat vector:** Multi-profile equipment toggle solves the "what
  gym am I at" problem cheaply; ML program generation is years of
  training-data lead. Algorithm balances muscle groups by recovery.
- **Their gap (our wedge):** No injury filtering at recommendation
  layer (manual per-session skip). No QR scan. No celebrity content.
  No HRV ingestion despite advertising "AI".
- **Their advantage we have to live with:** 1,000+ exercises with
  video; 7+ years of usage data feeding the algorithm.
- **Counter:** Lead marketing with "Fitbod makes you skip exercises
  manually — we don't show them." That single sentence is the
  positioning.

### 2. Centr — celebrity-tier price benchmark

- **Pricing:** $29.99/mo or $149.99/yr (~$12.50/mo). 7-day trial.
- **Threat vector:** Marquee celebrity (Hemsworth) + 1,400 workouts +
  nutrition + meditation. Defines what "celebrity-trainer app" means
  in 2026.
- **Their gap (our wedge):** Static programs — "doesn't adapt to how
  you slept" is the #1 reviewer complaint. No HRV. No injury filter.
  $30/mo monthly is genuinely expensive.
- **Their advantage we have to live with:** 50:1 content depth on
  day one. We can't out-content them.
- **Counter:** Don't try to. Compete on personalisation depth, not
  catalog size. Our $19.99 monthly undercuts by 33%; the annual
  comparison is what matters — *price the annual at $149.99 to mirror
  Centr exactly* (currently we don't have annual, see "Pricing actions"
  below).

### 3. Hevy + Hevy Trainer — price floor

- **Pricing:** $2.99/mo, $23.99/yr, or $74.99 lifetime. **Cheapest
  paid app in category.** Hevy Trainer (Feb 2026) just added AI
  workout generation bundled with Pro.
- **Threat vector:** Anyone shopping for "cheap workout tracker"
  defaults here. Their social feed is the strongest in category.
  Their AI just shipped.
- **Their gap (our wedge):** No equipment scan. No injury intake. No
  HRV (despite heavy user demand on Reddit). No celebrity content. No
  Apple Watch / Garmin / WHOOP / Oura integration as of May 2026.
- **Their advantage we have to live with:** $2.99/mo is the price
  floor. Our $9.99 Standard needs to obviously justify a 3.3× premium
  in <5 seconds on the subscription page.
- **Counter:** First-screen onboarding must hit "AI-personalised +
  injury-safe + QR-scan equipment" before the user closes the modal.
  Standard tier value props need to be obvious and visual.

## Suggested new features (prioritised backlog)

Re-ordered against what the market shows is missing or expected.
Numbers in brackets reference roadmap phases in `IMPLEMENTATION_PLAN.md`.

### Tier 0 — required to ship a credible v1

These are table-stakes; every $10+/mo competitor has them. Without
them, our Standard tier feels half-baked next to Fitbod or Hevy on
day one of trial.

- **0.1 Wear OS companion** — set logging, rest timer, workout start
  / pause / complete from the wrist. Phase 6.0. Days, not weeks.
- **0.2 Exercise video for every movement** — Phase 2E catalog
  scraper, already queued. Need ~200 exercises with video before
  feels like a real catalog.
- **0.3 Rest timer with auto-trigger on log** — Phase 3 follow-up.
  Single screen.
- **0.4 Plate + warm-up calculator** — single utility widget on
  `WorkoutPlayerPage`.
- **0.5 Health Connect (Android) + Apple Health (iOS) sync** — write
  completed workouts to system rings; read step count for "for you"
  ranking.
- **0.6 Offline workout download** — cache `videoUrl` locally for the
  next 7 days of scheduled sessions.

### Tier 1 — make the differentiation real

Builds on the QR + injury-filter wedge so the marketing isn't empty
talk.

- **1.1 Equipment QR partnerships** — branded sticker pack that gym
  owners can request (web form). One mid-tier chain exclusive
  (Anytime Fitness / Crunch / EOS / European chains).
- **1.2 Injury-filter visibility on the page** — small banner on
  `EquipmentDetailPage` "Filtered out N exercises that conflict with
  your injuries" already exists; surface the same line on `Train` tab
  + on `Subscription` page upgrade copy.
- **1.3 Recovery score from wearable HRV/sleep** — HealthConnect or
  Garmin Connect API → daily score → adjusts "for you" ordering on
  Train tab. Centr/Hevy reviewers explicitly want this. White space
  at $10–20/mo.
- **1.4 Programmatic progressive overload** — given the user's last
  N logs of an exercise, suggest the next-session weight. Pure
  function on `workout_log_repository.dart` history. Hevy/Fitbod do
  this; we don't yet.

### Tier 2 — moat features (12–18 month lead potential)

Things that nobody big has shipped well yet. If we ship in 2026 we
own the marketing claim.

- **2.1 AI form-risk detection from phone camera** — Phase 6 in
  roadmap (master tasks 20, 38). On-device ML (MediaPipe Pose +
  custom rules) for the most-injured movements (squat, deadlift,
  bench, overhead press). **No major logger / program generator has
  shipped this.** Form Fix and Gymscore exist as standalones; bundle
  into the Celebrity tier and we leapfrog.
- **2.2 AI workout generator** — Phase 6 (master task 40). Compete
  with Fitbod by reading our 34-question intake + injury filter +
  recovery score. Our personalisation depth here is the differentiator.
- **2.3 Celebrity-led video plans** — Phase 6 (master task 12). The
  legal framework is the gate, not engineering. One signed celebrity
  trainer + 50 hand-curated workouts is enough for v1 of the
  Celebrity tier; we need to start the contracting work now if we
  want it for launch.

### Tier 3 — growth + retention

Quality-of-life and social. Drive monthly retention but don't change
the trial-to-paid conversion much.

- **3.1 Family plan on Standard** — +$3/mo for 1 extra account; +$6
  for 4. Mirrors Apple Fitness+ family-of-6.
- **3.2 Annual pricing** — $79.99/yr Standard (~$6.66/mo, 33% off);
  $149.99/yr Celebrity (mirrors Centr's annual exactly, undercuts on
  monthly). **This is a top-3 pricing improvement** — see actions
  below.
- **3.3 Social feed** — Hevy's strongest moat. Phase 6+. Friends list
  → recent activity → compare records. Build last because
  monetisation comes from content, not social.
- **3.4 Progress photos + body composition trend** — Strong/Hevy/Centr
  all have. Camera widget + secure Storage.

### Tier 4 — defensive

Things to ship pre-emptively before reviewers start punishing us.

- **4.1 Auto-cancellation transparency** — at trial end, send push +
  email reminder 48h before billing. Truth-in-Advertising flagged
  FitOn for dark patterns; MyFitnessPal eats this complaint daily.
  Cheap to ship, expensive to skip.
- **4.2 Account deletion + data export** — Phase 5 in roadmap (GDPR).
  Required pre-launch in EU.

## Pricing actions (top 3 changes)

These would land in <2 days of work on `subscription_models.dart` +
`subscription_page.dart`:

1. **Add annual pricing.** $79.99 Standard / $149.99 Celebrity.
   Annual is what users compare to Centr's annual; we currently force
   them to compare monthly to monthly which makes the gap look
   smaller than it is. Stripe price ids only — no Cloud Function
   change.
2. **Standard family plan tier.** $12.99/mo for 2 accounts; $14.99/mo
   for 4. Apple Fitness+ family-of-6 at $9.99 is the anchor users
   compare. Adding family is differentiation against Hevy ($2.99 has
   no family path).
3. **Lifetime price option (Celebrity tier).** Hevy has $74.99
   lifetime; Celebrity at $499 lifetime would price-anchor very
   nicely against $19.99/mo (= 25 months breakeven). Sticky early
   adopters; doesn't dilute monthly revenue much.

## Strategic recommendations (terse)

1. **Defend the QR-scan moat hard.** Provisional patent (~$2k legal).
   Pursue one mid-tier gym chain exclusive in 2026Q3.
2. **Ship Tier 0 features before any v1 marketing push.** Wear OS +
   exercise videos + rest timer + plate calculator + Health Connect +
   offline download. Without these, day-1-of-trial users churn back to
   Hevy/Fitbod.
3. **Make injury-filtering and onboarding depth the marketing
   leads.** Both are real, both are unique, both come for free
   because we already shipped them.
4. **Add annual pricing now.** Two days of work, lifts the
   trial-to-paid conversion meaningfully (annual is ~30% of paid
   conversions in this category per the Cora Health benchmarks).
5. **AI form-risk detection is a 12–18 month moat opportunity.** Ship
   it on Celebrity tier in 2026Q4 — earlier if Phase 5 compliance work
   doesn't blow up the timeline.
6. **Stop trying to out-content Centr/BODi.** They have decades of
   taped studio footage. We compete on personalisation depth, not
   catalog size. The exercise-catalog scraper (Phase 2E) only needs
   to grow us to ~200 movements — past that diminishing returns.

## Sources

Per-vendor URLs in `core/COMPETITIVE_ASSESSMENT_RAW.md` (40+ links).
Highlights:

- [Fitbod pricing 2026](https://fitbodapp.com/subscription/) — $15.99/mo, $95.99/yr
- [Hevy pricing](https://hevy.com/pricing) — $2.99/mo, $23.99/yr, $74.99 lifetime
- [Hevy Trainer launch (Feb 2026)](https://www.hevyapp.com/features/) — AI program generation now in Pro
- [Centr review (TechRadar, 2026)](https://www.techradar.com/health-fitness/fitness-apps/centr-review) — $29.99/mo, "doesn't adapt to recovery" reviewer complaint
- [Apple Fitness+ family sharing](https://www.apple.com/apple-fitness-plus/) — 6 users included at $9.99/mo
- [Peloton App tiers](https://www.pelobuddy.com/app-tiers-launch/) — Oct 2025 price hike, free tier eliminated
- [Future App](https://apps.apple.com/us/app/future-pro-personal-training/id1288178982) — $149/mo, iOS-only
- [Caliber](https://barbend.com/caliber-fitness-app-review/) — $200–300/mo human coaching
- [Best AI fitness apps 2026 (Gymscore)](https://www.gymscore.ai/best-ai-fitness-apps-2026/)
- [QR codes for gyms (Uniqode)](https://www.uniqode.com/blog/trending-use-cases/qr-codes-for-gyms) — confirms no major incumbent uses QR for personalised recommendations
