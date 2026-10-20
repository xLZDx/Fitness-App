# Fitness App — Open Decisions Register v1.3 (English Companion)

> **Fitness-App local translation adoption:** The local source `docs/Redisign/OPEN_DECISIONS_REGISTER_v1.3.md` has exactly the same Git blob SHA `b39a24ae56d569e764388a701c17c50a2b51c26c` as the originally translated source in `ReviewExistingExamples`. This English copy is historical documentary text, **not a current accepted product implementation, production UI locale or release decision**. No original file was changed.

**Original:** [OPEN_DECISIONS_REGISTER_v1.3.md](OPEN_DECISIONS_REGISTER_v1.3.md), Git blob `b39a24ae56d569e764388a701c17c50a2b51c26c`. [Duplicate source](https://github.com/xLZDx/ReviewExistingExamples/blob/docs/add-english-readme-20261010/src/imports/OPEN_DECISIONS_REGISTER_v1.3-1.md) has the same blob. This is an English translation of all 44 **historical** decision questions; it neither closes them nor changes their status, priority or owner.

## Corrected original counts

| Category | Decisions |
| --- | ---: |
| Debt carried forward from completed D1–D5 and D7 gates | 22 |
| D6 questions/blockers | 8 |
| Planned D8–D9 decisions | 14 |
| **Total** | **44** |

The original explained that an earlier count of **26 / 8 / 10** did not agree with the real gate distribution. The corrected categorization is **22 / 8 / 14**. Do not use these categories as evidence that the decisions themselves are all resolved.

## Required normalization (unchanged)

- **Q39:** `LOCKED — Flutter`.
- **Q19:** Replace older React Native phrasing with the current **Flutter / on-device ML** versus **demo prototype** question.
- **Q1 and Q41:** One light-theme decision, duplicated/continued in the later gate.
- **Q4:** Scope of platform health integration; do not describe an imaginary iOS integration as an already existing stub.

## D1 — Research, Audit, Information Architecture and Design System

| ID | Open question — English | Options | Owner | Note |
| --- | --- | --- | --- | --- |
| Q1 | Light theme: a complete theme system or only key screens? | Full D9 / 3–5 screens / Post-launch | Product + Design | Duplicate linked to Q41 |
| Q2 | Developer handoff: a separate screen inside the prototype, or only Figma annotations? | Prototype screen / Figma-only | Product | Internal process decision; not a UX launch blocker |
| Q3 | Token naming: finalize the vocabulary before D9? | Approve now / Refactor in D9 | Design + Dev | Not silently resolved |

## D2 — Onboarding and Body Metrics

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q4 | Which platforms are included in health integration? | Android now / Android plus separate iOS integration in the same release / Defer platform integration | Dev + Product |
| Q5 | Mandatory steps: which metrics belong in onboarding versus the user profile? | Goal + level minimum / All 13 | UX + Product |
| Q6 | Show BMI, or only weight and goal? | Hide / Show neutrally | Product |
| Q7 | Can onboarding be skipped entirely, or must at least three steps be completed? | Full skip / Minimum 3 / No skip | Product |

## D3 — Home and Navigation

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q8 | Calculate the recovery score on-device or on the backend? | Approximate on-device / Backend | Tech + Product |
| Q9 | When should a photo card appear on Home? | After two or more compatible photos / Only on milestones | UX |
| Q10 | Is a separate header adaptation required for the notch / Dynamic Island? | Native adaptation / Safe area sufficient | Dev |

## D4 — Scanner and Equipment

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q11 | What is the offline equipment catalog scope? | Top 50 / Top 200 / Full | Product + Dev |
| Q12 | Should unknown equipment be submitted for ML improvement? | Only with explicit consent / Local only | Privacy + Tech |
| Q13 | What is the fallback for unknown equipment? | Search / No fallback / Photo + ticket | UX |
| Q14 | Equipment detail presentation: full screen or bottom sheet? | Full page / Bottom sheet | UX |

## D5 — Exercise and Workout Player

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q15 | When should an automatic progression recommendation appear? | Immediately after +5% record / After two workouts / Never | Product |
| Q16 | Rest timer sound enabled by default? | On / Off | UX |
| Q17 | When should supersets and drop sets be supported? | MVP / D8 / Post-launch | Product |
| Q18 | Preserve an exercise substitution marker in workout history? | Save marker / No marker | Product |

## D6 — Technique Coach and Workout Summary

| ID | Question | Options / required artifact | Owner | Historical status |
| --- | --- | --- | --- | --- |
| Q19 | Form Check ML: what is the first implementation? | Real on-device ML in the current Flutter stack / Demo prototype | Tech + Product | **HARD BLOCKER** |
| Q20 | Which exercises are supported in the first release? | Top 5 / Top 15 / Entire library | Product | **HARD BLOCKER** |
| Q21 | Which camera angles and landmarks are supported per exercise? | Required matrix: exercise → side/front/45-degree → required landmarks | Sport Science | **HARD BLOCKER** |
| Q22 | Should Form Check history be recorded in the workout log? | Summary linked to workout / Session-only | Product | Provisional: **summary metadata only**, not frames/video |
| Q23 | How are voice cues generated? | On-device TTS / Pre-recorded files | Dev | **HARD BLOCKER** |
| Q24 | Which language is used for voice cues? | Russian only / Russian + English / Device/app system locale | Product | Provisional: app/system locale |
| Q25 | Show raw model confidence as a percentage? | Raw percent / Hide raw value | UX | Provisional: reliability label, **no raw percent** |
| Q26 | How does Workout Summary relate to the existing navigation route? | Replace existing WorkoutDone / Additional screen after it | Dev | **HARD BLOCKER** |

Provisional defaults are **not signed decisions**. Q19, Q20, Q21, Q23 and Q26 remain labeled as hard blockers in this source.

## D7 — Progress and Progress Photos

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q27 | Where are progress photos stored? | Local-only MVP / Cloud opt-in / Cloud by default | Privacy + Tech |
| Q28 | Anonymize faces before photo export? | Optional / On by default / Not included | Privacy + UX |
| Q29 | Which milestone tags are supported? | Standard only / Standard + custom | UX |
| Q30 | May photos from different camera angles be compared? | Block / Warn and allow | UX |

## D8 — Programs, AI Coach, Profile and Subscription

| ID | Question | Options | Owner |
| --- | --- | --- | --- |
| Q31 | When does the paywall appear? | After Plan Preview / At a usage limit | Product |
| Q32 | What are the free-tier limits? | Proposed counts / Different counts | Product |
| Q33 | How broad is AI Coach scope? | Workout-only / Global contextual | Product |
| Q34 | What technology powers AI Coach? | Contextual API / Rules / Custom model | Tech |
| Q35 | Available subscription periods? | Month + year / Also quarter | Product |
| Q36 | Family subscription? | No / Post-launch / D8 | Product |
| Q37 | Profile data export in MVP? | MVP / Post-launch | Legal + Product |
| Q38 | Garmin/Polar integrations? | D8 / Post-launch | Product |

## D9 — States, Accessibility, Platform and Prototype

| ID | Question | Options | Owner | Historical status |
| --- | --- | --- | --- | --- |
| Q39 | Which mobile implementation stack? | **Flutter** | Architecture | **LOCKED by existing architecture**; React Native/native rewrite out of scope |
| Q40 | What are the minimum OS versions? | Android 10+/iOS 16+ / Android 8+/iOS 15+ | Dev | Open |
| Q41 | When should the light theme ship? | D9 / Post-launch / System-only | Product | Duplicate/continuation of Q1 |
| Q42 | How broadly should reduced motion be supported? | Full alternatives / Critical paths only | Dev + Design | Open |
| Q43 | What is the offline mode scope? | Workout only / Home + Workout + Progress | Tech + Product | Open |
| Q44 | What kinds of push notifications are supported? | Workout only / Workout + photos + records | Product | Open |

## Governance and translation boundaries

- The 44 question identifiers and the owner/option sets are preserved in full. No unresolved question was automatically answered by translating a heading.
- The Q19 Flutter/on-device ML correction does **not** establish that a current real Form Check model exists or works.
- Q39 is the only specifically locked implementation-stack decision described here; the Q1/Q41 duplicate must not be counted as two separate approved choices.
- Privacy, medical/fitness language, media storage and subscriptions require their respective independent acceptance/consent gates.
- The original imported files are immutable source evidence. This English document is **not** a current product requirements rebaseline or proof of implemented features.

**Review status:** Complete English question register for documentary review — not a stakeholder signoff or release gate.
