# O0 — Minimal Onboarding Schema Proposal (English Historical Companion)

**Original:** [O0 onboarding schema proposal](O0_ONBOARDING_SCHEMA_2026-08-12.md), Git blob `937b3b8643f35312209f022efdd09e2c25d9c126`.  
**Original date:** August 12, 2026.  
**Historical status:** **DESIGN DOCUMENT, NOT IMPLEMENTED CODE**.

The specification required: *"Use existing profile and onboarding models. If required fields are absent, provide a minimal schema proposal and STOP until GO."* Reference in the original: `docs/Redisign/LATEST_DEV_SINGLE_FILE_MASTER_PROMPT_EN.md:386`.

A historical owner instruction authorized **O0 + P1**, but the report expressly states that **O0 ends here and none of the fields proposed below had yet been created**. This translation does not renew that authorization, perform a schema migration or override current project decisions.

## Method and authoritative input

The original author inspected code file by file instead of relying on memory. The actual proposed onboarding path came from the operator's screenshot and prototype `App.tsx:2387-2409` with `TOTAL_OB_STEPS = 9` at `App.tsx:1202`. A different prompt listed **18 content items**, not 18 independently verified prototype screens; those sources must not be silently treated as the same number of steps.

## Main finding — several concepts already existed

The app already had a closed `InjuryRegion` vocabulary of **eight** regions (`profile_models.dart:61-70`). Its documentation explained why a free-text-only region is unreliable and pointed to `step_health.dart:64-82`. The Figma body diagram could reuse that field. Existing onboarding was populating `Injury.bodyPart` (string) instead, leaving `Injury.region` null.

The original found a broad Firestore rule at `firestore.rules:12` matching `/users/{uid}/{coll}/{document=**}` without per-field validation; newly introduced fields would therefore be accepted as the rule then stood. This is an **observed past schema/rules gap**, not a recommendation to leave current rules unvalidated.

## Field-by-field comparison

| Intended onboarding selection | Existing source type at that checkpoint | Difference to resolve |
| --- | --- | --- |
| Main goal, **one of six** | `FitnessGoals` six booleans (`profile_models.dart:363-368`) | Multi-goal flags do not represent a single primary goal |
| Experience, four choices | `FitnessTier { beginner, intermediate, advanced }` (`:11`) | Missing first-time/never |
| Gym/home/outdoors/mixed | `EquipmentAccess.hasGymAccess` as `bool?` (`:471`) | Boolean cannot distinguish outdoors/mixed |
| Eight equipment categories | `EquipmentAccess.homeEquipment` as `List<String>` (`:472`) | Free-form values versus controlled selection |
| **Planned** days/week | `FitnessLevel.frequencyPerWeek` (`:410`) | That records actual **current** frequency, not the plan |
| Exact session minutes | `MotivationPrefs.preferredDuration` bucket (`:39`) | A category such as 30-to-45 cannot express exactly 45 minutes |
| Preferred weekdays | None | New field |
| Eight muscle-priority areas | None | New field |
| Seven barriers | `MotivationPrefs.motivation` free text (`:493`) | Multi-select taxonomy versus narrative |
| Body restrictions | Existing `InjuryRegion` eight values (`:61-70`) | **Reuse**, not a new field |
| Year of birth | `PersonalInfo.age` `int?` (`:213`) | New storage/compatibility policy |

## Proposed minimal schema — not authorized for implementation

**Core invariant: do not rename or delete existing model fields.** Reuse what exists; preserve old readers with carefully designed calculated compatibility properties.

### 1. PersonalInfo: birth year

```dart
final int? birthYear;               // New: onboarding data
int? get age => birthYear == null   // Derived: preserve current readers
    ? null : DateTime.now().year - birthYear!;
```

The source proposed converting an old age field to a birth year **at the read boundary** `firestore_profile_repository.dart:44` if birth year is absent. Estimated birth year may be off by about **one year** because birth month was never collected. **Explain the uncertainty** rather than silently claiming an exact birthday.

### 2. Main goal: extend ProgrammeGoal

Existing `ProgrammeGoal` from `features/programmes/data/programme.dart:30` had five values: `strength`, `muscle`, `weightLoss`, `form`, `comeback`. Add `endurance` and a single nullable primary goal on `FitnessGoals`.

```dart
enum ProgrammeGoal { strength, muscle, weightLoss, form, comeback, endurance }
// In FitnessGoals, one dominant choice:
final ProgrammeGoal? primary;
```

This avoids introducing a second enum and an unmaintained translation mapping to program selection.

**Actual costs:** Three exhaustive `switch` sites would need handling for the new value — `_goalHue` (`workouts_page.dart:850-856`), `CatalogLabels`, and an additional sixth color mapping in `AppPalette`. The compiler would flag unhandled cases.

**Keep the existing six `FitnessGoals` booleans**. The prototype chooses one dominant goal; the prior user profile form permitted multiple goals. These are different semantics, not mutually exclusive replacements.

### 3. Experience: add a fourth value

```dart
enum FitnessTier { never, beginner, intermediate, advanced }
```

