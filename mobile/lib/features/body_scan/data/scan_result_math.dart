/// Result arithmetic of one scan (design s12.1, s12.6, s12.6a). Pure Dart, no
/// Flutter imports.
library;

import 'dart:math' as math;

import '../../nutrition_plan/data/energy_math.dart';
import '../../nutrition_plan/data/safety_clamps.dart';
import 'body_fat_estimate.dart';
import 'provisional_estimator.dart';

/// Fat and lean mass with ranges, from a body-fat range and a body weight.
class MassSplit {
  const MassSplit({
    required this.fatKg,
    required this.fatLowKg,
    required this.fatHighKg,
    required this.leanKg,
    required this.leanLowKg,
    required this.leanHighKg,
  });

  final double fatKg;
  final double fatLowKg;
  final double fatHighKg;
  final double leanKg;
  final double leanLowKg;
  final double leanHighKg;
}

/// `FM = W v / 100`, range `W [l, h] / 100`; `LM = W - FM`, range
/// `[W - FM_high, W - FM_low]`. Null for a missing or non-positive weight (no
/// mass is shown, no division by zero).
MassSplit? massSplit({
  required double? weightKg,
  required double valuePct,
  required double lowPct,
  required double highPct,
}) {
  if (weightKg == null || !weightKg.isFinite || weightKg <= 0) return null;
  final fat = weightKg * valuePct / 100;
  final fatLow = weightKg * lowPct / 100;
  final fatHigh = weightKg * highPct / 100;
  return MassSplit(
    fatKg: fat,
    fatLowKg: fatLow,
    fatHighKg: fatHigh,
    leanKg: weightKg - fat,
    leanLowKg: weightKg - fatHigh,
    leanHighKg: weightKg - fatLow,
  );
}

/// Re-derives a PROVISIONAL estimate after the recorded weight was edited: the
/// formula depends on BMI, so the estimate itself changes (D-52). A
/// server-computed estimate is never changed by an edit; for it this returns
/// [estimate] unchanged.
BodyFatEstimate rederiveForEditedWeight({
  required BodyFatEstimate estimate,
  required EstimatorSubject subjectWithNewWeight,
}) {
  if (!estimate.provisional) return estimate;
  return const ProvisionalEstimator().estimateNow(subjectWithNewWeight);
}

/// Points still to go: `S_t - target`; null without a body-fat target (the
/// screen then shows weight-based progress).
double? pointsToGoal({double? smoothedPct, double? targetBodyFatPct}) {
  if (smoothedPct == null || targetBodyFatPct == null) return null;
  return smoothedPct - targetBodyFatPct;
}

/// Why no ETA is available.
enum GoalProjectionIssue {
  /// The goal weight's BMI is under 18.5.
  targetBelowHealthyRange,
  noPace,
}

/// Goal weight and the optional ETA (design 12.6a, D-38, D-77).
class GoalProjection {
  const GoalProjection({
    this.goalWeightKg,
    this.toLoseKg,
    this.weeksLow,
    this.weeksHigh,
    this.issue,
    this.etaHidden = false,
  });

  final double? goalWeightKg;
  final double? toLoseKg;

  /// The ETA as a range, `weeks * 0.8` .. `weeks * 1.3`, "if the pace holds".
  final double? weeksLow;
  final double? weeksHigh;
  final GoalProjectionIssue? issue;

  /// The ETA is hidden: provisional estimator, or a goal BMI under 20 (it
  /// would read as a promise to keep losing). Only the weekly pace is shown.
  final bool etaHidden;

  static const double etaLowFactor = 0.8;
  static const double etaHighFactor = 1.3;
}

/// `goalWeight = LM / (1 - target/100)` with `LM = W (1 - S_t/100)` (lean mass
/// assumed constant, which is optimistic); `toLose = W - goalWeight`;
/// `weeks = toLose / kgPerWeek` using the plan pace AFTER every clamp.
///
/// The target is clamped to 10-40 % male / 16-40 % otherwise first. A goal
/// weight under BMI 18.5 gives `targetBelowHealthyRange` and no figures.
/// Arithmetic check from the design: lean 65.83 kg at a 16 % target gives
/// 65.83 / 0.84 = 78.36 kg, 17.04 kg to lose from 95.4 kg, and 29.9 weeks at
/// 0.57 kg/week.
GoalProjection projectGoal({
  required double weightKg,
  required double heightCm,
  required double smoothedPct,
  required double targetBodyFatPct,
  required SexBasis sex,
  required double? kgPerWeek,
  required bool provisional,
}) {
  final target = math.min(
    math.max(
      targetBodyFatPct,
      sex == SexBasis.male
          ? SafetyClamps.targetBodyFatMinMale
          : SafetyClamps.targetBodyFatMinOther,
    ),
    SafetyClamps.targetBodyFatMax,
  );
  final lean = weightKg * (1 - smoothedPct / 100);
  final goalWeight = lean / (1 - target / 100);
  final goalBmi = bmiOf(goalWeight, heightCm);
  if (goalBmi != null && goalBmi < SafetyClamps.underweightBmi) {
    return const GoalProjection(
      issue: GoalProjectionIssue.targetBelowHealthyRange,
      etaHidden: true,
    );
  }
  final toLose = weightKg - goalWeight;
  final hide = provisional ||
      (goalBmi != null && goalBmi < SafetyClamps.etaHiddenBelowGoalBmi);
  if (kgPerWeek == null || kgPerWeek <= 0 || toLose <= 0) {
    return GoalProjection(
      goalWeightKg: goalWeight,
      toLoseKg: toLose,
      issue: GoalProjectionIssue.noPace,
      etaHidden: true,
    );
  }
  final weeks = toLose / kgPerWeek;
  return GoalProjection(
    goalWeightKg: goalWeight,
    toLoseKg: toLose,
    weeksLow: hide ? null : weeks * GoalProjection.etaLowFactor,
    weeksHigh: hide ? null : weeks * GoalProjection.etaHighFactor,
    etaHidden: hide,
  );
}
