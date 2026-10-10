# Fitness App — Full Figma Refactor Brief v1.1 + v1.3 Governance Update (English Companion)

> **Fitness-App local translation adoption:** The local source `docs/Redisign/FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.md` has exactly the same Git blob SHA `81538d09cb23d2c6acc8b84b61da5450128ca4cb` as the originally translated source in `ReviewExistingExamples`. This English copy is historical documentary text, **not a current accepted product implementation, production UI locale or release decision**. No original file was changed.

**Original:** [FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.md](FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3.md), Git blob `81538d09cb23d2c6acc8b84b61da5450128ca4cb`. An [identical -1 source copy](FIGMA_FULL_APP_REFACTOR_PROMPT_v1.3%20%281%29.md) shares that blob. **The source filename says v1.3, but its main heading says v1.1; the appended section is explicitly labeled "UPDATE v1.3". Both version labels are retained rather than silently changed.**

This English companion covers the **29 numbered master-design sections and the subsequent v1.3 Decision Registry update**. It is historical imported Figma input, **not** a newly adopted Fitness App master plan, a Flutter feature build, or product/release approval. Requirements concerning medical guidance, private photos, on-device pose inference and exercise library size remain subject to separate current-product verification.

## Assignment and product scope

Act as a lead product designer, senior mobile UX/UI designer and design-systems architect experienced in fitness, workout logging, computer vision, on-device ML and AI-assisted mobile apps.

Refactor the **existing** Android/iOS Fitness App into a coherent connected experience, rather than drawing unconnected showcase screens or replacing the product from scratch. Preserve actual product logic while removing the old generic tile-grid hierarchy.

Inspect supplied screenshots, references and videos as research material. Do not copy a competitor's app screen-for-screen. Record which UX patterns were **accepted, modified or rejected**, with rationale.

## 1. Product context

The original prompt describes Fitness App as a personal AI exercise assistant for the gym, home and outdoors. It **asserts** these eighteen functions as its then-intended context:

1. Catalogue of **1,887** unique exercises
2. Licensed high-quality anatomical exercise animations
3. Technique guidance and step-by-step instructions
4. Goal/experience/equipment/history/limitations-based recommendations
5. Contextual AI trainer
6. Camera-based equipment recognition
7. Detected-equipment page with relevant exercises
8. Camera technique checking and pose detection
9. Personalized workout plans
10. Weights, repetitions and sets log
11. Automatic rest timer
12. Workout history and progress
13. Muscle load and recovery assessment
14. Injury-aware filtering
15. Voice guidance
16. Health Connect and wearables
17. Progress photos and comparison
18. Light and dark themes

**Evidence warning:** These are historical design-input assertions, **not a validated current feature inventory**. In particular, the source's 1,887 count and camera-based form assessment must be verified against actual Fitness App code, catalog licensing and product gates before publication; another marketing project's canonical SPTR facts classify several capabilities differently.

The envisioned loop was **unknown equipment → scan → suitable exercises → anatomy/technique → completed sets → optional Form Check → saved result → progress and next recommendation**. The app should feel like an in-session guide, not a card directory.

## 2. Problems requiring before/after design audit

Demonstrate how the redesign addresses **all eleven** source findings:

1. Equal-sized tiles flatten the importance of features.
2. Home fails to tell the user what to do now.
3. Secondary content can dominate the actual workout.
4. Scanner does not feel like the unique differentiator.
5. Small exercise cards undersell visual instruction.
6. Progress shows empty generic tiles without interpretation.
7. AI looks like generic chat rather than a contextual coach.
8. Plain age/height/weight forms break the premium experience.
9. Set logging is overly dense and technical.
10. Empty/loading/error/permission states do not form a unified language.
11. The scan → exercise → workout → progress path feels disconnected.

## 3. Reference patterns — adopt and reject