The proposed first position makes the ordering readable. Four known integration sites: `exercise_filter.dart`, `step_level.dart`, `firestore_profile_repository.dart`, `set_timer_providers.dart`.

### 4. Training location and available equipment

```dart
enum TrainingLocation { gym, home, outdoor, mixed }
enum EquipmentKind {
  fullGym, machines, dumbbells, barbell, kettlebells,
  bands, bodyweight, cameraScan
}

// In EquipmentAccess:
final TrainingLocation? location;
final List<EquipmentKind> available;
bool? get hasGymAccess => location == null ? null
    : location == TrainingLocation.gym ||
      location == TrainingLocation.mixed;
```

Keep the existing free-text `homeEquipment` for equipment outside the controlled choices. Preserve the user's information without coercing it into a misleading category; unlike the new controlled set, that free-text material should not automatically drive exercise matching.

`cameraScan` is an **intention to recognize a machine**, not actual exercise equipment. It is in the same chip list only for onboarding convenience and **must not be treated as an equipment type in recommendation logic**.

### 5. TrainingSchedule: new submodel

```dart
class TrainingSchedule {
  final int? daysPerWeek;             // 2..6
  final int? sessionMinutes;          // 30, 45, 60, 75, 90
  final List<int> preferredWeekdays;  // DateTime.monday..sunday
}
// Add a schedule field to UserProfile.
```

**Do not reuse `FitnessLevel.frequencyPerWeek`.** It records present habits, while schedule records future intent. Combining them would destroy the baseline from which a real training plan could estimate change in workload.

`MotivationPrefs.preferredDuration` could remain a calculated compatibility value from the chosen `sessionMinutes`.

### 6. Priority body regions and training barriers

```dart
enum FocusZone {
  chest, back, shoulders, arms, core, glutes, legs, fullBody
}
enum TrainingBarrier {
  exerciseChoice, machineUse, techniqueDoubt, time,
  consistency, discomfort, none
}
```

Both are multi-select. **Do not reuse `InjuryRegion` for `FocusZone`**: one means **train this**; the other means **avoid or account for this**. Different domains include fullBody/core versus wrist/ankle. Merging them would create mutually irrelevant enum values.

### 7. Restrictions: no new field

Have onboarding populate existing `Injury.region` and reuse `InjuryRegionTag.tag` (`profile_models.dart:72-96`) for catalogue tagging.

## Owner decisions left unresolved in the source

1. **Upper back vs. `neck`.** Figma's restriction map proposed upper back where the current `InjuryRegion` had neck. Seven of the eight regions matched. This affects the canonical injury vocabulary for up to 1,887 catalogue exercises. Three explicit options:
   - **A:** Keep `neck` and label it in UI as **"Neck and upper back"**. **Author's recommendation only**, not approved.
   - **B:** Add a ninth `upperBack` region.
   - **C:** Rename `neck` to `upperBack`, **losing the explicit neck region**.
2. **Lifestyle questions.** Existing nutrition, smoking and alcohol details had no designated place in the short Figma onboarding. Options: a collapsible section within the medical step, another standalone step (changing the actual screen count), or move these to Profile. **Author suggested Profile**, since they are not needed before the first workout; this was not an approved privacy/data-collection change.
3. **Health Connect at step 8/9.** There was an interface seam `HealthService` but no completed integration. Options: honest unavailable state, implementation under separate gate, or remove the step. No fake platform integration is permitted.

## Deliberately excluded

- **No new data fields purely for a fake "generation" spinner or plan preview**. The design required a real generator and prohibited fabricated progress at cited `:382-383` and `:388`.
- **No separate second primary-goal enum**: extending `ProgrammeGoal` is the proposed solution.
- **No deletion/renaming** of existing fields. Preserve compatibility when introducing calculated fields.

## Scope estimate — preserve original internal arithmetic mistake

The source's closing paragraph says **"three new enums"**, but explicitly lists **four**: `TrainingLocation`, `EquipmentKind`, `FocusZone` and `TrainingBarrier`. Do **not** silently propagate the count "three" into a new implementation plan. Other originally estimated scope:

- Two existing enum extensions: `ProgrammeGoal` and `FitnessTier`.
- One new submodel: `TrainingSchedule`.
- Four new fields in existing models.
- Two fields becoming calculated compatibility properties.
- One read-side migration.
- No changes to Firestore Rules in this particular dated proposal.

All of this remained **unimplemented** when O0 finished.

## Historical authority and translation boundary

The original owner had historically said GO for **O0 + P1**, but the original document was explicitly a **proposal and STOP**, not proof that the suggested schema was accepted and deployed. This translation does not supply approval to mutate personal data, health forms, Firebase security rules or runtime schema.

All source-code names, example Dart snippets (with only comments translated), Q/field semantics, unresolved decisions and uncertainty qualifiers are preserved. No source code, credentials, database records, test suite, Figma artifact, user health data, owner permission or release gate was changed.

**Disposition: SOURCE-BOUND ENGLISH O0 PROPOSAL READY FOR INDEPENDENT SEMANTIC REVIEW; NOT A MIGRATION GO.**
