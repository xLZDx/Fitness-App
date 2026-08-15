# Recommendation Engine v1.1 — exact implementation map

## Design rule

Existing durable models/repositories stay authoritative. The new engine is a domain
layer, not a replacement backend.

## New feature boundary

Proposed directory:

```text
mobile/lib/features/recommendation/
  data/
    recommendation_context.dart
    recommendation_result.dart
    recommendation_reason.dart
    safety_verdict.dart
    safety_gate.dart
    exercise_eligibility.dart
    exercise_ranker.dart
    prescription.dart
    prescription_engine.dart
    load_prescription.dart
    load_engine.dart
    progression_decision.dart
    progression_engine.dart
    substitution_engine.dart
    recommendation_validator.dart
    recommendation_policy.dart
  state/
    recommendation_providers.dart
```

No route and no new state-management framework.

## Existing file mapping

### KEEP

`mobile/lib/features/profile/data/profile_models.dart`
- Keep `UserProfile`, `HealthHistory`, `FitnessGoals`, `FitnessLevel`,
  `EquipmentAccess`, `TrainingSchedule`.
- Do not duplicate them inside Recommendation Engine.

`mobile/lib/features/profile/state/profile_providers.dart`
- Keep as source of the merged profile.

`mobile/lib/features/equipment/state/equipment_providers.dart`
- Keep `screeningProfileProvider`.
- Keep raw catalog private.
- Keep `safeCatalogProvider` as an injury defence-in-depth layer.
- Keep scanner-specific equipment feeds.

`mobile/lib/features/equipment/data/exercise_filter.dart`
- Keep `filterContraindicated`, `safeFor`, `availableWith`,
  `focusZoneMuscles`.
- Recommendation eligibility calls these instead of reimplementing them.

`mobile/lib/features/programmes/data/programme.dart`
`mobile/lib/features/programmes/data/programme_repository.dart`
`mobile/lib/features/programmes/state/programme_providers.dart`
- Keep programme persistence and lifecycle.
- Replace only the decision inputs that choose and prescribe content.

`mobile/lib/features/workouts/data/workout_session.dart`
`mobile/lib/features/workouts/data/workout_session_repository.dart`
- Keep canonical session entity/repository.
- Extend additively for richer performed-set context.

`mobile/lib/features/visual_equipment/data/scan_outcome.dart`
`mobile/lib/features/visual_equipment/data/visual_equipment_match.dart`
- Keep uncertainty/source semantics.

`mobile/lib/features/form_check/data/pose_gate.dart`
- Keep visibility/confidence gating.

### EXTEND

`mobile/lib/features/workouts/data/scheduled_session.dart`
- Add an optional prescription snapshot keyed per exercise, or a similarly
  additive plan field.
- Old documents must parse exactly as today.
- Do not overload `durationMinutes` as training volume.

`mobile/lib/features/workouts/data/set_capture.dart`
- Evolve from a 2-field record into a backwards-compatible performed-set model
  in a dedicated migration gate.
- Required future optional fields:
  - weightKg
  - reps
  - rir or rpe
  - setType
  - prescribedSetIndex
- Keep canonical kg storage.

`WorkoutSessionExercise`
- Add optional snapshots:
  - equipmentId
  - loadContextKey
  - prescriptionId / recommendationId
- Old documents remain valid.

`mobile/lib/core/health/state/health_providers.dart`
- Add a longer-window provider only when recovery policy needs it.
- Preserve permissions and missing-data states.

### REPLACE AS DECISION-MAKERS

`mobile/lib/features/workouts/data/progression.dart`
- Replace policy internals with an adapter to `ProgressionEngine`.
- During migration, preserve the old public call only as a compatibility shell.
- Remove free-form English `reason`; return reason codes/localized UI.

`mobile/lib/features/home/data/suggestion_builder.dart`
- Keep `WorkoutSuggestion` UI shape temporarily.
- Replace selection/ranking internals with Recommendation Engine output.

`mobile/lib/features/personalisation/data/for_you_ranker.dart`
- Replace weakest-muscle inversion with an engine scoring component.
- Do not allow subjective "too hard" to increase training exposure.

`mobile/lib/features/personalisation/data/fitness_model.dart`
- Rename/reframe the concept if retained. It is closer to subjective tolerance
  history than physiological "fitness".
