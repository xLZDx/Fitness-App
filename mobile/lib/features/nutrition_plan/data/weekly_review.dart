/// The weekly review: ONE pure decision function (design s15), also used by the
/// post-scan plan decision. Pure Dart, no Flutter imports.
///
/// Safety properties, in order of importance:
///  * a user who is not `eligible` gets NO decision (null) and nothing is ever
///    written for them (D-55); there is no `referProfessional` decision value;
///  * a change needs two consecutive `behind` classifications and a 14-day
///    cooldown, except the immediate `tooFast` correction, which only ever
///    moves toward more energy for a loss goal;
///  * a change is never silently truncated: if the shifted range would leave
///    the recomputed bounds the decision becomes `keep(atSafetyLimit)`;
///  * `reasonCodes` is a closed, non-health set, always non-empty.
library;

import '../../profile/data/profile_models.dart';
import 'body_fat_trend_source.dart';
import 'nutrition_eligibility.dart';
import 'plan_calculator.dart';
import 'safety_clamps.dart';

/// How the observed weight trend compares with the plan's intended rate.
enum ReviewClass { onTrack, behind, ahead, driftUp, driftDown }

/// The closed decision set stored in `nutrition_plan_reviews`.
enum ReviewDecisionKind {
  keep,
  adjustKcal,
  adjustSteps,
  needMoreData,
  needRecalculation,
}

/// What the ownership mode does with a decision (design s18).
enum ReviewApplication {
  /// Coached: applied automatically, with a 7-day undo.
  applied,

  /// Shared: proposed, applied only on accept.
  proposed,

  /// Manual: shown as an insight, the plan is never changed.
  insightOnly,
}

/// Closed, localisable, non-health reason codes ("always explain why").
enum ReviewReason {
  onTrack,
  aheadOfPlan,
  behindWaiting,
  cooldownActive,
  tooFast,
  stepsRaised,
  kcalLowered,
  kcalRaised,
  atSafetyLimit,
  recomposition,
  driftTooLarge,
  needMoreDataPoints,
  needMoreDataSpan,
  autoAdjustOff,
}

/// The two auto-adjust toggles of the plan.
class AutoAdjust {
  const AutoAdjust({this.steps = true, this.kcal = true});

  final bool steps;
  final bool kcal;

  static const off = AutoAdjust(steps: false, kcal: false);
}

/// Everything the review reads. Built by the caller from the plan, the weight
/// series and the stored review history.
class ReviewInput {
  const ReviewInput({
    required this.eligibility,
    required this.goal,
    required this.ownership,
    required this.autoAdjust,
    required this.kcalRange,
    required this.bounds,
    required this.stepsGoal,
    required this.weightKg,
    required this.maxKgPerWeek,
    required this.intendedKgPerWeek,
    required this.weightPoints,
    required this.spanDays,
    required this.basePlanVersion,
    required this.now,
    this.weightSlopeKgPerWeek,
    this.previousClass,
    this.daysSinceLastKcalAdjust,
    this.driftFromInitialKcal = 0,
    this.bodyFatTrend,
  });

  final NutritionEligibility eligibility;
  final GoalDirection goal;
  final PlanOwnership ownership;
  final AutoAdjust autoAdjust;

  /// The CURRENT user range and the recomputed bounds.
  final KcalRange kcalRange;
  final PlanBounds bounds;
  final int stepsGoal;
  final double weightKg;

  /// The row maximum in kg per week, for the `tooFast` rule.
  final double maxKgPerWeek;

  /// Signed intended rate: negative for loss, positive for gain, 0 maintain.
  final double intendedKgPerWeek;

  /// Theil-Sen slope in kg/week, null when there is not enough data.
  final double? weightSlopeKgPerWeek;
  final int weightPoints;
  final int spanDays;

  /// The classification of the previous review, if any.
  final ReviewClass? previousClass;

