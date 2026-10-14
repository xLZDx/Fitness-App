# R11 — Implementation Plan From Operator Decisions (English Historical Translation)

**Original:** [R11 decision-response plan](PLAN_R11_DECISIONS_2026-08-12.md), exact Git blob `365deb5f85deff1f0734bcac7f855fd9db359d4c`.  
**Original date:** August 12, 2026.  
**Initial authority:** The original stated that **no sub-gate below was authorized yet**, and each required its own literal GO. Later sections record a completed P1 and changes to P4/P5; retain that dated progression rather than flattening to one status.

The operator answered six questions raised after gate `606a024`. This document captured the responses, code reconnaissance and subdivision into reviewable gates. It does **not** supersede `PLAN_REDESIGN_REMAINDER_2026-08-12.md`, which remained the separate outstanding-work map.

## Operator answers at the original checkpoint

| # | Topic | Recorded decision | Important qualification |
| --- | --- | --- | --- |
| 1 | Progress Photo privacy gate | **Do nothing** to the existing persistent strip | Permanent strip judged preferable to one-off card |
| 2 | Photo export | **Keep export forbidden** | "Photos never leave the phone" was part of the value proposition |
| 3 | Photo reminder | **Monthly** | Operator selected option "A" but explicitly **said monthly**, not every two weeks; words took precedence |
| 4 | Coach pause | Freeze rep count; **camera continues running** | Finish → summary and reset for new set |
| 5 | Onboarding | **Not option A**; keep existing seven steps initially, redesign step 2 with Figma | Later clarification changed the screen-placement interpretation |
| 6 | Birth year | Replace stored age; approximate migration `currentYear − age` | Same requirement as Figma `8`, item 10 |

**Do not interpret the table as new permission for today's application.** It is an exact historical owner-decision record.

## Conflict initially identified before P5

The initial Figma specification `8` (`LATEST_DEV_SINGLE_FILE_MASTER_PROMPT_EN.md:351-384`) listed **18 items** and also required **one primary question per screen**. The running onboarding had **seven** screens.

Keeping seven while following the spec literally looked inconsistent. The author adopted a **temporary interpretation for P1–P4, not approved final scope for P5**:

- Keep the **seven-screen structure** and merged questions.
- Adopt Figma **visual controls** — wheel/ruler pickers, anatomical diagram, choice cards.
- Thus do **not** enforce one question per screen for that existing design.

Under frozen structure, Figma-only entries like Value Proposition, Training Location, Schedule, Target Areas, Main Obstacle, Health Connect, Generating, Plan Preview, Account and notification permission would need to be integrated into seven screens, separately authorized or omitted.

**Later correction:** The prototype's `TOTAL_OB_STEPS = 9` referred to **nine screens**, while the spec's 18 entries were **content items**, not eighteen screens. The operator then instructed to use **Figma styling with the existing grouping** and resolved P5 into O-series work. Do not preserve the initial false 7-versus-18 interpretation as a final truth.

## Code reconnaissance — measured at the original snapshot

The running onboarding at `onboarding_page.dart:34-40` had seven screens: **Personal, Health, Goals, Level, Lifestyle, Equipment, Motivation**. The progress display used `_index + 1` over `_stepCount` at `:121`.

**Step 2 Health** contained **eight free text fields**, including injury items parsed from "body part: kind" separated by commas (`step_health.dart:63-82`). Entries without a colon were **silently discarded** by `.where((s) => s.contains(':'))` at `:72`. The prototype instead used `BodyDiagram` (`App.tsx:1443`) and `ChoiceCard` (`App.tsx:1218`).

**Step 1 Personal** combined age, gender, height, weight, BMI, weight goal/delta and activity level (`step_personal.dart:21-118`). R11b already provided some ruler controls, but not a birth-year wheel.

`age` reads touched a small surface: `profile_models.dart:205,213,223,230,238,545`, `firestore_profile_repository.dart:44`, `step_personal.dart:33,37` and `profile_page.dart:386`.

Existing `NotificationService` only scheduled `ScheduledSession` reminders via `scheduleReminder` and cancelled by session ID (`core/notifications/notification_service.dart:7-51`). A Progress Photo reminder was **not** a scheduled workout.

`RepSessionController._onFrame` (`:583`) was the single conversion point from frame to rep count, and `resetSet()` (`:775`) the one public reset mutator — an appropriate seam to pause counting.

## Gate breakdown and dated status corrections

The source split work for >2 hours, >=15 touched files or >=350 lines of specification into independently reviewable pieces.

