// T16 weekly_review_test (PLAN-12..PLAN-14, SAFE-15, N-11, N-12). The review is
// one pure decision function; every threshold of design s15 is tested on both
// sides of its boundary, and "never leaves the safe bounds" is tested as a
// property over a grid. Expected values are derived from the design text.
import 'package:fitness_app/features/nutrition_plan/data/body_fat_trend_source.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 15, 9);

/// A lose plan: range 1900-2110 inside bounds 1700-2440, steps goal 8500,
/// intended -0.40 kg/wk, row maximum 0.60 kg/wk (tooFast above 0.75).
ReviewInput _in({
  NutritionEligibility eligibility = const Eligible(),
  GoalDirection goal = GoalDirection.lose,
  PlanOwnership ownership = PlanOwnership.coached,
  AutoAdjust autoAdjust = const AutoAdjust(),
  KcalRange range = const KcalRange(1900, 2110),
  PlanBounds bounds = const PlanBounds(1700, 2440),
  int stepsGoal = 8500,
  double weightKg = 80,
  double maxKg = 0.60,
  double intended = -0.40,
  double? slope = -0.40,
  int points = 5,
  int span = 14,
  ReviewClass? previous,
  int? daysSince,
  int drift = 0,
  BodyFatTrendInput? bf,
  int version = 3,
}) =>
    ReviewInput(
      eligibility: eligibility,
      goal: goal,
      ownership: ownership,
      autoAdjust: autoAdjust,
      kcalRange: range,
      bounds: bounds,
      stepsGoal: stepsGoal,
      weightKg: weightKg,
      maxKgPerWeek: maxKg,
      intendedKgPerWeek: intended,
      weightSlopeKgPerWeek: slope,
      weightPoints: points,
      spanDays: span,
      previousClass: previous,
      daysSinceLastKcalAdjust: daysSince,
      driftFromInitialKcal: drift,
      bodyFatTrend: bf,
      basePlanVersion: version,
      now: _now,
    );

ReviewClass? _cls(ReviewInput i) => decide(i)!.classification;

