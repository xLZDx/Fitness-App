/// The nutrition plan calculator (design s13.3-s13.5): weekly rate, calorie
/// target, user range and slider bounds, macro ranges, steps goal and the
/// realistic-pace helper. Pure Dart, no Flutter imports.
///
/// Safety first: every function here applies the clamps of `safety_clamps.dart`
/// and the same bounds function re-validates a stored or edited range, so a
/// slider, a stored document or a review can never leave the bounds.
library;

import 'dart:math' as math;

import '../../profile/data/profile_models.dart';
import 'energy_math.dart';
import 'nutrition_inputs.dart';
import 'safety_clamps.dart';

/// Things the plan wants the UI to explain. Closed set; l10n keyed by name.
enum PlanFlag {
  /// A lose goal was coerced to maintain because BMI < 18.5.
  underweightNoDeficit,

  /// The target weight's BMI is below 18.5; it is rejected, no pace is shown.
  targetBelowHealthyRange,

  /// Carbohydrate would fall under 100 g; fat then protein moved toward their
  /// minimums.
  lowCarbBySafety,

  /// TDEE sits at or below the calorie floor, so the floor decides the range.
  floorBinding,

  /// No weigh-in within 14 days; the profile weight was used.
  weightStale,

  /// A requested weekly rate above the row maximum was clamped to it.
  rateClamped,
}

/// Weekly rate limits of one row of the table in design 13.3.
class WeeklyRateRow {
  const WeeklyRateRow({
    required this.defaultPct,
    required this.maxPct,
    required this.absoluteKg,
  });

  final double defaultPct;
  final double maxPct;
  final double absoluteKg;

  static const none = WeeklyRateRow(defaultPct: 0, maxPct: 0, absoluteKg: 0);
}

/// The rate row for [goal] at [bmi]. Lose below BMI 25 uses the low row; from
/// 25 up the high row (the 25-30 and >= 30 rows share numbers since D-38).
/// For 18.5 <= BMI < 20 a deficit is allowed only at 0.25 %/week. Callers
/// coerce a lose goal at BMI < 18.5 to maintain BEFORE asking.
WeeklyRateRow weeklyRateRow(GoalDirection goal, double bmi) {
  switch (goal) {
    case GoalDirection.maintain:
      return WeeklyRateRow.none;
    case GoalDirection.gain:
      return const WeeklyRateRow(
        defaultPct: SafetyClamps.gainRateDefaultPct,
        maxPct: SafetyClamps.gainRateMaxPct,
        absoluteKg: SafetyClamps.gainRateAbsoluteKg,
      );
    case GoalDirection.lose:
      final high = bmi >= SafetyClamps.bmiHighRowStart;
      var def = high
          ? SafetyClamps.lossRateHighBmiDefaultPct
          : SafetyClamps.lossRateLowBmiDefaultPct;
      var max = high
          ? SafetyClamps.lossRateHighBmiMaxPct
          : SafetyClamps.lossRateLowBmiMaxPct;
      final abs = high
          ? SafetyClamps.lossRateHighBmiAbsoluteKg
          : SafetyClamps.lossRateLowBmiAbsoluteKg;
      if (bmi < SafetyClamps.lowBmiDeficitBand) {
        def = math.min(def, SafetyClamps.lowBmiMaxRatePct);
        max = math.min(max, SafetyClamps.lowBmiMaxRatePct);
      }
      return WeeklyRateRow(defaultPct: def, maxPct: max, absoluteKg: abs);
  }
}

/// kg per week for [pct] percent of [weightKg], capped by the row's absolute
/// kg limit.
double kgPerWeekFor(WeeklyRateRow row, double pct, double weightKg) =>
    math.min(pct / 100 * weightKg, row.absoluteKg);

/// A calorie range the user sees.
class KcalRange {
  const KcalRange(this.low, this.high);

  final int low;
  final int high;

  int get width => high - low;
  double get mid => (low + high) / 2;

  @override
  bool operator ==(Object other) =>
      other is KcalRange && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => 'KcalRange($low-$high)';
}

