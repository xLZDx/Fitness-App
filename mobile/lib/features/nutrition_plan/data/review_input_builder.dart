/// Builds the [ReviewInput] of the weekly review from the stored plan, the
/// weight series and the stored review history (design s15). ONE builder is
/// used by the scheduler, by the live `weeklyReviewProvider` and by the
/// post-scan plan decision, so there is one decision path. Pure Dart, no
/// Flutter imports.
library;

import 'body_fat_trend_source.dart';
import 'nutrition_eligibility.dart';
import 'plan_review_record.dart';
import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';
import 'weight_entry.dart';

/// The review looks at the last 21 days of weigh-ins (design s15, 13.2).
const int kReviewWindowDays = 21;

/// The input of the review at [now], or null when there is no plan. The plan is
/// re-validated first, so the bounds the review checks are the recomputed ones.
/// [reviews] is newest first.
ReviewInput? buildReviewInput({
  required StoredNutritionPlan? plan,
  required NutritionEligibility eligibility,
  required Iterable<WeightEntry> weights,
  required List<PlanReviewRecord> reviews,
  required DateTime now,
  BodyFatTrendInput? bodyFatTrend,
}) {
  if (plan == null) return null;
  final p = plan.validated();
  final window = [
    for (final w in weights)
      if (!w.at.isAfter(now) &&
          now.difference(w.at).inMinutes <= kReviewWindowDays * 1440)
        w,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final span = window.length < 2
      ? 0
      : window.last.at.difference(window.first.at).inDays;
  final weightKg = window.isEmpty ? p.digest.weightKg : window.last.kg;
  return ReviewInput(
    eligibility: eligibility,
    goal: p.goal,
    ownership: p.ownership,
    autoAdjust: p.autoAdjust,
    kcalRange: p.kcalRange,
    bounds: p.kcalBounds,
    stepsGoal: p.stepsGoal,
    weightKg: weightKg,
    maxKgPerWeek: p.maxKgPerWeek,
    intendedKgPerWeek: p.intendedKgPerWeek,
    weightSlopeKgPerWeek: weightSlopeKgPerWeek(window, asOf: now),
    weightPoints: window.length,
    spanDays: span,
    previousClass: reviews.isEmpty ? null : reviews.first.classification,
    daysSinceLastKcalAdjust: p.daysSinceLastAdjust(now),
    driftFromInitialKcal: p.driftFromInitialKcal,
    basePlanVersion: p.planVersion,
    bodyFatTrend: bodyFatTrend,
    now: now,
  );
}