- It may supply a bounded feature, never a safety gate.

`mobile/lib/features/ai_planner/data/plan_builder.dart`
- Stop owning an independent eligibility/ranking algorithm.
- Convert to an adapter from `RecommendationEngine.buildSession(...)`.

`mobile/lib/features/recovery/data/deload_detector.dart`
- Convert to structured recovery/adherence signals.
- Do not directly prescribe fixed 0.5 training volume from a generic two-of-three
  rule.

### DEPRECATE / NARROW

`mobile/lib/features/ai_coach/ai_coach_context.dart`
- Remove authority to generate starting load and independent sets/reps.
- AI may explain:
  - setup;
  - observable technique;
  - common mistakes;
  - why an already-approved recommendation was chosen.
- Numeric prescription remains UI/domain-engine output.

## RecommendationContext

The provider should await all safety-critical asynchronous sources rather than
using `valueOrNull` where null can mean "still loading".

Conceptual structure:

```dart
class RecommendationContext {
  UserProfile? profile;
  List<ExerciseItem> catalog;
  List<WorkoutSession> workoutSessions;
  List<ScheduledSession> scheduledSessions;
  Programme? activeProgramme;
  List<HealthSnapshot> health;
  ScanContext? scan;
  FormContext? form;

  DateTime evaluatedAt;
  InputProvenance provenance;
}
```

Use the real existing model objects where practical; do not copy every field into a
parallel "User" DTO.

## One eligibility pipeline

Every surfaced exercise path eventually calls:

```text
SafetyGate
  ↓
ExerciseEligibility
  ├─ injury contraindications
  ├─ profile equipment/location
  ├─ current scan override (only when trustworthy)
  ├─ content-quality status
  ├─ special-population/clinical restrictions
  └─ unknown-data handling
  ↓
ELIGIBLE / ELIGIBLE_WITH_MODIFICATION / REVIEW_REQUIRED / INELIGIBLE
```

Ranking runs only after this.

## Scanner override semantics

A confident/confirmed scan means:
"this equipment is physically present for this request."

It may override the stored profile's normal location/equipment constraint for the
current session, but it must not mutate the profile automatically.

- `confident` cloud/text-confirmed -> may establish present equipment.
- `alternatives` -> user must select/confirm before exact equipment logic.
- offline classifier result -> remains alternatives.
- unknown/noEquipment/failed/timeout -> cannot establish identity.

## Load engine contract

Return one of:

```text
EXACT
RANGE
CALIBRATION_REQUIRED
BODYWEIGHT_OR_NONLOAD
UNAVAILABLE
BLOCKED
```

Exact kg requires:
- recent transferable performance;
- compatible load context;
- valid prescription target;
- known available increment;
- no safety state preventing prescription.

Never infer exact kg from:
- body mass;
- gender;
- experience tier alone;
- an LLM answer.

## Load context

Minimum v1 concept:

```text
free_weight:<equipmentId>
machine:<equipmentId>:<instance-or-unknown>
bodyweight
band:<resistance-known-or-unknown>
```

For machine loads, do not silently transfer exact kg across unknown machine instances.

## Progression decision

Return:
- PROGRESS
- HOLD
- REGRESS
- RECALIBRATE
- REVIEW_RECOVERY
- BLOCK

Each decision contains:
- trigger;
- basis;
- bounded max change;
- equipment rounding rule;
- staleness;
- confidence;
- reason codes.

No universal global `+2.5 kg`, `+5%`, or `-5%` rule.

## Programme/session planner

Preserve:
- Programme entity;
- Firestore repository;
- exact weekdays;
- one day = one multi-exercise workout.

Replace only the session-content algorithm.

Plan slots from:
1. objective;
2. movement/stimulus needs;
3. eligible exercise pool;
4. weekly/session dose;
5. time budget;
6. preference/history;
7. substitutions;
8. prescription per exercise.

Do not let alphabetical/catalog rotation masquerade as programming methodology.

## AI boundary

Recommended UI separation:

```text
Prescription card     <- deterministic engine
Why this recommendation <- deterministic reason codes + optional LLM wording
Technique coach       <- AI, no new numeric load/volume authority
```

The LLM must never be the only place where a prescribed kg/sets/reps exists.