/// Inclusive slider bounds in kcal, already rounded inward to 10.
class PlanBounds {
  const PlanBounds(this.minKcal, this.maxKcal);

  final int minKcal;
  final int maxKcal;

  bool contains(KcalRange r) => r.low >= minKcal && r.high <= maxKcal;

  @override
  bool operator ==(Object other) =>
      other is PlanBounds &&
      other.minKcal == minKcal &&
      other.maxKcal == maxKcal;

  @override
  int get hashCode => Object.hash(minKcal, maxKcal);

  @override
  String toString() => 'PlanBounds($minKcal-$maxKcal)';
}

/// Slider bounds (design 13.3), rounded INWARD to 10 kcal: lose
/// `[max(floor, TDEE - maxDeficit), TDEE]`, maintain `TDEE +- 300` (not under
/// the floor), gain `[TDEE, TDEE + min(500, 15 % TDEE)]` (not under the floor).
///
/// The interval always has room for the minimum range width. In the degenerate
/// case where TDEE sits at or under the floor the upper bound is lifted to
/// `min + 100`: the floor wins over the "not above TDEE" rule.
PlanBounds computeBounds({
  required GoalDirection goal,
  required double tdee,
  required int floorKcal,
  required double maxKgPerWeek,
}) {
  late int lo;
  late int hi;
  switch (goal) {
    case GoalDirection.lose:
      final maxDeficit = math.min(
        SafetyClamps.maxDeficitFractionOfTdee * tdee,
        maxKgPerWeek * SafetyClamps.kcalPerKg / 7,
      );
      lo = ceilToStep(
          math.max(floorKcal.toDouble(), tdee - maxDeficit),
          SafetyClamps.kcalRounding);
      hi = floorToStep(tdee, SafetyClamps.kcalRounding);
    case GoalDirection.maintain:
      lo = ceilToStep(
          math.max(
              floorKcal.toDouble(), tdee - SafetyClamps.maintainBoundsKcal),
          SafetyClamps.kcalRounding);
      hi = floorToStep(
          tdee + SafetyClamps.maintainBoundsKcal, SafetyClamps.kcalRounding);
    case GoalDirection.gain:
      lo = ceilToStep(math.max(floorKcal.toDouble(), tdee),
          SafetyClamps.kcalRounding);
      hi = floorToStep(
          tdee +
              math.min(SafetyClamps.maxSurplusKcal,
                  SafetyClamps.maxSurplusFractionOfTdee * tdee),
          SafetyClamps.kcalRounding);
  }
  if (hi < lo + SafetyClamps.minRangeWidthKcal) {
    hi = lo + SafetyClamps.minRangeWidthKcal;
  }
  return PlanBounds(lo, hi);
}

