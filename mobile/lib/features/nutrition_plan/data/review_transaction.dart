/// The PURE core of the atomic review transaction (design s15, D-57) and of the
/// undo. The Firestore repository runs it inside `runTransaction` and the
/// in-memory fake runs it directly, so both apply exactly the same rules.
/// No Flutter imports.
///
/// Order, as the design requires:
///  1. the review of the week already exists  -> no-op (the week key is the
///     idempotency guard);
///  2. no plan, or `planVersion != basePlanVersion` -> nothing written (a
///     decision made from stale inputs is recomputed);
///  3. cooldown, drift and bounds are re-checked against the PLAN DOCUMENT
///     (the cooldown, not the week key, stops two devices in different
///     timezones from double-adjusting);
///  4. the review document and the plan change are written together.
library;

import '../../profile/data/profile_models.dart';
import 'plan_calculator.dart';
import 'plan_review_record.dart';
import 'safety_clamps.dart';
import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';

/// The undo window of an automatically applied review.
const Duration kReviewUndoWindow = Duration(days: 7);

enum ReviewApplyOutcome {
  /// The review (and, when it applies, the plan change) was written.
  written,

  /// A review for this week already exists; nothing was written.
  alreadyReviewed,

  /// The plan changed since the decision was made; nothing was written.
  staleVersion,

  /// There is no readable plan; nothing was written.
  noPlan,

  /// The in-transaction re-check (cooldown, drift, bounds) refused the change;
  /// nothing was written and the next trigger recomputes.
  rejected,

  /// The transaction could not run (offline); nothing was written, the review
  /// is deferred, never half-queued.
  offline,
}

/// What a transaction attempt wants written.
class ReviewTxnResult {
  const ReviewTxnResult(this.outcome, {this.review, this.plan});

  final ReviewApplyOutcome outcome;

  /// Present only for [ReviewApplyOutcome.written].
  final PlanReviewRecord? review;

  /// The new plan document (already validated, `planVersion + 1`), present
  /// only when the review changes the plan.
  final StoredNutritionPlan? plan;
}

/// Decides what the transaction writes. [existingReview] and [currentPlan] are
/// what the two `get`s inside the transaction returned.
ReviewTxnResult planReviewTransaction({
  required String week,
  required WeeklyReviewDecision decision,
  required PlanReviewRecord? existingReview,
  required StoredNutritionPlan? currentPlan,
  required DateTime now,
}) {
  // 1. Idempotency guard.
  if (existingReview != null) {
    return const ReviewTxnResult(ReviewApplyOutcome.alreadyReviewed);
  }
  // 2. Plan and version.
  if (currentPlan == null) {
    return const ReviewTxnResult(ReviewApplyOutcome.noPlan);
  }
  if (currentPlan.planVersion != decision.basePlanVersion) {
    return const ReviewTxnResult(ReviewApplyOutcome.staleVersion);
  }
  final plan = currentPlan.validated();
  final record = PlanReviewRecord.fromDecision(week, decision, now);

  if (!decision.changesPlan) {
    return ReviewTxnResult(ReviewApplyOutcome.written, review: record);
  }

  // 3. Re-check the safety rules against the stored plan.
  final immediate = decision.reasonCodes.contains(ReviewReason.tooFast);
  final since = plan.daysSinceLastAdjust(now);
  if (!immediate &&
      since != null &&
      since < SafetyClamps.reviewCooldownDays) {
    return const ReviewTxnResult(ReviewApplyOutcome.rejected);
  }
  KcalRange? newRange;
  int? newSteps;
  int newDrift = plan.driftFromInitialKcal;
  if (decision.kind == ReviewDecisionKind.adjustKcal) {
    newDrift = plan.driftFromInitialKcal + decision.deltaKcal;
    if (newDrift.abs() > SafetyClamps.reviewDriftCapKcal) {
      return const ReviewTxnResult(ReviewApplyOutcome.rejected);
    }
    newRange = KcalRange(
      plan.kcalRange.low + decision.deltaKcal,
      plan.kcalRange.high + decision.deltaKcal,
    );
    if (!plan.kcalBounds.contains(newRange)) {
      return const ReviewTxnResult(ReviewApplyOutcome.rejected);
    }
  } else {
    newSteps = plan.stepsGoal + decision.deltaSteps;
    if (newSteps > SafetyClamps.stepsGoalMax) {
      return const ReviewTxnResult(ReviewApplyOutcome.rejected);
    }
  }

  // Shared proposes and manual only informs: the review is recorded, the plan
  // is untouched (a shared proposal is applied later on accept).
  if (decision.application != ReviewApplication.applied ||
      plan.ownership != PlanOwnership.coached) {
    return ReviewTxnResult(ReviewApplyOutcome.written, review: record);
  }

  // 4. Coached: apply with the 7-day undo record.
  final next = applyDecisionToPlan(
    plan,
    kcalRange: newRange,
    stepsGoal: newSteps,
    drift: newDrift,
    now: now,
    undo: ReviewUndo(
      week: week,
      prevKcalRange: plan.kcalRange,
      prevStepsGoal: plan.stepsGoal,
      prevDrift: plan.driftFromInitialKcal,
      expiresAt: now.add(kReviewUndoWindow),
    ),
  );
  return ReviewTxnResult(
    ReviewApplyOutcome.written,
    review: record,
    plan: next,
  );
}