**Adapt where useful:** one question per screen; onboarding progress; age/height/weight wheel and ruler pickers; anatomical muscle map; visual choice of goals and restrictions; personalized plan preview **before** registration or payment; media-first exercise cards; Today's workout hero; easy set logger; rest timer; compact programs; contextual AI Coach; progress photo side-by-side/slider; gentle contextual reminders.

**Reject:** sales countdowns; scratch cards/artificial discounts; paywall before demonstrated value; false urgency; unverified before/after marketing; guaranteed goal dates; BMI represented as diagnosis; body/beauty scores; contextless AI chat; ads interrupting core flows; one-size-fits-all grids; auto-publishing sensitive photos; invented AI precision.

## 4. UX principles

Each main screen must answer at least one: **What should I do now? Why is this recommended? How do I perform it? How can I save the result quickly? What changed? What is next?**

Use progressive disclosure: **one dominant action → short rationale/result → details on demand**.

Constraints:

- One dominant primary CTA per screen
- No more than **three** major conceptual blocks before first scroll
- One-handed access to important controls
- Hide secondary distractions during active workouts
- Do not use a grid as the universal layout
- Never show unverified metrics
- Keep exercise guidance distinct from medical diagnosis
- Never rely on color alone

## 5. Visual direction

Preserve the premium dark foundation, lime primary-action accent, large expressive type, media-first structure, deep neutral surfaces, restrained gradients, soft depth, rounded surfaces, purposeful motion and low clutter.

Create a **full light-theme adaptation**, not an inverted dark screenshot.

Use glassmorphism sparingly for camera overlays, floating controls, modal sheets and temporary status overlays — **not every scrolling card**.

## 6. Information architecture

Main bottom navigation, in this order: **Home / Scan / Workouts / Progress / Profile**.

| Destination | Subsections required by source |
| --- | --- |
| **Home** | Today's workout, Continue workout, Quick Scan, Recovery snapshot, Weekly progress, Milestones, and a photo-comparison card only with actual photo data |
| **Scan** | Camera, recognition states, top alternatives, unknown equipment, history, saved machine cards |
| **Workouts** | Current program, calendar, workout library, exercise library, equipment library, saved workouts, active workout |
| **Progress** | Summary, strength progression, volume, consistency, muscle load/recovery, measurements, Progress Photos, achievements, history |
| **Profile** | Personal data, goals, units, integrations, notifications, privacy, subscription, help |

Scanner is the most visible differentiator, while **Today's Workout stays Home's primary action**.

## 7. Complete onboarding — short mandatory portion plus optional personalization

### 7.1 Value proposition

Conceptual English heading: **"Your AI assistant at the gym."**  
Subtitle: **"Recognize equipment, find suitable exercises and check technique with your camera."**

Offer **Set up my plan**, **Continue without signing up**, and **Sign in**. This is mockup copy only: validate whether camera form checking is actually implemented before any marketing activation.

### 7.2 Primary goal

Single selection: Build muscle / Get stronger / Lose weight / Improve fitness / Improve endurance / Return after a break.

### 7.3 Experience level

First time / Beginner / Intermediate / Experienced, each with a plain-language explanation.

### 7.4 Workout location

Gym / Home / Outdoors / Mixed.

### 7.5 Equipment

Multi-select: Full gym / Selected machines / Dumbbells / Barbell / Kettlebells / Bands / Bodyweight / "I don't know the names; I'll scan equipment with the camera".

### 7.6 Schedule

Ask days per week, workout duration and preferred days. **Do not ask for notification permission yet.**

### 7.7 Limitations

Interactive body map: shoulder, elbow, wrist, upper back, lower back, hip, knee, ankle or no limitations.

Explanatory copy: "We use this to filter exercises that might not be suitable. This is **not medical diagnosis**."

### 7.8 Priority muscle areas (optional)

Interactive anatomical multi-select: chest, back, shoulders, arms, abs, glutes, legs and full body.

### 7.9 Main difficulty

