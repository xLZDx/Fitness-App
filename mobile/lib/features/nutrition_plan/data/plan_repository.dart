/// Storage of the nutrition plan and its weekly reviews (design s5.4, s5.5,
/// s15). Implementations: [FirestorePlanRepository] and the in-memory fake in
/// `in_memory_nutrition_repositories.dart` (the same pattern as
/// `ProfileRepository` / `MockProfileRepository`).
///
/// Every read re-validates the plan (bounds recomputed, design s13) and every
/// write re-validates it again, so a document can never put the user outside
/// the clamps. Nothing is ever written for a user who is not eligible: callers
/// check the device-local verdict first (D-55); the repository has no notion of
/// `referProfessional`.
library;

import 'plan_review_record.dart';
import 'review_transaction.dart';
import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';

enum PlanWriteOutcome {
  saved,

  /// The stored `planVersion` is not the one the caller read; nothing written.
  conflict,

  /// The write could not run (offline); nothing written.
  offline,
}

class PlanWriteResult {
  const PlanWriteResult(this.outcome, {this.plan});

  final PlanWriteOutcome outcome;

  /// The plan as stored (present when [outcome] is `saved`).
  final StoredNutritionPlan? plan;
}

class ReviewApplyResult {
  const ReviewApplyResult(this.outcome, {this.review, this.plan});

  final ReviewApplyOutcome outcome;
  final PlanReviewRecord? review;

  /// The plan after the transaction when it changed the plan.
  final StoredNutritionPlan? plan;
}

class UndoResult {
  const UndoResult(this.outcome, {this.plan});

  final UndoOutcome outcome;
  final StoredNutritionPlan? plan;
}

abstract class NutritionPlanRepository {
  /// The stored plan, validated; null when there is none or it is unreadable.
  /// Replays the latest value to new subscribers.
  Stream<StoredNutritionPlan?> watchPlan(String uid);

  Future<StoredNutritionPlan?> loadPlan(String uid);

  /// Writes [plan] as version `expectedVersion + 1` (version 1 when
  /// [expectedVersion] is null, which also requires that no plan exists).
  /// A version mismatch is a `conflict`, never an overwrite.
  Future<PlanWriteResult> savePlan(
    String uid,
    StoredNutritionPlan plan, {
    required int? expectedVersion,
  });

  /// The weekly review transaction (D-57): review + plan change in ONE
  /// transaction. See [planReviewTransaction] for the exact rules.
  Future<ReviewApplyResult> applyReview(
    String uid, {
    required String week,
    required WeeklyReviewDecision decision,
    required DateTime now,
  });

  /// The plan-only undo transaction of the last automatically applied review.
  Future<UndoResult> undoLastReview(
    String uid, {
    required int expectedVersion,
    required DateTime now,
  });

  /// Newest first, at most [limit] (the history shows the last 12).
  /// Unreadable documents are skipped.
  Stream<List<PlanReviewRecord>> watchReviews(String uid, {int limit = 12});

  Future<List<PlanReviewRecord>> loadRecentReviews(String uid,
      {int limit = 12});

  Future<PlanReviewRecord?> loadReview(String uid, String week);
}