  /// Null means the kcal range was never adjusted (no cooldown).
  final int? daysSinceLastKcalAdjust;

  /// Cumulative review adjustment since the initial range (signed kcal).
  final int driftFromInitialKcal;

  /// The `planVersion` the inputs were read at; written into the review so the
  /// transaction can refuse a stale decision (D-57).
  final int basePlanVersion;

  /// Optional smoothed body-fat trend, via the port (ignored when provisional).
  final BodyFatTrendInput? bodyFatTrend;
  final DateTime now;
}

/// The numeric inputs stored beside a decision for the "why" card.
class ReviewInputsRecord {
  const ReviewInputsRecord({
    required this.weightSlopeKgPerWeek,
    required this.intendedKgPerWeek,
    required this.dataPoints,
    this.bfTrendPts,
  });

  final double? weightSlopeKgPerWeek;
  final double intendedKgPerWeek;
  final int dataPoints;
  final double? bfTrendPts;
}

class WeeklyReviewDecision {
  const WeeklyReviewDecision({
    required this.kind,
    required this.reasonCodes,
    required this.application,
    required this.basePlanVersion,
    required this.inputs,
    this.classification,
    this.deltaKcal = 0,
    this.deltaSteps = 0,
    this.newRange,
    this.newStepsGoal,
    this.newDriftFromInitialKcal,
  });

  final ReviewDecisionKind kind;
  final List<ReviewReason> reasonCodes;
  final ReviewApplication application;
  final int basePlanVersion;
  final ReviewInputsRecord inputs;

  /// Null for `needMoreData`.
  final ReviewClass? classification;
  final int deltaKcal;
  final int deltaSteps;

  /// Set for `adjustKcal`: the range after the change (already inside the
  /// bounds).
  final KcalRange? newRange;

  /// Set for `adjustSteps`.
  final int? newStepsGoal;

  /// Set for `adjustKcal`: the drift after the change.
  final int? newDriftFromInitialKcal;

  /// True when the decision would change the plan (before ownership).
  bool get changesPlan =>
      kind == ReviewDecisionKind.adjustKcal ||
      kind == ReviewDecisionKind.adjustSteps;
}

const double _eps = 1e-9;

ReviewApplication _applicationFor(PlanOwnership o) => switch (o) {
      PlanOwnership.coached => ReviewApplication.applied,
      PlanOwnership.shared => ReviewApplication.proposed,
      PlanOwnership.manual => ReviewApplication.insightOnly,
    };

/// The signed intended weekly rate for a plan: loss negative, gain positive.
double intendedKgPerWeekFor(GoalDirection goal, double kgPerWeek) =>
    switch (goal) {
      GoalDirection.lose => -kgPerWeek,
      GoalDirection.gain => kgPerWeek,
      GoalDirection.maintain => 0,
    };

