# Change record: C10 onboarding nutrition step

## What changed
- `onboarding/data/step_answered.dart`: new `OnboardingStep.nutrition`; `kOnboardingOrder` now `... personal, lifestyle, healthFlags, nutrition, screening, preview` (D-75: the safety questions come first); `isOnboardingStepAnswered(nutrition)` = any `NutritionPrefs` field set or any allergen chip. `onboardingResumeIndex` logic is untouched.
- NEW `onboarding/steps/step_nutrition.dart` (`StepNutrition`) and NEW `onboarding/widgets/nutrition_inputs.dart` (the shared field widgets: goal, read-only target-weight line with link back and the realistic-pace message from `realisticPace`, target body fat, sex at birth, steps bucket + `HealthSyncCard`, allergens, excluded foods, meals per day, plan ownership, the locked notice, and `nutritionSafetyClear`). C11 reuses these.
- `steps/step_health_flags.dart`: the pregnancy question is extracted to `ProfessionalGuidanceQuestion` (same key `onb.flags.guidance`, wording widened to name breastfeeding) and the new `NutritionGuidanceQuestion` (exact EN/RU copy of design s16.2) follows it.
- `steps/step_lifestyle.dart` + `DietaryPreference.pescatarian` (stored by name, before `none`).
- `state/questionnaire_notifier.dart`: `updateNutrition`, `markNutritionCompleted` (stamps `completedAt` once). Allergens and both safety answers go through `updateHealth` / `HealthFlags.copyWith`.
- `onboarding_page.dart`: title/widget cases for the step; `_widgetFor` became an instance method so the step can link back to the personal screen; leaving an answered nutrition step stamps `completedAt`.
- ARB `onbStepNutrition`, `onbNutrition*`, `onbDietPescatarian` EN + RU; `healthStepProfessionalGuidance` widened in both languages.

## Why
Sprint plan C10; design s14, s16.2, D-75, D-55; coverage map ONB-*.

## Safety-first behaviour
A goal, default goal, pace line, body-fat target, sex, steps and ownership are rendered only when BOTH `professionalGuidance` and `nutritionGuidance` are `none` (`nutritionSafetyClear`). Otherwise the step shows one neutral line (no reason, no number) and keeps only allergens, excluded foods and meals per day.

## Deviations
- The goal chip shows a derived default as selected (without writing it) only when the questionnaire goals allow one; with no signal nothing is pre-selected. Same for sex at birth (derived from gender) and nothing is pre-selected for meals/ownership (captions state the defaults 3 / Coached).
- Body-fat target uses the existing `MeasureRuler` (clamped to the 10/16-40 % band on write) plus a clear chip, not a text field.
- Picking a steps bucket records `healthConnectChoice = manual`; recording `connected` stays with the C18 health seam read.
- Allergen labels use `onbNutritionAllergen*` keys; later food UI should reuse them via `foodAllergenLabel`.

## Affected contracts and paths
`DietaryPreference` gained a value (name-serialised, tolerant). Existing tests that count onboarding steps or assert the old pregnancy wording need updating by the test phase.

## Verification state
Not run, per DEVELOPMENT RULES v4. flutter_gen is not committed in this repo, so no generated l10n was touched.

## Review state
Pending the test phase and specialist reviewers.