Don't know what to do / Don't understand the equipment / Unsure of technique / Not enough time / Struggle with consistency / Discomfort or limitations / None.

### 7.10 Birth year

Vertical wheel: prominent selected year, faded neighboring values, haptics, direct input, accessible increment/decrement buttons and skip. **Store year, derive age.**

### 7.11 Height

Ruler picker: cm/ft, **1 cm** tick step, major marks, fixed center, direct input, haptics, **minus/plus** accessibility controls, optional.

### 7.12 Current weight

Horizontal ruler: kg/lbs, **0.1 kg** step, fixed indicator, direct entry, haptics, optional. If adult **and** age/height supplied, show a neutral informational card with BMI, approximate reference range, nearest-boundary difference and an explanation that muscle mass/body composition are not captured.

**Under age 20:** Do **not** apply adult BMI-category messaging. No weight shaming, compulsory weight loss, obesity diagnoses or "bad shape" language.

### 7.13 Target weight

Ruler markers for current/target values, kg difference and percentage of current weight. Preserve the source formula:

`(target - current) / current × 100`

Do not promise time to goal. Target weight remains **optional**.

### 7.14 Health Connect

Separate optional screen: steps, sleep, activity, recovery. Request system permissions **only after explicit Connect**.

### 7.15 Generating

Reflect only genuinely entered details; no fake progress or promises.

### 7.16 Plan Preview

**Before account/paywall**, show goal, workouts per week, duration, location, muscle priorities, first workout and genuine exercise posters — not invented catalogue content.

### 7.17 Account

After preview: Google / Apple / Email / Continue without account.

### 7.18 Notifications

Ask contextually only after the user selects a concrete day and time.

## 8. Home

Order: Greeting → Program progress → **Today's workout hero** → Start/Continue → Quick Scan → Recovery snapshot → Weekly calendar/stats → Last achievement → photo-comparison card (only with **at least two** photos).

Illustrative hero: "Today — Back and Biceps", "7 exercises · 48 minutes", **Start workout**. These numbers are illustrative, not a live plan.

Quick Scan is visually second only to workout hero. Do not show a blank photo-progress card; horizontal recovery cards must afford scrolling and must not crop the last item.

## 9. Scanner

Full-screen camera with states: permission, ready, targeting, capture, analyzing, high-confidence result, **top three alternatives**, unknown equipment, low light, no equipment visible, timeout, offline fallback, error and history.

Controls: corner brackets, sweep line, glass-style instruction pill, flash, capture, cancel, retry, history.

Results appear in a bottom sheet: equipment name, purpose, muscles, number of compatible exercises, suitability, **Open equipment**, alternatives and **"This is another machine"**.

For unknown items show the actual user photo, tentative name, description, uses, **"Content being prepared"**, and saved-card option. **Never silently substitute a close but wrong machine.**

## 10. Equipment page

Use a licensed, associated exercise hero image rather than arbitrary external stock imagery. Structure: cinematic hero, name/category, purpose, muscle groups, suitability badge, safety note, emphasized first recommended exercise, full exercise list, contextual AI Coach and Add to workout.

## 11. Exercise page

Media-first layout with anatomical animation, exercise title, primary/secondary muscles, level, equipment, recommendation rationale, three key technique steps, common mistakes, restrictions, past performance, AI Coach, Form Check and Start Exercise.

Expand complete instructions on demand. Form Check CTA is conditional on real exercise/model support.

## 12. Workout Player

Immersive active mode: large media, exercise position, set counter, elapsed time, previous performance, weight/reps inputs, optional RPE, notes, Form Check, replace/skip and guarded finish.

Main CTA **Complete set**. After saving: haptic signal, clear confirmation, **Undo**, automatic rest timer. Show historical sets in a bottom sheet rather than occupying the main screen.

## 13. Rest timer

Overlay or dedicated state with circular countdown, next target, **Ready sooner**, **+30 seconds**, pause, and completion haptic/notification where authorized.

