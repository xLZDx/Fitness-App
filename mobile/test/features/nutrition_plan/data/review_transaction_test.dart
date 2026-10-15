// C18 review_transaction_test. The PURE core of the D-57 atomic review
// transaction and of the 7-day undo. Every refusal must write NOTHING (no review,
// no plan), every success must write the review and the plan change together.
// Expected numbers are derived from design s13/s15 and the fixtures' hand-made
// bounds (1850..2400), not read back from the code under test.
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/review_transaction.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';

ReviewTxnResult _run({
  required WeeklyReviewDecision decision,
  StoredNutritionPlan? plan,
  PlanReviewRecord? existing,
  bool noPlan = false,
}) =>
    planReviewTransaction(
      week: kWeek,
      decision: decision,
      existingReview: existing,
      currentPlan: noPlan ? null : (plan ?? storedPlan()),
      now: kNow,
    );

void _expectNothingWritten(ReviewTxnResult r, ReviewApplyOutcome outcome) {
  expect(r.outcome, outcome);
  expect(r.review, isNull, reason: 'a refused transaction must not write a review');
  expect(r.plan, isNull, reason: 'a refused transaction must not write the plan');
}

PlanReviewRecord _existingReview() =>
    PlanReviewRecord.fromDecision(kWeek, keepDecision(), kNow);

