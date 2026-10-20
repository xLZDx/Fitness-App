// T13 safety_clamps_test (SAFE-08..SAFE-14). One assertion per constant of the
// design 13.6 clamp table so an accidental edit of any constant fails, plus
// behavioural checks that the clamps actually bind in computePlan. Expected
// numbers come from a hand/scratch derivation of design s13, not from the code.
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/safety_clamps.dart';
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
  double? target,
}) =>
    NutritionInputs(
      weightKg: w,
      heightCm: h,
      ageYears: age,
      sex: sex,
      activityLevel: level,
      goal: goal,
      typicalSteps: steps,
      weightTargetKg: target,
    );

void main() {
  group('SAFE-14 clamp constants (design 13.6)', () {
    test('minimum age 18', () => expect(SafetyClamps.minAdultAge, 18));
    test('BMR sex constants', () {
      expect(SafetyClamps.bmrConstantMale, 5);
      expect(SafetyClamps.bmrConstantFemale, -161);
      expect(SafetyClamps.bmrConstantUnspecified, -78);
    });
    test('activity factors never include 1.9', () {
      expect(SafetyClamps.factorSedentary, 1.2);
      expect(SafetyClamps.factorModerate, 1.375);
      expect(SafetyClamps.factorActive, 1.55);
      expect(SafetyClamps.factorVeryActive, 1.725);
    });
    test('steps bands for the cross-check', () {
      expect(SafetyClamps.stepsBandModerate, 5000);
      expect(SafetyClamps.stepsBandActive, 7500);
      expect(SafetyClamps.stepsBandVeryActive, 10000);
    });
    test('7700 kcal per kg', () => expect(SafetyClamps.kcalPerKg, 7700));
    test('absolute floors 1200 F / 1500 M', () {
      expect(SafetyClamps.absoluteFloorKcalFemale, 1200);
      expect(SafetyClamps.absoluteFloorKcalMale, 1500);
    });
    test('deficit 25 % of TDEE', () {
      expect(SafetyClamps.maxDeficitFractionOfTdee, 0.25);
    });
    test('surplus clamp 100 .. min(500, 15 %)', () {
      expect(SafetyClamps.minSurplusKcal, 100);
      expect(SafetyClamps.maxSurplusKcal, 500);
      expect(SafetyClamps.maxSurplusFractionOfTdee, 0.15);
    });
    test('weekly loss rates 0.5/0.75/0.5kg and 0.75/1.0/1.0kg', () {
      expect(SafetyClamps.lossRateLowBmiDefaultPct, 0.50);
      expect(SafetyClamps.lossRateLowBmiMaxPct, 0.75);
      expect(SafetyClamps.lossRateLowBmiAbsoluteKg, 0.5);
      expect(SafetyClamps.lossRateHighBmiDefaultPct, 0.75);
      expect(SafetyClamps.lossRateHighBmiMaxPct, 1.00);
      expect(SafetyClamps.lossRateHighBmiAbsoluteKg, 1.0);
      expect(SafetyClamps.bmiHighRowStart, 25);
      expect(SafetyClamps.bmiObeseRowStart, 30);
    });
    test('gain rates 0.25 default, 0.5 max, 0.5 kg', () {
      expect(SafetyClamps.gainRateDefaultPct, 0.25);
      expect(SafetyClamps.gainRateMaxPct, 0.50);
      expect(SafetyClamps.gainRateAbsoluteKg, 0.5);
    });
    test('tooFast factor 1.25', () => expect(SafetyClamps.tooFastFactor, 1.25));
    test('BMI guards 18.5 / 20 / 0.25 and ETA hidden below 20', () {
      expect(SafetyClamps.underweightBmi, 18.5);
      expect(SafetyClamps.lowBmiDeficitBand, 20);
      expect(SafetyClamps.lowBmiMaxRatePct, 0.25);
      expect(SafetyClamps.etaHiddenBelowGoalBmi, 20);
    });
    test('range construction: lose -200/+100, others +-150, width 100..400', () {
      expect(SafetyClamps.loseRangeBelowKcal, 200);
      expect(SafetyClamps.loseRangeAboveKcal, 100);
      expect(SafetyClamps.symmetricRangeHalfKcal, 150);
      expect(SafetyClamps.minRangeWidthKcal, 100);
      expect(SafetyClamps.maxRangeWidthKcal, 400);
      expect(SafetyClamps.kcalRounding, 10);
      expect(SafetyClamps.maintainBoundsKcal, 300);
    });
    test('rules backstop bounds mirror 1200 and 6000', () {
      expect(SafetyClamps.hardKcalMin, 1200);
      expect(SafetyClamps.hardKcalMax, 6000);
    });
    test('protein factors, 220 g cap and 40 % of kcal', () {
      expect(SafetyClamps.proteinMinMaintainPerKg, 1.4);
      expect(SafetyClamps.proteinMinChangePerKg, 1.6);
      expect(SafetyClamps.proteinTargetMaintainPerKg, 1.6);
      expect(SafetyClamps.proteinTargetLosePerKg, 2.0);
      expect(SafetyClamps.proteinTargetGainPerKg, 1.8);
      expect(SafetyClamps.proteinMaxPerKg, 2.2);
      expect(SafetyClamps.proteinMaxGrams, 220);
      expect(SafetyClamps.proteinMaxFractionOfKcal, 0.40);
      expect(SafetyClamps.referenceWeightBmiCap, 30);
      expect(SafetyClamps.proteinPerKgLeanMass, 2.2);
    });
    test('fat 20-35 % of kcal, 0.6 g/kg, point target 25 %', () {
      expect(SafetyClamps.fatMinFractionOfKcal, 0.20);
      expect(SafetyClamps.fatMaxFractionOfKcal, 0.35);
      expect(SafetyClamps.fatPointFractionOfKcal, 0.25);
      expect(SafetyClamps.fatMinPerKg, 0.6);
    });
    test('carbs >= 100 g; Atwater 4/4/9 and tolerance 25 % / 10 kcal', () {
      expect(SafetyClamps.carbMinGrams, 100);
      expect(SafetyClamps.kcalPerGramProtein, 4);
      expect(SafetyClamps.kcalPerGramCarb, 4);
      expect(SafetyClamps.kcalPerGramFat, 9);
      expect(SafetyClamps.atwaterTolerance, 0.25);
      expect(SafetyClamps.atwaterToleranceFloorKcal, 10);
      expect(SafetyClamps.proteinDisplayStepGrams, 5);
      expect(SafetyClamps.carbDisplayStepGrams, 5);
    });
    test('steps goal 6000-12000, +1000, rounding 500, user 2000-30000', () {
      expect(SafetyClamps.stepsGoalMin, 6000);
      expect(SafetyClamps.stepsGoalMax, 12000);
      expect(SafetyClamps.stepsGoalRounding, 500);
      expect(SafetyClamps.stepsGoalIncrement, 1000);
      expect(SafetyClamps.stepsUserMin, 2000);
      expect(SafetyClamps.stepsUserMax, 30000);
      expect(SafetyClamps.stepsBaseSedentary, 6000);
      expect(SafetyClamps.stepsBaseModerate, 7500);
      expect(SafetyClamps.stepsBaseActive, 9000);
      expect(SafetyClamps.stepsBaseVeryActive, 10000);
      expect(SafetyClamps.stepsBucketMidpoints, [2500, 4000, 6500, 9500, 12500]);
    });
    test('target body fat 10 M / 16 other / 40 max', () {
      expect(SafetyClamps.targetBodyFatMinMale, 10);
      expect(SafetyClamps.targetBodyFatMinOther, 16);
      expect(SafetyClamps.targetBodyFatMax, 40);
    });
    test('weight validity 30..300 and 14-day freshness', () {
      expect(SafetyClamps.weightMinKg, 30);
      expect(SafetyClamps.weightMaxKg, 300);
      expect(SafetyClamps.currentWeightFreshDays, 14);
    });
    test('review: step 150, cooldown 14 d, drift cap 400, deadband, data rule', () {
      expect(SafetyClamps.reviewStepKcal, 150);
      expect(SafetyClamps.reviewCooldownDays, 14);
      expect(SafetyClamps.reviewDriftCapKcal, 400);
      expect(SafetyClamps.maintainDriftStepKcal, 100);
      expect(SafetyClamps.reviewToleranceMinKgPerWeek, 0.15);
      expect(SafetyClamps.reviewToleranceFraction, 0.25);
      expect(SafetyClamps.maintainDriftPctPerWeek, 0.25);
      expect(SafetyClamps.reviewMinWeightPoints, 3);
      expect(SafetyClamps.reviewMinSpanDays, 7);
    });
  });

  group('SAFE-08 calorie floor binds in the plan', () {
    test('V-FLOOR-F: range low never under 1200, never the unfloored 1000', () {
      // female 50 kg 155 cm 40 y sedentary: TDEE 1329.3, floor 1200, raw
      // target range 1000..1300; the floor wins -> 1200..1300.
      final p = computePlan(_in(
          w: 50,
          h: 155,
          age: 40,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      expect(p.floorKcal, 1200);
      expect(p.kcalRange.low, 1200);
      expect(p.kcalRange.high, 1300);
      expect(p.bounds, const PlanBounds(1200, 1320));
      expect(p.targetKcal, closeTo(1200.0, 1e-9));
    });
    test('V-FLOOR-M: relative floor 2068 beats the absolute 1500', () {
      // male 100 kg 190 cm 25 y sedentary: BMR 2067.5, floor 2068.
      final p = computePlan(_in(
          w: 100,
          h: 190,
          age: 25,
          level: ActivityLevel.sedentary));
      expect(p.floorKcal, 2068);
      expect(p.kcalRange.low, greaterThanOrEqualTo(2068));
      expect(p.bounds.minKcal, greaterThanOrEqualTo(2068));
    });
    test('TDEE at or below the floor: the floor wins and the upper bound is min + 100', () {
      // female 48 kg 155 cm 75 y sedentary: BMR 912.75, TDEE 1095.3 < 1200.
      final p = computePlan(_in(
          w: 48,
          h: 155,
          age: 75,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      expect(p.tdee, closeTo(1095.3, 1e-9));
      expect(p.floorKcal, 1200);
      expect(p.flags, contains(PlanFlag.floorBinding));
      expect(p.targetKcal, 1200);
      expect(p.bounds, const PlanBounds(1200, 1300));
      expect(p.kcalRange, const KcalRange(1200, 1300));
    });
    test('maintain goal with TDEE far under the floor is lifted to the floor', () {
      // female 40 kg 140 cm 100 y: BMR 614, TDEE 736.8, floor 1200.
      final p = computePlan(_in(
          w: 40,
          h: 140,
          age: 100,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary,
          goal: GoalDirection.maintain));
      expect(p.targetKcal, 1200);
      expect(p.kcalRange, const KcalRange(1200, 1300));
      expect(p.kcalRange.low, greaterThanOrEqualTo(1200));
    });
    test('a stored low of 1199 or 900 is pulled up to the floor bound', () {
      final p = computePlan(
        _in(
            w: 50,
            h: 155,
            age: 40,
            sex: SexBasis.female,
            level: ActivityLevel.sedentary),
        userRange: const KcalRange(1199, 1299),
      );
      expect(p.kcalRange.low, 1200);
      final q = computePlan(
        _in(
            w: 50,
            h: 155,
            age: 40,
            sex: SexBasis.female,
            level: ActivityLevel.sedentary),
        userRange: const KcalRange(900, 1250),
      );
      expect(q.kcalRange.low, 1200);
      expect(q.kcalRange.width, inInclusiveRange(100, 400));
    });
    test('unspecified sex uses the 1500 absolute floor', () {
      // unspecified 60 kg 165 cm 30 y sedentary: BMR 1197.? = 600+1031.25-150-78 = 1403.25,
      // floor max(1500, 1403) = 1500.
      final p = computePlan(_in(
          w: 60,
          h: 165,
          sex: SexBasis.unspecified,
          level: ActivityLevel.sedentary));
      expect(p.bmr, 1403.25);
      expect(p.floorKcal, 1500);
    });
  });

  group('SAFE-09 maximum weekly loss', () {
    test('a requested 1.5 %/wk is clamped to the BMI-row maximum and flagged', () {
      // BMI 26.12 (80 kg, 175 cm): high row max 1.0 %/wk = 0.8 kg/wk.
      final p = computePlan(_in(w: 80, h: 175), ratePctPerWeek: 1.5);
      expect(p.ratePctPerWeek, 1.0);
      expect(p.kgPerWeek, closeTo(0.8, 1e-12));
      expect(p.flags, contains(PlanFlag.rateClamped));
    });
    test('BMI < 25: 1.5 clamps to 0.75 %/wk and the absolute 0.5 kg/wk wins', () {
      // 100 kg at 205 cm: BMI 23.8; 0.75 % = 0.75 kg but the absolute cap is 0.5.
      final p = computePlan(_in(w: 100, h: 205), ratePctPerWeek: 1.5);
      expect(p.ratePctPerWeek, 0.75);
      expect(p.kgPerWeek, 0.5);
      expect(p.maxKgPerWeek, 0.5);
      // target = TDEE 2937.34375 - min(0.5*7700/7 = 550, 25 % = 734.3, TDEE - floor)
      // = 2387.34375 ; range 2390..2490 after the bounds clamp.
      expect(p.targetKcal, closeTo(2387.34375, 1e-6));
      expect(p.kcalRange, const KcalRange(2390, 2490));
    });
    test('BMI >= 30: 120 kg at 175 cm, 1.0 % = 1.2 kg is capped to 1.0 kg', () {
      // BMI 39.18; active 1.55 -> TDEE 3330.5625; deficit min(1100, 832.6) = 832.64.
      final p = computePlan(
        _in(w: 120, h: 175, level: ActivityLevel.active),
        ratePctPerWeek: 1.5,
      );
      expect(p.kgPerWeek, 1.0);
      expect(p.targetKcal, closeTo(2497.921875, 1e-6));
      expect(p.kcalRange, const KcalRange(2500, 2600));
    });
    test('the slider low end never implies more than the weekly cap', () {
      // V-LOSE-M person: max deficit = min(25 % * 2447.5 = 611.9, 0.5*7700/7 = 550).
      final p = computePlan(_in(w: 80, h: 180));
      expect(p.bounds.minKcal, 1900); // ceil10(2447.5 - 550)
      expect(p.tdee - p.bounds.minKcal, lessThanOrEqualTo(550 + 10));
    });
    test('negative requested pace is floored at zero (no negative deficit)', () {
      final p = computePlan(_in(w: 80, h: 180), ratePctPerWeek: -1);
      expect(p.ratePctPerWeek, 0);
      expect(p.kgPerWeek, 0);
    });
  });

  group('SAFE-10 deficit and surplus caps', () {
    test('V-LOSE-M: the 25 % cap (611.9) does not bind below it (deficit 440)', () {
      final p = computePlan(_in(w: 80, h: 180));
      expect(p.targetKcal, closeTo(2007.5, 1e-9));
    });
    test('25 % TDEE cap binds when the pace asks for more', () {
      // 80 kg 175 cm: TDEE 2404.53125, pace 0.6 kg -> 660 > cap 601.1328125.
      final p = computePlan(_in(w: 80, h: 175));
      expect(p.targetKcal, closeTo(2404.53125 - 0.25 * 2404.53125, 1e-9));
      expect(p.targetKcal, closeTo(1803.3984375, 1e-9));
      expect(p.bounds, const PlanBounds(1810, 2400));
      expect(p.kcalRange, const KcalRange(1810, 1910));
    });
    test('TDEE - floor binds before the pace (V-FLOOR-F deficit = 129.3)', () {
      final p = computePlan(_in(
          w: 50,
          h: 155,
          age: 40,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      expect(p.tdee - p.targetKcal, closeTo(129.3, 1e-9));
    });
    test('surplus capped at 15 % of TDEE when that is under 500', () {
      // gain at the 0.5 %/wk max: delta 440 > min(500, 0.15 * 2447.5 = 367.125).
      final p = computePlan(
        _in(w: 80, h: 180, goal: GoalDirection.gain),
        ratePctPerWeek: 0.5,
      );
      expect(p.targetKcal, closeTo(2814.625, 1e-9));
    });
    test('surplus capped at 500 when 15 % of TDEE is larger', () {
      // 150 kg 190 cm 25 y very active: TDEE 4428.9375, 15 % = 664 > 500.
      final p = computePlan(
        _in(
            w: 150,
            h: 190,
            age: 25,
            level: ActivityLevel.veryActive,
            goal: GoalDirection.gain),
        ratePctPerWeek: 0.5,
      );
      expect(p.targetKcal, closeTo(4928.9375, 1e-9));
    });
    test('surplus is at least 100 even for a tiny requested pace', () {
      // 0.1 %/wk * 80 kg = 0.08 kg -> 88 kcal -> lifted to 100.
      final p = computePlan(
        _in(w: 80, h: 180, goal: GoalDirection.gain),
        ratePctPerWeek: 0.1,
      );
      expect(p.targetKcal, closeTo(2547.5, 1e-9));
    });
    test('default gain pace: 0.25 %/wk of 80 kg = 0.2 kg -> 220 kcal', () {
      final p = computePlan(_in(w: 80, h: 180, goal: GoalDirection.gain));
      expect(p.targetKcal, closeTo(2667.5, 1e-9));
      expect(p.kcalRange, const KcalRange(2520, 2810));
      expect(p.bounds, const PlanBounds(2450, 2810));
    });
  });

  group('SAFE-11 underweight guard', () {
    // 200 cm so BMI = weight / 4 is exact in binary floating point.
    test('BMI 17.9 asking to lose is coerced to maintain with the flag', () {
      final p = computePlan(_in(w: 71.6, h: 200));
      expect(p.requestedGoal, GoalDirection.lose);
      expect(p.goal, GoalDirection.maintain);
      expect(p.flags, contains(PlanFlag.underweightNoDeficit));
      expect(p.kgPerWeek, 0);
      expect(p.targetKcal, closeTo(p.tdee, 1e-9));
    });
    test('BMI 18.49 is refused, BMI 18.5 is allowed', () {
      final under = computePlan(_in(w: 73.96, h: 200));
      expect(under.goal, GoalDirection.maintain);
      final ok = computePlan(_in(w: 74, h: 200));
      expect(ok.bmi, 18.5);
      expect(ok.goal, GoalDirection.lose);
      expect(ok.flags, isNot(contains(PlanFlag.underweightNoDeficit)));
    });
    test('BMI 18.5: deficit at <= 0.25 %/wk (0.185 kg -> 203.5 kcal)', () {
      final p = computePlan(_in(w: 74, h: 200));
      expect(p.ratePctPerWeek, 0.25);
      expect(p.kgPerWeek, closeTo(0.185, 1e-12));
      expect(p.targetKcal, closeTo(2536.875 - 203.5, 1e-9));
      expect(p.kcalRange, const KcalRange(2340, 2440));
    });
    test('BMI 19.9 is capped at 0.25 %/wk even when asked for 0.75', () {
      final p = computePlan(_in(w: 79.6, h: 200), ratePctPerWeek: 0.75);
      expect(p.ratePctPerWeek, 0.25);
      expect(p.flags, contains(PlanFlag.rateClamped));
      expect(p.kcalRange, const KcalRange(2400, 2500));
    });
    test('BMI 20.0 uses the normal row (default 0.5, max 0.75)', () {
      final p = computePlan(_in(w: 80, h: 200));
      expect(p.bmi, 20.0);
      expect(p.ratePctPerWeek, 0.5);
      expect(p.maxKgPerWeek, 0.5);
      expect(p.targetKcal, closeTo(2619.375 - 440, 1e-9));
    });
    test('a target weight with BMI < 18.5 raises targetBelowHealthyRange', () {
      final p = computePlan(_in(w: 80, h: 180, target: 59)); // BMI 18.21
      expect(p.flags, contains(PlanFlag.targetBelowHealthyRange));
      final ok = computePlan(_in(w: 80, h: 180, target: 60)); // BMI 18.52
      expect(ok.flags, isNot(contains(PlanFlag.targetBelowHealthyRange)));
    });
  });

  group('SAFE-12 protein clamps', () {
    test('V-PROT-80: 80 kg lose -> min 128, target 160, max 176', () {
      final m = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1900, 2110),
      );
      expect(m.protein.minG, 128);
      expect(m.protein.targetG, 160);
      expect(m.protein.maxG, 176);
    });
    test('V-PROT-OB: 110 kg / 170 cm uses Wref 86.7 and the 40 % cap 180', () {
      expect(referenceWeightKg(110, 170), closeTo(86.7, 1e-9));
      final m = computeMacros(
        weightKg: 110,
        heightCm: 170,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1700, 1900), // kcalMid 1800
      );
      expect(m.protein.minG, 139);
      expect(m.protein.targetG, 173);
      expect(m.protein.maxG, 180); // raw 191 capped by 0.40 * 1800 / 4
    });
    test('V-PROT-220: 2.2 g/kg = 242 is capped at the absolute 220 g', () {
      final m = computeMacros(
        weightKg: 110,
        heightCm: 195,
        goal: GoalDirection.lose,
        kcal: const KcalRange(2700, 3000),
      );
      expect(m.protein.maxG, 220);
      expect(m.protein.targetG, 220);
    });
    test('a lean-mass target above max is clamped to max, below min to min', () {
      final hi = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1900, 2110),
        leanMassKg: 100, // 2.2 * 100 = 220 > 176
      );
      expect(hi.protein.targetG, 176);
      final lo = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1900, 2110),
        leanMassKg: 40, // 88 < 128
      );
      expect(lo.protein.targetG, 128);
    });
    test('maintain minimum is 1.4 g/kg (112) and gain target 1.8 g/kg (144)', () {
      final m = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.maintain,
        kcal: const KcalRange(1900, 2110),
      );
      expect(m.protein.minG, 112);
      expect(m.protein.targetG, 128);
      final g = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.gain,
        kcal: const KcalRange(1900, 2110),
      );
      expect(g.protein.minG, 128);
      expect(g.protein.targetG, 144);
    });
  });

  group('SAFE-13 fat / carbohydrate / steps / width clamps', () {
    test('V-FAT: kcalMid 1800, Wref 80 -> fat 48..70 (0.6 g/kg beats 20 %)', () {
      final m = computeMacros(
        weightKg: 80,
        heightCm: 180,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1700, 1900),
      );
      expect(m.fat.minG, 48);
      expect(m.fat.maxG, 70);
    });
    test('fat share is never under 20 % or over 35 % of kcalMid', () {
      for (final mid in [1500, 2000, 2500, 3000]) {
        final m = computeMacros(
          weightKg: 70,
          heightCm: 175,
          goal: GoalDirection.maintain,
          kcal: KcalRange(mid - 100, mid + 100),
        );
        expect(m.fat.minG * 9, greaterThanOrEqualTo(0.20 * mid - 5));
        expect(m.fat.maxG * 9, lessThanOrEqualTo(0.35 * mid + 5));
      }
    });
    test('carbohydrate floor 100 g and lowCarbBySafety', () {
      // 65 kg 175 cm, kcal 1200-1300: remainder under 100 g -> flagged.
      final m = computeMacros(
        weightKg: 65,
        heightCm: 175,
        goal: GoalDirection.lose,
        kcal: const KcalRange(1200, 1300),
      );
      expect(m.lowCarbBySafety, isTrue);
      expect(m.carbs.minG, 100);
      expect(m.carbs.maxG, 133);
      expect(m.targets.carbsG, 100);
      expect(m.targets.fatG, 39); // moved to the fat minimum first
      expect(m.targets.proteinG, 125);
      expect(m.protein.minG, 104);
      expect(m.protein.maxG, 125);
    });
    test('computed steps goal is always 6000..12000', () {
      for (final s in [0, 1000, 2500, 5500, 9500, 12500, 40000]) {
        final g = stepsGoalFor(typicalSteps: s);
        expect(g, inInclusiveRange(6000, 12000));
      }
    });
    test('range width 99 -> 100 and 401 -> 400 inside wide bounds', () {
      const b = PlanBounds(1500, 3000);
      expect(clampRangeToBounds(const KcalRange(2000, 2099), b),
          const KcalRange(2000, 2100));
      expect(clampRangeToBounds(const KcalRange(2000, 2401), b),
          const KcalRange(2000, 2400));
      expect(clampRangeToBounds(const KcalRange(2000, 2400), b),
          const KcalRange(2000, 2400));
      expect(clampRangeToBounds(const KcalRange(2000, 2100), b),
          const KcalRange(2000, 2100));
    });
  });

  group('SAFE-17 tiny and extreme profiles', () {
    void check(NutritionPlan p) {
      expect(p.bounds.maxKcal, greaterThanOrEqualTo(p.bounds.minKcal + 100));
      expect(p.kcalRange.low, greaterThanOrEqualTo(p.floorKcal));
      expect(p.kcalRange.low, greaterThanOrEqualTo(p.bounds.minKcal));
      expect(p.kcalRange.high, lessThanOrEqualTo(p.bounds.maxKcal));
      expect(p.kcalRange.width, inInclusiveRange(100, 400));
      for (final v in [p.bmr, p.tdee, p.targetKcal, p.kgPerWeek]) {
        expect(v.isFinite, isTrue);
      }
      expect(p.kcalRange.low % 10, 0);
      expect(p.kcalRange.high % 10, 0);
    }

    test('40 kg / 140 cm woman, age 18', () {
      final p = computePlan(_in(
          w: 40,
          h: 140,
          age: 18,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary));
      check(p);
      expect(p.kcalRange, const KcalRange(1200, 1300));
    });
    test('200 kg / 190 cm man, age 18, very active, lose', () {
      final p = computePlan(_in(
          w: 200, h: 190, age: 18, level: ActivityLevel.veryActive));
      check(p);
      expect(p.bounds, const PlanBounds(4260, 5350));
      expect(p.kcalRange, const KcalRange(4260, 4360));
    });
    test('age 100 woman, maintain', () {
      final p = computePlan(_in(
          w: 40,
          h: 140,
          age: 100,
          sex: SexBasis.female,
          level: ActivityLevel.sedentary,
          goal: GoalDirection.maintain));
      check(p);
    });
    test('200 kg / 190 cm man age 100, gain', () {
      final p = computePlan(_in(
          w: 200,
          h: 190,
          age: 100,
          level: ActivityLevel.veryActive,
          goal: GoalDirection.gain));
      check(p);
      expect(p.bounds, const PlanBounds(4650, 5140));
      expect(p.kcalRange, const KcalRange(4990, 5140));
    });
    test('grid: the slider interval is never empty (weights, heights, ages, sexes, activity)', () {
      for (final w in [40.0, 55.0, 70.0, 100.0, 140.0, 200.0]) {
        for (final h in [140.0, 160.0, 175.0, 190.0, 210.0]) {
          for (final a in [18, 40, 80]) {
            for (final s in SexBasis.values) {
              for (final l in ActivityLevel.values) {
                for (final g in GoalDirection.values) {
                  final p = computePlan(_in(
                      w: w, h: h, age: a, sex: s, level: l, goal: g));
                  check(p);
                }
              }
            }
          }
        }
      }
    });
  });
}
