# C23 part 1: food diary API client and repositories

## What changed
- `mobile/lib/features/food_diary/state/food_api.dart`: `FoodApi` interface over the four food callables (`analyzeMealPhoto`, `lookupBarcode`, `searchFoods`, `parseNutritionLabel`), the real `CallableFoodApi`, a scriptable `FakeFoodApi`, pure response parsers, and a closed `FoodApiFailure` set. `failed-precondition: feature-disabled` maps to `featureDisabled` (rendered later as a calm "not available yet" state, D-78).
- `mobile/lib/features/food_diary/state/diary_repository.dart`: `FoodDiaryRepository` and `SavedFoodsRepository` ports, the `SavedFood` model (500-item client cap) and in-memory fakes.
- `mobile/lib/features/food_diary/state/firestore_diary_repository.dart`: Firestore implementations (equality-only day query, Timestamp fields).

## Why
Spec row C23 (state, repositories plus fakes, callable client behind an interface plus fake).

## Contracts and paths
- Reads the callable shapes of C20. Analysed items without per-100 g values yield no `FoodItem` (never written as zeros). Item `foodRef` for model estimates is `llm:<slug>`.
- Firestore rules: `firestore.rules` already covers `food_entries` and `saved_foods` (owner-only create/update/delete, key allowlists, entry `source` enum, size limits). Item `sourceId` is not checked by the rules (only item `name` is, by design, for the expression budget), so `llm_estimate` is accepted. No rules change was needed; none was made. Health-data refusal (`referProfessional`) concerns plan documents, not diary documents.

## Verification
Not run (sprint rule: no checks before coding completes).