## 14. Technique Coach / Live Form Check — complete module-design requirements

This is a connected end-to-end interaction, **not** just a camera preview button. Before counting reps, the user must know phone placement, facing angle, body visibility, lighting, readiness, whether a rep counted, the **single most important** current correction, and the set outcome. Implementation capability requires separate current ML and sport-science verification.

### 14.1 Problems in the old screen

Use the actual previous screenshot to document: raw developer string `pose[pixels]...` exposed in UI; low-hierarchy technical text cards; no dominant rep counter; unclear quality gates; simultaneous instructions; setup guidance not distinct from live cues; ambiguous skeleton/overlays; flash/voice controls without clear states/labels; privacy notice competing with coaching mid-set.

Retain the useful ideas: real camera, angle silhouette, skeleton/keypoints, low-light/blur warning, optional voice and **on-device privacy copy only when the real app proves it**.

### 14.2 Contextual entry points

Exercise Page "Check technique", current exercise in Workout Player, optionally workout setup before the first working set.

Never create an unscoped generic camera feature. **Exercise ID, supported view and available detection type** must be known before launch.

### 14.3 Precheck/setup

Show exercise name, poster/reference frame, required **front / side / 45-degree** angle, phone placement and distance, required visible body regions, short honest privacy note and **Open camera** CTA.

Historical example: "Turn sideways. Place your phone around hip height and stand 2–3 meters away so your full body is visible." Such distances are example design copy, **not universal exercise requirements**.

Secondary options: "Why this angle?" / "I can't position my phone that way."

### 14.4 Live camera composition

Header **Technique Coach**, Back, flash, sound/TTS and optional Help. Camera should occupy **60–70%** of the available height before keyboard/sheets. Overlays: angle-specific silhouette, keypoints, connected skeleton, highlighted segments, safe-frame boundaries, quality banner and compact rep counter when analysis begins.

Do **not** display raw landmarks, pixel values, model confidence dumps, rule IDs, developer logs or internal classifier names.

### 14.5 Quality gates before counting

Distinct states: initializing; too dark; blurred; too close; too far; incomplete body; missing required joints; wrong angle; **multiple people in frame**; pose found/calibrating; ready.

Show short actionable messages, e.g. add light, steady/clean lens, move back, turn sideways, show feet, or ready to move.

**Before required gates pass: no rep counting, no form score, no positive/negative technique assessment.**

### 14.6 Ready state

After calibration show "Pose detected", "Start moving", **0 reps**, optional 3-second countdown and pause/exit. Auto-start only if reliably and safely implemented; otherwise explicit **Start set**.

### 14.7 Active coaching

Show dominant rep count, movement phase (up/down/hold), **one** live corrective cue, short reliability status and pause/finish.

Example cues: go slightly deeper, knees in line with feet, neutral spine, slow at bottom, rep could not be evaluated. Never present unsupported cues as measured facts.

Skeleton semantics: **neutral** joint visible/not evaluated; **green** within supported range; **amber** correction suggested; **red** current error; **grey/dashed** lost landmark. Always pair color with text/symbol.

### 14.8 Pose loss mid-set

Pause evaluation, do not increment count or accept partial rep, show a short recovery instruction, resume only after required gates recover if safe. Distinct examples: body missing, return to target frame, too dark, camera angle changed, rep not evaluated.

### 14.9 Voice guidance

Voice toggle in header. Displayed and spoken text use **the same localized phrase**. Do not overlap cues or repeat the same issue every second. Turning voice off retains visual cues; critical visibility loss should be communicated both visually and by voice when enabled.

### 14.10 Adaptive bottom panel

One status panel, not multiple verbose technical cards.

- **Before:** setup guidance, quality status, readiness checklist.
- **During:** reps, phase, one cue, pause/finish.

Show privacy explanation in precheck/help, not as a permanent obstructive card. "Analysis happens on-device, frames never leave the device" may appear **only if verified**. Otherwise mark this copy as a **pending Product Decision**, not an active promise.

