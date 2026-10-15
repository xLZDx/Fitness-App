// Shared fixtures of the C18 plan-state tests (not a test file itself).
//
// The reference plan is a LOSE plan for a male, 80 kg, 180 cm (BMI 24.7, the
// low-BMI row: max 0.75 %/week capped at 0.5 kg/week), TDEE 2400, BMR 1800:
//   floor            = max(1500, 1800)               = 1800
//   max deficit      = min(0.25 * 2400, 0.5*7700/7)  = min(600, 550) = 550
//   bounds           = [ceil10(max(1800, 1850)), floor10(2400)] = 1850..2400
// These are hand-derived from design s13.3, never read back from the code.
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// 2026-10-15 is a Thursday: ISO week 2026-W42.
final DateTime kNow = DateTime(2026, 10, 15, 9);
const String kWeek = '2026-W42';
const String kUid = 'u1';

const PlanBounds kLoseBounds = PlanBounds(1850, 2400);

const PlanInputsDigest kDigest = PlanInputsDigest(
  weightKg: 80,
  heightCm: 180,
  ageYears: 35,
  activityFactor: 1.375,
  tdee: 2400,
  bmr: 1800,
  sexBasis: SexBasis.male,
);

MacroPlan macrosOf(KcalRange r, {GoalDirection goal = GoalDirection.lose}) =>
    computeMacros(weightKg: 80, heightCm: 180, goal: goal, kcal: r);

/// A stored lose plan inside the bounds (range 2000-2200, steps 8500).
StoredNutritionPlan storedPlan({
  int version = 3,
  PlanOwnership ownership = PlanOwnership.coached,
  AutoAdjust autoAdjust = const AutoAdjust(),
  KcalRange range = const KcalRange(2000, 2200),
  int stepsGoal = 8500,
  DateTime? lastAdjust,
  int drift = 0,
  ReviewUndo? undo,
  GoalDirection goal = GoalDirection.lose,
  PlanInputsDigest digest = kDigest,
  PlanBounds bounds = kLoseBounds,
  double ratePct = 0.5,
  DateTime? computedAt,
}) {
  final m = computeMacros(
    weightKg: digest.weightKg,
    heightCm: digest.heightCm,
    goal: goal,
    kcal: range,
  );
  return StoredNutritionPlan(
    planVersion: version,
    ownership: ownership,
    autoAdjust: autoAdjust,
    goal: goal,
    ratePctPerWeek: ratePct,
    kcalRange: range,
    kcalBounds: bounds,
    protein: m.protein,
    fat: m.fat,
    carbs: m.carbs,
    stepsGoal: stepsGoal,
    digest: digest,
    computedAt: computedAt ?? DateTime(2026, 9, 1, 8),
    lastKcalAdjustAt: lastAdjust,
    driftFromInitialKcal: drift,
    reviewUndo: undo,
  );
}

/// A decision built by hand, so the transaction is tested in isolation from
/// `decide`.
WeeklyReviewDecision decisionOf({
  ReviewDecisionKind kind = ReviewDecisionKind.adjustKcal,
  List<ReviewReason> reasons = const [ReviewReason.kcalLowered],
  ReviewApplication application = ReviewApplication.applied,
  int base = 3,
  int deltaKcal = -150,
  int deltaSteps = 0,
  ReviewClass? cls = ReviewClass.behind,
}) =>
    WeeklyReviewDecision(
      kind: kind,
      reasonCodes: reasons,
      application: application,
      basePlanVersion: base,
      inputs: const ReviewInputsRecord(
        weightSlopeKgPerWeek: -0.1,
        intendedKgPerWeek: -0.4,
        dataPoints: 5,
      ),
      classification: cls,
      deltaKcal: deltaKcal,
      deltaSteps: deltaSteps,
    );

WeeklyReviewDecision stepsDecision({
  int base = 3,
  ReviewApplication application = ReviewApplication.applied,
}) =>
    decisionOf(
      kind: ReviewDecisionKind.adjustSteps,
      reasons: const [ReviewReason.stepsRaised],
      deltaKcal: 0,
      deltaSteps: 1000,
      base: base,
      application: application,
    );

WeeklyReviewDecision keepDecision({int base = 3}) => decisionOf(
      kind: ReviewDecisionKind.keep,
      reasons: const [ReviewReason.onTrack],
      deltaKcal: 0,
      base: base,
      cls: ReviewClass.onTrack,
    );
