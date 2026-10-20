# Change record: C04 profile model, nutrition preferences and health flags

## What changed
- `mobile/lib/features/profile/data/profile_models.dart`: new enums `SexAtBirth`, `GoalDirection`, `PlanOwnership`, `HealthConnectChoice`; new value class `NutritionPrefs` (sex at birth, goal direction, target body fat, typical daily steps, meals per day 2..6, excluded foods <= 20 items of <= 40 chars, plan ownership, Health Connect choice, completion time) with omit-empty `toJson`, tolerant `fromJson` (unknown enum names and wrongly typed values degrade to null, out-of-range meals per day reads as unanswered), `copyWith`, `==`/`hashCode`; `UserProfile.nutrition` (default `NutritionPrefs.empty`), serialised under `nutrition` in `UserProfile.toJson`.
- `mobile/lib/features/profile/data/firestore_profile_repository.dart`: `_fromMap` reads `nutrition` through `NutritionPrefs.fromJson` (absent block = empty).
- `mobile/lib/features/profile/data/sensitive_profile.dart`: `excludedFoods` joins the device-only block (`SensitiveProfile`, `extractSensitive`, `stripSensitive`, `mergeSensitive`, structural check), so the server profile never carries it (D-55).
- `mobile/lib/features/safety/data/health_flags.dart`: `NutritionGuidanceNeed {none, reported}`, `FoodAllergen` (closed EU-14 list), `HealthFlags.nutritionGuidance` / `foodAllergens` in `isUnanswered` (guidance only) / `isEmpty` (both) / `==` / `hashCode` / `toJson` / `fromJson` / `copyWith` / `toString`. `toJson` OMITS `nutritionGuidance` when null and `foodAllergens` when empty (D-70) so the deployed `flagsAreStripped` key allowlist keeps accepting the stripped block.

## Why
Design s14, s16 (profile model), D-9, D-11, D-12, D-55, D-70; sprint plan commit C04. Nothing is written until the user answers; old profile JSON round-trips without the new keys.

## Deviations (safe behaviour chosen)
- `DietaryPreference.pescatarian` is NOT added here. `onboarding/steps/step_lifestyle.dart` switches exhaustively over the enum and needs an l10n label, so adding the value in a pure-model commit would break compilation (SD-1/SD-3). It moves to C10 together with its chip and ARB keys.
- `excludedFoods` device-only handling needed edits in `sensitive_profile.dart`, which the plan's C04 row did not list; without them the field would reach Firestore and be refused by the rules allowlist, bricking profile saves.
- `FirestoreProfileRepository.save` uses `merge: true`, so clearing a nutrition field to null does not delete the stored key; same behaviour as every other profile field (known limit, unchanged).

## Affected contracts and paths
`UserProfile.toJson` gains a `nutrition` map (`{schema: 1, ...set fields}`); allowed by the existing profile rule (no top-level key allowlist) and by the C01 `nutritionOk` allowlist, which excludes `excludedFoods`. `health.flags` wire shape is unchanged when the new answers are empty.

## Verification state
Not run, per DEVELOPMENT RULES v4 (no tests, analyzer, build). Self-review by reading the diff. Focused tests are specified in the coverage map (T30, T31, T32, T33, T34).

## Review state
Pending the test phase and specialist reviewers.