void main() {
  group('step 1: the week key is the idempotency guard', () {
    test('an existing review of the week -> alreadyReviewed, nothing written', () {
      _expectNothingWritten(
        _run(decision: decisionOf(), existing: _existingReview()),
        ReviewApplyOutcome.alreadyReviewed,
      );
    });

    test('the guard runs BEFORE the plan checks (no plan, stale version)', () {
      _expectNothingWritten(
        _run(decision: decisionOf(), existing: _existingReview(), noPlan: true),
        ReviewApplyOutcome.alreadyReviewed,
      );
      _expectNothingWritten(
        _run(
          decision: decisionOf(base: 1),
          existing: _existingReview(),
          plan: storedPlan(version: 9),
        ),
        ReviewApplyOutcome.alreadyReviewed,
      );
    });
  });

  group('step 2: plan and version', () {
    test('no plan document -> noPlan, nothing written', () {
      _expectNothingWritten(
        _run(decision: decisionOf(), noPlan: true),
        ReviewApplyOutcome.noPlan,
      );
    });

    test('planVersion != basePlanVersion -> staleVersion for both directions', () {
      _expectNothingWritten(
        _run(decision: decisionOf(base: 3), plan: storedPlan(version: 4)),
        ReviewApplyOutcome.staleVersion,
      );
      _expectNothingWritten(
        _run(decision: decisionOf(base: 3), plan: storedPlan(version: 2)),
        ReviewApplyOutcome.staleVersion,
      );
    });

    test('a stale version is refused even for a no-change (keep) decision', () {
      _expectNothingWritten(
        _run(decision: keepDecision(base: 3), plan: storedPlan(version: 4)),
        ReviewApplyOutcome.staleVersion,
      );
    });

    test('the version check precedes the cooldown check', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(base: 3),
          plan: storedPlan(
              version: 4, lastAdjust: kNow.subtract(const Duration(days: 1))),
        ),
        ReviewApplyOutcome.staleVersion,
      );
    });
  });

  group('no-change decisions record the review and leave the plan alone', () {
    for (final kind in [
      ReviewDecisionKind.keep,
      ReviewDecisionKind.needMoreData,
      ReviewDecisionKind.needRecalculation,
    ]) {
      test('${kind.name} -> written, review only, no plan write', () {
        final r = _run(
          decision: decisionOf(
            kind: kind,
            reasons: const [ReviewReason.needMoreDataPoints],
            deltaKcal: 0,
            cls: kind == ReviewDecisionKind.needMoreData ? null : ReviewClass.behind,
          ),
        );
        expect(r.outcome, ReviewApplyOutcome.written);
        expect(r.plan, isNull);
        expect(r.review, isNotNull);
        expect(r.review!.week, kWeek);
        expect(r.review!.decision, kind);
        expect(r.review!.basePlanVersion, 3);
        expect(r.review!.decidedAt, kNow);
        expect(r.review!.deltaKcal, 0);
        expect(r.review!.reasonCodes, [ReviewReason.needMoreDataPoints]);
      });
    }

    test('the review keeps the classification for the next review', () {
      final r = _run(decision: keepDecision());
      expect(r.review!.classification, ReviewClass.onTrack);
    });

    test('keep is recorded even while the cooldown is active', () {
      final r = _run(
        decision: keepDecision(),
        plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 2))),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.review, isNotNull);
    });
  });

  group('step 3: the cooldown is re-checked against the PLAN document', () {
    test('13 days since the last change -> rejected, nothing written', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(),
          plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 13))),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('13 days 23 hours is still inside the cooldown (whole days)', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(),
          plan: storedPlan(
              lastAdjust:
                  kNow.subtract(const Duration(days: 13, hours: 23))),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('exactly 14 days -> allowed', () {
      final r = _run(
        decision: decisionOf(),
        plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 14))),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan, isNotNull);
    });

    test('never adjusted (null lastKcalAdjustAt) -> no cooldown', () {
      final r = _run(decision: decisionOf(), plan: storedPlan(lastAdjust: null));
      expect(r.outcome, ReviewApplyOutcome.written);
    });

    test('a steps change is also held by the cooldown', () {
      _expectNothingWritten(
        _run(
          decision: stepsDecision(),
          plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 5))),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('tooFast is exempt: applied one day after the last change', () {
      final r = _run(
        decision: decisionOf(
          deltaKcal: 150,
          reasons: const [ReviewReason.tooFast, ReviewReason.kcalRaised],
        ),
        plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 1))),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.kcalRange, const KcalRange(2150, 2350));
    });

    test('a decision without tooFast in the same position is rejected', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(
            deltaKcal: 150,
            reasons: const [ReviewReason.kcalRaised],
          ),
          plan: storedPlan(lastAdjust: kNow.subtract(const Duration(days: 1))),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('shared ownership is held by the cooldown too', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(application: ReviewApplication.proposed),
          plan: storedPlan(
            ownership: PlanOwnership.shared,
            lastAdjust: kNow.subtract(const Duration(days: 3)),
          ),
        ),
        ReviewApplyOutcome.rejected,
      );
    });
  });

  group('step 3: the drift cap (400 kcal) is re-checked', () {
    test('cumulative drift past the cap -> rejected', () {
      // 300 + (-150)... reaching -450: |-450| > 400.
      _expectNothingWritten(
        _run(decision: decisionOf(deltaKcal: -150), plan: storedPlan(drift: -300)),
        ReviewApplyOutcome.rejected,
      );
      _expectNothingWritten(
        _run(decision: decisionOf(deltaKcal: 150), plan: storedPlan(drift: 300)),
        ReviewApplyOutcome.rejected,
      );
    });

    test('drift landing exactly on the cap is allowed', () {
      final r = _run(
        decision: decisionOf(deltaKcal: -150),
        plan: storedPlan(drift: -250),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.driftFromInitialKcal, -400);
    });

    test('a change that REDUCES the drift is allowed even at the cap', () {
      final r = _run(
        decision: decisionOf(deltaKcal: 150),
        plan: storedPlan(drift: -400),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.driftFromInitialKcal, -250);
    });

    test('the drift is taken from the stored plan, not the decision', () {
      // The decision (made from older data) said newDrift = -150; the stored
      // plan already drifted -300, so the transaction must refuse.
      _expectNothingWritten(
        _run(
          decision: decisionOf(deltaKcal: -150),
          plan: storedPlan(drift: -300),
        ),
        ReviewApplyOutcome.rejected,
      );
    });
  });

  group('step 3: bounds are re-checked against the RECOMPUTED bounds', () {
    test('shifted range below the lower bound -> rejected', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(deltaKcal: -150),
          plan: storedPlan(range: const KcalRange(1900, 2100)),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('shifted range above the upper bound -> rejected', () {
      _expectNothingWritten(
        _run(
          decision: decisionOf(deltaKcal: 150),
          plan: storedPlan(range: const KcalRange(2250, 2400)),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('landing exactly on both bounds is allowed', () {
      final low = _run(
        decision: decisionOf(deltaKcal: -150),
        plan: storedPlan(range: const KcalRange(2000, 2200)),
      );
      expect(low.plan!.kcalRange, const KcalRange(1850, 2050));
      final high = _run(
        decision: decisionOf(deltaKcal: 150),
        plan: storedPlan(range: const KcalRange(2000, 2250)),
      );
      expect(high.plan!.kcalRange, const KcalRange(2150, 2400));
    });

    test('a stored kcalBounds field that was hand-widened does not help', () {
      // The document claims bounds 1000..6000; the recomputed ones are 1850..2400.
      _expectNothingWritten(
        _run(
          decision: decisionOf(deltaKcal: -150),
          plan: storedPlan(
            range: const KcalRange(1900, 2100),
            bounds: const PlanBounds(1000, 6000),
          ),
        ),
        ReviewApplyOutcome.rejected,
      );
    });

    test('the change is computed from the VALIDATED range, not the raw one', () {
      // A hand-edited range 1000-1100 is pulled to 1850-1950 first; +150 gives
      // 2000-2100.
      final r = _run(
        decision: decisionOf(
          deltaKcal: 150,
          reasons: const [ReviewReason.tooFast, ReviewReason.kcalRaised],
        ),
        plan: storedPlan(range: const KcalRange(1000, 1100)),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.kcalRange, const KcalRange(2000, 2100));
    });

    test('steps goal above 12,000 -> rejected; exactly 12,000 allowed', () {
      _expectNothingWritten(
        _run(decision: stepsDecision(), plan: storedPlan(stepsGoal: 11500)),
        ReviewApplyOutcome.rejected,
      );
      final r = _run(decision: stepsDecision(), plan: storedPlan(stepsGoal: 11000));
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.stepsGoal, 12000);
    });
  });

  group('step 4: a coached kcal change writes review + plan + undo together', () {
    late ReviewTxnResult r;
    final before = storedPlan(version: 3, drift: -100);
    setUp(() {
      r = _run(decision: decisionOf(deltaKcal: -150), plan: before);
    });

    test('both documents are produced by ONE result', () {
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.review, isNotNull);
      expect(r.plan, isNotNull);
      expect(r.review!.basePlanVersion, before.planVersion);
      expect(r.plan!.planVersion, before.planVersion + 1);
    });

    test('range shifted, drift accumulated, steps untouched', () {
      expect(r.plan!.kcalRange, const KcalRange(1850, 2050));
      expect(r.plan!.driftFromInitialKcal, -250);
      expect(r.plan!.stepsGoal, 8500);
    });

    test('macros are re-derived for the NEW range', () {
      final expected = macrosOf(const KcalRange(1850, 2050));
      expect(r.plan!.protein.maxG, expected.protein.maxG);
      expect(r.plan!.protein.targetG, expected.protein.targetG);
      expect(r.plan!.fat.minG, expected.fat.minG);
      expect(r.plan!.fat.maxG, expected.fat.maxG);
      expect(r.plan!.carbs.minG, expected.carbs.minG);
      expect(r.plan!.carbs.maxG, expected.carbs.maxG);
      // And the new carb band really differs from the old range's band.
      expect(r.plan!.carbs.maxG, isNot(before.carbs.maxG));
    });

    test('lastKcalAdjustAt is stamped with now', () {
      expect(r.plan!.lastKcalAdjustAt, kNow);
      expect(r.plan!.daysSinceLastAdjust(kNow), 0);
    });

    test('reviewUndo keeps the previous values and expires in exactly 7 days', () {
      final u = r.plan!.reviewUndo!;
      expect(u.week, kWeek);
      expect(u.prevKcalRange, const KcalRange(2000, 2200));
      expect(u.prevStepsGoal, 8500);
      expect(u.prevDrift, -100);
      expect(u.undone, isFalse);
      expect(u.expiresAt, kNow.add(const Duration(days: 7)));
      expect(kReviewUndoWindow, const Duration(days: 7));
    });

    test('the review document records delta, reasons and decision', () {
      expect(r.review!.decision, ReviewDecisionKind.adjustKcal);
      expect(r.review!.deltaKcal, -150);
      expect(r.review!.reasonCodes, [ReviewReason.kcalLowered]);
      expect(r.review!.week, kWeek);
    });

    test('the written plan is already validated (bounds recomputed)', () {
      expect(r.plan!.kcalBounds, kLoseBounds);
    });
  });

  group('step 4: a coached steps change', () {
    test('raises the goal, keeps kcal and drift, still starts the cooldown', () {
      final before = storedPlan(drift: -150, stepsGoal: 8500);
      final r = _run(decision: stepsDecision(), plan: before);
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan!.stepsGoal, 9500);
      expect(r.plan!.kcalRange, before.kcalRange);
      expect(r.plan!.driftFromInitialKcal, -150);
      expect(r.plan!.protein.targetG, before.protein.targetG);
      expect(r.plan!.planVersion, 4);
      expect(r.plan!.lastKcalAdjustAt, kNow);
      expect(r.plan!.reviewUndo!.prevStepsGoal, 8500);
      expect(r.plan!.reviewUndo!.prevKcalRange, before.kcalRange);
      expect(r.review!.deltaSteps, 1000);
    });
  });

  group('step 4: shared and manual write the review ONLY', () {
    for (final entry in {
      PlanOwnership.shared: ReviewApplication.proposed,
      PlanOwnership.manual: ReviewApplication.insightOnly,
    }.entries) {
      test('${entry.key.name}: kcal change is recorded, plan untouched', () {
        final r = _run(
          decision: decisionOf(application: entry.value),
          plan: storedPlan(ownership: entry.key),
        );
        expect(r.outcome, ReviewApplyOutcome.written);
        expect(r.review, isNotNull);
        expect(r.review!.decision, ReviewDecisionKind.adjustKcal);
        expect(r.review!.deltaKcal, -150);
        expect(r.plan, isNull,
            reason: 'a shared proposal waits for accept; manual only informs');
      });

      test('${entry.key.name}: steps change is recorded, plan untouched', () {
        final r = _run(
          decision: stepsDecision(application: entry.value),
          plan: storedPlan(ownership: entry.key),
        );
        expect(r.outcome, ReviewApplyOutcome.written);
        expect(r.review!.deltaSteps, 1000);
        expect(r.plan, isNull);
      });
    }

    test('ownership switched to shared after the decision -> not applied', () {
      // The decision was made for a coached plan (application: applied), but the
      // stored plan is shared now.
      final r = _run(
        decision: decisionOf(application: ReviewApplication.applied),
        plan: storedPlan(ownership: PlanOwnership.shared),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan, isNull);
    });

    test('a proposed decision on a coached plan is not auto-applied', () {
      final r = _run(
        decision: decisionOf(application: ReviewApplication.proposed),
        plan: storedPlan(ownership: PlanOwnership.coached),
      );
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.plan, isNull);
    });
  });

  group('applyDecisionToPlan', () {
    test('bumps the version, stamps the time, clears the undo when none given', () {
      final withUndo = storedPlan(
        undo: ReviewUndo(
          week: '2026-W40',
          prevKcalRange: const KcalRange(2100, 2300),
          prevStepsGoal: 8000,
          prevDrift: 0,
          expiresAt: kNow.add(const Duration(days: 1)),
        ),
      );
      final next = applyDecisionToPlan(
        withUndo,
        kcalRange: const KcalRange(2050, 2250),
        drift: -50,
        now: kNow,
      );
      expect(next.planVersion, 4);
      expect(next.kcalRange, const KcalRange(2050, 2250));
      expect(next.driftFromInitialKcal, -50);
      expect(next.lastKcalAdjustAt, kNow);
      expect(next.reviewUndo, isNull);
    });

    test('a range outside the bounds is pulled inside (validated)', () {
      final next = applyDecisionToPlan(
        storedPlan(),
        kcalRange: const KcalRange(1500, 1700),
        drift: 0,
        now: kNow,
      );
      expect(next.kcalRange.low, 1850);
      expect(kLoseBounds.contains(next.kcalRange), isTrue);
    });
  });

  group('undo transaction', () {
    ReviewUndo undo({
      bool undone = false,
      Duration remaining = const Duration(days: 3),
    }) =>
        ReviewUndo(
          week: kWeek,
          prevKcalRange: const KcalRange(2100, 2300),
          prevStepsGoal: 8000,
          prevDrift: -40,
          expiresAt: kNow.add(remaining),
          undone: undone,
        );

    UndoTxnResult run(StoredNutritionPlan? plan, {int version = 5}) =>
        planUndoTransaction(
            currentPlan: plan, expectedVersion: version, now: kNow);

    test('no plan -> noPlan', () {
      final r = run(null);
      expect(r.outcome, UndoOutcome.noPlan);
      expect(r.plan, isNull);
    });

    test('a different planVersion -> staleVersion, nothing restored', () {
      final r = run(storedPlan(version: 6, undo: undo()), version: 5);
      expect(r.outcome, UndoOutcome.staleVersion);
      expect(r.plan, isNull);
    });

    test('no undo record -> notAvailable', () {
      final r = run(storedPlan(version: 5));
      expect(r.outcome, UndoOutcome.notAvailable);
      expect(r.plan, isNull);
    });

    test('an already undone record -> notAvailable', () {
      final r = run(storedPlan(version: 5, undo: undo(undone: true)));
      expect(r.outcome, UndoOutcome.notAvailable);
      expect(r.plan, isNull);
    });

    test('expired exactly at expiresAt -> notAvailable (strict window)', () {
      final r = run(storedPlan(version: 5, undo: undo(remaining: Duration.zero)));
      expect(r.outcome, UndoOutcome.notAvailable);
    });

    test('expired in the past -> notAvailable', () {
      final r = run(storedPlan(
          version: 5, undo: undo(remaining: const Duration(days: -1))));
      expect(r.outcome, UndoOutcome.notAvailable);
    });

    test('one second before expiry -> undone', () {
      final r = run(storedPlan(
          version: 5, undo: undo(remaining: const Duration(seconds: 1))));
      expect(r.outcome, UndoOutcome.undone);
    });

    test('restores range, steps, drift, macros; bumps version; marks undone', () {
      final cur = storedPlan(
        version: 5,
        range: const KcalRange(1950, 2150),
        stepsGoal: 9500,
        drift: -190,
        lastAdjust: kNow.subtract(const Duration(days: 2)),
        undo: undo(),
      );
      final r = run(cur);
      expect(r.outcome, UndoOutcome.undone);
      final p = r.plan!;
      expect(p.planVersion, 6);
      expect(p.kcalRange, const KcalRange(2100, 2300));
      expect(p.stepsGoal, 8000);
      expect(p.driftFromInitialKcal, -40);
      final m = macrosOf(const KcalRange(2100, 2300));
      expect(p.carbs.maxG, m.carbs.maxG);
      expect(p.carbs.minG, m.carbs.minG);
      expect(p.protein.maxG, m.protein.maxG);
      expect(p.reviewUndo!.undone, isTrue);
      expect(p.reviewUndo!.week, kWeek);
      expect(p.reviewUndo!.prevKcalRange, const KcalRange(2100, 2300));
    });

    test('lastKcalAdjustAt is KEPT so the cooldown survives an undo', () {
      final adjusted = kNow.subtract(const Duration(days: 2));
      final r = run(storedPlan(version: 5, lastAdjust: adjusted, undo: undo()));
      expect(r.plan!.lastKcalAdjustAt, adjusted);
      expect(r.plan!.daysSinceLastAdjust(kNow), 2);
    });

    test('a second undo of the result is refused', () {
      final first = run(storedPlan(version: 5, undo: undo()));
      final second = run(first.plan, version: 6);
      expect(second.outcome, UndoOutcome.notAvailable);
    });
  });

  group('review then undo round trip', () {
    test('apply a coached change, undo it: original range, steps, drift', () {
      final original = storedPlan(version: 3, drift: -100);
      final applied = _run(decision: decisionOf(deltaKcal: -150), plan: original);
      final undone = planUndoTransaction(
        currentPlan: applied.plan,
        expectedVersion: 4,
        now: kNow.add(const Duration(days: 1)),
      );
      expect(undone.outcome, UndoOutcome.undone);
      expect(undone.plan!.kcalRange, original.kcalRange);
      expect(undone.plan!.stepsGoal, original.stepsGoal);
      expect(undone.plan!.driftFromInitialKcal, -100);
      expect(undone.plan!.planVersion, 5);
    });

    test('the undo is refused once the 7 days have passed', () {
      final applied = _run(decision: decisionOf(), plan: storedPlan());
      final tooLate = planUndoTransaction(
        currentPlan: applied.plan,
        expectedVersion: 4,
        now: kNow.add(const Duration(days: 7)),
      );
      expect(tooLate.outcome, UndoOutcome.notAvailable);
    });
  });
}
