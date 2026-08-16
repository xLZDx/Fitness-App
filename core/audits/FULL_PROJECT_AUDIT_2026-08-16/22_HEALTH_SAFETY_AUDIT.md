# 22 - Health and injury safety

Reviewed by a clinical-safety reviewer working from `.claude/agents/clinical-safety-gate.md`. Every
load-bearing claim below was then re-opened and confirmed against the source by the orchestrator;
where that changed the reading, it says so.

## The eligibility layer is well built, and it fails in one direction

The person-level gate is **fail-closed** and unusually careful. PAR-Q+ screening refuses on
unanswered questions (`par_q.dart:216-220`), there is a real refusal state rather than an empty list
(`plan_builder.dart:46-47`, `programme_builder.dart:318-320`), and `EligibilityNotice`
(`eligibility_notice.dart:46-69`) names the question responsible and routes the user back to change
it. This is the part of the product that is best engineered, and it should not be touched.

## BLOCKER 1 - the exercise-level gate fails OPEN

`mobile/lib/features/equipment/data/exercise_filter.dart:38`, confirmed by direct read:

```dart
bool isContraindicated(ExerciseItem exercise, Iterable<Injury> injuries) {
  if (exercise.contraindications.isEmpty) return false;
```

An exercise carrying no contraindication tags is declared not contraindicated and is served. The
same direction holds for movement restrictions: `eligibility.dart:282-289` iterates
`exercise.contraindications`, so an empty list means the loop body never runs and none of the nine
`MovementRestriction` values can ever match.

**Measured against the shipped asset: 360 of 1,887 rows carry no contraindication tag.** 19.1% of
the catalogue cannot be withheld from anyone, by any injury or restriction, on any surface - while
the UI states the list was screened. Nothing on screen separates "checked and cleared" from "never
checked".

The intent is written down (`exercise_filter.dart:67-68`, "Exercises with no contraindication tags
are always kept"), so this is a deliberate default rather than an oversight. It is still the wrong
default for a safety filter, and the standing instruction on this project is that safety-related
ambiguity fails closed.

## BLOCKER 2 - no pregnancy path exists

Confirmed by direct read. `ParQQuestion` has seven values (`par_q.dart:52-85`); none concerns
pregnancy. `MovementRestriction` has nine values (`health_flags.dart:45-84`); none concerns
pregnancy. The catalogue tag vocabulary carries no pregnancy, trimester, pelvic, prone, supine or
Valsalva tag. Two tests use "pregnancy" specifically as an **invalid** value, proving it is dropped
(`profile_models_test.dart:129-134`, `eligibility_test.dart:360-368`).

**A fair reading of the intent:** `cycle_phase.dart:56-64` records a deliberate decision not to hold
a pregnancy status, on the ground that "splitting it into medical categories would make this app hold
a pregnancy status and reason about it, which is a different product with a different regulatory
position." That is a defensible privacy and regulatory choice, and the audit records it as such.

**The consequence is still unaddressed.** Declining to *store* the status is not the same as
declining to *generate a plan*. Today a pregnant or early-postpartum user is asked nothing, warned
about nothing, and receives a full unmodified programme including loaded spinal flexion and supine
work. The minimal fix respects the recorded decision: one self-reported question whose only
persisted value is a boolean "cycle-derived and general programming may not apply", routed to
`wholePersonBlocks` with a referral - exactly the shape `SurgeryStatus.underRestrictions` already
uses. That holds no medical category and reasons about nothing.

## CRITICAL - the chest-pain refusal carries no urgency

`par_q.dart:123-126` + `app_en.arb:2146`. A user reporting pain in the chest at rest is blocked, and
told "talk to a doctor or a qualified exercise professional first" - the same routine wording used
for every other blocking answer. On non-onboarding surfaces they see only "No sessions right now".

## HIGH - surfaces that skip part of the gate

| Surface | Gap | Evidence |
|---|---|---|
| Programme enrolment, spec-less templates | no `SafetyContext` at all | `programme_providers.dart:199-206` |
| Equipment / scanner detail page | injury filter only, no whole-person gate | `equipment_detail_page.dart:31,322` |
| Train-tab chips other than "For you" | injury only, no movement restrictions | `workouts_page.dart:164-200` |
| Player "add exercise" picker | injury only | `workout_player_page.dart:798` |
| `ai::` rows | excluded only when `hasInjuries`, never for restriction-only profiles | `equipment_providers.dart:481-482` |

## HIGH - the honesty disclosure disarms at one tagged row

`safety_coverage_providers.dart:66-69` gates on `(byRegion[r] ?? 0) > 0`. A single tagged row for a
region flips the claim from "not screened" to "screened by rules" for every user with that injury.
Worse, the one honest string - `safetyFilterCoverage`, "X of Y exercises are tagged" - **exists in
both locales and is rendered nowhere.** Confirmed: `grep safetyFilterCoverage mobile/lib/` returns
only the two `.arb` definitions. Its tests assert the key exists, not that it is shown.

## What is genuinely strong

- **No health free text ever reaches an LLM.** All three prompt builders
  (`ai_coach_context.dart:97`, `ai_exercise_generator.dart:71`, `gemini_equipment_service.dart:118`)
  carry subject name, language and image bytes only. The refusal is written down, reasoned, and told
  to the user (`app_en.arb:2155`). This is the single best-executed decision in the product.
- Medication is captured as a PAR-Q+ boolean feeding an intensity ceiling, never classified.
- The refusal path names its reason and offers a route back.

## Collected and never read

Twelve health fields are stored and consumed by nothing: `conditions`, `allergies`, `medications`,
`physicalLimitations`, `recentSurgeries`, legacy `bloodPressure`, `otherConcerns`, `Injury.type`,
`Injury.note`, `smoking`, `alcohol`, and the dead getter `HealthFlags.blockedRegionTags`. They
persist to SharedPreferences unencrypted (`local_sensitive_store.dart:21-34`) and are included in
Android Auto Backup by choice (`:36-40`). Blood pressure is asked twice and only the second answer is
read.
