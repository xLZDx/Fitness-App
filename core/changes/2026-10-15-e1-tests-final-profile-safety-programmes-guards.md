# E1 tests: profile JSON, safety extensions, volume factor, architecture guards, map correction

## What
New tests
- mobile/test/features/profile/nutrition_prefs_json_test.dart (18)
- mobile/test/features/profile/health_flags_json_test.dart (15)
- mobile/test/core/architecture/pure_data_layer_guard_test.dart (6)
- mobile/test/core/architecture/import_graph_guard_test.dart (8)

Extended tests
- mobile/test/features/safety/health_flags_field_coverage_test.dart (12 total, 3 new)
- mobile/test/features/safety/health_rules_parity_test.dart (7 total, 3 new)
- mobile/test/features/safety/f014_persistence_merge_test.dart (14 total, 8 new)
- mobile/test/features/programmes/programme_builder_test.dart (47 total, 11 new: volumeFactor)

The map's `programmes/nutrition_advice_combination_test.dart` was not created as a separate file: adviseTrainingFromNutrition and
combinedIntensityCeiling (PROG-01..PROG-10) are already covered, with hand-derived values, in
nutrition_training_state_test.dart (53 tests).

## Product defect found and fixed (E1 source)
PLAN-29 requires an acyclic data import graph. The guard found a file-level cycle in the activity data layer:
activity_session.dart -> source_record.dart -> device_source.dart -> activity_session.dart. source_record.dart only needs the
`SourceKind` enum. Fix: `SourceKind` moved to mobile/lib/features/activity/data/source_kind.dart; device_source.dart imports and
RE-EXPORTS it (no caller changes), source_record.dart imports source_kind.dart. Behaviour is unchanged.

## Architecture finding (reported, not edited: other epics own the files)
PLAN-29 says "none the other way" (nutrition_plan must not import body_scan), but two non-data files do:
nutrition_plan/nutrition_plan_page.dart -> body_scan/state/body_scan_providers.dart and
nutrition_plan/state/scan_plan_context_source.dart -> body_scan/data/scan_plan_context.dart. The data layers stay acyclic, and
nutrition_plan/data imports no sibling feature. import_graph_guard_test pins exactly these two edges so a third one fails.

## Coverage map correction (V-LOSE-M / V-LOSE-CAP vs D-39)
The implementation is right and the map was wrong. Corrected in core/plans/BODY_SCAN_NUTRITION_TEST_COVERAGE_MAP_2026-10-15.md
(section 3 rows and PLAN-05):
- V-LOSE-M: target 2007.5, raw range 1807.5-2107.5, slider bounds 1900-2440, range pulled to 1900-2110.
- V-LOSE-CAP: target 1835.6, raw range 1640-1940, slider bounds 1840-2440, range pulled to 1840-1940.

## Verification
One `flutter test` invocation, run from D:\Repo\Fitness_App_bodyscan\mobile at HEAD 349a8d5 (plus the uncommitted files above),
over all 27 E1 test files, JSON reporter: 1075 passed, 0 failed, 0 skipped.
Per file: energy_math 39, safety_clamps 60, plan_calculator 66, nutrition_eligibility 53, weekly_review 70, missing_inputs 24,
nutrition_training_state 53, nutrition_inputs 21, scan_trend 53, weight_slope 33, scan_result_math 20, provisional_estimator 28,
plausibility 26, check_items 8, face_region 23, body_scan_flow_machine 256, body_scan_job 15, activity_models 36,
activity_merger 64, nutrition_prefs_json 18, health_flags_json 15, health_flags_field_coverage 12, health_rules_parity 7,
f014_persistence_merge 14, programme_builder 47, pure_data_layer_guard 6, import_graph_guard 8.
Not run: nothing else (no analyze, lint, build or full suite).
