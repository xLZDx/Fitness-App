// T22 scan_result_math_test (SCAN-14, SCAN-15, SCAN-44, design 12.1/12.6/12.6a).
// Mass split, weight-edit recompute, points to goal and goal projection.
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/provisional_estimator.dart';
import 'package:fitness_app/features/body_scan/data/scan_result_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SCAN-14 fat and lean mass', () {
    test('W=80, v=25, range 22-28: FM 20.0 (17.6-22.4), LM 60.0 (57.6-62.4)', () {
      final m = massSplit(
          weightKg: 80, valuePct: 25, lowPct: 22, highPct: 28)!;
      expect(m.fatKg, closeTo(20.0, 1e-9));
      expect(m.fatLowKg, closeTo(17.6, 1e-9));
      expect(m.fatHighKg, closeTo(22.4, 1e-9));
      expect(m.leanKg, closeTo(60.0, 1e-9));
      expect(m.leanLowKg, closeTo(57.6, 1e-9)); // W - FM_high
      expect(m.leanHighKg, closeTo(62.4, 1e-9)); // W - FM_low
    });
    test('fat + lean = weight for the point value', () {
      final m = massSplit(
          weightKg: 91.3, valuePct: 18.7, lowPct: 15, highPct: 22)!;
      expect(m.fatKg + m.leanKg, closeTo(91.3, 1e-9));
    });
    test('editing the weight to 82 recomputes FM/LM: FM 20.5, LM 61.5', () {
      final m = massSplit(
          weightKg: 82, valuePct: 25, lowPct: 22, highPct: 28)!;
      expect(m.fatKg, closeTo(20.5, 1e-9));
      expect(m.leanKg, closeTo(61.5, 1e-9));
      expect(m.fatLowKg, closeTo(18.04, 1e-9));
      expect(m.fatHighKg, closeTo(22.96, 1e-9));
    });
    test('weight 0, negative, null, NaN or infinite -> no mass, no divide-by-zero', () {
      for (final w in [0.0, -5.0, null, double.nan, double.infinity]) {
        expect(
            massSplit(weightKg: w, valuePct: 25, lowPct: 22, highPct: 28),
            isNull,
            reason: '$w');
      }
    });
    test('lean range is inverted against the fat range', () {
      final m = massSplit(
          weightKg: 70, valuePct: 30, lowPct: 25, highPct: 35)!;
      expect(m.leanLowKg, lessThan(m.leanKg));
      expect(m.leanHighKg, greaterThan(m.leanKg));
    });
  });

  group('SCAN-44 rederiveForEditedWeight', () {
    const est = ProvisionalEstimator();
    const subject80 = EstimatorSubject(
        heightCm: 180, weightKg: 80, ageYears: 30, sex: SexBasis.male);
    const subject82 = EstimatorSubject(
        heightCm: 180, weightKg: 82, ageYears: 30, sex: SexBasis.male);

    test('a provisional estimate is recomputed from the new weight', () {
      final before = est.estimateNow(subject80);
      final after = rederiveForEditedWeight(
          estimate: before, subjectWithNewWeight: subject82);
      expect(after.value, closeTo(21.07, 0.01)); // BMI 25.31 -> 21.0704
      expect(after.value, isNot(before.value));
      expect(after.provisional, isTrue);
    });
    test('a server (non-provisional) estimate is never changed by a weight edit', () {
      const server = BodyFatEstimate(
        value: 24.0,
        low: 22.0,
        high: 26.0,
        confidence: EstimateConfidence.medium,
        modelId: 'licensed-x',
        modelVersion: '1',
        provisional: false,
      );
      final after = rederiveForEditedWeight(
          estimate: server, subjectWithNewWeight: subject82);
      expect(identical(after, server), isTrue);
      expect(after.value, 24.0);
    });
    test('the rederived estimate keeps the provisional model identity', () {
      final after = rederiveForEditedWeight(
          estimate: est.estimateNow(subject80),
          subjectWithNewWeight: subject82);
      expect(after.modelId, 'provisional-anthropometric');
    });
  });

  group('SCAN-15 points to goal', () {
    test('smoothed 22.5, target 15 -> 7.5 points to go', () {
      expect(pointsToGoal(smoothedPct: 22.5, targetBodyFatPct: 15), 7.5);
    });
    test('below target is negative (already past the goal)', () {
      expect(pointsToGoal(smoothedPct: 14, targetBodyFatPct: 15), -1.0);
    });
    test('null without a target (the screen falls back to weight progress) or without a value', () {
      expect(pointsToGoal(smoothedPct: 22.5), isNull);
      expect(pointsToGoal(targetBodyFatPct: 15), isNull);
      expect(pointsToGoal(), isNull);
    });
  });

  group('projectGoal (design 12.6a)', () {
    test('reference arithmetic: 95.4 kg at 31 % to 16 %: goal 78.36 kg, 17.04 kg to lose, 29.9 weeks at 0.57 kg/wk', () {
      final g = projectGoal(
        weightKg: 95.4,
        heightCm: 170,
        smoothedPct: 31.0,
        targetBodyFatPct: 16,
        sex: SexBasis.male,
        kgPerWeek: 0.57,
        provisional: false,
      );
      expect(g.goalWeightKg!, closeTo(78.3643, 1e-3));
      expect(g.toLoseKg!, closeTo(17.0357, 1e-3));
      expect(g.etaHidden, isFalse);
      expect(g.issue, isNull);
      // weeks 29.8872; shown as a range weeks * 0.8 .. weeks * 1.3
      expect(g.weeksLow!, closeTo(23.9098, 1e-3));
      expect(g.weeksHigh!, closeTo(38.8534, 1e-3));
      expect(GoalProjection.etaLowFactor, 0.8);
      expect(GoalProjection.etaHighFactor, 1.3);
    });
    test('lean mass is assumed constant: 80 kg at 25 % to 20 % -> 75.0 kg, 5.0 kg to lose', () {
      final g = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 25,
        targetBodyFatPct: 20,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: false,
      );
      expect(g.goalWeightKg!, closeTo(75.0, 1e-9));
      expect(g.toLoseKg!, closeTo(5.0, 1e-9));
      expect(g.weeksLow!, closeTo(12.5 * 0.8, 1e-6));
      expect(g.weeksHigh!, closeTo(12.5 * 1.3, 1e-6));
    });
    test('a target below the sex floor is clamped first (male 5 -> 10, female 12 -> 16)', () {
      final m = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 25,
        targetBodyFatPct: 5,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: false,
      );
      // lean 60 / 0.90 = 66.667
      expect(m.goalWeightKg!, closeTo(66.6667, 1e-3));
      final f = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 30,
        targetBodyFatPct: 12,
        sex: SexBasis.female,
        kgPerWeek: 0.4,
        provisional: false,
      );
      // lean 56 / 0.84 = 66.667
      expect(f.goalWeightKg!, closeTo(66.6667, 1e-3));
    });
    test('unspecified sex uses the 16 % floor', () {
      final u = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 30,
        targetBodyFatPct: 12,
        sex: SexBasis.unspecified,
        kgPerWeek: 0.4,
        provisional: false,
      );
      expect(u.goalWeightKg!, closeTo(56 / 0.84, 1e-9));
    });
    test('a target above 40 % is clamped to 40', () {
      final g = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 45,
        targetBodyFatPct: 55,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: false,
      );
      expect(g.goalWeightKg!, closeTo(44 / 0.60, 1e-9)); // lean 44, 40 %
    });
    test('goal weight under BMI 18.5 -> targetBelowHealthyRange, no figures at all', () {
      // 60 kg, 180 cm, 15 %: lean 51 / 0.9 = 56.67 kg = BMI 17.49
      final g = projectGoal(
        weightKg: 60,
        heightCm: 180,
        smoothedPct: 15,
        targetBodyFatPct: 10,
        sex: SexBasis.male,
        kgPerWeek: 0.3,
        provisional: false,
      );
      expect(g.issue, GoalProjectionIssue.targetBelowHealthyRange);
      expect(g.goalWeightKg, isNull);
      expect(g.toLoseKg, isNull);
      expect(g.weeksLow, isNull);
      expect(g.etaHidden, isTrue);
    });
    test('goal BMI 18.5..20 hides the ETA but still shows the goal weight', () {
      // 70 kg 180 cm 20 % -> 10 %: goal 62.22 kg = BMI 19.2
      final g = projectGoal(
        weightKg: 70,
        heightCm: 180,
        smoothedPct: 20,
        targetBodyFatPct: 10,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: false,
      );
      expect(g.issue, isNull);
      expect(g.goalWeightKg!, closeTo(62.2222, 1e-3));
      expect(g.toLoseKg!, closeTo(7.7778, 1e-3));
      expect(g.etaHidden, isTrue);
      expect(g.weeksLow, isNull);
      expect(g.weeksHigh, isNull);
    });
    test('the provisional estimator never shows an ETA', () {
      final g = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 25,
        targetBodyFatPct: 20,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: true,
      );
      expect(g.etaHidden, isTrue);
      expect(g.weeksLow, isNull);
      expect(g.goalWeightKg!, closeTo(75.0, 1e-9));
    });
    test('no pace, a zero pace, or a target already reached -> noPace issue and no ETA', () {
      for (final kg in [null, 0.0, -0.1]) {
        final g = projectGoal(
          weightKg: 80,
          heightCm: 180,
          smoothedPct: 25,
          targetBodyFatPct: 20,
          sex: SexBasis.male,
          kgPerWeek: kg,
          provisional: false,
        );
        expect(g.issue, GoalProjectionIssue.noPace, reason: '$kg');
        expect(g.weeksLow, isNull);
        expect(g.etaHidden, isTrue);
      }
      final reached = projectGoal(
        weightKg: 80,
        heightCm: 180,
        smoothedPct: 18,
        targetBodyFatPct: 20,
        sex: SexBasis.male,
        kgPerWeek: 0.4,
        provisional: false,
      );
      expect(reached.issue, GoalProjectionIssue.noPace);
      expect(reached.toLoseKg!, lessThan(0));
    });
  });
}
