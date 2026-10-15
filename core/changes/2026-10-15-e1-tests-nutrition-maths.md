# E1 tests: nutrition maths, clamps, plan, eligibility, weekly review

## What
Added (written; run results are recorded in the follow-up change record):
- mobile/test/features/nutrition_plan/data/energy_math_test.dart (T12)
- mobile/test/features/nutrition_plan/data/safety_clamps_test.dart (T13)
- mobile/test/features/nutrition_plan/data/plan_calculator_test.dart (T14)
- mobile/test/features/nutrition_plan/data/nutrition_eligibility_test.dart (T15)
- mobile/test/features/nutrition_plan/data/weekly_review_test.dart (T16)

## Why
Coverage map v1.1 sections 4.3 and 4.4 (PLAN-01..14, SAFE-01..17). Expected numbers were derived with an independent scratch oracle written from the design s13 text, not from the implementation.

## Deviation resolved
The lose range follows D-39 (-200/+100) and is pulled inside the slider bounds: V-LOSE-M gives range 1900-2110 with bounds 1900-2440 (not 1860-2160); V-LOSE-CAP gives 1840-1940. Independent arithmetic confirms the implementation; the map is corrected in a later commit of this series.

## Verification state
Committed before the first run (coordinator request). Not yet executed at this commit.
