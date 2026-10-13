# Phase 2 candidate: body-composition scan + adaptive-coaching features — reference app walkthrough

**Status:** DRAFT candidate plan, not approved, not started. Documentation-first per DEVELOPMENT RULES v4 (`~/.claude/CLAUDE.md` §5): this file is the input to the required TDD/design/sprint-planning pass, not a substitute for it.

**Source:** operator-recorded screen walkthrough of a third-party reference app ("BodyFat AI", Android/Galaxy S23 Ultra, operator's own test account `korostelevivan@gmail.com`), `D:\Downloads\video_2026-10-09_15-01-09.mp4` (5:46, 48 MB). Reviewed by extracting 31 chronological frames (scene-change detection + gap-fill, ~every 5-15s) and reading them directly — not a transcript, so UI copy is approximate where partially visible. No audio track content captured (video appears to have no narration, just a screen recording with a selfie-cam PiP inset).

**Why this file exists:** operator asked to watch the video, extract the information in it, group it, and turn it into a phase-2 implementation plan. This is that grouping + plan. Nothing in it has been implemented, committed, or scheduled — it is an input for the required Plan/review pass before any sprint starts.

---

## 1. What the video actually shows (chronological, grouped)

| Time | Screen | Content |
|---|---|---|
| 0:01–0:05 | Phone homescreen → app launch | Reference app icon tapped from homescreen |
| 0:05–0:12 | Landing / paywall | "Fat loss. Made simple." headline, before/after progress-photo slider (Side-by-side / Slider toggle), "Build my plan" CTA, "About 3 minutes · Photos stay private" |
| 0:12–0:31 | Onboarding Q&A | Sex at birth, age (slider), "which direction" (goal direction), sleep hours ("Recovery" section — "How much do you usually sleep?") |
| 0:31–0:46 | Goal visualization | Illustrative 3D-ish body model, "choose your dream body fat", Reset control |
| 1:25–1:30 | Device integration | Health Connect (Android) read-only steps/activity permission request, explicit "never your weight, heart rate or medical records" disclaimer, vs. "Use manual checkboxes" fallback |
| 1:30–1:37 | Account gate | "Sign in to save your estimate" — explains *why* an account is required ("photos are analysed on our servers... estimate and plan follow you to any phone"), Google sign-in |
| 1:40–1:57 | Home / Nutrition tab | Daily kcal ring (goal 2,400, +640 exercise credit, remaining), protein/carbs/fat bars, **AI Meal Scan** entry point with 4 alternate input methods (Barcode / Food label / Describe / Search) |
| 2:00–2:14 | AI Meal Scan flow | Camera permission → photo → "Analysing meal" → result: detected ingredients ("cooked white rice · water"), **portion-confidence %** (24%, 73% in two examples), full macro breakdown, editable meal name |
| 2:14 | **"Check these" uncertainty disclosure** | Model surfaces specific unresolved ambiguities as tappable chips ("Liquid could be another pale soup or beverage", "Bowl dimensions and liquid depth are unclear", "Frying oil type and absorbed amount are unknown") — each opens a note field instead of silently guessing |
| 2:29–2:35 | Food diary | Breakfast/Lunch/Dinner/Snacks sections, per-meal `+`/`...` actions, "Diet Remix" teaser (locked until meals logged), nutrition-label OCR scan (camera frame overlay) |
| 2:47–2:53 | Progress — loading | "Loading your progress" |
| 2:53–3:08 | Progress — body scan results | "Your photo journey — Baseline photo saved", **"Future You · latest scan vs your goal · AI preview"**, tabs (Body fat / Weight / Lean mass), estimated body-fat % with 1M/3M/6M/All range toggle, explicit uncertainty note ("dots are single readings, which vary about ±1 pt") |
| 3:08 | Scan history | Dated list of weekly scans (date, bodyweight, body-fat %, "Photos available"), **Compare** action |
| 3:33–3:53 | Plan tab (adaptive coaching) | Daily kcal target as an **editable range slider** (not a fixed number — 1,560–1,860), protein minimum, steps goal, "Your coach is listening" (every weigh-in/meal/step/scan feeds a weekly review), **Coached / Shared / Manual** toggle for who owns the targets, "Let my coach adjust my step goal" toggle, links to "How your plan adapts" / "How your pace is set" |
| 3:58–4:09 | Profile | Account identity, "Plan settings" / "Plan & targets" / "Units", scan reminders (**weekly, Sun 08:00** + optional daily prompt) |
| 4:09–4:30 | Support | "Take the 60-second tour", Help Centre, **"Data sources" (where nutrition data comes from)**, Rate app, one-tap sentiment ("How are you enjoying..."), Product survey, Contact us, Terms |
| 5:10–5:36 | Privacy explainer | "What happens to my photos? Stored **face-blurred**, only used for estimate/comparison. Privacy & data lets you set how long they are kept, or delete them." + **"Message us"** topic-routed support form (Scanning and photos / Food logging / Plan and targets / Membership / Account / Privacy / Something is broken / Something else) with free-text field |

A 294s frame briefly shows the Google Play Store app list — this is the operator tabbing away mid-recording, not part of the reference app; excluded from the plan.

---

## 2. Grouped into feature themes

### A. Body-composition photo scan (net-new pillar for Fitness_App)
- 3-pose weekly scan (Front/Side/Back — seen in the attached screenshots, consistent with the video's "Scan history" and "Progress" tabs)
- On-device setup guidance before capture: distance/lighting/position checks with live pass/fail indicators
- Server-side body-fat % estimate with explicit measurement-error disclosure (±1 pt) and a visible trend line vs. single-reading dots
- Baseline → latest and previous → latest comparison modes, side-by-side or slider
- "Future You" generative preview (goal body vs. current scan) — explicitly marked illustrative
- Face-blurred storage, user-controlled retention/deletion, explained in plain language at point of relevance (not just buried in a privacy policy)

### B. AI meal/nutrition logging (adjacent to, not replacing, Fitness_App's existing equipment-recognition pillar)
- Multi-entry-point logging: photo scan, barcode, food-label OCR, free-text describe, search
- Portion-confidence percentage shown alongside every AI estimate
- **"Check these" uncertainty chips** — the single most transferable UX pattern for Fitness_App, independent of whether body-scan or meal-scan ships: Fitness_App's own equipment-recognition accuracy is measured at 0/18–1/18 on real photos (`core/CURRENT_STATE.md`, `scanner-pipeline-location` row); a low-confidence-disclosure pattern like this is a cheap way to make a weak model trustworthy by being honest about what it doesn't know, rather than hiding the error rate
- Food diary structured by meal slot with per-item edit/remove

### C. Adaptive coaching / plan ownership model
- Target ranges instead of fixed single numbers (kcal shown as a band, not a point)
- Explicit, named ownership modes: Coached (app sets everything) / Shared / Manual
- Weekly automatic review cycle, with an explicit "your coach is listening" framing of what evidence feeds it (weigh-ins, meals, steps, scans)
- Granular per-metric auto-adjust toggles (e.g. step goal only)

### D. Platform integration & reminders
- Health Connect (Android) read-only steps/activity, explicit scope disclaimer, manual fallback always available
- Weekly scan reminder with a default day/time, optional daily prompt — opt-in, not forced

### E. Trust, support and transparency surface
- "Data sources" page (where the nutrition database comes from) — a direct answer to a question users and reviewers both ask
- Topic-routed support form rather than one generic contact box
- One-tap sentiment check-in, separate from the longer product survey

---

## 3. What's genuinely new vs. what Fitness_App already has

| Theme | Fitness_App today | Gap |
|---|---|---|
| A. Body-composition scan | Not present. Current AI pillars are equipment recognition (camera→gym machine ID) and Form Coach (camera→rep-form feedback). No body-fat/photo-progress feature exists. | **Net-new feature area** — needs its own design pass, not a bolt-on |
| B. Meal/nutrition AI logging | Not present as a feature; `scripts/catalog` is equipment/exercise content, not food | **Net-new**, but the uncertainty-disclosure *pattern* (not the feature) is reusable immediately on equipment recognition |
| C. Adaptive coaching ranges | Not present; current plan/target model is simpler | Smaller, UX-level change if pursued |
| D. Health Connect / reminders | Unconfirmed — not referenced in files reviewed this session | Needs a repo check before scoping |
| E. Support/data-sources transparency | `core/review/` and decision docs exist internally, but nothing user-facing like a "Data sources" page was found in this session's review | Low-cost, high-trust addition regardless of A/B |

---

## 4. Phase-2 candidate plan (sequencing, not yet a sprint)

This is a candidate ordering for the required docs-first pass (TDD + design + sprint plan with epics/stories/DoD, per DEVELOPMENT RULES v4), not an approved backlog. Nothing here is scheduled.

1. **E first, standalone, cheapest, no new pillar:** uncertainty-disclosure pattern applied to the *existing* equipment-recognition result screen (surfaces the real 0/18–1/18 accuracy honestly instead of a silent wrong answer) + a "Data sources" page. Both are UI/copy-level, no new ML, no new data pipeline. Closest in spirit to the scanner-accuracy finding already on record.
2. **D, scoped:** confirm whether Health Connect integration exists; if not, evaluate as a small, independent addition (read-only steps, explicit scope, manual fallback) — decide after a repo check, not assumed from the video.
3. **C, scoped:** target-as-range instead of fixed number, Coached/Shared/Manual ownership toggle — a plan-model change, needs its own design doc since it touches the subscription/target data model.
4. **B, full feature:** AI meal scan + food diary — a new content/ML pillar (nutrition database, portion estimation model, food diary data model). Comparable in scope to the original equipment-recognition build, not a quick addition.
5. **A, full feature, largest:** body-composition photo scan pillar — new capture flow, new ML/estimation model (or a licensed third-party SDK — worth evaluating build-vs-buy given the equipment-recognition accuracy lesson), new privacy handling (face-blurring, retention controls), new Progress tab content, "Future You" generative preview (raises its own consent/accuracy-disclosure questions, same as the deepfake item already flagged as a compliance blocker in `FITNESS_APP_TASK_LIST.md` item 67 — any generative "preview of you" content should go through the same consent/legal review, not be treated as a simple feature).

Items 4 and 5 are each roughly equipment-recognition-sized undertakings — this is not a one-sprint list. The operator should treat 1–3 as separate, smaller decisions from 4–5 before committing to either new AI pillar, since both 4 and 5 carry the same "does the model actually work on real user photos" risk that is unresolved for the *existing* equipment-recognition pillar.

---

## 5. Explicit open questions for the operator (not engineering-closeable)

- Which of A–E, if any, should enter scope for Phase 2 — this is a product-strategy decision, not inferable from the reference video alone.
- For A and B: build in-house (repeats the equipment-recognition accuracy risk) vs. license a third-party body-composition/nutrition-estimation API — a cost/control tradeoff only the operator can weigh.
- For A's "Future You" generative preview specifically: same consent/legal category as the wishlist's deepfake item — needs a decision before any design work, not after.

No code, data model, or UI work has started on any of this. This file is the grouped input for that decision and the subsequent docs-first pass.
