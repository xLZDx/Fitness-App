// T91 day_totals_test (FOOD-18 day totals as ranges, FOOD-19 per-meal
// targets). Expected numbers are worked by hand (root-sum-square).
import 'dart:math' as math;

import 'package:fitness_app/features/food_diary/data/day_totals.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:flutter_test/flutter_test.dart';

const _targets = DayTargets(
  kcalLow: 1800,
  kcalTarget: 2000,
  kcalHigh: 2200,
  proteinMinG: 100,
);

MacroTotals _t({
  double kcalLow = 0,
  required double kcalMid,
  double? kcalHigh,
  double proteinMid = 0,
}) =>
    MacroTotals(
      kcal: MacroRange(kcalLow, kcalMid, kcalHigh ?? kcalMid),
      proteinG: MacroRange.exact(proteinMid),
      carbsG: MacroRange.zero,
      fatG: MacroRange.zero,
    );

void main() {
  group('RSS combination', () {
    test('two items each 100 below mid give 141.4 below, not 200', () {
      final d = computeDayTotals([
        _t(kcalLow: 900, kcalMid: 1000, kcalHigh: 1000),
        _t(kcalLow: 900, kcalMid: 1000, kcalHigh: 1000),
      ], _targets);
      expect(d.totals.kcal.mid, 2000);
      expect(d.totals.kcal.low, closeTo(2000 - 100 * math.sqrt2, 1e-9));
      expect(d.totals.kcal.low, closeTo(1858.5786, 1e-3));
      expect(d.totals.kcal.high, 2000, reason: 'no upward spread');
    });

    test('upper and lower spreads are combined independently', () {
      // A: 60/100/130, B: 70/100/120 -> down sqrt(40^2+30^2)=50,
      // up sqrt(30^2+20^2)=sqrt(1300)
      final d = computeDayTotals([
        _t(kcalLow: 60, kcalMid: 100, kcalHigh: 130),
        _t(kcalLow: 70, kcalMid: 100, kcalHigh: 120),
      ], _targets);
      expect(d.totals.kcal.mid, 200);
      expect(d.totals.kcal.low, closeTo(150, 1e-9));
      expect(d.totals.kcal.high, closeTo(200 + math.sqrt(1300), 1e-9));
    });

    test('three equal spreads: sqrt(3) x spread', () {
      final e = _t(kcalLow: 90, kcalMid: 100, kcalHigh: 110);
      final d = computeDayTotals([e, e, e], _targets);
      expect(d.totals.kcal.mid, 300);
      expect(d.totals.kcal.low, closeTo(300 - 10 * math.sqrt(3), 1e-9));
      expect(d.totals.kcal.high, closeTo(300 + 10 * math.sqrt(3), 1e-9));
    });

    test('RSS spread is never wider than the plain sum of spreads', () {
      final e = _t(kcalLow: 50, kcalMid: 100, kcalHigh: 150);
      final d = computeDayTotals([e, e, e, e], _targets);
      // RSS of 4 x 50 = 100; plain sum would be 200
      expect(d.totals.kcal.mid - d.totals.kcal.low, closeTo(100, 1e-9));
      expect(d.totals.kcal.high - d.totals.kcal.mid, closeTo(100, 1e-9));
    });

    test('exact entries add exactly with zero spread', () {
      final d = computeDayTotals([
        _t(kcalMid: 500, kcalLow: 500, kcalHigh: 500),
        _t(kcalMid: 700, kcalLow: 700, kcalHigh: 700),
      ], _targets);
      expect(d.totals.kcal, MacroRange.exact(1200));
    });

    test('macros other than kcal are combined too', () {
      final a = MacroTotals(
        kcal: MacroRange.zero,
        proteinG: MacroRange(20, 30, 40),
        carbsG: MacroRange(0, 10, 10),
        fatG: MacroRange(5, 5, 5),
      );
      final d = computeDayTotals([a, a], _targets);
      expect(d.totals.proteinG.mid, 60);
      expect(d.totals.proteinG.low, closeTo(60 - 10 * math.sqrt2, 1e-9));
      expect(d.totals.proteinG.high, closeTo(60 + 10 * math.sqrt2, 1e-9));
      expect(d.totals.carbsG.low, closeTo(20 - 10 * math.sqrt2, 1e-9));
      expect(d.totals.carbsG.high, 20);
      expect(d.totals.fatG, MacroRange.exact(10));
    });
  });

  group('empty day', () {
    test('no entries: zero totals, below range, full distance to the low end',
        () {
      final d = computeDayTotals(const [], _targets);
      expect(d.totals, MacroTotals.zero);
      expect(d.status, KcalStatus.below);
      expect(d.belowRangeBy, 1800);
      expect(d.remainingKcal, 2200);
      expect(d.proteinMinimumReached, isFalse);
    });

    test('empty day with protein minimum null never shows the tick', () {
      const t = DayTargets(kcalLow: 1800, kcalTarget: 2000, kcalHigh: 2200);
      expect(computeDayTotals(const [], t).proteinMinimumReached, isFalse);
      expect(
          computeDayTotals([_t(kcalMid: 2000, proteinMid: 500)], t)
              .proteinMinimumReached,
          isFalse,
          reason: 'null minimum hides the tick even with lots of protein');
    });

    test('an entry with zero totals behaves as an empty day', () {
      final d = computeDayTotals([MacroTotals.zero], _targets);
      expect(d.status, KcalStatus.below);
      expect(d.belowRangeBy, 1800);
    });
  });

  group('status uses mid with inclusive bounds', () {
    DayTotals at(double mid) =>
        computeDayTotals([_t(kcalMid: mid, kcalLow: mid, kcalHigh: mid)], _targets);

    test('just below the low end', () {
      final d = at(1799.99);
      expect(d.status, KcalStatus.below);
      expect(d.belowRangeBy, closeTo(0.01, 1e-9));
      expect(d.remainingKcal, closeTo(400.01, 1e-9));
    });

    test('exactly the low bound is within; nothing below', () {
      final d = at(1800);
      expect(d.status, KcalStatus.within);
      expect(d.belowRangeBy, 0);
      expect(d.remainingKcal, 400);
    });

    test('target is within', () {
      final d = at(2000);
      expect(d.status, KcalStatus.within);
      expect(d.belowRangeBy, 0);
      expect(d.remainingKcal, 200);
    });

    test('exactly the high bound is within; remaining is 0', () {
      final d = at(2200);
      expect(d.status, KcalStatus.within);
      expect(d.remainingKcal, 0);
    });

    test('just above the high end is above; remaining clamps to 0', () {
      final d = at(2200.01);
      expect(d.status, KcalStatus.above);
      expect(d.remainingKcal, 0);
      expect(d.belowRangeBy, 0);
    });

    test('status follows mid, not the low or high edge of the spread', () {
      // mid 2000 is within although low 1858 is below the range low... and
      // high 2141 is within; mid 1700 with high 1900 is still below.
      final within = computeDayTotals([
        _t(kcalLow: 900, kcalMid: 1000, kcalHigh: 1000),
        _t(kcalLow: 900, kcalMid: 1000, kcalHigh: 1000),
      ], _targets);
      expect(within.status, KcalStatus.within);
      final below = computeDayTotals(
          [_t(kcalLow: 1500, kcalMid: 1700, kcalHigh: 1900)], _targets);
      expect(below.status, KcalStatus.below);
      expect(below.belowRangeBy, 100);
    });

    test('remaining is measured against the top of the range, not the target',
        () {
      final d = at(1500);
      expect(d.remainingKcal, 700, reason: '2200 - 1500, not 2000 - 1500');
      expect(d.belowRangeBy, 300);
    });
  });

  group('protein minimum', () {
    DayTotals withProtein(double p) =>
        computeDayTotals([_t(kcalMid: 2000, proteinMid: p)], _targets);

    test('exactly the minimum counts as reached', () {
      expect(withProtein(100).proteinMinimumReached, isTrue);
    });
    test('just under is not reached', () {
      expect(withProtein(99.99).proteinMinimumReached, isFalse);
    });
    test('above is reached', () {
      expect(withProtein(100.01).proteinMinimumReached, isTrue);
    });
    test('protein mid is summed across entries before comparing', () {
      final d = computeDayTotals([
        _t(kcalMid: 500, proteinMid: 60),
        _t(kcalMid: 500, proteinMid: 40),
      ], _targets);
      expect(d.proteinMinimumReached, isTrue);
      final d2 = computeDayTotals([
        _t(kcalMid: 500, proteinMid: 60),
        _t(kcalMid: 500, proteinMid: 39.9),
      ], _targets);
      expect(d2.proteinMinimumReached, isFalse);
    });
  });

  group('mealShares', () {
    test('1 meal is 100 %', () {
      expect(mealShares(1), [1.0]);
    });
    test('2 meals are 50/50', () {
      expect(mealShares(2), [0.5, 0.5]);
    });
    test('3 meals are exactly 30/35/35', () {
      expect(mealShares(3), [0.30, 0.35, 0.35]);
    });
    test('zero and negative meals degrade to one meal', () {
      expect(mealShares(0), [1.0]);
      expect(mealShares(-4), [1.0]);
    });

    test('4 meals: one 10 % snack, mains keep 30/35/35 of the remaining 90 %',
        () {
      final s = mealShares(4);
      expect(s.length, 4);
      expect(s[0], closeTo(0.27, 1e-12));
      expect(s[1], closeTo(0.315, 1e-12));
      expect(s[2], closeTo(0.315, 1e-12));
      expect(s[3], closeTo(0.10, 1e-12));
    });

    test('5 meals: two snacks at 10 %, mains scaled to 80 %', () {
      final s = mealShares(5);
      expect(s.length, 5);
      expect(s[0], closeTo(0.24, 1e-12));
      expect(s[1], closeTo(0.28, 1e-12));
      expect(s[2], closeTo(0.28, 1e-12));
      expect(s[3], closeTo(0.10, 1e-12));
      expect(s[4], closeTo(0.10, 1e-12));
    });

    test('7 meals: four snacks reach the 40 % snack cap exactly', () {
      final s = mealShares(7);
      expect(s.sublist(3), everyElement(closeTo(0.10, 1e-12)));
      expect(s[0], closeTo(0.18, 1e-12));
    });

    test('8 meals: snacks share the capped 40 % evenly (8 % each)', () {
      final s = mealShares(8);
      expect(s.length, 8);
      expect(s.sublist(3), everyElement(closeTo(0.08, 1e-12)));
      expect(s[0], closeTo(0.18, 1e-12));
      expect(s[1], closeTo(0.21, 1e-12));
    });

    test('shares always sum to 100 % and stay positive for 1 to 30 meals', () {
      for (var n = 1; n <= 30; n++) {
        final s = mealShares(n);
        expect(s.length, n, reason: 'n=$n');
        expect(s.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-12),
            reason: 'n=$n');
        expect(s.every((v) => v > 0), isTrue, reason: 'n=$n');
      }
    });
  });

  group('mealKcalTargets', () {
    test('3 meals split low/target/high 30/35/35', () {
      final r = mealKcalTargets(3, _targets);
      expect(r.length, 3);
      expect(r[0].low, closeTo(540, 1e-9));
      expect(r[0].mid, closeTo(600, 1e-9));
      expect(r[0].high, closeTo(660, 1e-9));
      expect(r[1].low, closeTo(630, 1e-9));
      expect(r[1].mid, closeTo(700, 1e-9));
      expect(r[1].high, closeTo(770, 1e-9));
      expect(r[2], r[1]);
    });

    test('the meal targets add back up to the day plan for 1..8 meals', () {
      for (var n = 1; n <= 8; n++) {
        final r = mealKcalTargets(n, _targets);
        expect(r.length, n);
        expect(r.fold<double>(0, (a, b) => a + b.low), closeTo(1800, 1e-9));
        expect(r.fold<double>(0, (a, b) => a + b.mid), closeTo(2000, 1e-9));
        expect(r.fold<double>(0, (a, b) => a + b.high), closeTo(2200, 1e-9));
        for (final m in r) {
          expect(m.low <= m.mid && m.mid <= m.high, isTrue);
        }
      }
    });

    test('a single meal gets the whole plan', () {
      final r = mealKcalTargets(1, _targets);
      expect(r.single, MacroRange(1800, 2000, 2200));
    });
  });
}
