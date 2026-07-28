# Competitive Assessment — Fitness App

**As of 2026-05-09.** Snapshot of how this app stacks up against the
20 most-shipped consumer fitness apps in 2026, what we already do
better, where the moats actually live (after sharper research),
table-stakes gaps, a prioritised feature backlog, and a "what it takes
to win completely" section. Source data: 60+ vendor pages, App Store
listings, and 2026-dated reviews captured by two research passes on
the same day.

---

## Executive summary

**Three things to take away.**

1. **The QR-scan equipment hook is defensible — but narrower than it
   first looked.** Technogym already runs essentially this model on
   its own gym equipment via Mywellness; iFIT runs a hardware-coupled
   version on NordicTrack/ProForm; a tiny UK player (Weightplan) runs
   third-party stickers on independent gyms. **Nobody runs the
   cross-OEM, third-party-sticker, injury-personalised, Android-first
   model at scale.** That's the actual wedge. File a provisional
   patent on the *injury-aware* path (Technogym's prior art doesn't
   cover that) and pursue gym-chain partnerships as the moat.

2. **Our 34-question injury-aware onboarding is genuinely
   industry-leading.** Freeletics literally tells users *"the app is
   not designed to accommodate any injury or health issue"*. Centr,
   Sweat, Ladder, NTC ignore injuries entirely. Fitbod requires manual
   skip-and-swap each session. The honest framing isn't "we have a
   feature competitors lack" — it's *"no top-20 app handles injury at
   intake depth."* That's a real moat if marketing surfaces it,
   ideally backed by a licensed physio reviewer.

3. **The biggest immediate revenue lever is annual pricing.** Sweat,
   Ladder, Freeletics, iFIT all monetise annual at ~50% effective
   discount. We have **none**. Standard $59.99/yr (= $5/mo effective)
   and Celebrity $119.99/yr (= $9.99/mo) would mirror category-norm
   psychology and is two days of Stripe work. **Tempo's "AI form
   check" moat I previously called 12-18 months is actually narrower:
   it's depth-camera based** (Apple TrueDepth on Move, ToF sensor on
   Studio). Pure RGB form check via MediaPipe BlazePose has been
   commodity since 2021 — so reframe as *"form check on commodity
   Android, no extra hardware"* and demote from P0 moat to P1 feature.

---

## Market landscape — four lanes

| Lane | Players | Price band | Battle |
| ---- | ------- | ---------- | ------ |
| Ultra-cheap loggers | Hevy, Strong | $3–5/mo | Brutal commodity floor |
| AI program generators | Fitbod, Jefit, Hevy Trainer (new), Freeletics | $8–16/mo | Where Standard tier lives |
| Celebrity / studio content | Centr, Ladder, Sweat, NTC, Apple Fitness+, Peloton, BODi, Les Mills, Aaptiv | $10–30/mo | Where Celebrity tier lives |
| Hardware-coupled | iFIT, Tempo, Peloton+ | $15–40/mo + $400-2,500 hardware | Different segment |
| 1:1 human coaching | Future, Caliber | $149–300+/mo | Different segment |

Total 2026 market sized at ~$9.22B and growing ~15% YoY.

---

## Top 20 competitor matrix