### 14.11 End-of-set summary

Show counted reps, reliably evaluated reps, **unevaluable reps**, one/two strengths, at most one/two priority adjustments, and actions **Repeat set / Continue workout / View technique**.

Do not display a global score when many reps failed visibility/quality gates. Do not offer video replay unless real recording exists. Frame storage/recording requires a **separate opt-in and product/privacy decision**.

### 14.12 Required states

Create high-fidelity screens/variants for: unsupported exercise; angle selection; permission explanation; denied/permanently denied; unavailable camera; initialization; dark/blurred/too close/too far; partial body; missing joints; wrong angle; multiple people; calibration/ready/countdown; active counting; correct/warning/error cues; lost pose; paused; unevaluable rep; detector error; thermal/performance warning; completed; insufficient-data summary.

### 14.13 Named Figma components

Include exact source component names:

`TechniqueCoachCameraFrame`, `ExerciseAngleGuide`, `PoseSkeletonOverlay`, `PoseSegmentState`, `QualityGateBanner`, `CalibrationIndicator`, `LiveRepCounter`, `MovementPhaseIndicator`, `LiveCueCard`, `TechniqueCoachStatusPanel`, `VoiceCueToggle`, `FormCheckSummaryCard`.

Variants, where applicable: default, active, warning, error, disabled, loading and accessible.

### 14.14 Accessibility

No color-only skeleton meaning; speak/label readiness and pose loss; **48px+ controls**; captions for TTS; ability to disable animation/voice; high-contrast overlay; large usable pause/finish controls; landscape and portrait states; support long Russian strings without blocking the camera.

### 14.15 Clickable Technique Coach prototype

`Exercise Page → Check technique → Precheck → Camera permission → Low light → Correct light → Wrong angle → Correct angle → Calibration → Ready → First rep → Live cue → Pose lost → Pose restored → Complete set → Technique summary → Return to Workout Player`.

## 15. Workout Summary

Show duration, exercises, sets, training volume, records, perceived effort, measured form highlights (only if available), recovery impact (only if measured), and next workout. Do not reduce this to meaningless gamification.

## 16. Progress

Ten views: summary, consistency, volume, key exercise progress, goal progress, muscle load/recovery, measurements, Progress Photos, achievements and history.

Use recovery labels **High / Medium / Low / Insufficient data** where supported. Each chart answers a concrete user question rather than displaying a number for decoration.

## 17. Progress Photos

Core flow: **Progress → Progress Photos → Gallery → Compare → Export**, not Profile/onboarding.

### 17.1–17.2 Empty and privacy

Empty-state explanation, **Add first photo** CTA and privacy note. Before first save explain that photos are personal, not automatically published, and export is user-controlled. **Do not promise an unverified storage policy.**

### 17.3 Capture

Front/side/back/free angles; silhouette; full-screen camera; grid; **3/5/10-second timer**; flash/camera switch; preview/retake/save; optional date, weight, note, milestone.

### 17.4 Gallery

Chronological timeline with thumbnail, date, angle, optional weight, note, milestone, filters, multi-select, editing, deleting and comparing.

### 17.5 Compare

Side-by-side and interactive slider; swap, reselect, hide weight/date, fit/fill and reset. Manual zoom, x/y offsets, rotation and reset. **No body morphing**.

### 17.6 Export

**Always preview before share**. Optional hide weight/date, face blur, watermark, background, save/share. **Weight hidden by default.**

### 17.7–17.8 Home and reminder

Home card only with **two compatible photos**, below workout/scanner priority. After first save, optional 2/4/8-week reminder or no reminder.

**Prohibited:** body score, photo-estimated body-fat %, attractiveness score, medical conclusions, automatic posting and fabricated AI body assessment.

