// T14 plan_calculator_test (PLAN-03..PLAN-09, PLAN-11, SAFE-08/10/17).
//
// Expected values were derived independently (design s13 text, scratch
// arithmetic), not read off the implementation.
//
// DEVIATION FROM MAP v1.1 s3 (resolved here, map corrected in the same
// change): the lose range follows D-39 (target -200 / +100, not +-150) and is
// then pulled inside the slider bounds (design 13.3 "must lie inside the
// bounds"). V-LOSE-M therefore gives range 1900-2110 (raw 1810-2110, low
// raised to the bound 1900), bounds 1900-2440; V-LOSE-CAP gives range
// 1840-1940 (raw 1640-1940, low raised to the bound 1840).
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

NutritionInputs _in({
  required double w,
  required double h,
  int age = 30,
  SexBasis sex = SexBasis.male,
  ActivityLevel level = ActivityLevel.moderatelyActive,
  GoalDirection goal = GoalDirection.lose,
  int? steps,
  bool stale = false,
}) =>
    NutritionInputs(
      weightKg: w,
      heightCm: h,
      ageYears: age,
      sex: sex,
      activityLevel: level,
      goal: goal,
      typicalSteps: steps,
      weightStale: stale,
    );

void main() {
  group('weekly rate rows (PLAN-04)', () {
    test('lose BMI boundary: 24.99 -> low row, 25.00 -> high row', () {
      final low = weeklyRateRow(GoalDirection.lose, 24.99);
      expect((low.defaultPct, low.maxPct, low.absoluteKg), (0.5, 0.75, 0.5));
      final high = weeklyRateRow(GoalDirection.lose, 25.00);
      expect((high.defaultPct, high.maxPct, high.absoluteKg), (0.75, 1.0, 1.0));
    });
    test('29.99 and 30.00 share the high row numbers (D-38)', () {
      for (final bmi in [29.99, 30.00, 45.0]) {
        final r = weeklyRateRow(GoalDirection.lose, bmi);
        expect((r.defaultPct, r.maxPct, r.absoluteKg), (0.75, 1.0, 1.0));
      }
    });
    test('18.5 <= BMI < 20: deficit rate capped at 0.25 %/wk; 20.0 is normal', () {
      for (final bmi in [18.5, 19.0, 19.99]) {
        final r = weeklyRateRow(GoalDirection.lose, bmi);
        expect((r.defaultPct, r.maxPct, r.absoluteKg), (0.25, 0.25, 0.5));
      }
      final r = weeklyRateRow(GoalDirection.lose, 20.0);
      expect((r.defaultPct, r.maxPct, r.absoluteKg), (0.5, 0.75, 0.5));
    });
    test('gain 0.25 default, 0.5 max, 0.5 kg; maintain is all zero', () {
      final g = weeklyRateRow(GoalDirection.gain, 22);
      expect((g.defaultPct, g.maxPct, g.absoluteKg), (0.25, 0.5, 0.5));
      final m = weeklyRateRow(GoalDirection.maintain, 22);
      expect((m.defaultPct, m.maxPct, m.absoluteKg), (0.0, 0.0, 0.0));
    });
    test('kgPerWeekFor applies the absolute kg cap (120 kg, 1.0 % = 1.2 -> 1.0)', () {
      final high = weeklyRateRow(GoalDirection.lose, 35);
      expect(kgPerWeekFor(high, 1.0, 120), 1.0);
      expect(kgPerWeekFor(high, 0.75, 120), closeTo(0.9, 1e-12));
      final low = weeklyRateRow(GoalDirection.lose, 23);
      expect(kgPerWeekFor(low, 0.75, 100), 0.5);
      expect(kgPerWeekFor(low, 0.5, 80), closeTo(0.4, 1e-12));
    });
  });

  group('V-LOSE-M (PLAN-05): male 80 kg 180 cm 30 y moderately active, lose', () {
    final p = computePlan(_in(w: 80, h: 180));
    test('energy chain', () {
      expect(p.bmr, 1780.0);
      expect(p.activityFactor, 1.375);
      expect(p.tdee, 2447.5);
      expect(p.floorKcal, 1780);
      expect(p.bmi, closeTo(24.6914, 1e-4));
      expect(p.goal, GoalDirection.lose);
    });
    test('row <25: 0.50 %/wk = 0.40 kg/wk = 440 kcal/day; 25 % cap 611.9 not binding', () {
      expect(p.ratePctPerWeek, 0.5);
      expect(p.kgPerWeek, closeTo(0.4, 1e-12));
      expect(p.maxKgPerWeek, 0.5); // 0.75 % = 0.6 kg, absolute cap 0.5
      expect(p.targetKcal, closeTo(2007.5, 1e-9));
    });
    test('bounds 1900-2440 and the range pulled inside them: 1900-2110', () {
      // maxDeficit = min(611.875, 0.5 * 7700 / 7 = 550) = 550 -> low 1897.5 -> 1900.
      expect(p.bounds, const PlanBounds(1900, 2440));
      // raw -200/+100 around 2007.5 is 1810..2110; low is raised to the bound.
      expect(p.kcalRange, const KcalRange(1900, 2110));
      expect(p.bounds.contains(p.kcalRange), isTrue);
    });
    test('lose: range high never above TDEE', () {
      expect(p.kcalRange.high, lessThanOrEqualTo(p.tdee));
    });
    test('macros: protein 128/160/176, fat 48..78, carbs 124..292, targets 160/56/215', () {
      expect(p.macros.protein.minG, 128);
      expect(p.macros.protein.targetG, 160);
      expect(p.macros.protein.maxG, 176);
      expect(p.macros.fat.minG, 48);
      expect(p.macros.fat.maxG, 78);
      expect(p.macros.carbs.minG, 124);
      expect(p.macros.carbs.maxG, 292);
      expect(p.macros.targets.proteinG, 160);
      expect(p.macros.targets.fatG, 56);
      expect(p.macros.targets.carbsG, 215);
      expect(p.macros.lowCarbBySafety, isFalse);
      expect(p.flags, isEmpty);
    });
    test('implied kcal of the point targets is within 5 % of kcalMid 2005', () {
      // 4*160 + 9*56 + 4*215 = 640 + 504 + 860 = 2004
      expect(p.macros.targets.impliedKcal, 2004);
      expect((p.macros.targets.impliedKcal - 2005).abs() / 2005, lessThan(0.05));
    });
    test('steps goal for a moderately active user without typical steps: 8500', () {
      expect(p.stepsGoal, 8500);
    });
    test('pace at the row maximum (0.75 %/wk): target 1897.5, range 1900-2000', () {
      final q = computePlan(_in(w: 80, h: 180), ratePctPerWeek: 0.75);
      expect(q.kgPerWeek, 0.5);
      expect(q.targetKcal, closeTo(1897.5, 1e-9));
      expect(q.kcalRange, const KcalRange(1900, 2000));
    });
  });

  group('V-LOSE-CAP (PLAN-05, SAFE-10): the 25 % TDEE cap binds', () {
    test('computeBounds with the high row: 1840-2440; raw 1640-1940 is pulled to 1840-1940', () {
      // The map's abstract person (TDEE 2447.5, floor 1780, row 25-30: 0.8 kg/wk
      // = 880 kcal/day) - cap 0.25 * 2447.5 = 611.875 binds, target 1835.625.
      final b = computeBounds(
        goal: GoalDirection.lose,
        tdee: 2447.5,
        floorKcal: 1780,
        maxKgPerWeek: 0.8,
      );
      expect(b, const PlanBounds(1840, 2440));
      expect(clampRangeToBounds(const KcalRange(1640, 1940), b),
          const KcalRange(1840, 1940));
    });
    test('real person 80 kg 175 cm (BMI 26.12): target 1803.4, bounds 1810-2400, range 1810-1910', () {
      final p = computePlan(_in(w: 80, h: 175));
      expect(p.bmr, 1748.75);
      expect(p.tdee, closeTo(2404.53125, 1e-9));
      expect(p.floorKcal, 1749);
      expect(p.kgPerWeek, closeTo(0.6, 1e-12)); // 0.75 %/wk
      expect(p.targetKcal, closeTo(0.75 * 2404.53125, 1e-9));
      expect(p.bounds, const PlanBounds(1810, 2400));
      expect(p.kcalRange, const KcalRange(1810, 1910));
      expect(p.macros.protein.minG, 128);
      expect(p.macros.protein.maxG, 176);
      expect(p.macros.fat.minG, 48);
      expect(p.macros.fat.maxG, 72);
      expect(p.macros.carbs.minG, 115);
      expect(p.macros.carbs.maxG, 242);
      expect(p.macros.targets.proteinG, 160);
      expect(p.macros.targets.fatG, 52);
      expect(p.macros.targets.carbsG, 190);
    });
  });

  group('V-FLOOR-F (SAFE-08/10): floor and TDEE - floor deficit', () {
    final p = computePlan(_in(
        w: 50,
        h: 155,
        age: 40,
        sex: SexBasis.female,
        level: ActivityLevel.sedentary));
    test('chain: BMR 1107.75, TDEE 1329.3, floor 1200, deficit capped at 129.3', () {
      expect(p.bmr, 1107.75);
      expect(p.tdee, closeTo(1329.3, 1e-9));
      expect(p.floorKcal, 1200);
      expect(p.targetKcal, closeTo(1200.0, 1e-9));
    });
    test('range 1200-1300 within bounds 1200-1320, never under the floor', () {
      expect(p.bounds, const PlanBounds(1200, 1320));
      expect(p.kcalRange, const KcalRange(1200, 1300));
      expect(p.kcalRange.high, lessThanOrEqualTo(p.tdee));
    });
    test('macros: protein 80/100/110, fat 30..49, carbs 100..178, targets 100/35/135', () {
      expect(p.macros.protein.minG, 80);
      expect(p.macros.protein.targetG, 100);
      expect(p.macros.protein.maxG, 110);
      expect(p.macros.fat.minG, 30);
      expect(p.macros.fat.maxG, 49);
      expect(p.macros.carbs.minG, 100);
      expect(p.macros.carbs.maxG, 178);
      expect(p.macros.targets.proteinG, 100);
      expect(p.macros.targets.fatG, 35);
      expect(p.macros.targets.carbsG, 135);
    });
    test('sedentary steps goal 7000', () => expect(p.stepsGoal, 7000));
  });

  group('maintain and gain (PLAN-05/06)', () {
    test('maintain: target = TDEE 2447.5, +-150 -> 2300-2600, bounds 2150-2740', () {
      final p = computePlan(_in(w: 80, h: 180, goal: GoalDirection.maintain));
      expect(p.targetKcal, 2447.5);
      expect(p.bounds, const PlanBounds(2150, 2740));
      expect(p.kcalRange, const KcalRange(2300, 2600));
      expect(p.kgPerWeek, 0);
      expect(p.macros.protein.minG, 112);
      expect(p.macros.protein.targetG, 128);
      expect(p.macros.protein.maxG, 176);
      expect(p.macros.fat.minG, 54);
      expect(p.macros.fat.maxG, 95);
      expect(p.macros.carbs.minG, 185);
      expect(p.macros.carbs.maxG, 417);
      expect(p.macros.targets.proteinG, 130);
      expect(p.macros.targets.fatG, 68);
      expect(p.macros.targets.carbsG, 330);
    });
    test('gain: target 2667.5 (+220), bounds 2450-2810, range 2520-2810 (low >= TDEE)', () {
      final p = computePlan(_in(w: 80, h: 180, goal: GoalDirection.gain));
      expect(p.targetKcal, closeTo(2667.5, 1e-9));
      expect(p.bounds, const PlanBounds(2450, 2810));
      expect(p.kcalRange, const KcalRange(2520, 2810));
      expect(p.kcalRange.low, greaterThanOrEqualTo(p.tdee));
      expect(p.macros.protein.minG, 128);
      expect(p.macros.protein.targetG, 144);
      expect(p.macros.protein.maxG, 176);
      expect(p.macros.targets.proteinG, 145);
      expect(p.macros.targets.fatG, 74);
      expect(p.macros.targets.carbsG, 355);
    });
    test('female 60 kg 165 cm maintain: 1320.25 -> TDEE 1815.34375, range 1670-1970', () {
      final p = computePlan(_in(
          w: 60, h: 165, sex: SexBasis.female, goal: GoalDirection.maintain));
      expect(p.bmr, 1320.25);
      expect(p.tdee, closeTo(1815.34375, 1e-9));
      expect(p.floorKcal, 1320);
      expect(p.bounds, const PlanBounds(1520, 2110));
      expect(p.kcalRange, const KcalRange(1670, 1970));
      expect(p.macros.targets.proteinG, 100);
      expect(p.macros.targets.fatG, 51);
      expect(p.macros.targets.carbsG, 245);
    });
    test('maintain bounds never go under the floor even for a low TDEE', () {
      final b = computeBounds(
        goal: GoalDirection.maintain,
        tdee: 1300,
        floorKcal: 1200,
        maxKgPerWeek: 0,
      );
      expect(b.minKcal, 1200); // 1000 would be under the floor
      expect(b.maxKcal, 1600);
    });
  });

  group('underweight and weightStale flags', () {
    test('BMI 16.98 lose -> maintain + underweightNoDeficit, range around TDEE', () {
      final p = computePlan(_in(w: 55, h: 180));
      expect(p.goal, GoalDirection.maintain);
      expect(p.requestedGoal, GoalDirection.lose);
      expect(p.flags, contains(PlanFlag.underweightNoDeficit));
      expect(p.tdee, closeTo(2103.75, 1e-9));
      expect(p.bounds, const PlanBounds(1810, 2400));
      expect(p.kcalRange, const KcalRange(1950, 2250));
      expect(p.macros.protein.minG, 77);
      expect(p.macros.protein.targetG, 88);
      expect(p.macros.protein.maxG, 121);
      expect(p.macros.targets.proteinG, 90);
      expect(p.macros.targets.fatG, 58);
      expect(p.macros.targets.carbsG, 305);
    });
    test('weightStale input is surfaced as a flag', () {
      final p = computePlan(_in(w: 80, h: 180, stale: true));
      expect(p.flags, contains(PlanFlag.weightStale));
    });
    test('TDEE <= floor raises floorBinding', () {
      final p = computePlan(_in(
          w: 48,
          h: 155,
          age: 75,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      expect(p.flags, contains(PlanFlag.floorBinding));
    });
  });

  group('steps cross-check inside the plan (PLAN-02)', () {
    test('steps 4000 lowers the factor of an active user to 1.2 (TDEE 2136)', () {
      final p = computePlan(_in(
          w: 80, h: 180, level: ActivityLevel.moderatelyActive, steps: 4000));
      expect(p.activityFactor, 1.2);
      expect(p.tdee, closeTo(2136.0, 1e-9));
      expect(p.targetKcal, closeTo(1780.0, 1e-9)); // TDEE - floor binds: 356 < 440
      expect(p.bounds, const PlanBounds(1780, 2130));
      expect(p.kcalRange, const KcalRange(1780, 1880));
    });
    test('steps 12000 cannot raise a sedentary questionnaire answer', () {
      final p = computePlan(_in(
          w: 80, h: 180, level: ActivityLevel.sedentary, steps: 12000));
      expect(p.activityFactor, 1.2);
    });
  });

  group('PLAN-03: no exercise credit', () {
    test('NutritionInputs has no exercise field; plan depends only on inputs', () {
      final a = computePlan(_in(w: 80, h: 180));
      final b = computePlan(_in(w: 80, h: 180));
      expect(a.kcalRange, b.kcalRange);
      expect(a.targetKcal, b.targetKcal);
    });
  });

  group('PLAN-06 bounds and re-validation', () {
    test('lose bounds for V-LOSE-M numbers', () {
      expect(
        computeBounds(
            goal: GoalDirection.lose,
            tdee: 2447.5,
            floorKcal: 1780,
            maxKgPerWeek: 0.5),
        const PlanBounds(1900, 2440),
      );
    });
    test('gain bounds [TDEE, TDEE + min(500, 15 %)]: 2450-2810', () {
      expect(
        computeBounds(
            goal: GoalDirection.gain,
            tdee: 2447.5,
            floorKcal: 1780,
            maxKgPerWeek: 0.4),
        const PlanBounds(2450, 2810),
      );
    });
    test('degenerate TDEE <= floor: upper bound lifted to min + 100', () {
      expect(
        computeBounds(
            goal: GoalDirection.lose,
            tdee: 1095.3,
            floorKcal: 1200,
            maxKgPerWeek: 0.12),
        const PlanBounds(1200, 1300),
      );
      expect(
        computeBounds(
            goal: GoalDirection.lose,
            tdee: 1200,
            floorKcal: 1200,
            maxKgPerWeek: 0.5),
        const PlanBounds(1200, 1300),
      );
    });
    test('bounds are rounded INWARD to 10 (low up, high down)', () {
      final b = computeBounds(
        goal: GoalDirection.lose,
        tdee: 2447.5,
        floorKcal: 1500,
        maxKgPerWeek: 0.5,
      );
      expect(b.minKcal % 10, 0);
      expect(b.minKcal, greaterThanOrEqualTo(2447.5 - 550)); // 1897.5 -> 1900
      expect(b.maxKcal, lessThanOrEqualTo(2447.5)); // -> 2440
    });
    test('a stored range outside the bounds is pulled inside on load', () {
      const b = PlanBounds(1900, 2440);
      expect(clampRangeToBounds(const KcalRange(1500, 1600), b),
          const KcalRange(1900, 2000));
      expect(clampRangeToBounds(const KcalRange(3000, 3100), b),
          const KcalRange(2340, 2440));
      expect(clampRangeToBounds(const KcalRange(2000, 2100), b),
          const KcalRange(2000, 2100)); // inside: untouched
    });
    test('width is clamped to 100..400 and stays inside the bounds', () {
      const b = PlanBounds(1900, 2440);
      expect(clampRangeToBounds(const KcalRange(2000, 2050), b),
          const KcalRange(2000, 2100));
      expect(clampRangeToBounds(const KcalRange(2000, 2500), b),
          const KcalRange(2000, 2400));
      expect(clampRangeToBounds(const KcalRange(2400, 2900), b),
          const KcalRange(2340, 2440));
    });
    test('userRange passed to computePlan is re-validated against the recomputed bounds', () {
      final p = computePlan(_in(w: 80, h: 180),
          userRange: const KcalRange(1000, 3000));
      expect(p.kcalRange, const KcalRange(1900, 2300));
      expect(p.bounds.contains(p.kcalRange), isTrue);
    });
    test('KcalRange / PlanBounds value semantics', () {
      expect(const KcalRange(1900, 2000), const KcalRange(1900, 2000));
      expect(const KcalRange(1900, 2000).hashCode,
          const KcalRange(1900, 2000).hashCode);
      expect(const KcalRange(1900, 2000).width, 100);
      expect(const KcalRange(1900, 2000).mid, 1950);
      expect(const PlanBounds(1, 2).contains(const KcalRange(1, 2)), isTrue);
      expect(const PlanBounds(2, 3).contains(const KcalRange(1, 2)), isFalse);
      expect(const PlanBounds(1, 2).contains(const KcalRange(1, 3)), isFalse);
    });
  });

  group('PLAN-07 protein', () {
    MacroPlan m(double w, double h, GoalDirection g, int lo, int hi,
            {double? lean}) =>
        computeMacros(
          weightKg: w,
          heightCm: h,
          goal: g,
          kcal: KcalRange(lo, hi),
          leanMassKg: lean,
        );

    test('BMI <= 30 uses the body weight; > 30 uses 30 * (H/100)^2', () {
      expect(referenceWeightKg(80, 180), 80);
      expect(referenceWeightKg(97, 180), 97); // BMI 29.94 stays
      expect(referenceWeightKg(110, 170), closeTo(86.7, 1e-9));
      expect(referenceWeightKg(120, 175), closeTo(91.875, 1e-9));
    });
    test('V-PROT-OB complete band', () {
      final r = m(110, 170, GoalDirection.lose, 1700, 1900);
      expect((r.protein.minG, r.protein.targetG, r.protein.maxG), (139, 173, 180));
      expect((r.fat.minG, r.fat.maxG), (52, 70));
      expect((r.carbs.minG, r.carbs.maxG), (100, 219));
    });
    test('V-PROT-220 inside a full plan (110 kg, 195 cm, very active)', () {
      final p = computePlan(_in(
          w: 110, h: 195, age: 35, level: ActivityLevel.veryActive));
      expect(p.bmi, closeTo(28.93, 0.01));
      expect(p.kcalRange, const KcalRange(2780, 2900));
      expect(p.macros.protein.minG, 176);
      expect(p.macros.protein.targetG, 220);
      expect(p.macros.protein.maxG, 220);
      expect(p.macros.targets.proteinG, 220);
      expect(p.macros.fat.minG, 66);
      expect(p.macros.fat.maxG, 110);
      expect(p.macros.targets.fatG, 79);
      expect(p.macros.targets.carbsG, 315);
    });
    test('obese plan: V-PROT-OB person full plan (110 kg 170 cm 35 y)', () {
      final p = computePlan(_in(w: 110, h: 170, age: 35));
      expect(p.bmr, 1992.5);
      expect(p.floorKcal, 1993);
      expect(p.kgPerWeek, closeTo(0.825, 1e-12)); // 0.75 % of 110
      expect(p.bounds, const PlanBounds(2060, 2730));
      expect(p.kcalRange, const KcalRange(2060, 2160));
      expect(p.macros.protein.minG, 139);
      expect(p.macros.protein.targetG, 173);
      expect(p.macros.protein.maxG, 191);
      expect(p.macros.targets.proteinG, 175);
    });
    test('the minimum is the minimum: min < target < max for every goal', () {
      for (final g in GoalDirection.values) {
        final r = m(80, 180, g, 1900, 2110);
        expect(r.protein.minG, lessThan(r.protein.targetG));
        expect(r.protein.targetG, lessThan(r.protein.maxG));
      }
    });
    test('protein max never exceeds 40 % of kcalMid / 4 even for a heavy ref weight', () {
      final r = m(100, 185, GoalDirection.lose, 1200, 1300); // kcalMid 1250
      expect(r.protein.maxG, 125); // floor(0.4 * 1250 / 4)
      expect(r.protein.minG, 125); // min bounded by max
    });
  });

  group('PLAN-08 fat and carbohydrate', () {
    test('carbMin <= carbMax and carbMin >= 100 across a grid', () {
      for (final w in [45.0, 60.0, 80.0, 100.0, 130.0]) {
        for (final mid in [1250, 1500, 2000, 2500, 3200]) {
          for (final g in GoalDirection.values) {
            final r = computeMacros(
              weightKg: w,
              heightCm: 175,
              goal: g,
              kcal: KcalRange(mid - 50, mid + 50),
            );
            expect(r.carbs.minG, greaterThanOrEqualTo(100));
            expect(r.carbs.minG, lessThanOrEqualTo(r.carbs.maxG));
            expect(r.targets.carbsG, greaterThanOrEqualTo(100));
            expect(r.protein.minG, lessThanOrEqualTo(r.protein.maxG));
            expect(r.fat.minG, lessThanOrEqualTo(r.fat.maxG));
            expect(r.targets.proteinG,
                inInclusiveRange(r.protein.minG, r.protein.maxG));
          }
        }
      }
    });
    test('remainder under 100 g: fat moves to its minimum first, flagged lowCarbBySafety', () {
      final r = computeMacros(
        weightKg: 65,
        heightCm: 175,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1200, 1300),
      );
      expect(r.lowCarbBySafety, isTrue);
      expect(r.targets.fatG, r.fat.minG);
      expect(r.targets.fatG, 39);
      expect(r.targets.carbsG, 100);
      expect(r.targets.proteinG, 125);
      expect(r.carbs.minG, 100);
      expect(r.carbs.maxG, 133);
    });
    test('protein is lowered toward its minimum when fat alone is not enough', () {
      // 75 kg 175 cm, kcal 1200-1300 (mid 1250): protein max 125, min 120,
      // fat min 45. Carbs (1250 - 4*125 - 9*45)/4 = 86.25 < 100 and fat is
      // already at its minimum, so protein drops to its minimum 120.
      final r = computeMacros(
        weightKg: 75,
        heightCm: 175,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1200, 1300),
      );
      expect(r.lowCarbBySafety, isTrue);
      expect(r.protein.minG, 120);
      expect(r.protein.maxG, 125);
      expect(r.targets.proteinG, 120);
      expect(r.targets.fatG, 45);
      expect(r.targets.carbsG, 100);
    });
    test('no flag when the remainder is comfortably above 100 g', () {
      final r = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.maintain,
        kcal: const KcalRange(2300, 2600),
      );
      expect(r.lowCarbBySafety, isFalse);
    });
    test('computePlan sets the plan flag when the macros are low-carb by safety', () {
      // 80 kg 175 cm woman: BMR 600... just assert the flag mirrors the macros.
      final p = computePlan(_in(
          w: 48,
          h: 155,
          age: 75,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      expect(p.flags.contains(PlanFlag.lowCarbBySafety),
          p.macros.lowCarbBySafety);
    });
  });

  group('PLAN-09 steps goal', () {
    test('V-STEPS: sedentary base 6000 -> 7000; very active 10000 -> 11000', () {
      expect(stepsGoalFor(level: ActivityLevel.sedentary), 7000);
      expect(stepsGoalFor(level: ActivityLevel.veryActive), 11000);
    });
    test('V-STEPS: bucket 12500 clamps to 12000; bucket 2500 clamps to 6000', () {
      expect(stepsGoalFor(typicalSteps: 12500), 12000);
      expect(stepsGoalFor(typicalSteps: 2500), 6000);
    });
    test('other buckets: 4000 -> 6000 (clamp), 6500 -> 7500, 9500 -> 10500', () {
      expect(stepsGoalFor(typicalSteps: 4000), 6000);
      expect(stepsGoalFor(typicalSteps: 6500), 7500);
      expect(stepsGoalFor(typicalSteps: 9500), 10500);
    });
    test('activity bases 7500 / 9000 and the unknown-activity default', () {
      expect(stepsGoalFor(level: ActivityLevel.moderatelyActive), 8500);
      expect(stepsGoalFor(level: ActivityLevel.active), 10000);
      expect(stepsGoalFor(), 7000);
    });
    test('typical steps win over the activity level', () {
      expect(
          stepsGoalFor(level: ActivityLevel.veryActive, typicalSteps: 6500),
          7500);
    });
    test('roundTo500 half rounds up: 7250 -> 8250 -> 8500; 7249 -> 8249 -> 8000', () {
      expect(stepsGoalFor(typicalSteps: 7250), 8500);
      expect(stepsGoalFor(typicalSteps: 7249), 8000);
    });
    test('exact edges: base 11000 -> 12000 stays, 11250 -> 12250 -> 12500 -> 12000', () {
      expect(stepsGoalFor(typicalSteps: 11000), 12000);
      expect(stepsGoalFor(typicalSteps: 11250), 12000);
      expect(stepsGoalFor(typicalSteps: 5000), 6000);
    });
  });

  group('PLAN-11 realistic pace', () {
    test('lose from target below current: 80 kg -> 71 kg at 0.4 kg/wk = 23 weeks', () {
      final r = realisticPace(weightKg: 80, heightCm: 180, targetWeightKg: 71);
      expect(r.direction, GoalDirection.lose);
      expect(r.kgPerWeek!, closeTo(0.4, 1e-12));
      expect(r.weeks, 23); // ceil(9 / 0.4 = 22.5)
    });
    test('gain: 70 kg -> 73 kg at 0.25 %/wk = 0.175 kg/wk = 18 weeks', () {
      final r = realisticPace(weightKg: 70, heightCm: 175, targetWeightKg: 73);
      expect(r.direction, GoalDirection.gain);
      expect(r.kgPerWeek!, closeTo(0.175, 1e-12));
      expect(r.weeks, 18); // ceil(17.14)
    });
    test('high BMI uses 0.75 %/wk: 120 kg -> 100 kg = ceil(20 / 0.9) = 23 weeks', () {
      final r = realisticPace(weightKg: 120, heightCm: 175, targetWeightKg: 100);
      expect(r.kgPerWeek!, closeTo(0.9, 1e-12));
      expect(r.weeks, 23);
    });
    test('target BMI < 18.5 -> targetBelowHealthyRange and NO pace', () {
      final r = realisticPace(weightKg: 80, heightCm: 180, targetWeightKg: 55);
      expect(r.targetBelowHealthyRange, isTrue);
      expect(r.kgPerWeek, isNull);
      expect(r.weeks, isNull);
    });
    test('target at BMI 18.52 (60 kg / 180 cm) is accepted', () {
      final r = realisticPace(weightKg: 80, heightCm: 180, targetWeightKg: 60);
      expect(r.targetBelowHealthyRange, isFalse);
      expect(r.weeks, isNotNull);
    });
    test('underweight person asking to lose: coerced to maintain, no pace', () {
      final r = realisticPace(
        weightKg: 55,
        heightCm: 180,
        targetWeightKg: 60,
        goal: GoalDirection.lose,
      );
      expect(r.underweightNoDeficit, isTrue);
      expect(r.direction, GoalDirection.maintain);
      expect(r.kgPerWeek, isNull);
    });
    test('maintain and equal weights give no pace', () {
      final a = realisticPace(
        weightKg: 80,
        heightCm: 180,
        targetWeightKg: 80,
      );
      expect(a.direction, GoalDirection.maintain);
      expect(a.kgPerWeek, isNull);
      final b = realisticPace(
        weightKg: 80,
        heightCm: 180,
        targetWeightKg: 75,
        goal: GoalDirection.maintain,
      );
      expect(b.kgPerWeek, isNull);
    });
    test('an explicit goal overrides the direction implied by the target', () {
      final r = realisticPace(
        weightKg: 70,
        heightCm: 175,
        targetWeightKg: 73,
        goal: GoalDirection.gain,
      );
      expect(r.direction, GoalDirection.gain);
    });
  });

  group('target body fat clamp', () {
    test('male 10..40', () {
      expect(clampTargetBodyFatPct(8, SexBasis.male), 10);
      expect(clampTargetBodyFatPct(10, SexBasis.male), 10);
      expect(clampTargetBodyFatPct(25, SexBasis.male), 25);
      expect(clampTargetBodyFatPct(40, SexBasis.male), 40);
      expect(clampTargetBodyFatPct(45, SexBasis.male), 40);
    });
    test('female and unspecified 16..40', () {
      for (final s in [SexBasis.female, SexBasis.unspecified]) {
        expect(clampTargetBodyFatPct(12, s), 16);
        expect(clampTargetBodyFatPct(15.9, s), 16);
        expect(clampTargetBodyFatPct(16, s), 16);
        expect(clampTargetBodyFatPct(41, s), 40);
      }
    });
  });

  group('MacroTargets', () {
    test('impliedKcal = 4P + 9F + 4C', () {
      const t = MacroTargets(proteinG: 100, fatG: 50, carbsG: 200);
      expect(t.impliedKcal, 400 + 450 + 800);
    });
  });
}
