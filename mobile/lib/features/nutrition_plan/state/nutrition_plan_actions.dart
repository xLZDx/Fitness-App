/// User-driven plan writes for the Plan screen (C19): create the first plan,
/// edit the range / steps / ownership / auto-adjust toggles, accept a shared
/// proposal and undo a coached review.
///
/// Every write: requires an `eligible` device-local verdict (nothing is ever
/// written for anyone else, D-55), re-validates against the recomputed bounds,
/// is fenced by the account-deletion flag, and is a version-checked write (a
/// concurrent change from another device is a `conflict`, never an overwrite).
/// The data-notice acknowledgement (D-79) is the caller's job, as for weights.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_deletion/state/account_deletion_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/nutrition_eligibility.dart';
import '../data/plan_calculator.dart';
import '../data/plan_repository.dart';
import '../data/plan_review_record.dart';
import '../data/review_transaction.dart';
import '../data/safety_clamps.dart';
import '../data/stored_nutrition_plan.dart';
import '../data/weekly_review.dart';
import 'nutrition_providers.dart';
import 'weight_providers.dart';

enum PlanActionStatus {
  saved,
  conflict,
  offline,
  signedOut,
  notEligible,
  noInputs,
  noPlan,

  /// The stored plan could not be read (or the read failed); nothing written.
  unreadable,

  /// The change would leave the safety bounds / drift cap, or is not a pending
  /// proposal; nothing written.
  refused,
}

class PlanActionResult {
  const PlanActionResult(this.status, {this.plan});

  final PlanActionStatus status;
  final StoredNutritionPlan? plan;

  bool get saved => status == PlanActionStatus.saved;
}

class NutritionPlanActions {
  NutritionPlanActions(this._ref);

  final Ref _ref;

  /// The signed-in uid when writing is allowed, else the refusing status.
  (String?, PlanActionStatus?) _gate() {
    final uid = _ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return (null, PlanActionStatus.signedOut);
    if (_ref.read(accountBeingDeletedUidProvider) == uid) {
      return (null, PlanActionStatus.signedOut);
    }
    final verdict = _ref.read(nutritionEligibilityProvider);
    if (verdict == null || verdict is! Eligible) {
      return (null, PlanActionStatus.notEligible);
    }
    return (uid, null);
  }

  PlanActionResult _fromWrite(PlanWriteResult r) => switch (r.outcome) {
        PlanWriteOutcome.saved =>
          PlanActionResult(PlanActionStatus.saved, plan: r.plan),
        PlanWriteOutcome.conflict =>
          const PlanActionResult(PlanActionStatus.conflict),
        PlanWriteOutcome.offline =>
          const PlanActionResult(PlanActionStatus.offline),
      };

  /// Creates the first plan from the profile when none exists; returns the
  /// existing plan untouched when there is one.
  Future<PlanActionResult> ensurePlan() async {
    final (uid, refused) = _gate();
    if (uid == null) return PlanActionResult(refused!);
    final repo = _ref.read(nutritionPlanRepositoryProvider);
    final existing = await repo.loadPlan(uid);
    if (existing != null) {
      return PlanActionResult(PlanActionStatus.saved, plan: existing);
    }
    final inputs = _ref.read(nutritionInputsProvider)?.inputs;
    if (inputs == null) {
      return const PlanActionResult(PlanActionStatus.noInputs);
    }
    final profile = _ref.read(currentProfileProvider).valueOrNull;
    final computed = computePlan(inputs);
    final plan = StoredNutritionPlan.fromComputed(
      computed,
      now: _ref.read(nutritionClockProvider)(),
      digest: StoredNutritionPlan.digestOf(
        computed,
        inputs.weightKg,
        inputs.heightCm,
        inputs.ageYears,
        inputs.sex,
      ),
      ownership: profile?.nutrition.planOwnership ?? PlanOwnership.coached,
    );
    return _fromWrite(await repo.savePlan(uid, plan, expectedVersion: null));
  }

  /// Loads the fresh plan, applies [mutate] and writes it version-checked; one
  /// retry when another device wrote in between.
  Future<PlanActionResult> _update(
    StoredNutritionPlan? Function(StoredNutritionPlan plan) mutate,
  ) async {
    final (uid, refused) = _gate();
    if (uid == null) return PlanActionResult(refused!);
    final repo = _ref.read(nutritionPlanRepositoryProvider);
    for (var attempt = 0; attempt < 2; attempt++) {
      final current = await repo.loadPlan(uid);
      if (current == null) return const PlanActionResult(PlanActionStatus.noPlan);
      final next = mutate(current);
      if (next == null) return const PlanActionResult(PlanActionStatus.refused);
      final r = await repo.savePlan(uid, next,
          expectedVersion: current.planVersion);
      if (r.outcome != PlanWriteOutcome.conflict) return _fromWrite(r);
    }
    return const PlanActionResult(PlanActionStatus.conflict);
  }