See the more detailed, separately translated [Progress Photo Comparison brief](https://github.com/xLZDx/ReviewExistingExamples/blob/docs/add-english-readme-20261010/src/imports/pasted_text/progress-photo-compare.en.md).

## 18. Workout library and programs

Filters: goal, level, location, equipment, duration, muscles, physical limitations, return after a break and short workouts. Do **not** make Men/Women the primary categorization.

Program card: poster, title, weeks, days/week, duration, level, equipment, goal and honest suitability label.

## 19. AI Coach

Open contextual AI from equipment, exercise, workout, summary, recovery and plan, not a standalone answer engine without context.

Answer structure: **short answer → reason → personal context → practical next action → expandable details**. Include suggestion chips. Do not position AI as a medical doctor.

## 20. Profile, Settings and Subscription

Profile includes personal data, goals, units, integrations, notifications, privacy, subscription and help.

A paywall appears **only after preview or demonstrated value**, with transparent free/premium comparison, monthly/yearly pricing, trial, billing date, cancellation and restore purchase. No fake countdown or false discount.

## 21. Design System

Build semantic Figma Variables and components.

### Source color-token names

`backgroundPrimary`, `backgroundSecondary`, `surfacePrimary`, `surfaceElevated`, `surfaceInteractive`, `textPrimary`, `textSecondary`, `textDisabled`, `accentPrimary`, `accentSecondary`, `success`, `warning`, `danger`, `outline`, `cameraOverlay`, `poseCorrect`, `poseWarning`, `poseError`.

### Typography

Display, H1/H2/H3, Title, Body, Body Small, Label, Caption, Numeric Large and Numeric Medium.

### Spacing and radius

Spacing: **4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48**.  
Radius: **8 / 12 / 16 / 20 / 24 / Full**.

### Source component families

Buttons, icon buttons, navigation, top bars, choices, chips, recommendation hero, media cards, `BodyMetricPicker`, set logger, rest timer, camera overlay, recognition sheet, `TechniqueCoachCameraFrame`, `ExerciseAngleGuide`, `PoseSkeletonOverlay`, `QualityGateBanner`, `LiveRepCounter`, `MovementPhaseIndicator`, `LiveCueCard`, `TechniqueCoachStatusPanel`, `FormCheckSummaryCard`, AI insight, progress cards, progress-photo timeline, comparison slider, and standard empty/loading/error/permission states.

For each component where applicable: default, pressed, focused, selected, disabled, loading, error, success.

## 22. Accessibility

Touch targets **44–48px minimum** as platform-appropriate, WCAG AA contrast, Dynamic Type, scale variants **1.0 / 1.3 / 1.6 / 2.0**, screen-reader order, visible focus, no color-only meaning, reduced motion, long Russian strings, one-handed use, drag alternatives and safe-area behavior. Technique Coach's **48px+** specific requirement is not weakened by the general range.

## 23. Android and iOS adaptation

Android: Material 3 interaction behaviors, predictive back, edge-to-edge, permissions and standard bottom sheets.

iOS: safe areas, swipe back, native modal behavior, Dynamic Type and platform permissions.

**One brand system with platform-native conventions**, not two unrelated products.

## 24. Motion

Use **150–250ms** control feedback, **250–400ms** transitions, fade-through, shared-axis, bottom sheet, scan result, saved-set acknowledgment, rest countdown, skeleton-to-content transitions; include reduced-motion equivalents.

## 25. Standard states for every feature

Loading, empty, partial data, stale data, retryable error, terminal error, offline, permission denied, permission permanently denied, unavailable hardware, interrupted flow.

## 26. Figma file structure (source ordering preserved)

`00 Cover`  
`01 Research & Reference Analysis`  
`02 Current UI Audit`  
`03 UX Principles`  
`04 Information Architecture`  
`05 User Flows`  
`06 Moodboards`  
`07 Visual Directions`  
`08 Final Design System`  
`09 Components`  
`10 Onboarding`  
`11 Body Metrics`  
`12 Home`  
`13 Scanner`  
`14 Equipment`  
`15 Exercise`  
`16 Workout Player`  
`17 Technique Coach / Form Check`  
`18 Workout Summary`  
`19 Progress`  
`20 Progress Photos`  
`21 Programs`  
`22 AI Coach`  
`23 Profile & Settings`  
`24 Subscription`  
`25 States`  
`26 Android Adaptations`  
`27 iOS Adaptations`  
`28 Light Theme`  
`29 Dark Theme`  
`30 Interactive Prototype`  
`31 Before / After`  
`32 Developer Handoff`  
`33 Product Decisions`.

## 27. Clickable end-to-end prototype

`First launch → Onboarding → Body Metrics → Generating → Plan Preview → Account → Home → Scan → Recognition Result → Equipment → Exercise → Workout Player → Complete Set → Rest Timer → Technique Coach Setup → Live Form Check → Technique Summary → Workout Summary → Progress → Add first photo → Add second photo → Compare → Export Preview → Updated Home`.

Also demonstrate key failure, empty, offline and permission paths.

## 28. Design gates and review stop

Do not design all gates concurrently without review.

- **D1:** Research, existing audit, IA, design direction
- **D2:** Onboarding and Body Metrics
- **D3:** Home and Navigation
- **D4:** Scanner and Equipment
- **D5:** Exercise and Workout Player
- **D6:** Technique Coach setup, quality gates, live Form Check and summary
- **D7:** Progress and Progress Photos
- **D8:** Programs, AI Coach, Profile and Subscription
- **D9:** States, accessibility, platform adaptations and final prototype

**After every gate**, show screens, state variants, design rationale and unresolved product decisions. **STOP for review**. Do not interpret this translation request as a waiver of the original gate process.

## 29. Definition of Done

The source's **17** criteria are:

1. Home is no longer a grid of identical tiles.
2. Users understand the next action.
3. Scanner visually communicates the differentiated product function.
4. Plan preview appears before account/paywall.
5. Body metrics use usable pickers and truthful non-diagnostic copy.
6. Set logging works comfortably with one hand.
7. Technique Coach includes setup, quality gates, rep counter and cues, and refuses to assess movement without sufficient visibility.
8. Progress interprets actual collected data.
9. Progress Photos are private and have a full comparison flow.
10. AI is contextual rather than a generic chat.
11. Light/dark are full systems, not filter modes.
12. Android/iOS platform adaptations are documented.
13. Accessibility states exist.
14. All core empty/loading/error/permission states exist.
15. End-to-end interactive prototype is navigable.
16. Developer handoff includes tokens, dimensions, states and interactions.
17. No fabricated features or metrics are shown.

**Original instruction:** Start with **Design Gate D1**, provide its result and **STOP**. Do not infer the original owner approved starting D2–D9.

---

# Appended UPDATE v1.3 — Internal Decision Registry / Open Questions Governance

This update belongs to the imported master prompt and must not be confused with a deployed customer-facing screen. Build an **internal Research/Architecture prototype tab** to support Product, Design, Engineering, Privacy, Legal and Sport Science decisions.

## Location and count

Add a fourth tab **"Decisions · 44"** alongside the existing Analysis, Architecture and System tabs. In the original prototype it used a Russian label; the label here is an **English translation for reference**, not an automatic app locale change.

Show a compact summary:

| Metric | Historical requested count |
| --- | ---: |
| Total decisions | **44** |
| Debt from previously completed gates | **22** |
| Questions blocking/associated with D6 | **8** |
| Future D8–D9 decisions | **14** |
| Critical contradictions | **4** |

**The previous 26/8/10 summary was inconsistent** and must not be reused. Avoid displaying all 44 entries as giant cards.

## Filters, statuses and rows

Filters: **Gate D1–D9**, status, owner, priority, blocking/nonblocking, and Product/UX/Design/Tech/Privacy/Legal/Sport Science.

Source statuses: **Open**, **Needs Research**, **Needs Product Decision**, **Needs Technical Decision**, **Blocker**, **Decided**, **Deferred**, **Locked by Existing Architecture**.

Each compact row shows question ID, gate, short title, owner, status, priority, blocker badge and required-before/deadline.

The detail drawer contains the complete question, background/rationale, alternatives, provisional recommendation (if any), owner, dependencies, affected screens/services, deadline, final decision (when actually made), rationale, decision date and Figma/Git/ADR/code reference.

## Four required canonical corrections

1. **Q39:** Flutter is the existing locked architecture. Status **Locked by Existing Architecture**, value Flutter; do not offer React Native/native rewrite in this UI refactor.
2. **Q19:** Replace obsolete React Native+TFLite wording with the actual open choice: **real on-device ML in the existing Flutter stack vs demo prototype**.
3. **Q1/Q41:** They are **one light-theme product decision**. Retain both IDs for traceability, mark Q41 duplicate/continuation of Q1 and close both with one owner decision.
4. **Q4:** Describe genuine platform scope: Android health integration now, separate iOS integration later, or both real platform integrations in the same release. Never treat a fake iOS stub as equivalent to delivery.

## Gate-specific decision discipline

Do not block all design work until all 44 are resolved. Classify decisions as:

- Hard blocker of the **current** gate
- Soft decision with a safe **provisional** default
- Future decision
- Architecture locked
- Duplicate/merge needed

Create a visible D6 panel **"Must decide before continuing"** with true hard blockers:

**Q19** ML implementation scope; **Q20** first supported exercises; **Q21** exercise→angle/landmark matrix; **Q23** TTS architecture; **Q26** relationship to existing WorkoutDone/summary routing.

The source's permitted **provisional, not final** defaults:

- **Q22:** Summary metadata only; no saved video/frames until storage approved.
- **Q24:** App/system language for voice cues.
- **Q25:** Human-readable reliability label rather than raw confidence percentage.

See the [complete English 44-question register](OPEN_DECISIONS_REGISTER_v1.3.en.md) for all Q1–Q44 wordings and owners.

## Internal registry visual system and prototype

Preserve dark-premium internal governance styling: lime for active/resolved/selected, red **only** for blocker/conflict, amber for decisions needed, neutral for future/deferred, compact rows, sticky filters and no giant per-question cards.

Clickable path:

`Research → Decisions → Filter D6 → Open Q19 → Compare options → Mark provisional recommendation → Return → Filter Owner: Product → Open Q20`

Demonstrate conflict badge, duplicate badge, locked decision and one resolved item with rationale.

## Developer handoff boundary

Mark the screen clearly:

`INTERNAL DESIGN GOVERNANCE SCREEN`  
`NOT END-USER PRODUCT SCOPE`

The Decision Registry may remain Figma-only internal documentation; it is **not required in the production Flutter client**. Any real operational decision-management tool would be a separately scoped admin/internal project with its own authorization and tests.

## Translation, fidelity and safety notes

- The English text is source-linked, covers all 29 numbered sections and the full appended v1.3 update, and does **not** rewrite either original source copy.
- The prompt's eighteen supposed existing features, catalogue size of 1,887, camera Form Check and "on-device no-cloud" privacy text are **not verified in this repository during translation**. Treat as historical design premises until verified by the current product owner, implementation and source-of-truth contracts.
- BMI is informational rather than diagnosis; under-20 users must not receive adult BMI categorization. Progress-photo privacy requires real storage/access controls. No user camera, body photo or health data was processed or disclosed.
- Historic **D1 STOP-after-review** and D6 hard blockers remain operative *as source requirements*, not overwritten by this document.
- No actual Figma file, interactive prototype, React/Flutter UI, ML inference, released subscription, production app or independent reviewer signoff was produced by this translation.

**Document status: Complete source-structured English companion for review, not implemented or approved current design.**
