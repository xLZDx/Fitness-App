// C18 review_input_builder_test. ONE builder feeds the scheduler, the live
// provider and the post-scan decision, so its window, previous-class and
// cooldown-days wiring decide every review.
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/review_input_builder.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';

WeightEntry _w(Duration ago, double kg) =>
    WeightEntry(at: kNow.subtract(ago), kg: kg);

PlanReviewRecord _review(String week, ReviewClass? cls) => PlanReviewRecord(
      week: week,
      decidedAt: kNow,
      basePlanVersion: 1,
      decision: ReviewDecisionKind.keep,
      deltaKcal: 0,
      deltaSteps: 0,
      reasonCodes: const [ReviewReason.onTrack],
      inputs: const ReviewInputsRecord(
        weightSlopeKgPerWeek: null,
        intendedKgPerWeek: -0.4,
        dataPoints: 3,
      ),
      classification: cls,
    );

ReviewInput? _build({
  required List<WeightEntry> weights,
  List<PlanReviewRecord> reviews = const [],
  plan = 'default',
}) =>
    buildReviewInput(
      plan: plan == 'default' ? storedPlan() : plan,
      eligibility: const Eligible(),
      weights: weights,
      reviews: reviews,
      now: kNow,
    );

void main() {
  test('the review window is 21 days', () {
    expect(kReviewWindowDays, 21);
  });

  test('no plan -> no input', () {
    expect(_build(weights: const [], plan: null), isNull);
  });

  group('window and span', () {
    test('an entry exactly 21 days old is in; one minute older is out', () {
      final i = _build(weights: [
        _w(const Duration(days: 21), 82),
        _w(const Duration(days: 21, minutes: 1), 90),
        _w(const Duration(days: 1), 80),
      ])!;
      expect(i.weightPoints, 2);
      expect(i.spanDays, 20);
    });

    test('a future-dated entry is ignored', () {
      final i = _build(weights: [
        _w(const Duration(days: 3), 80),
        WeightEntry(at: kNow.add(const Duration(hours: 1)), kg: 70),
      ])!;
      expect(i.weightPoints, 1);
      expect(i.weightKg, 80);
    });

    test('span is whole days between the first and last point', () {
      final i = _build(weights: [
        _w(const Duration(days: 14), 80),
        _w(const Duration(days: 7), 79.3),
        _w(Duration.zero, 78.6),
      ])!;
      expect(i.weightPoints, 3);
      expect(i.spanDays, 14);
    });

    test('fewer than two points -> span 0', () {
      expect(_build(weights: [_w(const Duration(days: 2), 80)])!.spanDays, 0);
      expect(_build(weights: const [])!.spanDays, 0);
    });

    test('entries are sorted: input order does not matter', () {
      final a = _build(weights: [
        _w(const Duration(days: 14), 80),
        _w(Duration.zero, 78.6),
        _w(const Duration(days: 7), 79.3),
      ])!;
      final b = _build(weights: [
        _w(Duration.zero, 78.6),
        _w(const Duration(days: 7), 79.3),
        _w(const Duration(days: 14), 80),
      ])!;
      expect(a.weightKg, 78.6);
      expect(b.weightKg, 78.6);
      expect(a.weightSlopeKgPerWeek, b.weightSlopeKgPerWeek);
    });

    test('the slope of a straight -0.7 kg/week series is -0.7', () {
      final i = _build(weights: [
        _w(const Duration(days: 14), 80),
        _w(const Duration(days: 7), 79.3),
        _w(Duration.zero, 78.6),
      ])!;
      expect(i.weightSlopeKgPerWeek, closeTo(-0.7, 0.01));
    });

    test('no data: slope null, weight falls back to the plan digest', () {
      final i = _build(weights: const [])!;
      expect(i.weightSlopeKgPerWeek, isNull);
      expect(i.weightPoints, 0);
      expect(i.weightKg, 80);
    });

    test('the weight is the LATEST point of the window', () {
      final i = _build(weights: [
        _w(const Duration(days: 10), 85),
        _w(const Duration(days: 1), 83.5),
      ])!;
      expect(i.weightKg, 83.5);
    });
  });

  group('plan wiring', () {
    test('goal, ownership, autoAdjust, steps and version come from the plan', () {
      final i = _build(
        weights: const [],
        plan: storedPlan(
          version: 8,
          ownership: PlanOwnership.shared,
          autoAdjust: const AutoAdjust(steps: false, kcal: true),
          stepsGoal: 9000,
        ),
      )!;
      expect(i.basePlanVersion, 8);
      expect(i.goal, GoalDirection.lose);
      expect(i.ownership, PlanOwnership.shared);
      expect(i.autoAdjust.steps, isFalse);
      expect(i.autoAdjust.kcal, isTrue);
      expect(i.stepsGoal, 9000);
      expect(i.eligibility, isA<Eligible>());
      expect(i.now, kNow);
    });

    test('the bounds are the RECOMPUTED ones, not the stored field', () {
      final i = _build(
        weights: const [],
        plan: storedPlan(bounds: const PlanBounds(1000, 6000)),
      )!;
      expect(i.bounds, kLoseBounds);
    });

    test('the range is the validated range', () {
      final i = _build(
        weights: const [],
        plan: storedPlan(range: const KcalRange(1000, 1100)),
      )!;
      expect(i.kcalRange, const KcalRange(1850, 1950));
    });

    test('max and intended rates: 0.5 kg/week cap, -0.4 intended', () {
      final i = _build(weights: const [])!;
      expect(i.maxKgPerWeek, closeTo(0.5, 1e-9));
      expect(i.intendedKgPerWeek, closeTo(-0.4, 1e-9));
    });

    test('drift is carried over', () {
      expect(_build(weights: const [], plan: storedPlan(drift: -250))!
          .driftFromInitialKcal, -250);
    });
  });

  group('cooldown days', () {
    test('never adjusted -> null (no cooldown)', () {
      expect(_build(weights: const [])!.daysSinceLastKcalAdjust, isNull);
    });

    test('whole days since lastKcalAdjustAt', () {
      final i = _build(
        weights: const [],
        plan: storedPlan(
            lastAdjust: kNow.subtract(const Duration(days: 13, hours: 20))),
      )!;
      expect(i.daysSinceLastKcalAdjust, 13);
    });
  });

  group('previousClass', () {
    test('taken from the NEWEST review (first in the list)', () {
      final i = _build(weights: const [], reviews: [
        _review('2026-W41', ReviewClass.behind),
        _review('2026-W40', ReviewClass.ahead),
      ])!;
      expect(i.previousClass, ReviewClass.behind);
    });

    test('no reviews -> null; a newest review without class -> null', () {
      expect(_build(weights: const [])!.previousClass, isNull);
      expect(
          _build(weights: const [], reviews: [_review('2026-W41', null)])!
              .previousClass,
          isNull);
    });
  });

  group('end to end with decide()', () {
    test('two consecutive behind weeks and no cooldown lead to a steps change', () {
      // Slope -0.1 on a -0.4 plan is behind (e = +0.3 > tol 0.15).
      final i = _build(
        weights: [
          _w(const Duration(days: 14), 80.0),
          _w(const Duration(days: 7), 79.9),
          _w(Duration.zero, 79.8),
        ],
        reviews: [_review('2026-W41', ReviewClass.behind)],
      )!;
      final d = decide(i)!;
      expect(d.classification, ReviewClass.behind);
      expect(d.kind, ReviewDecisionKind.adjustSteps);
      expect(d.basePlanVersion, 3);
    });

    test('the same series without a previous behind only waits', () {
      final i = _build(weights: [
        _w(const Duration(days: 14), 80.0),
        _w(const Duration(days: 7), 79.9),
        _w(Duration.zero, 79.8),
      ])!;
      expect(decide(i)!.kind, ReviewDecisionKind.keep);
      expect(decide(i)!.reasonCodes, [ReviewReason.behindWaiting]);
    });
  });
}
