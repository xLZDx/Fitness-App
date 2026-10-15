# E0 tests follow-up: C20 food callables wired into T06 and T07, map rows T136/T137

## What
- `release_guard.test.ts` (T06): the deferred six-callable expectation is now real. After C20 the guard set is six callables; tests pin the exact list, that the lookup callables are not in the AI set, that a missing or guard-stripped source file of either food callable FAILS the candidate check, and that the healthy guard passes. The `test.todo` is removed.
- `scaling.test.ts` (T07): the deployed-surface registry now lists `analyzeMealPhoto`, `parseNutritionLabel` (AI_METERED, fn-ai-runtime, concurrency 10) and `lookupBarcode`, `searchFoods` (FOOD_LOOKUP, fn-data, platform concurrency); the surface count test is thirty.
- Coverage map section 12.7 registers the two E0 files that were not in the map: T136 (feature_gates_test, extended) and T137 (data_notice_test, new).

## Why
The C20 commit exported four new endpoints, which the registry count test is designed to catch; the guard set grew to six, which was recorded as deferred.

## Paths
functions/src/__tests__/release_guard.test.ts, functions/src/__tests__/scaling.test.ts, core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md

## Verification
Single-file jest runs: release_guard 80 passed, scaling 122 passed. The complete E0 evidence record is core/changes/2026-10-15-e0-test-evidence.md.
