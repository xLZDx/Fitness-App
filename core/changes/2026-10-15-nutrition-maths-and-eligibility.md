# Change record: C05 nutrition maths, safety clamps and eligibility

## What changed
Pure Dart (no Flutter imports):
- `mobile/lib/core/math/series_math.dart` (new, neutral location, D-71): `SeriesPoint`, `ewmaAlpha` (irregular gap clamped to 0.5-28 days, optional `1/n` warm-up), `ewmaStep` (optional winsorising), `ewmaSeries`, `median`, `theilSenSlopePerDay`, `theilSenSlopePerWeek` (21-day window, >= 3 points, >= 7 days span, pairs >= 2 days apart).
- `mobile/lib/features/nutrition_plan/data/safety_clamps.dart`: every number of design s13.6 and s29 as a named constant in `SafetyClamps` with its provenance tag.
- `energy_math.dart`: `SexBasis`, `resolveSexBasis`, `bmiOf`, `bmr` (Mifflin-St Jeor, constants +5 / -161 / -78), activity and steps factors (lower of the two), `tdee`, `calorieFloor`, rounding helpers, kcal/kJ and salt/sodium helpers, `resolveKcal` (kcal wins over kJ), Atwater check with tolerance `max(25 %, 10 kcal)`.
- `weight_entry.dart`: `WeightEntry` (tolerant JSON, 30-300 kg), `weightDayKey`, `latestWeightWithin`, `weightSlopeKgPerWeek`, `smoothedWeightKg` (tau 7 days).
- `missing_inputs.dart`: `NutritionInput`, `missingNutritionInputs(profile)`, `deriveGoalDirection`.
- `nutrition_inputs.dart`: `resolveCurrentWeight` (entry within 14 days, else profile weight flagged stale), `NutritionInputs.resolve` -> `NutritionInputsResolution`.
- `plan_calculator.dart`: `weeklyRateRow`, `computeBounds`, `clampRangeToBounds`, `computeMacros` (protein min/target/max with reference weight, 220 g and 40 % caps, lean-mass variant, fat 20-35 %, carbs >= 100 g, point targets with `lowCarbBySafety`, 5 g display rounding), `stepsGoalFor`, `computePlan`, `realisticPace`, `clampTargetBodyFatPct`.
- `nutrition_eligibility.dart`: `evaluateNutritionEligibility` (design s14 rows 1-9 in order; sealed `Eligible` / `ReferProfessional` / `NeedsAnswer` / `NeedsProfile`), computed on the device only, never persisted (D-55).

## Why
Sprint plan commit C05; design s13, s14, s16.3, D-9, D-12, D-13, D-23, D-24, D-29, D-37, D-38, D-39, D-42, D-55, D-71.

## Deviations and vector conflicts (safe behaviour chosen; the test author must use these)
1. **Calorie range for a lose goal follows design D-39 (target -200 / +100), not the coverage-map vectors V-LOSE-M / V-LOSE-CAP, which show +-150.** D-39 is the later, explicit decision (design precedence). Maintain and gain use +-150.
2. **The range is clamped inside the slider bounds, and the bounds apply the deficit cap to the LOW end** (design 13.3: "the user range must lie inside the bounds"). Hand-derived results for the map inputs: V-LOSE-M (male 80 kg, 180 cm, 30 y, factor 1.375): TDEE 2447.5, kgPerWeek 0.40, dailyDelta 440, target 2007.5, bounds 1900-2440 (maximum rate is the absolute 0.5 kg/week = 550 kcal, below the 25 % cap of 611.9), range 1900-2110. V-LOSE-CAP style case (25 % cap binding): target 1835.6, bounds low 1840, range 1840-1940. The map's 1860-2160 / 1690-1990 are therefore superseded; TDEE, kgPerWeek, dailyDelta, deficit and target values match the map. The map vectors should be corrected in the test phase.
3. V-EWMA: the map's S = 25.5669 (alpha 0.28347 on the second reading) holds for `ewmaAlpha`/`ewmaStep` without a reading count and for `ewmaSeries(warmupMean: false)`. With the D-37 warm-up (`warmupMean: true`, used by the body-fat trend in C07) the second reading is weighted 0.5 by design.
4. When TDEE is at or below the calorie floor (tiny or very old profiles) the plan target and range are raised to the floor and the upper bound is lifted to `min + 100`; the plan carries `PlanFlag.floorBinding`. The floor wins over the "never above TDEE" rule so the interval is never empty.
5. Kcal bounds and the range are rounded INWARD to 10 kcal (low up, high down); the calorie floor value itself stays an exact integer (`round(BMR)`, e.g. 2068).
6. The protein point target shown in the header rounds UP to 5 g but is clamped back into [min, max]; the band `targetG` stays the unrounded integer (V-PROT-OB shows 173).
7. Carbohydrate max is lifted to 100 g when the energy arithmetic would give less, so `carbMin <= carbMax` and `carbMin >= 100` always hold.
8. `ReferProfessional` carries one reason (first match wins); `reasons` returns that single value as a list.
9. `NutritionInputs.resolve` prefers the health-platform 14-day median steps over the self-reported bucket (PLAN-09).

## Affected contracts and paths
New files only (above). `lowestAgeAt` is used for the age gate, `ageAt` for the energy maths (the higher age gives the lower, more conservative BMR).

## Verification state
Not run, per DEVELOPMENT RULES v4. Self-review by reading. Focused tests: coverage map T12-T15, T17, T19, T21, T37.

## Review state
Pending the test phase and specialist reviewers.
