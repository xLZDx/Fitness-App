// C18 stored_nutrition_plan_test. The stored plan is the user's CHOICE, never
// the source of safety: validated() must recompute the bounds from the digest
// and pull everything inside the clamps; tryFromMap must read only an ACTIVE,
// well-formed plan (needsProfile / unreadable = "no plan"), and no
// referProfessional value may exist in the document. Bounds for the reference
// digest (male, 80 kg, 180 cm, TDEE 2400, BMR 1800) are hand-derived: lose
// 1850..2400, maintain 2100..2700, gain 2400..2760.
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';

void main() {
  group('validated(): bounds are recomputed from the digest', () {
    test('a hand-widened stored kcalBounds is replaced (lose 1850..2400)', () {
      final p = storedPlan(bounds: const PlanBounds(1000, 6000)).validated();
      expect(p.kcalBounds, const PlanBounds(1850, 2400));
    });

    test('maintain bounds are TDEE +- 300 = 2100..2700', () {
      final p = storedPlan(
        goal: GoalDirection.maintain,
        range: const KcalRange(2300, 2500),
        ratePct: 0,
        bounds: const PlanBounds(1, 9999),
      ).validated();
      expect(p.kcalBounds, const PlanBounds(2100, 2700));
    });

    test('gain bounds are TDEE .. TDEE + min(500, 15 %) = 2400..2760', () {
      final p = storedPlan(
        goal: GoalDirection.gain,
        range: const KcalRange(2450, 2600),
        ratePct: 0.25,
        bounds: const PlanBounds(1, 9999),
      ).validated();
      expect(p.kcalBounds, const PlanBounds(2400, 2760));
    });

    test('the calorie floor (BMR 1800 for a male) lifts the lower bound', () {
      // A low-TDEE digest: tdee 1900, bmr 1800 -> floor 1800; the lose bound is
      // max(1800, 1900 - min(475, 550)) = 1800 (ceil10).
      const digest = PlanInputsDigest(
        weightKg: 80,
        heightCm: 180,
        ageYears: 35,
        activityFactor: 1.2,
        tdee: 1900,
        bmr: 1800,
        sexBasis: SexBasis.male,
      );
      final p = storedPlan(
        digest: digest,
        range: const KcalRange(1500, 1600),
      ).validated();
      expect(p.kcalBounds.minKcal, 1800);
      expect(p.kcalRange.low, greaterThanOrEqualTo(1800));
    });
  });

  group('validated(): the range is pulled inside and the macros follow', () {
    test('a range under the lower bound moves up; macros re-derived', () {
      final raw = storedPlan(range: const KcalRange(1000, 1100));
      final p = raw.validated();
      expect(p.kcalRange, const KcalRange(1850, 1950));
      final expected = macrosOf(const KcalRange(1850, 1950));
      expect(p.carbs.maxG, expected.carbs.maxG);
      expect(p.carbs.minG, expected.carbs.minG);
      expect(p.fat.maxG, expected.fat.maxG);
      expect(p.protein.maxG, expected.protein.maxG);
      expect(p.carbs.maxG, isNot(raw.carbs.maxG),
          reason: 'the stale macros of the invalid range must not survive');
    });

    test('a range over the upper bound moves down to 2300..2400', () {
      final p = storedPlan(range: const KcalRange(3000, 3200)).validated();
      expect(p.kcalRange, const KcalRange(2300, 2400));
    });

    test('a range wider than 400 is narrowed to 400', () {
      final p = storedPlan(range: const KcalRange(1900, 2400)).validated();
      expect(p.kcalRange, const KcalRange(1900, 2300));
    });

    test('a range narrower than 100 is widened to 100', () {
      final p = storedPlan(range: const KcalRange(2000, 2050)).validated();
      expect(p.kcalRange, const KcalRange(2000, 2100));
    });

    test('a valid plan is returned unchanged (macros kept as stored)', () {
      final raw = storedPlan();
      final p = raw.validated();
      expect(p.kcalRange, raw.kcalRange);
      expect(p.protein.targetG, raw.protein.targetG);
      expect(p.fat.minG, raw.fat.minG);
      expect(p.carbs.maxG, raw.carbs.maxG);
      expect(p.planVersion, raw.planVersion);
      expect(p.driftFromInitialKcal, raw.driftFromInitialKcal);
    });

    test('validated() is idempotent', () {
      final once = storedPlan(range: const KcalRange(1000, 1100)).validated();
      final twice = once.validated();
      expect(twice.kcalRange, once.kcalRange);
      expect(twice.carbs.maxG, once.carbs.maxG);
      expect(twice.kcalBounds, once.kcalBounds);
    });

    test('other fields survive validation untouched', () {
      final lastAdjust = DateTime(2026, 9, 20);
      final p = storedPlan(
        range: const KcalRange(1000, 1100),
        ownership: PlanOwnership.shared,
        autoAdjust: const AutoAdjust(steps: false, kcal: true),
        lastAdjust: lastAdjust,
        drift: -200,
        version: 7,
      ).validated();
      expect(p.ownership, PlanOwnership.shared);
      expect(p.autoAdjust.steps, isFalse);
      expect(p.autoAdjust.kcal, isTrue);
      expect(p.lastKcalAdjustAt, lastAdjust);
      expect(p.driftFromInitialKcal, -200);
      expect(p.planVersion, 7);
      expect(p.goal, GoalDirection.lose);
    });
  });

  group('validated(): steps goal and rate clamps', () {
    test('steps below 2,000 and above 30,000 are clamped', () {
      expect(storedPlan(stepsGoal: 100).validated().stepsGoal, 2000);
      expect(storedPlan(stepsGoal: 99999).validated().stepsGoal, 30000);
      expect(storedPlan(stepsGoal: 2000).validated().stepsGoal, 2000);
      expect(storedPlan(stepsGoal: 30000).validated().stepsGoal, 30000);
      expect(storedPlan(stepsGoal: 12345).validated().stepsGoal, 12345);
    });

    test('rate above the row maximum (0.75 %) is pulled down', () {
      expect(storedPlan(ratePct: 5).validated().ratePctPerWeek, 0.75);
    });

    test('a negative rate becomes 0; maintain can only hold 0', () {
      expect(storedPlan(ratePct: -1).validated().ratePctPerWeek, 0);
      expect(
        storedPlan(goal: GoalDirection.maintain, ratePct: 0.4)
            .validated()
            .ratePctPerWeek,
        0,
      );
    });
  });

  group('derived rates', () {
    test('lose: max 0.5 kg/week (absolute cap), intended -0.4', () {
      final p = storedPlan(ratePct: 0.5);
      expect(p.maxKgPerWeek, closeTo(0.5, 1e-9));
      expect(p.intendedKgPerWeek, closeTo(-0.4, 1e-9));
    });

    test('maintain: intended 0 and max 0', () {
      final p = storedPlan(goal: GoalDirection.maintain, ratePct: 0);
      expect(p.intendedKgPerWeek, 0);
      expect(p.maxKgPerWeek, 0);
    });

    test('gain: intended is positive', () {
      final p = storedPlan(goal: GoalDirection.gain, ratePct: 0.25);
      expect(p.intendedKgPerWeek, closeTo(0.2, 1e-9));
    });
  });

  group('daysSinceLastAdjust', () {
    test('null when never adjusted', () {
      expect(storedPlan().daysSinceLastAdjust(kNow), isNull);
    });

    test('whole days, floored', () {
      final p = storedPlan(
          lastAdjust: kNow.subtract(const Duration(days: 9, hours: 23)));
      expect(p.daysSinceLastAdjust(kNow), 9);
    });
  });

  group('copyWith', () {
    test('clearReviewUndo removes the undo; omitting keeps it', () {
      final undo = ReviewUndo(
        week: kWeek,
        prevKcalRange: const KcalRange(2100, 2300),
        prevStepsGoal: 8000,
        prevDrift: 0,
        expiresAt: kNow.add(const Duration(days: 7)),
      );
      final p = storedPlan(undo: undo);
      expect(p.copyWith(planVersion: 9).reviewUndo, isNotNull);
      expect(p.copyWith(clearReviewUndo: true).reviewUndo, isNull);
      expect(p.copyWith(planVersion: 9).planVersion, 9);
    });
  });

  group('ReviewUndo', () {
    ReviewUndo undo({bool undone = false}) => ReviewUndo(
          week: kWeek,
          prevKcalRange: const KcalRange(2100, 2300),
          prevStepsGoal: 8000,
          prevDrift: -40,
          expiresAt: DateTime(2026, 10, 22, 9),
          undone: undone,
        );

    test('available strictly before expiresAt and only while not undone', () {
      expect(undo().isAvailableAt(DateTime(2026, 10, 22, 8, 59, 59)), isTrue);
      expect(undo().isAvailableAt(DateTime(2026, 10, 22, 9)), isFalse);
      expect(undo().isAvailableAt(DateTime(2026, 10, 23)), isFalse);
      expect(undo(undone: true).isAvailableAt(DateTime(2026, 10, 16)), isFalse);
    });

    test('markUndone keeps every other field', () {
      final u = undo().markUndone();
      expect(u.undone, isTrue);
      expect(u.week, kWeek);
      expect(u.prevKcalRange, const KcalRange(2100, 2300));
      expect(u.prevStepsGoal, 8000);
      expect(u.prevDrift, -40);
      expect(u.expiresAt, DateTime(2026, 10, 22, 9));
    });

    test('toMap / tryFromMap round trip', () {
      final back = ReviewUndo.tryFromMap(undo(undone: true).toMap())!;
      expect(back.week, kWeek);
      expect(back.prevKcalRange, const KcalRange(2100, 2300));
      expect(back.prevStepsGoal, 8000);
      expect(back.prevDrift, -40);
      expect(back.expiresAt, DateTime(2026, 10, 22, 9));
      expect(back.undone, isTrue);
    });

    test('a record with a missing or inverted field reads as null', () {
      final good = undo().toMap();
      expect(ReviewUndo.tryFromMap(null), isNull);
      expect(ReviewUndo.tryFromMap('x'), isNull);
      expect(ReviewUndo.tryFromMap({...good}..remove('week')), isNull);
      expect(ReviewUndo.tryFromMap({...good}..remove('expiresAt')), isNull);
      expect(
        ReviewUndo.tryFromMap({
          ...good,
          'prevKcalRange': {'low': 2300, 'high': 2100},
        }),
        isNull,
      );
    });
  });

  group('PlanInputsDigest', () {
    test('round trip', () {
      final back = PlanInputsDigest.tryFromMap(kDigest.toMap())!;
      expect(back.weightKg, 80);
      expect(back.heightCm, 180);
      expect(back.ageYears, 35);
      expect(back.activityFactor, 1.375);
      expect(back.tdee, 2400);
      expect(back.bmr, 1800);
      expect(back.sexBasis, SexBasis.male);
    });

    test('zero weight, missing field or unknown sex reads as null', () {
      final m = kDigest.toMap();
      expect(PlanInputsDigest.tryFromMap({...m, 'weightKg': 0}), isNull);
      expect(PlanInputsDigest.tryFromMap({...m, 'tdee': -1}), isNull);
      expect(PlanInputsDigest.tryFromMap({...m, 'sexBasis': 'x'}), isNull);
      expect(PlanInputsDigest.tryFromMap({...m}..remove('bmr')), isNull);
      expect(PlanInputsDigest.tryFromMap(null), isNull);
    });
  });

  group('toMap / tryFromMap round trip', () {
    test('every persisted field survives', () {
      final lastAdjust = DateTime(2026, 10, 1, 7);
      final undo = ReviewUndo(
        week: '2026-W40',
        prevKcalRange: const KcalRange(2100, 2300),
        prevStepsGoal: 8000,
        prevDrift: -50,
        expiresAt: DateTime(2026, 10, 8, 7),
      );
      final src = storedPlan(
        version: 6,
        ownership: PlanOwnership.shared,
        autoAdjust: const AutoAdjust(steps: true, kcal: false),
        range: const KcalRange(1950, 2150),
        stepsGoal: 9500,
        lastAdjust: lastAdjust,
        drift: -250,
        undo: undo,
        ratePct: 0.6,
      );
      final back = StoredNutritionPlan.tryFromMap(src.toMap())!;
      expect(back.planVersion, 6);
      expect(back.ownership, PlanOwnership.shared);
      expect(back.autoAdjust.steps, isTrue);
      expect(back.autoAdjust.kcal, isFalse);
      expect(back.goal, GoalDirection.lose);
      expect(back.ratePctPerWeek, 0.6);
      expect(back.kcalRange, const KcalRange(1950, 2150));
      expect(back.kcalBounds, kLoseBounds);
      expect(back.protein.minG, src.protein.minG);
      expect(back.protein.targetG, src.protein.targetG);
      expect(back.protein.maxG, src.protein.maxG);
      expect(back.fat.minG, src.fat.minG);
      expect(back.fat.maxG, src.fat.maxG);
      expect(back.carbs.minG, src.carbs.minG);
      expect(back.carbs.maxG, src.carbs.maxG);
      expect(back.stepsGoal, 9500);
      expect(back.digest.tdee, 2400);
      expect(back.computedAt, src.computedAt);
      expect(back.lastKcalAdjustAt, lastAdjust);
      expect(back.driftFromInitialKcal, -250);
      expect(back.reviewUndo!.week, '2026-W40');
      expect(back.reviewUndo!.prevKcalRange, const KcalRange(2100, 2300));
    });

    test('the document is ACTIVE schema 1 and has no referProfessional', () {
      final m = storedPlan().toMap();
      expect(m['status'], 'active');
      expect(m['schema'], 1);
      expect(m['planVersion'], 3);
      expect(m.containsKey('referProfessional'), isFalse);
      expect(m.toString().toLowerCase().contains('referprofessional'), isFalse);
      expect(m.containsKey('lastKcalAdjustAt'), isFalse,
          reason: 'omitted until a review changed the plan');
      expect(m.containsKey('reviewUndo'), isFalse);
    });

    test('the time encoder is applied to every timestamp', () {
      final src = storedPlan(
        lastAdjust: DateTime(2026, 10, 1),
        undo: ReviewUndo(
          week: kWeek,
          prevKcalRange: const KcalRange(2100, 2300),
          prevStepsGoal: 8000,
          prevDrift: 0,
          expiresAt: DateTime(2026, 10, 8),
        ),
      );
      final m = src.toMap(time: (t) => 'T:${t.toIso8601String()}');
      expect(m['computedAt'], startsWith('T:'));
      expect(m['lastKcalAdjustAt'], startsWith('T:'));
      expect((m['reviewUndo'] as Map)['expiresAt'], startsWith('T:'));
    });
  });

  group('tryFromMap: only a readable ACTIVE plan', () {
    Map<String, dynamic> good() => storedPlan().toMap();

    test('status needsProfile reads as no plan', () {
      expect(
          StoredNutritionPlan.tryFromMap({...good(), 'status': 'needsProfile'}),
          isNull);
    });

    test('any other status (including referProfessional) reads as no plan', () {
      expect(
          StoredNutritionPlan.tryFromMap(
              {...good(), 'status': 'referProfessional'}),
          isNull);
      expect(StoredNutritionPlan.tryFromMap({...good()}..remove('status')),
          isNull);
    });

    test('non-map input reads as no plan', () {
      expect(StoredNutritionPlan.tryFromMap(null), isNull);
      expect(StoredNutritionPlan.tryFromMap('active'), isNull);
      expect(StoredNutritionPlan.tryFromMap(const [1, 2]), isNull);
    });

    test('version < 1, missing steps, bad goal, inverted range, no digest', () {
      expect(StoredNutritionPlan.tryFromMap({...good(), 'planVersion': 0}),
          isNull);
      expect(StoredNutritionPlan.tryFromMap({...good()}..remove('stepsGoal')),
          isNull);
      expect(
          StoredNutritionPlan.tryFromMap({...good(), 'goalDirection': 'zzz'}),
          isNull);
      expect(
          StoredNutritionPlan.tryFromMap({
            ...good(),
            'kcalRange': {'low': 2200, 'high': 2000},
          }),
          isNull);
      expect(
          StoredNutritionPlan.tryFromMap({...good()}..remove('inputsDigest')),
          isNull);
    });

    test('a non-integer kcal (2000.5) is unreadable, an integral double is fine', () {
      expect(
          StoredNutritionPlan.tryFromMap({
            ...good(),
            'kcalRange': {'low': 2000.5, 'high': 2200},
          }),
          isNull);
      final p = StoredNutritionPlan.tryFromMap({
        ...good(),
        'kcalRange': {'low': 2000.0, 'high': 2200.0},
      })!;
      expect(p.kcalRange, const KcalRange(2000, 2200));
    });
  });

  group('tryFromMap: tolerant defaults', () {
    test('missing autoAdjust -> both on; individual false is kept', () {
      final m = storedPlan().toMap()..remove('autoAdjust');
      final p = StoredNutritionPlan.tryFromMap(m)!;
      expect(p.autoAdjust.steps, isTrue);
      expect(p.autoAdjust.kcal, isTrue);
      final q = StoredNutritionPlan.tryFromMap({
        ...storedPlan().toMap(),
        'autoAdjust': {'steps': false},
      })!;
      expect(q.autoAdjust.steps, isFalse);
      expect(q.autoAdjust.kcal, isTrue);
    });

    test('unknown ownership -> coached (the default mode)', () {
      final p = StoredNutritionPlan.tryFromMap(
          {...storedPlan().toMap(), 'ownership': 'wizard'})!;
      expect(p.ownership, PlanOwnership.coached);
    });

    test('missing macro bands are re-derived for the range', () {
      final m = storedPlan().toMap()
        ..remove('protein')
        ..remove('fat')
        ..remove('carbs');
      final p = StoredNutritionPlan.tryFromMap(m)!;
      final expected = macrosOf(const KcalRange(2000, 2200));
      expect(p.protein.maxG, expected.protein.maxG);
      expect(p.fat.maxG, expected.fat.maxG);
      expect(p.carbs.maxG, expected.carbs.maxG);
    });

    test('missing kcalBounds fall back to the range (validated later)', () {
      final m = storedPlan().toMap()..remove('kcalBounds');
      final p = StoredNutritionPlan.tryFromMap(m)!;
      expect(p.kcalBounds, const PlanBounds(2000, 2200));
      expect(p.validated().kcalBounds, kLoseBounds);
    });

    test('missing drift -> 0, missing computedAt -> epoch, no undo -> null', () {
      final m = storedPlan().toMap()
        ..remove('driftFromInitialKcal')
        ..remove('computedAt');
      final p = StoredNutritionPlan.tryFromMap(m)!;
      expect(p.driftFromInitialKcal, 0);
      expect(p.computedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(p.reviewUndo, isNull);
      expect(p.lastKcalAdjustAt, isNull);
    });

    test('timestamps are read from ISO strings and epoch millis', () {
      final iso = StoredNutritionPlan.tryFromMap({
        ...storedPlan().toMap(),
        'lastKcalAdjustAt': '2026-10-01T07:00:00.000',
      })!;
      expect(iso.lastKcalAdjustAt, DateTime(2026, 10, 1, 7));
      final millis = StoredNutritionPlan.tryFromMap({
        ...storedPlan().toMap(),
        'lastKcalAdjustAt': DateTime(2026, 10, 1, 7).millisecondsSinceEpoch,
      })!;
      expect(millis.lastKcalAdjustAt, DateTime(2026, 10, 1, 7));
    });

    test('a hand-edited document is not trusted: validated() fixes it', () {
      final m = storedPlan().toMap();
      m['kcalRange'] = {'low': 900, 'high': 1000};
      m['kcalBounds'] = {'min': 900, 'max': 6000};
      m['stepsGoal'] = 1;
      final p = StoredNutritionPlan.tryFromMap(m)!.validated();
      expect(p.kcalBounds, kLoseBounds);
      expect(p.kcalRange, const KcalRange(1850, 1950));
      expect(p.stepsGoal, 2000);
    });
  });
}