### P1 — DONE on August 12 (the later status in this file)

1. **Privacy-strip and export** were closed by **decisions**, not new implementation: keep the persistent privacy strip (`progress_photos_page.dart:396-419`), and keep export forbidden (`local_progress_photos_repository.dart:68-72`).
2. A **monthly reminder** was implemented through a new general `NotificationService.scheduleAt(id, fireAt, ...)` method. `scheduleReminder` was built on top so expiry/cancel logic had one implementation. Saving a photo used a single `kProgressPhotoReminderId`, rescheduling that one reminder instead of stacking many.
3. The UI explained the reminder **before** requesting notification permission and only if notifications were enabled, avoiding a promise it could not honor.

An implementation detail: two test doubles used Dart `implements`, so adding the interface method required updates to **both** mocks — method bodies were not inherited.

### P1 — original design proposal, preserved for provenance

The earlier proposal was to close privacy/export through `PLAN_REDESIGN_REMAINDER_2026-08-12.md` and `DECISION_LOG.md` rather than writing a new privacy gate, and to support a monthly reminder at photo-save time (+30 days) without another Settings toggle. Existing `settings.notifications_enabled` should govern the reminder.

The later implemented `scheduleAt` approach supersedes the earlier proposal. This section is **not** evidence that photo export had been enabled.

### P2 — Form Coach active/paused/summary

The phases existed at `coach_phase_providers.dart` but were not yet wired.

1. `paused` blocks counting through **one phase-based guard** in `RepSessionController._onFrame`; do not create a second controlling boolean.
2. Keep camera and detector running (`_openCamera`, `_startDetector`), per original operator choice.
3. `finish()` → `summary`, show real set results using existing `_SetSummaryCard`, **New set** action → `resetSet()` + `active`.
4. Provide pause/resume/finish controls above the preview.

**Risk: MEDIUM**, because the actual rep counter changes. A test must send frames **while paused** and show the rep count does **not** grow — repainting a Pause button is insufficient.

**Excluded:** Calibration. No trustworthy "detector stabilized" signal existed; requiring N consecutive valid frames would need a separate design after P2.

### P3 — Birth year instead of stored age

Add `ProfilePersonal.birthYear`; calculate `age` for existing readers. Migrate at `firestore_profile_repository.dart:44` via `birthYear ??= currentYear − age`. Add an accessible `WheelYear` control with direct entry, plus/minus and haptics if `HapticFeedback` exists. Replace the numerical age input in `step_personal.dart`.

**Data risk: MEDIUM**. This is an approximate migration, **±1 year** because birth month was unknown. Explain the approximation in the first UI visit.

The later O-series plan **absorbed P3 into O8**, so do not build P3 again as an independent gate.

### P4 — CANCELLED by the operator

Initial P4 would replace the eight-field Health step with Figma `BodyDiagram` and `ChoiceCard`. The operator, once told that "step 2" was the current Health page, explicitly instructed **not to change that convenient screen**.

P4 was recorded as a **cancelled** design direction, not simply uncompleted work.

The original ambiguity "make step 2 like Figma" remained; a plausible interpretation was the combined Personal screen, to be addressed through P3. **Do not silently invent an owner decision.**

### P4-lite — silent loss of injury data, survives P4 cancellation

`step_health.dart:72` filtered injury strings without a colon. A user could type "my knee hurts" and see a filled field, but nothing reached the profile. **Proposed fix:** retain an unparsed injury with an empty type rather than discard it. No visual redesign required.

**Honesty restriction:** This did **not** immediately improve safety; `exercise_filter.dart` filtered **zero out of 1,887** exercises at the source checkpoint because the catalogue lacked actual contraindication tags. Preserving data makes it available later, but **must not** be sold as "now safer."

**Risk: LOW**, one parser function and tests.

### P5 — replaced with O-series after new owner screenshots

The owner supplied actual Figma flow screenshots, clarifying **"Figma visual design; keep our logical grouping"**.

The source corrected the earlier 7-vs-18 confusion: Figma `8` enumerated **18 content areas**, but `App.tsx:2387-2409` implemented **nine prototype steps** (`TOTAL_OB_STEPS = 9` at `:1202`). The implementation already combined many questions, so the literal one-question-per-screen language was not an accurate description of the prototype.

#### Target seven-screen grouping