/// The weekly review decision, or null when the user is not eligible.
WeeklyReviewDecision? decide(ReviewInput i) {
  if (!i.eligibility.allowsNumbers) return null;
  final application = _applicationFor(i.ownership);
  final slope = i.weightSlopeKgPerWeek;
  final bf = i.bodyFatTrend;
  final record = ReviewInputsRecord(
    weightSlopeKgPerWeek: slope,
    intendedKgPerWeek: i.intendedKgPerWeek,
    dataPoints: i.weightPoints,
    bfTrendPts: bf != null && !bf.provisional && !bf.seriesChanged
        ? bf.changePts
        : null,
  );

  WeeklyReviewDecision build(
    ReviewDecisionKind kind,
    List<ReviewReason> reasons, {
    ReviewClass? cls,
    int deltaKcal = 0,
    int deltaSteps = 0,
    KcalRange? newRange,
    int? newSteps,
    int? newDrift,
  }) =>
      WeeklyReviewDecision(
        kind: kind,
        reasonCodes: List.unmodifiable(reasons),
        application: application,
        basePlanVersion: i.basePlanVersion,
        inputs: record,
        classification: cls,
        deltaKcal: deltaKcal,
        deltaSteps: deltaSteps,
        newRange: newRange,
        newStepsGoal: newSteps,
        newDriftFromInitialKcal: newDrift,
      );

  // 2. Data sufficiency.
  final enoughPoints = i.weightPoints >= SafetyClamps.reviewMinWeightPoints;
  final enoughSpan = i.spanDays >= SafetyClamps.reviewMinSpanDays;
  if (!enoughPoints || !enoughSpan || slope == null) {
    return build(ReviewDecisionKind.needMoreData, [
      if (!enoughPoints || slope == null) ReviewReason.needMoreDataPoints,
      if (!enoughSpan) ReviewReason.needMoreDataSpan,
    ]);
  }

  // 3. Classification.
  final flatThreshold =
      SafetyClamps.maintainDriftPctPerWeek / 100 * i.weightKg;
  final ReviewClass cls;
  if (i.goal == GoalDirection.maintain) {
    cls = slope > flatThreshold + _eps
        ? ReviewClass.driftUp
        : (slope < -flatThreshold - _eps
            ? ReviewClass.driftDown
            : ReviewClass.onTrack);
  } else {
    final tol = _max(
      SafetyClamps.reviewToleranceMinKgPerWeek,
      SafetyClamps.reviewToleranceFraction * i.intendedKgPerWeek.abs(),
    );
    final e = slope - i.intendedKgPerWeek;
    if (e.abs() <= tol + _eps) {
      cls = ReviewClass.onTrack;
    } else if (i.goal == GoalDirection.lose) {
      cls = e > 0 ? ReviewClass.behind : ReviewClass.ahead;
    } else {
      cls = e < 0 ? ReviewClass.behind : ReviewClass.ahead;
    }
  }

  // Applies a kcal shift: drift cap first, then the bounds (never truncate).
  WeeklyReviewDecision kcalChange(int delta, List<ReviewReason> why) {
    final newDrift = i.driftFromInitialKcal + delta;
    if (newDrift.abs() > SafetyClamps.reviewDriftCapKcal) {
      return build(
        ReviewDecisionKind.needRecalculation,
        [...why.where((r) => r == ReviewReason.tooFast), ReviewReason.driftTooLarge],
        cls: cls,
      );
    }
    final shifted = KcalRange(i.kcalRange.low + delta, i.kcalRange.high + delta);
    if (!i.bounds.contains(shifted)) {
      return build(
        ReviewDecisionKind.keep,
        [...why.where((r) => r == ReviewReason.tooFast), ReviewReason.atSafetyLimit],
        cls: cls,
      );
    }
    return build(
      ReviewDecisionKind.adjustKcal,
      why,
      cls: cls,
      deltaKcal: delta,
      newRange: shifted,
      newDrift: newDrift,
    );
  }

  // 4. Faster than allowed: immediate correction toward more energy (loss) or
  // less (gain). No waiting period, no two-review rule.
  if (i.goal != GoalDirection.maintain && i.maxKgPerWeek > 0) {
    final limit = i.maxKgPerWeek * SafetyClamps.tooFastFactor;
    final tooFast = i.goal == GoalDirection.lose
        ? slope < -limit - _eps
        : slope > limit + _eps;
    if (tooFast) {
      final delta = i.goal == GoalDirection.lose
          ? SafetyClamps.reviewStepKcal
          : -SafetyClamps.reviewStepKcal;
      return kcalChange(delta, [
        ReviewReason.tooFast,
        delta > 0 ? ReviewReason.kcalRaised : ReviewReason.kcalLowered,
      ]);
    }
  }

  // 6. Recomposition: weight on track or flat while body fat meaningfully
  // falls (only a trustworthy, non-provisional series counts).
  final bfDown = bf != null && bf.isMeaningfulDecrease;
  final weightFlat = slope.abs() <= flatThreshold + _eps;
  if (bfDown && (cls == ReviewClass.onTrack || weightFlat)) {
    return build(
      ReviewDecisionKind.keep,
      [if (cls == ReviewClass.onTrack) ReviewReason.onTrack, ReviewReason.recomposition],
      cls: cls,
    );
  }

  if (cls == ReviewClass.onTrack) {
    return build(ReviewDecisionKind.keep, [ReviewReason.onTrack], cls: cls);
  }
  if (cls == ReviewClass.ahead) {
    return build(ReviewDecisionKind.keep, [ReviewReason.aheadOfPlan], cls: cls);
  }

  // 5. behind / drift: two consecutive classifications AND the cooldown.
  if (i.previousClass != cls) {
    return build(ReviewDecisionKind.keep, [ReviewReason.behindWaiting], cls: cls);
  }
  final cooldown = i.daysSinceLastKcalAdjust;
  if (cooldown != null && cooldown < SafetyClamps.reviewCooldownDays) {
    return build(ReviewDecisionKind.keep, [ReviewReason.cooldownActive], cls: cls);
  }

  final manual = i.ownership == PlanOwnership.manual;
  final stepsOk = manual || i.autoAdjust.steps;
  final kcalOk = manual || i.autoAdjust.kcal;

  // (a) Steps first, for a loss goal only (more steps for someone who is
  // gaining on purpose would work against the goal).
  if (i.goal == GoalDirection.lose &&
      cls == ReviewClass.behind &&
      stepsOk &&
      i.stepsGoal + SafetyClamps.stepsGoalIncrement <=
          SafetyClamps.stepsGoalMax) {
    return build(
      ReviewDecisionKind.adjustSteps,
      [ReviewReason.stepsRaised],
      cls: cls,
      deltaSteps: SafetyClamps.stepsGoalIncrement,
      newSteps: i.stepsGoal + SafetyClamps.stepsGoalIncrement,
    );
  }
  // (b) Then calories.
  if (!kcalOk) {
    return build(ReviewDecisionKind.keep, [ReviewReason.autoAdjustOff], cls: cls);
  }
  final int delta;
  if (i.goal == GoalDirection.maintain) {
    delta = cls == ReviewClass.driftUp
        ? -SafetyClamps.maintainDriftStepKcal
        : SafetyClamps.maintainDriftStepKcal;
  } else {
    delta = i.goal == GoalDirection.lose
        ? -SafetyClamps.reviewStepKcal
        : SafetyClamps.reviewStepKcal;
  }
  return kcalChange(
    delta,
    [delta > 0 ? ReviewReason.kcalRaised : ReviewReason.kcalLowered],
  );
}

double _max(double a, double b) => a > b ? a : b;

// --- ISO week key ------------------------------------------------------------

/// ISO-8601 week key `yyyy-Www` of the calendar date `year-month-day`.
///
/// The year is the ISO week-year (the year of the week's Thursday), so
/// 2026-12-31 and 2027-01-01 are both `2026-W53` and 2027-01-04 is `2027-W01`.
String isoWeekKeyForDate(int year, int month, int day) {
  final date = DateTime.utc(year, month, day);
  // Monday = 1 .. Sunday = 7; move to the Thursday of this ISO week.
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(jan1).inDays + 1;
  final week = (dayOfYear - 1) ~/ 7 + 1;
  final y = thursday.year.toString().padLeft(4, '0');
  return '$y-W${week.toString().padLeft(2, '0')}';
}

/// The review week key for the instant [at], on the calendar of the user's
/// timezone, given EXPLICITLY as its UTC offset (so the result never depends
/// on the machine's zone). Use the local offset at decision time.
String reviewWeekKey(DateTime at, {required Duration utcOffset}) {
  final local = at.toUtc().add(utcOffset);
  return isoWeekKeyForDate(local.year, local.month, local.day);
}
