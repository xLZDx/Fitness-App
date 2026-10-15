# E2 tests: onboarding nutrition step (part 1)

## What
- NEW `mobile/test/features/onboarding/onboarding_nutrition_data_test.dart` (47 tests): kOnboardingOrder (D-75 order), `isOnboardingStepAnswered(nutrition)` per field, `nutritionSafetyClear`, `nutritionProfileSheets` / `missingNutritionInputs`, steps buckets, `DietaryPreference.pescatarian`, device-only `stripSensitive` behaviour, `QuestionnaireDraft.updateNutrition` / `markNutritionCompleted`, excluded-food limits in `NutritionPrefs.fromJson`.
- NEW `mobile/test/features/onboarding/step_nutrition_test.dart` (50 tests): lock-out (six locked combinations, no numbers), exact pace message and live region, read-only target weight with Change link, defaults not written, steps buckets, HealthSyncCard embedded, allergen chips, excluded-food add/dedupe/limit/remove, exact EN/RU safety copy on the health-flags step, pescatarian chip, RU text scale 2.0 at 360x640.

## Why
Coverage map rows ONB-01..ONB-10, ONB-13..ONB-16, A11Y-06, I18N-08.

## Verification
```
cd D:\Repo\Fitness_App_bodyscan\mobile
flutter test --no-pub -r expanded test/features/onboarding/onboarding_nutrition_data_test.dart   -> 47 passed
flutter test --no-pub -r expanded test/features/onboarding/step_nutrition_test.dart              -> 50 passed
```
Flutter 3.27.1 (D:\flutter\bin). Final head is recorded in the last E2 change record.