/// The plan after a review change: new range (macros re-derived) or steps goal,
/// `planVersion + 1`, `lastKcalAdjustAt`, the drift and the optional undo.
/// Used by the coached transaction and by accepting a shared proposal.
StoredNutritionPlan applyDecisionToPlan(
  StoredNutritionPlan plan, {
  KcalRange? kcalRange,
  int? stepsGoal,
  required int drift,
  required DateTime now,
  ReviewUndo? undo,
}) {
  final macros = kcalRange == null ? null : plan.macrosFor(kcalRange);
  return plan
      .copyWith(
        planVersion: plan.planVersion + 1,
        kcalRange: kcalRange,
        stepsGoal: stepsGoal,
        protein: macros?.protein,
        fat: macros?.fat,
        carbs: macros?.carbs,
        lastKcalAdjustAt: now,
        driftFromInitialKcal: drift,
        reviewUndo: undo,
        clearReviewUndo: undo == null,
      )
      .validated();
}

enum UndoOutcome { undone, staleVersion, noPlan, notAvailable, offline }

class UndoTxnResult {
  const UndoTxnResult(this.outcome, {this.plan});

  final UndoOutcome outcome;
  final StoredNutritionPlan? plan;
}

/// The plan-only undo transaction: checks `planVersion`, that an undo record
/// exists, is not used and has not expired, then restores the previous values
/// and sets `undone = true`. `lastKcalAdjustAt` is kept so the cooldown still
/// holds after an undo.
UndoTxnResult planUndoTransaction({
  required StoredNutritionPlan? currentPlan,
  required int expectedVersion,
  required DateTime now,
}) {
  if (currentPlan == null) return const UndoTxnResult(UndoOutcome.noPlan);
  if (currentPlan.planVersion != expectedVersion) {
    return const UndoTxnResult(UndoOutcome.staleVersion);
  }
  final undo = currentPlan.reviewUndo;
  if (undo == null || !undo.isAvailableAt(now)) {
    return const UndoTxnResult(UndoOutcome.notAvailable);
  }
  final plan = currentPlan.validated();
  final macros = plan.macrosFor(undo.prevKcalRange);
  final next = plan
      .copyWith(
        planVersion: plan.planVersion + 1,
        kcalRange: undo.prevKcalRange,
        stepsGoal: undo.prevStepsGoal,
        protein: macros.protein,
        fat: macros.fat,
        carbs: macros.carbs,
        driftFromInitialKcal: undo.prevDrift,
        reviewUndo: undo.markUndone(),
      )
      .validated();
  return UndoTxnResult(UndoOutcome.undone, plan: next);
}