void main() {
  group('step 1: only an eligible user gets a decision (D-55)', () {
    final refused = <String, NutritionEligibility>{
      'referProfessional underAge': const ReferProfessional(ReferReason.underAge),
      'referProfessional guidance': const ReferProfessional(ReferReason.guidance),
      'referProfessional clinician':
          const ReferProfessional(ReferReason.clinician),
      'needsAnswer': const NeedsAnswer(NutritionQuestion.nutritionGuidance),
      'needsProfile': const NeedsProfile([NutritionInput.height]),
    };
    refused.forEach((name, e) {
      test('$name -> null (no numbers, nothing to write)', () {
        expect(decide(_in(eligibility: e)), isNull);
      });
    });
    test('the decision enum has no referProfessional value', () {
      expect(ReviewDecisionKind.values.map((e) => e.name),
          ['keep', 'adjustKcal', 'adjustSteps', 'needMoreData', 'needRecalculation']);
    });
  });

  group('step 2 data sufficiency (PLAN-12, N-12)', () {
    test('fewer than 3 points -> needMoreData(points), plan unchanged', () {
      final d = decide(_in(points: 2, span: 14))!;
      expect(d.kind, ReviewDecisionKind.needMoreData);
      expect(d.reasonCodes, [ReviewReason.needMoreDataPoints]);
      expect(d.classification, isNull);
      expect(d.changesPlan, isFalse);
      expect(d.deltaKcal, 0);
      expect(d.newRange, isNull);
    });
    test('3 points over 6 days still needs more data (span)', () {
      final d = decide(_in(points: 3, span: 6))!;
      expect(d.kind, ReviewDecisionKind.needMoreData);
      expect(d.reasonCodes, [ReviewReason.needMoreDataSpan]);
    });
    test('2 points over 6 days names both reasons', () {
      final d = decide(_in(points: 2, span: 6))!;
      expect(d.reasonCodes,
          [ReviewReason.needMoreDataPoints, ReviewReason.needMoreDataSpan]);
    });
    test('3 points over 7 days is enough', () {
      final d = decide(_in(points: 3, span: 7))!;
      expect(d.kind, isNot(ReviewDecisionKind.needMoreData));
    });
    test('a null slope (the series said not enough data) is needMoreData', () {
      final d = decide(_in(slope: null, points: 5, span: 14))!;
      expect(d.kind, ReviewDecisionKind.needMoreData);
      expect(d.reasonCodes, [ReviewReason.needMoreDataPoints]);
    });
    test('needMoreData still carries the ownership application and plan version', () {
      final d = decide(_in(
          points: 1, span: 1, ownership: PlanOwnership.shared, version: 9))!;
      expect(d.application, ReviewApplication.proposed);
      expect(d.basePlanVersion, 9);
    });
  });

  group('step 3 classification: V-REVIEW deadband boundaries', () {
    test('intended -0.40: tol = max(0.15, 0.10) = 0.15; |e| = tol is onTrack', () {
      // slope -0.25: e = +0.15 ; slope -0.55: e = -0.15
      expect(_cls(_in(slope: -0.25)), ReviewClass.onTrack);
      expect(_cls(_in(slope: -0.55)), ReviewClass.onTrack);
    });
    test('tol + 0.01 is behind (slower) or ahead (faster) for a loss goal', () {
      expect(_cls(_in(slope: -0.24)), ReviewClass.behind);
      expect(_cls(_in(slope: 0.10)), ReviewClass.behind); // gaining on a loss plan
      expect(_cls(_in(slope: -0.56)), ReviewClass.ahead);
    });
    test('intended -0.80: tol = 0.20 (25 % of intended)', () {
      final base = _in(intended: -0.80, maxKg: 1.0);
      expect(_cls(_in(intended: -0.80, maxKg: 1.0, slope: -0.60)),
          ReviewClass.onTrack); // e = +0.20
      expect(_cls(_in(intended: -0.80, maxKg: 1.0, slope: -1.00)),
          ReviewClass.onTrack); // e = -0.20
      expect(_cls(_in(intended: -0.80, maxKg: 1.0, slope: -0.59)),
          ReviewClass.behind);
      expect(_cls(_in(intended: -0.80, maxKg: 1.0, slope: -1.01)),
          ReviewClass.ahead);
      expect(base.intendedKgPerWeek, -0.80);
    });
    test('gain goal: behind when gaining slower, ahead when faster', () {
      GoalDirection g = GoalDirection.gain;
      ReviewClass? c(double s) =>
          _cls(_in(goal: g, intended: 0.20, maxKg: 0.40, slope: s));
      expect(c(0.05), ReviewClass.onTrack); // e = -0.15
      expect(c(0.35), ReviewClass.onTrack); // e = +0.15
      expect(c(0.04), ReviewClass.behind);
      expect(c(0.36), ReviewClass.ahead);
    });
    test('maintain: drift threshold 0.25 % of 80 kg = 0.20 kg/wk', () {
      ReviewClass? c(double s) => _cls(_in(
          goal: GoalDirection.maintain, intended: 0, maxKg: 0, slope: s));
      expect(c(0.0), ReviewClass.onTrack);
      expect(c(0.20), ReviewClass.onTrack);
      expect(c(0.21), ReviewClass.driftUp);
      expect(c(-0.20), ReviewClass.onTrack);
      expect(c(-0.21), ReviewClass.driftDown);
    });
    test('the maintain threshold scales with body weight (100 kg -> 0.25)', () {
      ReviewClass? c(double s) => _cls(_in(
          goal: GoalDirection.maintain,
          intended: 0,
          maxKg: 0,
          weightKg: 100,
          slope: s));
      expect(c(0.25), ReviewClass.onTrack);
      expect(c(0.26), ReviewClass.driftUp);
    });
    test('on track -> keep(onTrack), no change', () {
      final d = decide(_in(slope: -0.40))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.onTrack]);
      expect(d.changesPlan, isFalse);
    });
    test('ahead of plan (not too fast) -> keep(aheadOfPlan)', () {
      final d = decide(_in(slope: -0.70))!; // -0.70 is within 0.75 limit
      expect(d.classification, ReviewClass.ahead);
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.aheadOfPlan]);
    });
  });

  group('step 4 tooFast: immediate bounded correction (maxRate * 1.25)', () {
    test('max 0.60 -> limit 0.75: -0.75 is NOT tooFast, -0.76 is', () {
      expect(decide(_in(slope: -0.75))!.kind, ReviewDecisionKind.keep);
      final d = decide(_in(slope: -0.76))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.reasonCodes, [ReviewReason.tooFast, ReviewReason.kcalRaised]);
    });
    test('loss too fast raises kcal by exactly 150 with no waiting and no cooldown', () {
      final d = decide(_in(slope: -0.90, daysSince: 1, previous: null))!;
      expect(d.deltaKcal, 150);
      expect(d.newRange, const KcalRange(2050, 2260));
      expect(d.newDriftFromInitialKcal, 150);
      expect(d.application, ReviewApplication.applied);
    });
    test('gain too fast lowers kcal by 150: max 0.40 -> limit 0.50', () {
      const range = KcalRange(2500, 2650);
      const bounds = PlanBounds(2350, 2810);
      expect(
          decide(_in(
                  goal: GoalDirection.gain,
                  intended: 0.20,
                  maxKg: 0.40,
                  slope: 0.50,
                  range: range,
                  bounds: bounds))!
              .kind,
          ReviewDecisionKind.keep);
      final d = decide(_in(
          goal: GoalDirection.gain,
          intended: 0.20,
          maxKg: 0.40,
          slope: 0.51,
          range: range,
          bounds: bounds))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.deltaKcal, -150);
      expect(d.newRange, const KcalRange(2350, 2500));
      expect(d.reasonCodes, [ReviewReason.tooFast, ReviewReason.kcalLowered]);
    });
    test('tooFast at the top of the bounds is keep(atSafetyLimit), never truncated', () {
      final d = decide(_in(
        slope: -0.90,
        range: const KcalRange(2300, 2440),
        bounds: const PlanBounds(1700, 2440),
      ))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.tooFast, ReviewReason.atSafetyLimit]);
      expect(d.newRange, isNull);
      expect(d.deltaKcal, 0);
    });
    test('tooFast does not apply to maintain', () {
      final d = decide(_in(
          goal: GoalDirection.maintain, intended: 0, maxKg: 0, slope: -2.0))!;
      expect(d.reasonCodes, isNot(contains(ReviewReason.tooFast)));
    });
    test('tooFast pushes drift over 400 into needRecalculation (reasons keep tooFast)', () {
      final d = decide(_in(slope: -0.90, drift: 300))!; // 300 + 150 = 450
      expect(d.kind, ReviewDecisionKind.needRecalculation);
      expect(d.reasonCodes, [ReviewReason.tooFast, ReviewReason.driftTooLarge]);
    });
  });

  group('step 5 behind: two consecutive classifications AND a 14-day cooldown', () {
    ReviewInput behind({int? daysSince, ReviewClass? previous = ReviewClass.behind, AutoAdjust? auto, int steps = 8500, int drift = 0, KcalRange? range, PlanBounds? bounds, PlanOwnership own = PlanOwnership.coached}) =>
        _in(
          slope: -0.10, // e = +0.30 > tol
          previous: previous,
          daysSince: daysSince,
          autoAdjust: auto ?? const AutoAdjust(),
          stepsGoal: steps,
          drift: drift,
          range: range ?? const KcalRange(1900, 2110),
          bounds: bounds ?? const PlanBounds(1700, 2440),
          ownership: own,
        );

    test('a single behind (no previous) -> keep(behindWaiting)', () {
      final d = decide(behind(previous: null))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.behindWaiting]);
      expect(d.classification, ReviewClass.behind);
    });
    test('previous onTrack or ahead is not "two consecutive"', () {
      expect(decide(behind(previous: ReviewClass.onTrack))!.kind,
          ReviewDecisionKind.keep);
      expect(decide(behind(previous: ReviewClass.ahead))!.kind,
          ReviewDecisionKind.keep);
    });
    test('cooldown 13 days -> keep(cooldownActive); 14 days -> acts', () {
      final d13 = decide(behind(daysSince: 13))!;
      expect(d13.kind, ReviewDecisionKind.keep);
      expect(d13.reasonCodes, [ReviewReason.cooldownActive]);
      final d14 = decide(behind(daysSince: 14))!;
      expect(d14.changesPlan, isTrue);
    });
    test('never adjusted (null days) means no cooldown', () {
      expect(decide(behind(daysSince: null))!.changesPlan, isTrue);
    });
    test('order: steps +1000 first (goal 8500 -> 9500)', () {
      final d = decide(behind(daysSince: 20))!;
      expect(d.kind, ReviewDecisionKind.adjustSteps);
      expect(d.deltaSteps, 1000);
      expect(d.newStepsGoal, 9500);
      expect(d.reasonCodes, [ReviewReason.stepsRaised]);
      expect(d.deltaKcal, 0);
      expect(d.newRange, isNull);
    });
    test('steps goal + 1000 == 12000 is allowed; 12500 is not (falls to kcal -150)', () {
      final ok = decide(behind(daysSince: 20, steps: 11000))!;
      expect(ok.kind, ReviewDecisionKind.adjustSteps);
      expect(ok.newStepsGoal, 12000);
      final over = decide(behind(daysSince: 20, steps: 11500))!;
      expect(over.kind, ReviewDecisionKind.adjustKcal);
      expect(over.deltaKcal, -150);
      expect(over.newRange, const KcalRange(1750, 1960));
      expect(over.reasonCodes, [ReviewReason.kcalLowered]);
    });
    test('steps toggle off -> kcal -150 exactly', () {
      final d = decide(behind(
          daysSince: 20, auto: const AutoAdjust(steps: false, kcal: true)))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.deltaKcal, -150);
      expect(d.newDriftFromInitialKcal, -150);
    });
    test('both toggles off (coached) -> keep(autoAdjustOff)', () {
      final d = decide(behind(daysSince: 20, auto: AutoAdjust.off))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.autoAdjustOff]);
    });
    test('kcal toggle off but steps on: steps still adjust', () {
      final d = decide(behind(
          daysSince: 20, auto: const AutoAdjust(steps: true, kcal: false)))!;
      expect(d.kind, ReviewDecisionKind.adjustSteps);
    });
    test('SAFE-15 at the lower bound: keep(atSafetyLimit), range never below bound', () {
      final d = decide(behind(
        daysSince: 20,
        steps: 12000,
        range: const KcalRange(1800, 1900),
        bounds: const PlanBounds(1800, 2440),
      ))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.atSafetyLimit]);
      expect(d.newRange, isNull); // never silently truncated
      expect(d.deltaKcal, 0);
      expect(d.newDriftFromInitialKcal, isNull);
    });
    test('SAFE-15 boundary: shifted low exactly on the bound is allowed, one under is not', () {
      final on = decide(behind(
        daysSince: 20,
        steps: 12000,
        range: const KcalRange(1850, 1950),
        bounds: const PlanBounds(1700, 2440),
      ))!;
      expect(on.kind, ReviewDecisionKind.adjustKcal);
      expect(on.newRange, const KcalRange(1700, 1800));
      final under = decide(behind(
        daysSince: 20,
        steps: 12000,
        range: const KcalRange(1849, 1949),
        bounds: const PlanBounds(1700, 2440),
      ))!;
      expect(under.kind, ReviewDecisionKind.keep);
      expect(under.reasonCodes, [ReviewReason.atSafetyLimit]);
    });
    test('steps never go above 12000 and are never reduced automatically', () {
      for (final s in [8500, 11000, 11500, 12000]) {
        final d = decide(behind(daysSince: 20, steps: s))!;
        expect(d.deltaSteps, greaterThanOrEqualTo(0));
        if (d.newStepsGoal != null) expect(d.newStepsGoal, lessThanOrEqualTo(12000));
      }
    });
    test('cumulative drift: -250 -> -400 allowed; -251 -> -401 is needRecalculation', () {
      final ok = decide(behind(
          daysSince: 20, steps: 12000, drift: -250))!;
      expect(ok.kind, ReviewDecisionKind.adjustKcal);
      expect(ok.newDriftFromInitialKcal, -400);
      final over = decide(behind(
          daysSince: 20, steps: 12000, drift: -251))!;
      expect(over.kind, ReviewDecisionKind.needRecalculation);
      expect(over.reasonCodes, [ReviewReason.driftTooLarge]);
      expect(over.newRange, isNull);
      expect(over.changesPlan, isFalse);
    });
    test('positive drift can offset: drift +150 then -150 = 0 is fine', () {
      final d = decide(behind(daysSince: 20, steps: 12000, drift: 150))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.newDriftFromInitialKcal, 0);
    });
    test('gain goal behind twice: kcal +150, never steps', () {
      final d = decide(_in(
        goal: GoalDirection.gain,
        intended: 0.20,
        maxKg: 0.40,
        slope: 0.0,
        previous: ReviewClass.behind,
        daysSince: 30,
        range: const KcalRange(2500, 2650),
        bounds: const PlanBounds(2450, 2810),
      ))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.deltaKcal, 150);
      expect(d.newRange, const KcalRange(2650, 2800));
      expect(d.reasonCodes, [ReviewReason.kcalRaised]);
    });
    test('gain goal at the upper bound -> keep(atSafetyLimit)', () {
      final d = decide(_in(
        goal: GoalDirection.gain,
        intended: 0.20,
        maxKg: 0.40,
        slope: 0.0,
        previous: ReviewClass.behind,
        daysSince: 30,
        range: const KcalRange(2670, 2810),
        bounds: const PlanBounds(2450, 2810),
      ))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.atSafetyLimit]);
    });
  });

  group('maintain drift', () {
    ReviewInput m(double slope,
            {ReviewClass? previous, int? daysSince, int drift = 0}) =>
        _in(
          goal: GoalDirection.maintain,
          intended: 0,
          maxKg: 0,
          slope: slope,
          previous: previous,
          daysSince: daysSince,
          drift: drift,
          range: const KcalRange(2300, 2600),
          bounds: const PlanBounds(2150, 2740),
        );

    test('driftUp twice -> -100 kcal', () {
      final d = decide(m(0.5, previous: ReviewClass.driftUp))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
      expect(d.deltaKcal, -100);
      expect(d.newRange, const KcalRange(2200, 2500));
    });
    test('driftDown twice -> +100 kcal', () {
      final d = decide(m(-0.5, previous: ReviewClass.driftDown))!;
      expect(d.deltaKcal, 100);
      expect(d.newRange, const KcalRange(2400, 2700));
    });
    test('driftUp after driftDown is not two consecutive of the same kind', () {
      final d = decide(m(0.5, previous: ReviewClass.driftDown))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.behindWaiting]);
    });
    test('maintain never uses the steps rule', () {
      final d = decide(m(0.5, previous: ReviewClass.driftUp, daysSince: 40))!;
      expect(d.kind, ReviewDecisionKind.adjustKcal);
    });
    test('maintain cooldown applies too', () {
      final d = decide(m(0.5, previous: ReviewClass.driftUp, daysSince: 13))!;
      expect(d.reasonCodes, [ReviewReason.cooldownActive]);
    });
    test('drift cap: -300 + -100 = -400 allowed, -301 -> -401 needRecalculation', () {
      expect(
          decide(m(0.5, previous: ReviewClass.driftUp, drift: -300))!.kind,
          ReviewDecisionKind.adjustKcal);
      expect(
          decide(m(0.5, previous: ReviewClass.driftUp, drift: -301))!.kind,
          ReviewDecisionKind.needRecalculation);
    });
    test('on-track maintain -> keep(onTrack)', () {
      expect(decide(m(0.1))!.reasonCodes, [ReviewReason.onTrack]);
    });
  });

  group('step 6 recomposition', () {
    const down = BodyFatTrendInput(
        meaningful: true, changePts: -1.5, modelId: 'licensed-x');

    test('weight flat while body fat meaningfully falls -> keep(recomposition)', () {
      // intended -0.40, slope -0.05: e = +0.35 -> behind; |slope| <= 0.2 -> flat.
      final d = decide(_in(
          slope: -0.05, previous: ReviewClass.behind, daysSince: 30, bf: down))!;
      expect(d.kind, ReviewDecisionKind.keep);
      expect(d.reasonCodes, [ReviewReason.recomposition]);
      expect(d.changesPlan, isFalse);
    });
    test('on-track weight with falling body fat names both reasons', () {
      final d = decide(_in(slope: -0.40, bf: down))!;
      expect(d.reasonCodes, [ReviewReason.onTrack, ReviewReason.recomposition]);
    });
    test('weight clearly behind and not flat is NOT rescued by the body-fat trend', () {
      // intended -0.80, slope -0.40: behind and |slope| 0.40 > 0.20.
      final d = decide(_in(
          intended: -0.80,
          maxKg: 1.0,
          slope: -0.40,
          previous: ReviewClass.behind,
          daysSince: 30,
          bf: down))!;
      expect(d.reasonCodes, isNot(contains(ReviewReason.recomposition)));
      expect(d.changesPlan, isTrue);
    });
    test('an increase, a non-meaningful change, a provisional series and a changed series are ignored', () {
      final ignored = [
        const BodyFatTrendInput(
            meaningful: true, changePts: 1.5, modelId: 'x'),
        const BodyFatTrendInput(
            meaningful: false, changePts: -1.5, modelId: 'x'),
        const BodyFatTrendInput(
            meaningful: true, changePts: -1.5, modelId: 'x', provisional: true),
        const BodyFatTrendInput(
            meaningful: true,
            changePts: -1.5,
            modelId: 'x',
            seriesChanged: true),
      ];
      for (final bf in ignored) {
        final d = decide(_in(
            slope: -0.05, previous: ReviewClass.behind, daysSince: 30, bf: bf))!;
        expect(d.reasonCodes, isNot(contains(ReviewReason.recomposition)),
            reason: '$bf');
        expect(d.changesPlan, isTrue);
      }
    });
    test('the stored inputs carry the trend only for a trustworthy series', () {
      expect(decide(_in(bf: down))!.inputs.bfTrendPts, -1.5);
      expect(
          decide(_in(
                  bf: const BodyFatTrendInput(
                      meaningful: true,
                      changePts: -2,
                      modelId: 'x',
                      provisional: true)))!
              .inputs
              .bfTrendPts,
          isNull);
      expect(decide(_in())!.inputs.bfTrendPts, isNull);
    });
    test('tooFast takes precedence over recomposition', () {
      final d = decide(_in(slope: -0.90, bf: down))!;
      expect(d.reasonCodes, contains(ReviewReason.tooFast));
    });
  });

  group('BodyFatTrendInput / source port', () {
    test('isMeaningfulDecrease needs meaningful, negative, trusted', () {
      expect(down().isMeaningfulDecrease, isTrue);
      expect(down(meaningful: false).isMeaningfulDecrease, isFalse);
      expect(down(change: 0).isMeaningfulDecrease, isFalse);
      expect(down(change: 0.5).isMeaningfulDecrease, isFalse);
      expect(down(provisional: true).isMeaningfulDecrease, isFalse);
      expect(down(changed: true).isMeaningfulDecrease, isFalse);
    });
    test('the unwired default reports no trend', () {
      expect(const NoBodyFatTrendSource().currentTrend(), isNull);
      expect(BodyFatTrendInput.none.isMeaningfulDecrease, isFalse);
    });
  });

  group('PLAN-14 ownership matrix', () {
    ReviewInput behindOwn(PlanOwnership o,
            {AutoAdjust auto = const AutoAdjust()}) =>
        _in(
            slope: -0.10,
            previous: ReviewClass.behind,
            daysSince: 20,
            ownership: o,
            autoAdjust: auto);

    test('coached -> applied; shared -> proposed; manual -> insightOnly', () {
      expect(decide(behindOwn(PlanOwnership.coached))!.application,
          ReviewApplication.applied);
      expect(decide(behindOwn(PlanOwnership.shared))!.application,
          ReviewApplication.proposed);
      expect(decide(behindOwn(PlanOwnership.manual))!.application,
          ReviewApplication.insightOnly);
    });
    test('the SAME decision content for all three ownerships (only application differs)', () {
      final a = decide(behindOwn(PlanOwnership.coached))!;
      final b = decide(behindOwn(PlanOwnership.shared))!;
      final c = decide(behindOwn(PlanOwnership.manual))!;
      for (final d in [b, c]) {
        expect(d.kind, a.kind);
        expect(d.deltaSteps, a.deltaSteps);
        expect(d.newStepsGoal, a.newStepsGoal);
        expect(d.reasonCodes, a.reasonCodes);
      }
    });
    test('manual ignores the toggles and still produces an insight', () {
      final d = decide(behindOwn(PlanOwnership.manual, auto: AutoAdjust.off))!;
      expect(d.kind, ReviewDecisionKind.adjustSteps);
      expect(d.application, ReviewApplication.insightOnly);
    });
    test('the review decision carries basePlanVersion for the transaction (D-57)', () {
      expect(decide(_in(version: 41))!.basePlanVersion, 41);
    });
    test('identical inputs give identical decisions (one decision path)', () {
      final a = decide(behindOwn(PlanOwnership.coached))!;
      final b = decide(behindOwn(PlanOwnership.coached))!;
      expect(a.kind, b.kind);
      expect(a.reasonCodes, b.reasonCodes);
      expect(a.deltaSteps, b.deltaSteps);
    });
  });

  group('step 8 closed reasons and bounds, as a property', () {
    test('every outcome has non-empty reason codes (except needMoreData with data)', () {
      final slopes = [-2.0, -1.0, -0.9, -0.76, -0.75, -0.56, -0.4, -0.25, -0.1, 0.0, 0.3];
      for (final goal in GoalDirection.values) {
        for (final slope in [...slopes, null]) {
          for (final prev in [null, ...ReviewClass.values]) {
            for (final days in [null, 5, 14]) {
              for (final own in PlanOwnership.values) {
                final d = decide(_in(
                  goal: goal,
                  intended: goal == GoalDirection.lose
                      ? -0.4
                      : (goal == GoalDirection.gain ? 0.2 : 0),
                  maxKg: goal == GoalDirection.maintain ? 0 : 0.6,
                  slope: slope,
                  previous: prev,
                  daysSince: days,
                  ownership: own,
                  range: const KcalRange(1900, 2110),
                  bounds: const PlanBounds(1850, 2200),
                ))!;
                expect(d.reasonCodes, isNotEmpty);
                expect(d.deltaSteps, greaterThanOrEqualTo(0));
                if (d.kind == ReviewDecisionKind.adjustKcal) {
                  const b = PlanBounds(1850, 2200);
                  expect(b.contains(d.newRange!), isTrue,
                      reason: 'range ${d.newRange}');
                  expect(d.deltaKcal.abs(), anyOf(150, 100));
                  expect(d.newDriftFromInitialKcal!.abs(), lessThanOrEqualTo(400));
                } else {
                  expect(d.newRange, isNull);
                  expect(d.deltaKcal, 0);
                }
                if (d.kind == ReviewDecisionKind.adjustSteps) {
                  expect(d.newStepsGoal, lessThanOrEqualTo(12000));
                  expect(d.deltaSteps, 1000);
                }
              }
            }
          }
        }
      }
    });
  });

  group('intended rate sign', () {
    test('loss negative, gain positive, maintain zero', () {
      expect(intendedKgPerWeekFor(GoalDirection.lose, 0.4), -0.4);
      expect(intendedKgPerWeekFor(GoalDirection.gain, 0.2), 0.2);
      expect(intendedKgPerWeekFor(GoalDirection.maintain, 0.4), 0);
    });
  });

  group('PLAN-15 ISO week keys', () {
    test('2026-12-31 and 2027-01-01 are both 2026-W53; 2027-01-04 is 2027-W01', () {
      expect(isoWeekKeyForDate(2026, 12, 31), '2026-W53');
      expect(isoWeekKeyForDate(2027, 1, 1), '2026-W53');
      expect(isoWeekKeyForDate(2027, 1, 3), '2026-W53'); // Sunday
      expect(isoWeekKeyForDate(2027, 1, 4), '2027-W01');
    });
    test('2026-10-15 (Thursday) is 2026-W42; Sunday 18th too; Monday 19th is W43', () {
      expect(isoWeekKeyForDate(2026, 10, 15), '2026-W42');
      expect(isoWeekKeyForDate(2026, 10, 12), '2026-W42'); // Monday
      expect(isoWeekKeyForDate(2026, 10, 18), '2026-W42');
      expect(isoWeekKeyForDate(2026, 10, 19), '2026-W43');
    });
    test('year edges: 2026-01-01 is W01, 2025-12-29 is 2026-W01, 2020-W53 exists', () {
      expect(isoWeekKeyForDate(2026, 1, 1), '2026-W01');
      expect(isoWeekKeyForDate(2025, 12, 29), '2026-W01');
      expect(isoWeekKeyForDate(2024, 12, 30), '2025-W01');
      expect(isoWeekKeyForDate(2021, 1, 3), '2020-W53');
      expect(isoWeekKeyForDate(2021, 1, 4), '2021-W01');
    });
    test('the key is zero padded: W01..W09', () {
      expect(isoWeekKeyForDate(2026, 2, 3), '2026-W06');
    });
    test('reviewWeekKey uses the explicit UTC offset, not the machine zone', () {
      final sundayLate = DateTime.utc(2026, 10, 18, 23, 30);
      expect(reviewWeekKey(sundayLate, utcOffset: Duration.zero), '2026-W42');
      expect(reviewWeekKey(sundayLate, utcOffset: const Duration(hours: 2)),
          '2026-W43'); // local Monday 01:30
      final mondayEarly = DateTime.utc(2026, 10, 19, 1, 30);
      expect(reviewWeekKey(mondayEarly, utcOffset: const Duration(hours: -5)),
          '2026-W42'); // local Sunday 20:30
      expect(reviewWeekKey(mondayEarly, utcOffset: Duration.zero), '2026-W43');
    });
    test('one key per ISO week: all seven days of a week share a key', () {
      final keys = {
        for (var d = 12; d <= 18; d++) isoWeekKeyForDate(2026, 10, d),
      };
      expect(keys, {'2026-W42'});
    });
  });
}

BodyFatTrendInput down({
  bool meaningful = true,
  double change = -1.5,
  bool provisional = false,
  bool changed = false,
}) =>
    BodyFatTrendInput(
      meaningful: meaningful,
      changePts: change,
      modelId: 'm',
      provisional: provisional,
      seriesChanged: changed,
    );
