# C23 part 2: diary providers, actions, search controller

## What changed
- `mobile/lib/features/food_diary/state/diary_providers.dart`: repository providers (in-memory default), bundled generic table loader (rootBundle), selected day, `diaryVisibleProvider` (hidden unless the eligibility verdict allows numbers, so hidden for referProfessional), day entries stream, day targets from the stored plan, day totals, `FoodDiaryActions` (deletion fence, validation, closed status), and `FoodSearchController` (3-char minimum, explicit submit, 600 ms debounce, last-results cache, bundled results offline, feature-disabled to a not-available phase).
- `mobile/lib/main.dart`: overrides the two repository providers with the Firestore implementations.

## Why
Spec row C23. The data-notice gate (D-79) stays a UI responsibility, as for the weight log.

## Verification
Not run (no checks before sprint coding completes).