/// Pulls [range] inside [bounds] and into the allowed width (100-400 kcal).
/// Used on every load, every edit and before every write.
KcalRange clampRangeToBounds(KcalRange range, PlanBounds bounds) {
  const minW = SafetyClamps.minRangeWidthKcal;
  const maxW = SafetyClamps.maxRangeWidthKcal;
  final low = _clampInt(range.low, bounds.minKcal, bounds.maxKcal - minW);
  final high = _clampInt(
    range.high,
    low + minW,
    math.min(bounds.maxKcal, low + maxW),
  );
  return KcalRange(low, high);
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Protein band in grams per day.
class ProteinBand {
  const ProteinBand({
    required this.minG,
    required this.targetG,
    required this.maxG,
  });

  final int minG;
  final int targetG;
  final int maxG;
}

/// A min/max gram band (fat, carbohydrate).
class GramBand {
  const GramBand({required this.minG, required this.maxG});

  final int minG;
  final int maxG;
}

/// Single-number targets for the plan header, display-rounded (protein UP to
/// 5 g, carbs to the nearest 5 g, fat to 1 g). The 4/4/9 energy they imply may
/// differ from the mid calories by up to 5 % because of the rounding.
class MacroTargets {
  const MacroTargets({
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  final int proteinG;
  final int fatG;
  final int carbsG;

  int get impliedKcal => (SafetyClamps.kcalPerGramProtein * proteinG +
          SafetyClamps.kcalPerGramFat * fatG +
          SafetyClamps.kcalPerGramCarb * carbsG)
      .round();
}

/// Macro ranges and point targets for a calorie range.
class MacroPlan {
  const MacroPlan({
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.targets,
    required this.lowCarbBySafety,
  });

  final ProteinBand protein;
  final GramBand fat;
  final GramBand carbs;
  final MacroTargets targets;
  final bool lowCarbBySafety;
}

/// Reference weight for protein and fat: the body weight, or for BMI above 30
/// the weight at BMI 30 (protein is not scaled to excess mass).
double referenceWeightKg(double weightKg, double heightCm) {
  final bmi = bmiOf(weightKg, heightCm);
  if (bmi == null || bmi <= SafetyClamps.referenceWeightBmiCap) return weightKg;
  final m = heightCm / 100;
  return SafetyClamps.referenceWeightBmiCap * m * m;
}

/// Macro ranges for [kcal] (design 13.4). [leanMassKg] enables the lean-mass
/// protein variant (D-42) and must be passed only when a non-provisional,
/// confident body-fat trend exists; the min/max clamps still win.
MacroPlan computeMacros({
  required double weightKg,
  required double heightCm,
  required GoalDirection goal,
  required KcalRange kcal,
  double? leanMassKg,
}) {
  final wref = referenceWeightKg(weightKg, heightCm);
  final kcalMid = kcal.mid;

  // Protein.
  final minPerKg = goal == GoalDirection.maintain
      ? SafetyClamps.proteinMinMaintainPerKg
      : SafetyClamps.proteinMinChangePerKg;
  final targetPerKg = switch (goal) {
    GoalDirection.lose => SafetyClamps.proteinTargetLosePerKg,
    GoalDirection.maintain => SafetyClamps.proteinTargetMaintainPerKg,
    GoalDirection.gain => SafetyClamps.proteinTargetGainPerKg,
  };
  final maxFromKcal = (SafetyClamps.proteinMaxFractionOfKcal *
          kcalMid /
          SafetyClamps.kcalPerGramProtein)
      .floor();
  final pMax = math.min(
    math.min((SafetyClamps.proteinMaxPerKg * wref).round(),
        SafetyClamps.proteinMaxGrams),
    maxFromKcal,
  );
  final pMin = math.min((minPerKg * wref).round(), pMax);
  final rawTarget = (leanMassKg != null && leanMassKg > 0)
      ? SafetyClamps.proteinPerKgLeanMass * leanMassKg
      : targetPerKg * wref;
  final pTarget = _clampInt(rawTarget.round(), pMin, pMax);

  // Fat.
  final fatMin = math.max(
    SafetyClamps.fatMinPerKg * wref,
    SafetyClamps.fatMinFractionOfKcal *
        kcalMid /
        SafetyClamps.kcalPerGramFat,
  );
  final fatMaxRaw = SafetyClamps.fatMaxFractionOfKcal *
      kcalMid /
      SafetyClamps.kcalPerGramFat;
  final fMin = fatMin.round();
  final fMax = math.max(fatMaxRaw.round(), fMin);

  // Carbohydrate.
  final carbMaxRaw = (kcal.high -
          SafetyClamps.kcalPerGramProtein * pMin -
          SafetyClamps.kcalPerGramFat * fMin) /
      SafetyClamps.kcalPerGramCarb;
  final carbMinRaw = (kcal.low -
          SafetyClamps.kcalPerGramProtein * pMax -
          SafetyClamps.kcalPerGramFat * fMax) /
      SafetyClamps.kcalPerGramCarb;
  final cMax = math.max(carbMaxRaw.round(), SafetyClamps.carbMinGrams);
  final cMin = math.min(
    math.max(carbMinRaw.round(), SafetyClamps.carbMinGrams),
    cMax,
  );

  // Point targets.
  var protein = pTarget.toDouble();
  var fat = _clampDouble(
    SafetyClamps.fatPointFractionOfKcal *
        kcalMid /
        SafetyClamps.kcalPerGramFat,
    fMin.toDouble(),
    fMax.toDouble(),
  );
  double carbsOf() =>
      (kcalMid -
          SafetyClamps.kcalPerGramProtein * protein -
          SafetyClamps.kcalPerGramFat * fat) /
      SafetyClamps.kcalPerGramCarb;
  var lowCarb = false;
  if (carbsOf() < SafetyClamps.carbMinGrams) {
    lowCarb = true;
    // Fat first, toward its minimum.
    final needKcal = (SafetyClamps.carbMinGrams - carbsOf()) *
        SafetyClamps.kcalPerGramCarb;
    fat = math.max(fMin.toDouble(), fat - needKcal / SafetyClamps.kcalPerGramFat);
    if (carbsOf() < SafetyClamps.carbMinGrams) {
      // Then protein, toward its minimum.
      final need2 = (SafetyClamps.carbMinGrams - carbsOf()) *
          SafetyClamps.kcalPerGramCarb;
      protein = math.max(
          pMin.toDouble(), protein - need2 / SafetyClamps.kcalPerGramProtein);
    }
  }
  final carbs = math.max(carbsOf(), SafetyClamps.carbMinGrams.toDouble());
  final displayProtein = _clampInt(
    ceilToStep(protein, SafetyClamps.proteinDisplayStepGrams),
    pMin,
    pMax,
  );

  return MacroPlan(
    protein: ProteinBand(minG: pMin, targetG: pTarget, maxG: pMax),
    fat: GramBand(minG: fMin, maxG: fMax),
    carbs: GramBand(minG: cMin, maxG: cMax),
    targets: MacroTargets(
      proteinG: displayProtein,
      fatG: fat.round(),
      carbsG: math.max(
        roundToStep(carbs, SafetyClamps.carbDisplayStepGrams),
        SafetyClamps.carbMinGrams,
      ),
    ),
    lowCarbBySafety: lowCarb,
  );
}

double _clampDouble(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// The computed steps goal (design 13.5): the base (typical steps, else by
/// activity) plus 1,000, rounded to 500 and clamped to 6,000-12,000.
int stepsGoalFor({ActivityLevel? level, int? typicalSteps}) {
  final base = typicalSteps ??
      switch (level) {
        ActivityLevel.sedentary || null => SafetyClamps.stepsBaseSedentary,
        ActivityLevel.moderatelyActive => SafetyClamps.stepsBaseModerate,
        ActivityLevel.active => SafetyClamps.stepsBaseActive,
        ActivityLevel.veryActive => SafetyClamps.stepsBaseVeryActive,
      };
  final goal = roundToStep(
    (base + SafetyClamps.stepsGoalIncrement).toDouble(),
    SafetyClamps.stepsGoalRounding,
  );
  return _clampInt(goal, SafetyClamps.stepsGoalMin, SafetyClamps.stepsGoalMax);
}

/// The full computed plan. Always recomputable from the inputs; stored values
/// are only the user's current choice.
class NutritionPlan {
  const NutritionPlan({
    required this.goal,
    required this.requestedGoal,
    required this.bmr,
    required this.activityFactor,
    required this.tdee,
    required this.floorKcal,
    required this.bmi,
    required this.ratePctPerWeek,
    required this.kgPerWeek,
    required this.maxKgPerWeek,
    required this.targetKcal,
    required this.kcalRange,
    required this.bounds,
    required this.macros,
    required this.stepsGoal,
    required this.flags,
  });

  /// The goal actually planned (a lose goal may be coerced to maintain).
  final GoalDirection goal;
  final GoalDirection requestedGoal;
  final double bmr;
  final double activityFactor;
  final double tdee;
  final int floorKcal;
  final double bmi;
  final double ratePctPerWeek;
  final double kgPerWeek;
  final double maxKgPerWeek;
  final double targetKcal;
  final KcalRange kcalRange;
  final PlanBounds bounds;
  final MacroPlan macros;
  final int stepsGoal;
  final Set<PlanFlag> flags;
}

/// Computes the plan for [inputs].
///
/// [ratePctPerWeek] is the user's chosen pace (clamped to the row maximum);
/// null means the row default. [userRange] is a stored or edited range, pulled
/// inside the recomputed bounds; null means the computed one.
/// [leanMassKgForProtein] enables the lean-mass protein variant (see
/// [computeMacros]).
NutritionPlan computePlan(
  NutritionInputs inputs, {
  double? ratePctPerWeek,
  KcalRange? userRange,
  double? leanMassKgForProtein,
}) {
  final flags = <PlanFlag>{};
  if (inputs.weightStale) flags.add(PlanFlag.weightStale);

  final bmi = inputs.bmi;
  var goal = inputs.goal;
  if (goal == GoalDirection.lose && bmi < SafetyClamps.underweightBmi) {
    goal = GoalDirection.maintain;
    flags.add(PlanFlag.underweightNoDeficit);
  }
  final target = inputs.weightTargetKg;
  if (target != null) {
    final tb = bmiOf(target, inputs.heightCm);
    if (tb != null && tb < SafetyClamps.underweightBmi) {
      flags.add(PlanFlag.targetBelowHealthyRange);
    }
  }

  final bmrKcal = bmr(
    weightKg: inputs.weightKg,
    heightCm: inputs.heightCm,
    ageYears: inputs.ageYears,
    sex: inputs.sex,
  );
  final factor = combinedActivityFactor(
        level: inputs.activityLevel,
        typicalSteps: inputs.typicalSteps,
      ) ??
      SafetyClamps.factorSedentary;
  final tdeeKcal = tdee(bmrKcal, factor);
  final floorKcal = calorieFloor(bmrKcal, inputs.sex);
  if (tdeeKcal <= floorKcal) flags.add(PlanFlag.floorBinding);

  final row = weeklyRateRow(goal, bmi);
  var pct = ratePctPerWeek ?? row.defaultPct;
  if (pct > row.maxPct) {
    pct = row.maxPct;
    flags.add(PlanFlag.rateClamped);
  }
  if (pct < 0) pct = 0;
  final kgWeek = kgPerWeekFor(row, pct, inputs.weightKg);
  final maxKgWeek = kgPerWeekFor(row, row.maxPct, inputs.weightKg);
  final dailyDelta = kgWeek * SafetyClamps.kcalPerKg / 7;

  double targetKcal;
  switch (goal) {
    case GoalDirection.lose:
      final deficit = math.max(
        0.0,
        math.min(
          dailyDelta,
          math.min(
            SafetyClamps.maxDeficitFractionOfTdee * tdeeKcal,
            tdeeKcal - floorKcal,
          ),
        ),
      );
      targetKcal = tdeeKcal - deficit;
    case GoalDirection.gain:
      final cap = math.min(
        SafetyClamps.maxSurplusKcal,
        SafetyClamps.maxSurplusFractionOfTdee * tdeeKcal,
      );
      final surplus =
          math.min(math.max(dailyDelta, SafetyClamps.minSurplusKcal), cap);
      targetKcal = tdeeKcal + surplus;
    case GoalDirection.maintain:
      targetKcal = tdeeKcal;
  }
  // Never plan below the floor, even when TDEE itself is under it.
  targetKcal = math.max(targetKcal, floorKcal.toDouble());

  final bounds = computeBounds(
    goal: goal,
    tdee: tdeeKcal,
    floorKcal: floorKcal,
    maxKgPerWeek: maxKgWeek,
  );
  final KcalRange raw;
  if (userRange != null) {
    raw = userRange;
  } else if (goal == GoalDirection.lose) {
    raw = KcalRange(
      roundToStep(targetKcal - SafetyClamps.loseRangeBelowKcal,
          SafetyClamps.kcalRounding),
      roundToStep(targetKcal + SafetyClamps.loseRangeAboveKcal,
          SafetyClamps.kcalRounding),
    );
  } else {
    raw = KcalRange(
      roundToStep(targetKcal - SafetyClamps.symmetricRangeHalfKcal,
          SafetyClamps.kcalRounding),
      roundToStep(targetKcal + SafetyClamps.symmetricRangeHalfKcal,
          SafetyClamps.kcalRounding),
    );
  }
  final range = clampRangeToBounds(raw, bounds);

  final macros = computeMacros(
    weightKg: inputs.weightKg,
    heightCm: inputs.heightCm,
    goal: goal,
    kcal: range,
    leanMassKg: leanMassKgForProtein,
  );
  if (macros.lowCarbBySafety) flags.add(PlanFlag.lowCarbBySafety);

  return NutritionPlan(
    goal: goal,
    requestedGoal: inputs.goal,
    bmr: bmrKcal,
    activityFactor: factor,
    tdee: tdeeKcal,
    floorKcal: floorKcal,
    bmi: bmi,
    ratePctPerWeek: pct,
    kgPerWeek: kgWeek,
    maxKgPerWeek: maxKgWeek,
    targetKcal: targetKcal,
    kcalRange: range,
    bounds: bounds,
    macros: macros,
    stepsGoal:
        stepsGoalFor(level: inputs.activityLevel, typicalSteps: inputs.typicalSteps),
    flags: flags,
  );
}

/// Result of [realisticPace], shown on the onboarding step.
class PaceEstimate {
  const PaceEstimate({
    required this.direction,
    this.kgPerWeek,
    this.weeks,
    this.targetBelowHealthyRange = false,
    this.underweightNoDeficit = false,
  });

  final GoalDirection direction;

  /// The safe default pace in kg per week; null when no pace applies.
  final double? kgPerWeek;

  /// Whole weeks to reach the target at that pace (rounded up); null when no
  /// pace applies.
  final int? weeks;

  /// The target weight's BMI is under 18.5: rejected, no pace is shown.
  final bool targetBelowHealthyRange;

  /// A lose direction at BMI < 18.5 was coerced to maintain.
  final bool underweightNoDeficit;
}

/// The "at a safe pace this takes about N weeks" estimate (design 16.2). The
/// direction comes from [goal] when given, else from target vs current weight.
PaceEstimate realisticPace({
  required double weightKg,
  required double heightCm,
  required double targetWeightKg,
  GoalDirection? goal,
}) {
  final targetBmi = bmiOf(targetWeightKg, heightCm);
  final bmi = bmiOf(weightKg, heightCm);
  var direction = goal ??
      (targetWeightKg < weightKg
          ? GoalDirection.lose
          : (targetWeightKg > weightKg
              ? GoalDirection.gain
              : GoalDirection.maintain));
  if (targetBmi == null || bmi == null) {
    return PaceEstimate(direction: GoalDirection.maintain);
  }
  if (targetBmi < SafetyClamps.underweightBmi) {
    return PaceEstimate(direction: direction, targetBelowHealthyRange: true);
  }
  if (direction == GoalDirection.lose && bmi < SafetyClamps.underweightBmi) {
    return const PaceEstimate(
      direction: GoalDirection.maintain,
      underweightNoDeficit: true,
    );
  }
  if (direction == GoalDirection.maintain) {
    return const PaceEstimate(direction: GoalDirection.maintain);
  }
  final row = weeklyRateRow(direction, bmi);
  final kg = kgPerWeekFor(row, row.defaultPct, weightKg);
  final delta = (targetWeightKg - weightKg).abs();
  if (kg <= 0 || delta <= 0) {
    return PaceEstimate(direction: direction);
  }
  return PaceEstimate(
    direction: direction,
    kgPerWeek: kg,
    weeks: (delta / kg).ceil(),
  );
}

/// Clamps a target body-fat percent into the allowed band for [sex]
/// (10-40 male, 16-40 otherwise).
double clampTargetBodyFatPct(double pct, SexBasis sex) {
  final min = sex == SexBasis.male
      ? SafetyClamps.targetBodyFatMinMale
      : SafetyClamps.targetBodyFatMinOther;
  return _clampDouble(pct, min, SafetyClamps.targetBodyFatMax);
}
