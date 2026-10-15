# Change record: C09 nutrition-aware programme hook

## What changed
- `mobile/lib/features/nutrition_plan/data/nutrition_training_state.dart` (new, pure Dart): `NutritionTrainingInput`, `TrainingNutritionAdvice`, closed `TrainingNutritionReason` codes (no energy-availability or RED-S wording), `adviseTrainingFromNutrition` implementing design s30.3 rules 1-9 (neutral unless eligible with known phase and calories; deficit 0.20 -> volume 0.85, 0.10 -> 0.95 with no intensity change; surplus boost 1.05 only with sleep >= 7 h and protein adherence >= 0.7; protein adherence needs >= 4 logged days; protein low in a deficit -> deload `consider`; sleep < 6 h -> intensity delta -0.05; loss faster than 1.25 x the plan maximum -> volume <= 0.90 and `consider`; intake <= floor x 1.05 with >= 5 sessions -> `recommended` plus the generic professional line; the existing recovery signal -> `recommended`; volume clamped 0.70-1.05, intensity delta -0.10..0), and `combinedIntensityCeiling` (the most conservative of base, age cap, screening ceiling and hint cap, then only LOWERED by the nutrition delta, never below the planner floor).
- `mobile/lib/features/programmes/data/programme_builder.dart`: WIRED per SD-7 because the seam is small. `ProgrammeBuildRequest.volumeFactor` (default 1.0, neutral), `setsAfterNutrition`, and a proportionally trimmed weekly-minimum in `validateProgramme` so a trimmed programme is not refused for being trimmed. Exercise selection, the eligibility layer, age band, screening ceiling and injury filter are untouched.

## Why
Sprint plan commit C09; design s30, D-33, SD-7. Nutrition can lower load, never raise a cap that safety set.

## Decisions and deviations
- SD-7 outcome: the programme builder seam (`ProgrammeBuildRequest`) is a one-parameter change and is wired. `intensityCapDelta` has NO consumer in `buildProgramme` (it schedules sets, not intensity); its consumer is the AI planner / suggestion path, which is left UNWIRED here and recorded: the planner (`ai_planner/data/plan_builder.dart`, `ceiling`) can call `combinedIntensityCeiling` in a later commit, and the Riverpod provider that feeds live inputs is created in C18.
- The builder treats a factor above 1.0 as 1.0 (the 1.05 surplus boost is advice for a human-facing hint, not a way to add sets) and a factor below 0.70 as 0.70. Sets use `round(setsPerSlot * factor)` with a minimum of 1; with 3 sets per slot a factor of 0.85 or 0.95 therefore rounds back to 3 and only a factor near 0.70 changes the programme. This is a conscious, conservative consequence of integer sets.
- The `NutritionTrainingInput` fields `phase`, `kcalMid`, `floorKcal` are nullable (unknown -> neutral) and `planMaxRatePctPerWeek` was added for the fast-loss rule, which needs the plan's maximum rate.

## Affected contracts and paths
`ProgrammeBuildRequest` gains an optional named parameter with a neutral default; existing callers are unchanged.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: coverage map T18, T35, T36 (builder test: existing expectations must pass unchanged with no parameter).

## Review state
Pending the test phase and specialist reviewers.
