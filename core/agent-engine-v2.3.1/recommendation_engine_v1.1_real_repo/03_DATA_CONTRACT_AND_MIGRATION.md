# Data contract and migration

## Principle

Do not introduce a parallel backend schema first. Evolve current Firestore-compatible
models additively, with tolerant readers, then migrate behavior.

## 1. UserProfile

KEEP current UserProfile as canonical intake model.

### Medication extension

Current:
```dart
List<String> medications;
```

Recommendation runtime needs a separate **verified normalization result**:

```dart
class MedicationExerciseContext {
  String rawName;
  String? normalizedName;
  String? drugClass;
  Set<String> exerciseEffectTags;
  String? verifiedSource;
  DateTime? verifiedAt;
}
```

Do not silently replace the raw user-entered strings. Preserve them as source data.

If normalization is unavailable:
- `normalizationStatus = unresolved`;
- do not infer a drug class from model memory;
- use a conservative fallback for any prescription dimension that depends on
  medication effects.

## 2. Performed sets

Current:
```dart
typedef SetCapture = ({double? weightKg, int? reps});
```

Target additive model:
```dart
class PerformedSet {
  double? weightKg;
  int? reps;
  double? rir;
  double? rpe;
  PerformedSetType type;
  int? prescribedSetIndex;
}
```

Backward reader:
- `{weightKg, reps}` -> valid PerformedSet with new fields null.
- never require migration before an old workout can be read.

## 3. WorkoutSessionExercise

Add optional:
```text
equipmentId
loadContextKey
recommendationId
prescriptionId
```

Why:
- same exercise on different machine contexts must not automatically transfer exact kg;
- every future recommendation should be auditable back to the rule/result that produced it.

## 4. ScheduledSession

Do not reinterpret `durationMinutes`.

Add an optional per-exercise plan snapshot, for example:
```text
prescriptionsByExerciseId
```

Each prescription:
```text
exerciseId
sets
repRange or duration target
targetRir / targetRpe
restSeconds
loadTarget
loadBasis
progressionRuleId
stopConditions
reasonCodes
```

Old row:
- no prescription -> current behavior.

New row:
- Workout Player can render real target and compare actual vs planned.

## 5. Recommendation audit trace

Do not store private health values in the trace.

Store:
```text
recommendationId
engineVersion
rulesetVersion
catalogVersion / metadataVersion
input-presence flags
safetyState
eligibility decision
reasonCodes
loadBasis
progressionDecision
createdAt
```

The trace answers "why did the app recommend this?" without copying sensitive
questionnaire text into analytics/server logs.

## 6. Exercise recommendation metadata

Current ExerciseItem fields are not enough for substitution/load semantics.

Do not mutate the vendor source conceptually into medical truth.

Create a versioned overlay under the already-recursive `assets/data/` asset root:

```text
assets/data/recommendation/
  exercise_metadata.v1.json
  clinical_safety_rules.v1.json
  medication_effects.v1.json
  prescription_policy.v1.json
```

The current pubspec already includes `assets/data/`, so a nested recommendation
directory must still be verified in an APK/integration test before relying on it;
the repo has previously had a non-recursive asset packaging defect for another
directory.

Overlay fields may include:
```text
canonicalId / aliasOf
movementPatterns
movementProperties
skillDemand
loadMode
loadTransferClass
substitutionFamily
restrictionTags
contentQuality
equipmentResolutionStatus
```

Every safety-critical generated/curated field needs provenance/owner status.
