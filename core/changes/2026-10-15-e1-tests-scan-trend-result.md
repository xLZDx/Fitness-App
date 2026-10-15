# E1 tests: scan trend, weight slope, result maths, provisional estimator

## What
- mobile/test/features/body_scan/data/scan_trend_test.dart (T20)
- mobile/test/features/body_scan/data/weight_slope_test.dart (T21)
- mobile/test/features/body_scan/data/scan_result_math_test.dart (T22)
- mobile/test/features/body_scan/data/provisional_estimator_test.dart (T78)
- fix in mobile/test/features/nutrition_plan/data/energy_math_test.dart: 2252 / 4.184 is 538.2409 (the map's 538.2 is rounded); test defect, not a product defect.

## Independent derivations
EWMA vectors (alpha 0.283469, 0.023528, 0.736403, 0.133122; S 25.5669 and 26.1339), warm-up weights (1/2, 1/3), Theil-Sen vectors, Deurenberg values and goal-weight arithmetic were derived with a scratch script, not copied from the implementation. Map deviations: V-EWMA 25.5669 holds only without the D-37 warm-up (tested both ways); the provisional range is clamped 3..60 and the value 5..55.

## Verification
`flutter test` of energy_math_test + the four files above (run from D:\Repo\Fitness_App_bodyscan\mobile): 173 passed, 0 failed.