| Figma step | Intended content | Existing source counterpart |
| --- | --- | --- |
| 1/9 | Main goal + level | Existing Goals and Level steps **combined**, as owner requested |
| 2/9 | Location + equipment | Equipment step plus new location question |
| 3/9 | Schedule | New |
| 4/9 | Body limitations/priorities | Existing Health content moved into a disclosure area |
| 5/9 | Barriers | Partly Motivation |
| 6/9 and 7/9 | Birth year + height and weight/target | **Combined About You** with existing gender/activity |
| 8/9 | Health Connect | New/choice needed at this checkpoint |
| 9 outside screen count | Generation, Plan Preview, Account | New, dependent on a real generator |

**The intended result was seven screens**, Figma styling with approved grouping.

#### Health details under the body diagram

The owner requested an **Additional Information** expandable block under limitations within step 4/9, retaining the original Health step's full free-text controls: conditions, allergies, medicines, injuries, restrictions, surgery, blood pressure and other concerns.

This reconciled "current Health screen is useful; don't rewrite it" with visual relocation. Data and free-form entry behavior should remain unchanged even if shown under a disclosure.

#### Missing from Figma but present in the app

- **Gender**: `missingBodyAnswersProvider` required it for the Form Coach silhouette; keep it on About You.
- **Lifestyle** (diet/smoking/alcohol): No approved placement in Figma. Possible second disclosure, eighth screen, or Profile only. **Owner decision still required.**

## O-series sub-gates replacing P5

### O0 — Schema proposal and STOP

The spec expressly demanded a minimal schema document and STOP when fields were missing. New concepts included `location`, available `equipment`, `daysPerWeek`, `sessionDuration`, `preferredDays`, `focusZones`, `barriers` and `birthYear`, potentially affecting `profile_models.dart`, `questionnaire_notifier.dart`, `firestore_profile_repository.dart` and rules.

**O0 output is documentation, zero code. Further implementation requires GO.** See [O0 English source-bound companion](O0_ONBOARDING_SCHEMA_2026-08-12.en.md).

### O1 — Figma onboarding shell

Progress indicator, back control, section titles, selectable cards, chips, lime primary action and optional skip. Source aimed to restyle existing seven screens without changing sequence. Risk LOW.

### O2 — Screen order and resumable draft

Move seven screens into new order, preserve onboarding draft and allow return. High risk due to navigation; resumability tests mandatory.

### O3–O7 — Individual functional screens

- O3: Goal + level (1/9)
- O4: Location + equipment (2/9)
- O5: Schedule (3/9)
- O6: Body (4/9) with map, tabs, two chip grids and **Additional Information** free-text disclosure
- O7: Barriers (5/9)

O6 was the largest design scope, with body map, limitations vs priorities and the retained medical questionnaire.

### O8 — Combined About You and P3

Merge Figma 6/9 + 7/9 with birth year wheel `9.1`, migration `year = currentYear − age`, height, weight/goal, gender and activity.

### O9 — Health Connect, undecided in this original document

At that point only `HealthService` interface existed, not real Health Connect. Options: honest unavailable state, separately approved integration, or remove onboarding step.

**Historical update and precedence:** The later [O-series resume report](RESUME_O_SERIES_2026-08-12.en.md) records that the operator subsequently **SKIPPED O9** and reserved device integrations for another gate. Do not read the earlier open question as still unresolved at the later checkpoint.

### O10 — Real generation, preview and account

No fake plan-generator progress or guaranteed goal forecast (`:382-383`). Preview must use a **real generator**, not a fixture (`:388`). Verify actual capability before building a UI; if missing, report a genuine product dependency.

## Explicit exclusions from this R11 plan

- **Real-device testing** of distributed APK `1.0.0 (2360)` at commit `606a024`, including whether front-facing camera preview was mirrored, required the actual authorized operator phone. The source recorded the intended distribution recipient; no address is recopied here.
- `compileSdk` 35 versus 36 was a separate Android build-configuration gate.
- `F3` remained after R11 gates.
- Paywall was **HELD** until actual pricing choices.

## Approval and source chronology

This record includes an early statement that each P gate required a literal GO; later sections report P1 completed, P4 cancelled, P5 replaced with O-series, and O9 later skipped in a separate August 12 checkpoint. These distinctions are **historical evidence**, not a new present-day authorization.

The source's complete original operator quotation remains in the unchanged Russian record. No Figma routes, private user health fields, Firestore rules, subscriptions, app code, phone, tests, commit or remote push were changed by the English translation.

**Status: FULL ENGLISH HISTORICAL R11 DECISION PLAN FOR INDEPENDENT SEMANTIC REVIEW; NOT AN EXECUTABLE OR CURRENT GO.**