  /// The slider result. The range is pulled inside the recomputed bounds; an
  /// edit by a coached user switches ownership to shared (design s18); the
  /// macros follow the range.
  Future<PlanActionResult> setKcalRange(KcalRange range) => _update((p) {
        final bounds = p.recomputeBounds();
        final fitted = clampRangeToBounds(range, bounds);
        final macros = p.macrosFor(fitted);
        return p.copyWith(
          kcalRange: fitted,
          kcalBounds: bounds,
          protein: macros.protein,
          fat: macros.fat,
          carbs: macros.carbs,
          ownership: p.ownership == PlanOwnership.coached
              ? PlanOwnership.shared
              : p.ownership,
        );
      });

  Future<PlanActionResult> setStepsGoal(int steps) => _update((p) => p.copyWith(
        stepsGoal: steps
            .clamp(SafetyClamps.stepsUserMin, SafetyClamps.stepsUserMax)
            .toInt(),
      ));

  /// Takes effect at the next review; never rewrites the current range.
  Future<PlanActionResult> setOwnership(PlanOwnership ownership) =>
      _update((p) => p.copyWith(ownership: ownership));

  /// Manual forces both toggles off in effect (the review ignores them); the
  /// stored values are the user's choice.
  Future<PlanActionResult> setAutoAdjust(AutoAdjust autoAdjust) =>
      _update((p) => p.copyWith(autoAdjust: autoAdjust));

  /// Accepts a SHARED proposal: applies the review's change to the plan it was
  /// decided against. Refused when the plan moved on, the plan is not shared,
  /// the review proposes nothing, or the change would leave the bounds or the
  /// drift cap.
  Future<PlanActionResult> acceptProposal(PlanReviewRecord review) async {
    final (uid, refused) = _gate();
    if (uid == null) return PlanActionResult(refused!);
    final repo = _ref.read(nutritionPlanRepositoryProvider);
    final plan = await repo.loadPlan(uid);
    if (plan == null) return const PlanActionResult(PlanActionStatus.noPlan);
    final kcal = review.decision == ReviewDecisionKind.adjustKcal;
    final steps = review.decision == ReviewDecisionKind.adjustSteps;
    if ((!kcal && !steps) ||
        plan.ownership != PlanOwnership.shared ||
        plan.planVersion != review.basePlanVersion) {
      return const PlanActionResult(PlanActionStatus.refused);
    }
    KcalRange? newRange;
    int? newSteps;
    var drift = plan.driftFromInitialKcal;
    if (kcal) {
      drift += review.deltaKcal;
      newRange = KcalRange(plan.kcalRange.low + review.deltaKcal,
          plan.kcalRange.high + review.deltaKcal);
      if (drift.abs() > SafetyClamps.reviewDriftCapKcal ||
          !plan.recomputeBounds().contains(newRange)) {
        return const PlanActionResult(PlanActionStatus.refused);
      }
    } else {
      newSteps = plan.stepsGoal + review.deltaSteps;
      if (newSteps > SafetyClamps.stepsGoalMax) {
        return const PlanActionResult(PlanActionStatus.refused);
      }
    }
    final next = applyDecisionToPlan(
      plan,
      kcalRange: newRange,
      stepsGoal: newSteps,
      drift: drift,
      now: _ref.read(nutritionClockProvider)(),
    );
    return _fromWrite(
      await repo.savePlan(uid, next, expectedVersion: review.basePlanVersion),
    );
  }

  /// Undo of the last automatically applied (coached) review, within 7 days.
  Future<PlanActionResult> undoLastReview() async {
    final (uid, refused) = _gate();
    if (uid == null) return PlanActionResult(refused!);
    final repo = _ref.read(nutritionPlanRepositoryProvider);
    final plan = await repo.loadPlan(uid);
    if (plan == null) return const PlanActionResult(PlanActionStatus.noPlan);
    final r = await repo.undoLastReview(
      uid,
      expectedVersion: plan.planVersion,
      now: _ref.read(nutritionClockProvider)(),
    );
    return switch (r.outcome) {
      UndoOutcome.undone =>
        PlanActionResult(PlanActionStatus.saved, plan: r.plan),
      UndoOutcome.staleVersion =>
        const PlanActionResult(PlanActionStatus.conflict),
      UndoOutcome.noPlan => const PlanActionResult(PlanActionStatus.noPlan),
      UndoOutcome.notAvailable =>
        const PlanActionResult(PlanActionStatus.refused),
      UndoOutcome.offline => const PlanActionResult(PlanActionStatus.offline),
    };
  }
}

final nutritionPlanActionsProvider =
    Provider<NutritionPlanActions>((ref) => NutritionPlanActions(ref));