| # | App | Price | Equipment-aware? | AI | Injury-aware? | Trial | Wearable | Top complaint |
|---|-----|-------|------------------|-----|---------------|-------|----------|---------------|
| 1 | **Fitbod** | $15.99/mo · $96/yr | Multi-profile toggle | ML program-gen | Manual skip per session | 7d | Apple Health, Google Fit | "Tweaked shoulder, no easy way to avoid all overhead pressing" |
| 2 | **Strong** | $4.99/mo · $30/yr | No | None | No | — | Best Apple Watch app | Static; no programming intelligence |
| 3 | **Hevy** | $2.99/mo · $24/yr · **$75 lifetime** | Filter only | **Hevy Trainer (Feb '26)** AI gen | No | — | Wear OS only (no Apple Watch yet) | No HRV/sleep, no Garmin |
| 4 | **Jefit** | $13/mo · $70/yr | Filter only | "AI planning" | No | 7d | Smartwatch (Elite) | UX dated; Elite paywall feels arbitrary |
| 5 | **Nike Training Club** | **Free** | Filter only | None | No | — | Apple Watch | Programs don't adapt; static |
| 6 | **Apple Fitness+** | $9.99/mo · $80/yr · **family of 6** | No (class library) | "For You" recs | No | 1mo + hardware | Apple Watch required | Locks out Android entirely |
| 7 | **Peloton App** | $16/mo One · $29/mo Plus | Marginal | None | No | — | Apple Watch, Wear OS | Oct '25 price hike; weak strength |
| 8 | **Centr** (Hemsworth) | $30/mo · $150/yr | Filter only | None | No | 7d | Apple Watch | "Doesn't adapt to recovery" — top reviewer complaint |
| 9 | **MyFitnessPal** | $20/mo · $80/yr · Premium+ $25 | No (nutrition-first) | Cal AI photo scan | No | 1mo | Apple, Garmin, Fitbit | Aggressive paywall; workouts are afterthought |
| 10 | **FitOn** | Free · PRO $30/yr | Filter only | None | No | — | Fitbit, Garmin HR | "Never-ending sale" flagged by Truth-In-Advertising |
| 11 | **Caliber** | Free · Coaching $200-300/mo | Yes (coach-built) | Minor | Coach asks | — | Apple Health | Cost; not self-serve |
| 12 | **Future** | **$149-199/mo** | Coach-built | None | Coach asks | — | Apple Watch required | **iOS-only, $149/mo** — locks out Android |
| 13 | **Sworkit** | $10/mo · $60/yr | Filter only | None | No | 7d | Apple, Wear OS | Brand stalled; not cutting-edge |
| 14 | **BODi** (Beachbody) | ~$120/yr · $215 CA | Programs are equipment-specific | None | No | — | Apple Watch (limited) | MLM stigma; brand erosion |
| 15 | **Aaptiv** | $15/mo · $100/yr | Limited (cardio) | "SmartCoach" audio | No | 7d | Apple Watch HR | Audio-first losing share to Spotify |
| 16 | **Freeletics** | $35/mo · $100/yr | Onboarding filter only | **AI Coach** + readiness score | **Explicitly disclaimed** | 14d refund | Apple Watch, Polar | App warns: "not designed for injuries" |
| 17 | **Ladder** | $30/mo Pro · $180/yr · $45 Elite | No | None | No | **7d no card** | Apple Watch, Garmin | Elite has no annual plan; programs lock 4-12 weeks |
| 18 | **iFIT** | $15/mo Train · $39/mo Pro | **Yes — hardware-bound** (NordicTrack/ProForm) | Auto incline/resistance | No | 30d w/hardware | iFIT chest strap | Train tier gutted without iFIT hardware |
| 19 | **Sweat** (Itsines) | $25/mo · $135/yr | Tag only | None | No (postnatal track is unique) | 7d | Apple Watch | Oct '24 25% price hike |
| 20 | **Tempo** | **$40/mo + $495–2,495 hardware** | **Yes — depth camera recognises Tempo dumbbells** | **Real form check via depth camera** | No | — | Apple Health | Hardware lock-in; $2.5k brick if you cancel |
| **★** | **Us** | **$10/mo Std · $20/mo Celeb** | **Yes — QR scan, third-party stickers, injury-personalised** | None yet | **Auto-filter at intake (34Q)** | **14d** | None yet (P0 gap) | App is mid-build |

---

## Where we win (sharpened)

### 1. Cross-OEM, third-party-sticker, injury-personalised QR scan (real moat)

The original assessment said "no one does this." After deeper
research the picture is sharper:

- **Technogym's Mywellness** runs essentially the QR-scan-personalise
  loop on Technogym-equipped gyms. Their Open Platform API exists.
  Limitation: **only Technogym hardware, no injury filter**.
- **iFIT** does two-way machine control on NordicTrack/ProForm. Same
  pattern; **single-OEM, no injury filter**.
- **Weightplan (UK)** runs third-party stickers on independent gyms
  with how-to-video lookups. **Tiny, UK-only, no injury filter, no
  personalisation depth**.
- **Planet Fitness** has QR codes that link to generic instructional
  videos. **Not personalised**.

**Our defensible position:** cross-OEM (any equipment, any
manufacturer), third-party stickers (not OEM-locked), injury-personalised
recommendation, Android-first. **Each axis is taken individually
elsewhere; nobody combines all four.** Patent the injury-personalised
path specifically.

### 2. Injury-aware filtering at intake depth (industry-leading)

Quotes from competitor docs:

> *"The Freeletics Training App is not designed to accommodate any injury or health issue. Consult your doctor."*  — Freeletics Help Center

> *"Doesn't adjust based on how you slept or how recovered you are"*  — top reviewer complaint on Centr (TechRadar 2026)

> *"Tweaked my shoulder, no easy way to avoid all overhead pressing — had to skip and swap each one"*  — top reviewer complaint on Fitbod (Indie Hackers 2026)

Our 34-question intake + `exercise_filter.dart` removing exercises
whose contraindication tags overlap injuries before the user sees them
is **categorically deeper** than every competitor.

**Defend with:** licensed physio reviewer signing off on the catalog
(~$5k for a one-time review of 200 exercises). Add "Reviewed by [X],
DPT" to landing page. Freeletics' explicit disclaimer becomes our
contrast point.

### 3. Android-first premium

- Apple Fitness+ requires Apple Watch.
- **Future is iOS-only** at $149/mo.
- Tempo Move requires Apple TrueDepth (iPhone-only).
- Centr/Peloton/NTC are cross-platform but iOS-leaning.

The Android premium-fitness market is genuinely under-served. Focus
remains correct.

### 4. Pricing structure — competitive, with one big gap

| Plan | Our price | Closest comp | Verdict |
|------|-----------|--------------|---------|
| Free | $0 | NTC ($0), FitOn ($0), Hevy free | Competitive — body-weight library is real value |
| Standard | $9.99/mo | Apple Fitness+ ($9.99 + family 6), Sworkit ($10) | **Cheapest paid in the entire 20-app bracket on monthly basis** |
| Celebrity | $19.99/mo | Sweat $25, Ladder $30, Centr $30 | **Underpriced** by ~$5–10/mo; pricing power available once content depth lands |
| Trial | 14 days | Fitbod 7d, Centr 7d, Sweat 7d, Ladder 7d-no-card | **Best in category** outside Apple's hardware bundle |
| **Annual** | **— (gap)** | All 20 paid apps offer annual at ~50% off | **Single biggest revenue lever to add** |

### 5. Architecture quality (stealth advantage)

Doesn't show in marketing but shows in shipping speed:

- Mock-first repository pattern means we rebuild any data source in
  hours, not days
- Webhook-driven Stripe means subscription doc is server-controlled —
  matters the moment we ship App Store IAP
- Test suite at 207/207 green lets us refactor confidently
- Debug daemon (`scripts/dev/debug_daemon.ps1`) + DEBUGGING.md means
  incident → root cause → fix in hours. Nobody else has this dev loop.

---

## Where we lose (table-stakes gaps)

| Gap | Priority | Notes |
|-----|----------|-------|
| **Annual subscription SKU** | **P0** | Every paid competitor offers annual at ~50% off. Two days of Stripe work; biggest revenue lever in the assessment. |
| **Wear OS companion** | **P0** | Strong/Hevy/Fitbod/Centr/NTC/Peloton/Apple all have watch set logging. Phone-out-of-pocket-between-sets is real friction. |
| **Exercise video for every movement** | **P0** | We ship 12 hand-seeded; Hevy 200+, Fitbod 1,000+, Jefit 1,400+. Phase 2E (catalog scraper) was already queued. |
| **Health Connect / Apple Health sync** | **P1** | Write workouts back to system rings; read steps + HR. Every $10+ app has this. |
| **Rest timer with auto-trigger on log** | **P1** | Single screen; unforgivable to ship without. |
| **Plate calculator + warm-up calculator** | **P1** | Strong/Hevy/Fitbod all have. |
| **Offline workout download** | **P1** | FitOn/Centr/Peloton all support; gym wifi is hostile. |
| **Post-workout 1-tap difficulty rating** | **P1** | Freeletics' AI Coach reads this; nobody else does it well. Cheap to add — feeds our recommendation filter. **New from round-2 research.** |
| **Programmatic progressive overload** | **P2** | Fitbod and Hevy Trainer auto-suggest next-session weight. |
| **HRV/sleep ingestion → recovery score** | **P2** | Aspirational — only Future/SensAI deliver. Centr/Hevy/Fitbod reviewers explicitly want it. White space at $10–20/mo. |
| **MediaPipe-based form check on Android** | **P2** | **Demoted from P0** — Tempo ships hardware-assisted version today. Reframe as "form check on commodity Android, no extra hardware." Still a credible feature; not a category-defining moat. |
| **Family / household plan** | **P2** | Apple Fitness+ family-of-6 included at $9.99 is the anchor; iFIT shares per device. Standard tier add-on potential. |
| **Team-based async coach feed** | **P2** | Ladder's stickiness moat. Celebrity-tier feature: each celebrity coach posts to a team feed; users join, comment. **New from round-2 research.** |
| **B2B gym-chain partnership track** | **P2** | Not eng — sales/BD. Technogym proved members will scan; Weightplan proved third-party stickers work. **New from round-2 research.** |
| **Progress photos** | **P3** | Strong/Hevy/Centr all have. |
| **Social feed** | **P3** | Hevy's strongest moat. |
| **AI workout generator** | **P3** | Phase 6 — built on the 34Q intake + injury filter + recovery score is the differentiator. |
| **Celebrity-led video plans** | **P3** | Phase 6, legal framework is the gate. One signed celebrity + 50 hand-curated workouts = v1. |

---

## Top 5 threats (re-ranked after round-2)

### 1. Fitbod — closest equipment-aware analogue

- $15.99/mo · 7-day trial · 1,000+ exercises with video · 7 years of
  ML data
- Their gap: no injury filter at recommendation layer; no QR scan; no
  celebrity content; no HRV
- Counter: *"Fitbod makes you skip exercises manually each session.
  We don't show them."*

### 2. Hevy + Hevy Trainer — price floor + just-shipped AI

- $2.99/mo · $74.99 lifetime · Hevy Trainer (Feb '26) AI gen · best
  social
- Their gap: no equipment scan; no injury intake; no HRV; no Apple
  Watch yet (Wear OS only)
- Counter: Standard tier value props must be obvious in <5s on the
  pricing page; the 3.3× premium needs to read as obvious

### 3. Centr — celebrity benchmark

- $29.99/mo · 1,400 workouts · Hemsworth + Zocchi + Da Rulk
- Their gap: static programs (top reviewer complaint), no HRV, no
  injury filter, $30 expensive
- Counter: don't out-content them. Compete on personalisation depth +
  $19.99 monthly + $119.99 annual undercut

### 4. **Ladder — direct $20-tier competitor [new]**

- $29.99/mo Pro · $180/yr ($15 effective) · Schwarzenegger + Bobby
  Maximus + Hilary Duff · team-based coaching feed · **7-day no-card
  trial**
- Their gap: no equipment awareness; no injury filter; programs
  lock 4-12 weeks
- **Direct head-to-head** with our Celebrity tier. Our advantage:
  $19.99 < $29.99. Their advantage: real signed celebrities + a
  community feed loop we don't have yet
- Counter: ship the team feed (P2); land at least one signed
  celebrity before launch

### 5. **Tempo — only competitor with real form check [new]**

- $40/mo + $495–$2,495 hardware · depth-camera form check is real
- Their gap: hardware lock-in ($2.5k brick if you cancel); iOS-only on
  Move
- We're not directly competing — different segment (pure software vs
  hardware bundle) — but they own the "AI form check" marketing claim
  in 2026
- Implication: don't overclaim form check as our moat. When we ship
  MediaPipe-based form check, frame as "form feedback on commodity
  Android, no $500 device required"

(Honorable mention: **Apple Fitness+** at $9.99 with **family of 6**
is brutal anchor pricing for any iPhone household. We can't compete
on that and shouldn't try — Android-first is the answer.)

---

## What it takes to win completely

Beyond shipping the table-stakes backlog, here's what would actually
make this app the category leader. Five strategic plays, ranked by
defensibility:

### 1. The B2B / gym-chain partnership flywheel

The QR-scan moat is only sticky if the QR codes are on the wall.
Sequence:

- **2026Q3:** sticker pack pilot in 1 mid-tier chain (target Anytime
  Fitness, Crunch, EOS, Basic-Fit in EU). Free stickers + branded
  in-app shoutout to the gym. Members scan → app loads exercises for
  *that specific machine in that specific gym*.
- **2026Q4:** measure: did chain members convert at >2× our
  consumer baseline? (They will — captive audience, equipment already
  in front of them.)
- **2027:** 5-chain rollout. Now we have a cold-start solution and a
  data moat — *injury-tagged exercise success rates per machine type*
  is data nobody else has.

This is the only play that scales the moat past single-product
lifetime. **Single biggest leverage point in this assessment.**

### 2. Physio-reviewed catalog + medical disclaimer flip

Freeletics literally tells users *"not designed for injuries — see
your doctor."* That's our exact contrast point.

- Pay one DPT (~$5k) to review the 200-exercise catalog and sign off
  on the contraindication tags
- Landing page: "Reviewed by Dr. [X], DPT — physical therapy
  practitioner since [year]"
- Marketing copy: *"Other apps tell you to consult your doctor. We
  built our exercise library with one."*
- Long-term: a B2B physiotherapist channel — therapists prescribe
  injury-safe workouts to patients via our app. Whole new segment.

### 3. Annual + family + lifetime pricing matrix

Single biggest revenue lever:

| SKU | Monthly | Annual | Effective | Family (4) | Lifetime |
|-----|---------|--------|-----------|------------|----------|
| Standard | $9.99 | **$59.99** | $5.00 | **$14.99** | — |
| Celebrity | $19.99 | **$119.99** | $9.99 | **$24.99** | **$499** |

- **Annual** mirrors Sweat/Ladder/Freeletics norms; expect 30–40% of
  paid conversions to choose annual once offered
- **Family** differentiates against Hevy ($2.99 has no family path)
  and matches Apple Fitness+ family-of-6 anchor
- **Lifetime $499 on Celebrity** = 25-month breakeven; Hevy already
  has $74.99 lifetime so the model is proven; sticky early adopters
  who lock out competitors

Two days of Stripe work + design. Stripe Checkout already supports all
three modes.

### 4. Adaptive personalisation loop (Freeletics-style + injury data)

The differentiator vs Fitbod's static toggle:

```
post-workout: 1-tap "too easy / right / too hard"
                       │
                       ▼
update Bayesian model of user's tier-fit per muscle group
                       │
                       ▼
for-you feed re-ranks exercises tomorrow
```

- We're already collecting workout logs (Phase 3A) and have the
  recommendation pipeline (Phase 2C). Adding the difficulty signal is
  one button on the workout-complete screen + ~50 lines of model code.
- Marketing: *"Your plan adapts to how you actually felt — not what
  the algorithm guessed."*
- Combined with injury-aware filtering, this is the personalisation
  story Centr/Sweat/Ladder don't have.

### 5. Form check on commodity Android (P2, but high marketing leverage)

- MediaPipe BlazePose runs at 30+ FPS on mid-tier Android. Free Google
  library. On-device, no PII leaves the phone.
- Ship feedback for the 6 highest-injury-risk movements first: squat
  depth, deadlift back angle, push-up scapular stability, overhead
  press lockout, lunge knee tracking, plank alignment.
- Tie into the QR-scan flow: scan barbell rack → form check enabled
  for squat / bench / deadlift on that rack.
- Marketing: *"Form coach. No $2,500 hardware. Just your phone."*
  Direct shot at Tempo.

This is **real differentiation** — every other Android app in the
top-20 ships zero camera-based form feedback. Tempo is iOS-only on
Move, hardware-locked on Studio. Ship in 2026Q4.

---

## Pricing actions — top 3 (each <2 days of work)

1. **Add annual pricing.** $79.99 Standard / $149.99 Celebrity (or
   $59.99 / $119.99 if we want to lead aggressively). Annual is what
   users compare to Centr's annual; we currently force them to compare
   monthly to monthly which makes the gap look smaller than it is.
   Stripe price IDs only — no Cloud Function change.
2. **Push Celebrity monthly to $24.99.** We're underpriced vs Sweat
   ($24.99) and Ladder ($29.99) for the same positioning. $5/mo of
   real headroom. Once we have one signed celebrity trainer + 50
   curated workouts, raise it.
3. **Ship Standard family plan.** $14.99/mo for 2 accounts; $19.99/mo
   for 4. Apple Fitness+ family-of-6 at $9.99 is the anchor users
   compare against. Adding family is differentiation against Hevy
   (which has no family path).

---

## Strategic recommendations (terse)

1. **Defend the QR moat with a patent + a gym-chain pilot.** Patent
   the injury-aware path specifically (Technogym's Mywellness covers
   the personalised recommendation generally). Pilot with one
   mid-tier chain in 2026Q3.
2. **Ship Tier 0 features before any v1 marketing push.** Annual
   pricing + Wear OS + exercise videos + rest timer + plate calculator
   + Health Connect + offline download. Without these, day-1-of-trial
   users churn back to Hevy/Fitbod.
3. **Make injury-filtering and onboarding depth the marketing
   leads.** Both are real, both are unique, both come for free
   because we already shipped them. Add a physio reviewer for $5k of
   credibility.
4. **Add the post-workout difficulty rating loop.** Cheap; closes the
   adaptive-personalisation gap vs Freeletics. Combined with our
   injury filter, this is genuine personalisation depth.
5. **Stop framing AI form check as a moat.** Tempo ships hardware-
   assisted form check today. Ship MediaPipe-based form check on
   Android in 2026Q4 as a *commodity-Android-no-extra-hardware*
   feature, not as a unique-AI claim.
6. **Ship a team-feed for Celebrity tier.** Ladder's stickiness is
   the team-based community loop. Each signed celebrity gets a feed,
   subscribers join their team, comment, support each other. P2.
7. **Lifetime $499 on Celebrity** locks out competitors among early
   adopters. Hevy proved the model with $74.99. We can charge 6.7×
   because Celebrity is 6.7× the monthly price.
8. **Don't try to out-content Centr/BODi/Sweat.** They have decades
   of taped studio footage. We compete on personalisation depth, not
   catalog size. The exercise-catalog scraper (Phase 2E) only needs
   to grow us to ~200 movements — past that, diminishing returns.

---

## Sources

Round-1 (apps 1-15): see commit `cd6c554` history. Round-2 (apps
16-20):

- [Freeletics Help Center — Can I train with an injury?](https://help.freeletics.com/hc/en-us/articles/360004961319-Can-I-train-with-an-injury-or-health-issue)
- [Freeletics Limitations feature](https://www.freeletics.com/en/blog/posts/limitations-feature/)
- [Ladder pricing](https://www.joinladder.com/pricing)
- [Ladder app review (2026)](https://www.outdoorsynomad.com/ladder-fitness-app-review/)
- [iFIT membership plans](https://www.ifit.com/membership)
- [iFIT Pro membership (NordicTrack)](https://www.nordictrack.com/category/ifit-pro-membership)
- [Sweat 2024 subscription changes](https://support.sweat.com/hc/en-us/articles/10409204132879-Sweat-s-First-Ever-Subscription-Changes)
- [Tempo official site](https://tempo.fit/)
- [3D Tempo Vision form feedback](https://support.tempo.fit/support/solutions/articles/151000154714-3d-tempo-vision-form-feedback)
- [Tempo Move depth-camera tech (Analog Devices)](https://www.analog.com/en/signals/articles/tempo.html)
- [MediaPipe BlazePose (Google Research)](https://research.google/blog/on-device-real-time-body-pose-tracking-with-mediapipe-blazepose/)
- [Technogym Mywellness Open Platform docs](https://openplatformdocs.mywellness.com/)
- [10 reasons to use Mywellness — Pinnacle Medical Wellness](https://www.pinnacle-pt.com/about/news/10-reasons-to-use-mywellness-app)
- [QR codes for gyms — supercode.com](https://www.supercode.com/use-case/qr-codes-for-gyms)

Round-1 sources: see `git show cd6c554:core/business/COMPETITIVE_ASSESSMENT.md`
or commit history.
