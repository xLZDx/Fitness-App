# Mobile review fixes 4: unreadable plan, scanDone rerun, degraded food entries (SF-F8, SF-F10, SF-F12)

## What
- SF-F8: an existing but unreadable `nutrition_plan/main` throws `PlanUnreadableException` (stream error / load error) instead of reading as "no plan"; the plan page shows its load error with a Retry button (invalidates the stored plan provider); plan writes that hit it end as `PlanActionStatus.unreadable` (failure snackbar) instead of an unhandled error; the weekly review run reports `failed` rather than silently skipping.
- SF-F10: a `scanDone` review trigger that arrives while a run is in flight sets a flag and one more pass runs after it.
- SF-F12: `FoodEntry.fromJson` sets `degraded` when `loggedAt` or `totals` is missing/unreadable (such an entry is never written back).

## Why
Silent-failure-hunter findings SF-F8, SF-F10, SF-F12.

## Paths
mobile/lib/features/nutrition_plan/data/plan_repository.dart, .../data/firestore_plan_repository.dart, .../state/nutrition_plan_actions.dart, .../nutrition_plan_page.dart, .../state/review_scheduler.dart, mobile/lib/features/food_diary/data/food_entry.dart; tests: nutrition_plan_page_test.dart, review_scheduler_test.dart, food_entry_test.dart

## Contracts
`NutritionPlanRepository.loadPlan/watchPlan` may now throw `PlanUnreadableException`; new enum value `PlanActionStatus.unreadable`.

## Verification
Not run (operator rules).
