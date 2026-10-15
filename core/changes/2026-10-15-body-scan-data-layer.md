# Change record: C07 body scan data layer (pure parts)

## What changed
Pure Dart, no Flutter imports, all under `mobile/lib/features/body_scan/data/`:
- `check_items.dart`: closed `CheckCode` enum (13 codes), `CheckAction`, l10n key name, `parseCheckCodes` (unknown dropped, stable order).
- `body_fat_estimate.dart`: `BodyFatEstimate` (value, range, confidence level, model id/version, provisional, check codes; tolerant JSON), `EstimateConfidence`.
- `provisional_estimator.dart`: `BodyCompositionEstimator` provider interface, `EstimatorSubject/Input`, `deurenbergBodyFatPct`, `ProvisionalEstimator` (on-device, `provisional-anthropometric` / `deurenberg-1991-v0`, value clamped 5-55, half-width 5.0, confidence low, no photos) (D-3, D-52).
- `plausibility.dart`: `evaluatePlausibility` (reject outside 3-60, far-from-profile > 12 skipped for provisional, wide range > 4, weight jump > 3 kg in 7 days, weight missing/stale, large jump vs trend `> max(4, 2.5 hw)`, manual capture lowers confidence).
- `scan_trend.dart`: `computeScanTrend` using `core/math/series_math.dart` (tau 21 d, winsorise +-4, D-37 warm-up `alpha >= 1/n`), segmentation by `modelId`+`modelVersion` with change markers (D-54), `noiseThresholdPts`, `changeLabelBetween`, `fourWeekLabel`, `trendHalfWidth` (`hwMean * max(0.85, n_eff^-0.5)` from the third reading), client-derived baseline/start value.
- `scan_result_math.dart`: `massSplit` (fat/lean ranges), `rederiveForEditedWeight` (provisional estimate follows the new weight), `pointsToGoal`, `projectGoal` (goal weight, ETA range 0.8x-1.3x, hidden when provisional or goal BMI < 20, `targetBelowHealthyRange`).
- `face_region.dart`: head-box geometry from landmarks (nose/ears at likelihood >= 0.3, radius `max(1.35 x spread, 0.40 x shoulder width)`, half-side 1.5 r, 0.3 r extra upward, 15 % margin, clamped), crown fallback for back views, FAIL-CLOSED verdict (`noLandmarks`, `cannotSize`), frame-to-pixel mapping.
- `body_scan_job.dart`: `JobStatus`, `backoffSeconds` (`min(2^n, 300)`), `BodyScanJob` (5 attempts then `failed(retriable)`, fatal errors never retry, retry resets).
- `body_scan_flow_machine.dart`: `nextFlow(state, event, context)` implementing the design s10 table with effects, cancel from every active state (`deleteBodyScan` or a pending remote delete only when something may be uploaded), illegal events are no-ops, `resumeStateFor`.
- `scan_plan_context.dart`: PORT `ScanPlanContextSource` with the safe measurement-only default and `surfaceModeFor(eligibility)` (D-71, D-74).
- `face_check_port.dart`: PORT `FaceCheckPort` with the fail-closed `UnavailableFaceCheck` default (D-69).
- `body_scan_entry.dart`, `body_scan_repository.dart`: server entry view with tolerant JSON; repository interface only.

## Why
Sprint plan commit C07; design s8-s12, D-3, D-37, D-52, D-54, D-69, D-71, D-73, D-74.

## Deviations and notes (safe behaviour chosen)
- The ML Kit landmark set in the repo has only nose and ears for the head (no eyes or mouth corners), so the head set is nose, left ear, right ear.
- The provisional estimator keeps the RANGE edges inside the plausibility window 3-60, so an extreme value (clamped to 5 or 55) never yields a range that would be rejected; the half-width is exactly 5.0 everywhere else.
- `fourWeekLabel` takes the reference `S(t-28d)` from the newest reading at or before 28 days ago, or the series' first smoothed value for a younger series; the window mean half-width uses the readings inside the window. The map's EWMA vectors hold for `TrendConfig(warmupMean: false)`; the default config applies the D-37 warm-up.
- `hwMean` of the trend interval is the weight-weighted mean half-width over the EWMA weights (sum 1).
- The `estimateOutOfRange` rejection is a flag on `PlausibilityResult` (it is not one of the 13 chip codes).
- A retake from the review screen returns to review after the shot (state flag `retake`).

## Affected contracts and paths
New files only. `body_scan` imports `nutrition_plan/data` (allowed edge); `nutrition_plan` imports nothing from `body_scan`.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: coverage map T20-T27 and the re-pathed `body_scan/data/provisional_estimator_test.dart`.

## Review state
Pending the test phase and specialist reviewers.
