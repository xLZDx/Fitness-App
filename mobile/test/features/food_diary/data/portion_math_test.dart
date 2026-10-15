// T90 portion_math_test (FOOD-17 portion maths, FOOD-20 hidden-oil totals,
// FOOD-04 Atwater tolerance, FOOD-23 quick log). Expected values are worked by
// hand from per100g x grams / 100.
import 'dart:math' as math;

import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/data/portion_math.dart';
import 'package:flutter_test/flutter_test.dart';

const _rice = Per100g(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5);
const _oil = Per100g(kcal: 884, proteinG: 0, carbsG: 0, fatG: 100);

FoodItem _item(
  String ref,
  Per100g p,
  MacroRange grams, {
  FoodSource source = FoodSource.usda,
}) =>
    FoodItem(
      foodRef: ref,
      name: ref,
      grams: grams,
      per100g: p,
      source: source,
    );

FoodEntry _entry(List<FoodItem> items, {List<CheckItem> checks = const []}) =>
    buildEntry(
      id: 'e1',
      day: '2026-10-15',
      slot: MealSlot.dinner,
      loggedAt: DateTime.utc(2026, 10, 15, 19),
      name: 'Dinner',
      source: EntrySource.photo,
      confidence: EntryConfidence.medium,
      items: items,
      checkThese: checks,
      model: const ModelRef(id: 'gemini', version: '2'),
    );

void _expectRange(MacroRange r, double lo, double mid, double hi) {
  expect(r.low, closeTo(lo, 1e-9), reason: 'low');
  expect(r.mid, closeTo(mid, 1e-9), reason: 'mid');
  expect(r.high, closeTo(hi, 1e-9), reason: 'high');
}

void main() {
  group('itemMacros', () {
    test('80/100/150 g of 200 kcal, 10 P, 20 C, 5 F per 100 g', () {
      final m = itemMacros(_rice, MacroRange(80, 100, 150));
      _expectRange(m.kcal, 160, 200, 300);
      _expectRange(m.proteinG, 8, 10, 15);
      _expectRange(m.carbsG, 16, 20, 30);
      _expectRange(m.fatG, 4, 5, 7.5);
    });

    test('exact grams give a degenerate range', () {
      final m = itemMacros(_rice, MacroRange.exact(250));
      _expectRange(m.kcal, 500, 500, 500);
      _expectRange(m.proteinG, 25, 25, 25);
    });

    test('zero grams give zero everywhere', () {
      final m = itemMacros(_rice, MacroRange.zero);
      expect(m, MacroTotals.zero);
    });

    test('a zero-nutrient food gives zero macros for any grams', () {
      final m = itemMacros(
          const Per100g(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
          MacroRange(10, 20, 30));
      expect(m, MacroTotals.zero);
    });

    test('low <= mid <= high holds for every macro', () {
      final m = itemMacros(_rice, MacroRange(33, 77, 191));
      for (final r in [m.kcal, m.proteinG, m.carbsG, m.fatG]) {
        expect(r.low <= r.mid && r.mid <= r.high, isTrue);
      }
    });

    test('unsorted/negative grams are sanitised before scaling', () {
      final m = itemMacros(_rice, MacroRange(150, -10, 80));
      // sanitised to (0, 80, 150)
      _expectRange(m.kcal, 0, 160, 300);
    });

    test('itemTotals uses the item grams and per100g', () {
      final it = _item('gen:1', _rice, MacroRange(80, 100, 150));
      expect(itemTotals(it), itemMacros(_rice, MacroRange(80, 100, 150)));
    });
  });

  group('entryTotalsOf (RSS)', () {
    test('two items: mids add, spreads combine by root-sum-square', () {
      final a = _item('a', const Per100g(kcal: 100, proteinG: 0, carbsG: 0, fatG: 0),
          MacroRange(50, 100, 150)); // 50/100/150 kcal
      final b = _item('b', const Per100g(kcal: 50, proteinG: 0, carbsG: 0, fatG: 0),
          MacroRange(100, 200, 300)); // 50/100/150 kcal
      final t = entryTotalsOf([a, b]);
      _expectRange(t.kcal, 200 - 50 * math.sqrt2, 200, 200 + 50 * math.sqrt2);
      expect(t.kcal.low, closeTo(129.2893, 1e-3));
      expect(t.kcal.high, closeTo(270.7107, 1e-3));
    });

    test('an exact item adds to mid and adds no spread', () {
      final a = _item('a', _rice, MacroRange(80, 100, 150));
      final b = _item('b', _rice, MacroRange.exact(100));
      final t = entryTotalsOf([a, b]);
      // a: 160/200/300 kcal; b: 200 exactly
      _expectRange(t.kcal, 400 - 40, 400, 400 + 100);
    });

    test('no items give zero totals', () {
      expect(entryTotalsOf(const []), MacroTotals.zero);
    });
  });

  group('buildEntry', () {
    test('derives totals from items and keeps the supplied fields', () {
      final e = _entry([_item('a', _rice, MacroRange.exact(200))]);
      expect(e.totals.kcal, MacroRange.exact(400));
      expect(e.id, 'e1');
      expect(e.slot, MealSlot.dinner);
      expect(e.model!.id, 'gemini');
      expect(e.degraded, isFalse);
    });

    test('stored totals are never trusted: toJson carries recomputed ones', () {
      final e = _entry([_item('a', _rice, MacroRange.exact(50))]);
      expect(e.toJson()['totals']['kcal'],
          {'low': 100.0, 'mid': 100.0, 'high': 100.0});
    });
  });

  group('editItemGrams', () {
    final a = _item('a', _rice, MacroRange(80, 100, 150));
    final b = _item('b', const Per100g(kcal: 100, proteinG: 0, carbsG: 0, fatG: 0),
        MacroRange(50, 100, 150));
    final base = _entry([a, b]);

    test('edited item becomes exact grams; other item is untouched', () {
      final e = editItemGrams(base, 0, 120);
      expect(e.items[0].grams, MacroRange.exact(120));
      expect(identical(e.items[1], b), isTrue,
          reason: 'untouched item is the same object');
      expect(e.items[1].grams, MacroRange(50, 100, 150));
      expect(e.items[0].per100g, _rice);
      expect(e.items[0].foodRef, 'a');
    });

    test('totals are re-derived: edited item exact, the other keeps spread',
        () {
      final e = editItemGrams(base, 0, 120);
      // a: 240 kcal exact; b: 50/100/150
      _expectRange(e.totals.kcal, 290, 340, 390);
    });

    test('editing the only spread item to exact collapses the total range',
        () {
      final e = editItemGrams(_entry([b]), 0, 80);
      expect(e.totals.kcal, MacroRange.exact(80));
    });

    test('editing to the same grams as before the range gives exact mid', () {
      final e = editItemGrams(base, 0, 100);
      expect(e.items[0].grams, MacroRange.exact(100));
      _expectRange(e.totals.kcal, 250, 300, 350);
    });

    test('zero grams, negative, NaN and infinity all become 0 g', () {
      for (final g in [0.0, -5.0, double.nan, double.infinity]) {
        final e = editItemGrams(base, 0, g);
        expect(e.items[0].grams, MacroRange.zero, reason: '$g');
        expect(itemTotals(e.items[0]), MacroTotals.zero, reason: '$g');
      }
    });

    test('out-of-range index throws RangeError', () {
      expect(() => editItemGrams(base, -1, 10), throwsRangeError);
      expect(() => editItemGrams(base, 2, 10), throwsRangeError);
      expect(() => editItemGrams(_entry(const []), 0, 10), throwsRangeError);
    });

    test('original entry is not mutated; entry fields are preserved', () {
      final e = editItemGrams(base, 1, 40);
      expect(base.items[1].grams, MacroRange(50, 100, 150));
      expect(e.id, base.id);
      expect(e.day, base.day);
      expect(e.slot, base.slot);
      expect(e.name, base.name);
      expect(e.model!.version, '2');
      expect(e.items.length, 2);
    });
  });

  group('withItems', () {
    test('swaps items in and recomputes totals', () {
      final e = withItems(_entry([_item('a', _rice, MacroRange.exact(100))]),
          [_item('b', _rice, MacroRange.exact(300))]);
      expect(e.items.single.foodRef, 'b');
      expect(e.totals.kcal, MacroRange.exact(600));
    });
  });

  group('quickLogEntry', () {
    FoodEntry q({
      double kcal = 350,
      double p = 20,
      double c = 40,
      double f = 10,
    }) =>
        quickLogEntry(
          id: 'q1',
          day: '2026-10-15',
          slot: MealSlot.snack,
          loggedAt: DateTime.utc(2026, 10, 15, 15),
          name: 'Bar',
          kcal: kcal,
          proteinG: p,
          carbsG: c,
          fatG: f,
        );

    test('one user:quick item of exactly 100 g', () {
      final e = q();
      expect(e.items.length, 1);
      expect(e.items.single.foodRef, 'user:quick');
      expect(e.items.single.grams, MacroRange.exact(100));
      expect(quickLogGrams, 100);
      expect(e.items.single.source, FoodSource.user);
      expect(e.items.single.matchQuality, MatchQuality.exact);
    });

    test('totals equal the typed values exactly', () {
      final e = q();
      expect(e.totals.kcal, MacroRange.exact(350));
      expect(e.totals.proteinG, MacroRange.exact(20));
      expect(e.totals.carbsG, MacroRange.exact(40));
      expect(e.totals.fatG, MacroRange.exact(10));
    });

    test('entry is manual, high confidence, no model, no check chips', () {
      final e = q();
      expect(e.source, EntrySource.manual);
      expect(e.confidence, EntryConfidence.high);
      final j = e.toJson();
      expect(j.containsKey('model'), isFalse);
      expect(j.containsKey('checkThese'), isFalse);
      expect(j['source'], 'manual');
      expect((j['items'] as List).length, 1);
      expect((j['items'] as List).single['sourceId'], 'user');
    });

    test('macros default to 0 when only calories are typed', () {
      final e = quickLogEntry(
        id: 'q2',
        day: '2026-10-15',
        slot: MealSlot.lunch,
        loggedAt: DateTime.utc(2026, 10, 15, 12),
        name: 'Something',
        kcal: 500,
      );
      expect(e.totals.kcal, MacroRange.exact(500));
      expect(e.totals.proteinG, MacroRange.zero);
      expect(e.totals.carbsG, MacroRange.zero);
      expect(e.totals.fatG, MacroRange.zero);
    });

    test('negative, NaN and infinite inputs become 0', () {
      final e = q(kcal: -10, p: double.nan, c: double.infinity, f: -1);
      expect(e.totals, MacroTotals.zero);
    });

    test('fractional values are kept (123.4 kcal -> 123.4)', () {
      expect(q(kcal: 123.4).totals.kcal.mid, closeTo(123.4, 1e-12));
    });
  });

  group('isAtwaterConsistent (max(25 %, 10 kcal))', () {
    // 4 kcal per g of carbs makes the Atwater figure easy to control.
    Per100g carbs(double kcal, double carbsG) =>
        Per100g(kcal: kcal, proteinG: 0, carbsG: carbsG, fatG: 0);

    test('V-ATWATER: kcal 100, Atwater 125 accepted, 126 flagged', () {
      expect(isAtwaterConsistent(carbs(100, 31.25)), isTrue); // 125
      expect(isAtwaterConsistent(carbs(100, 31.5)), isFalse); // 126
    });

    test('V-ATWATER: kcal 100, Atwater 75 accepted, 74 flagged', () {
      expect(isAtwaterConsistent(carbs(100, 18.75)), isTrue); // 75
      expect(isAtwaterConsistent(carbs(100, 18.5)), isFalse); // 74
    });

    test('a real label (Nutella V-OFF row) within tolerance is consistent', () {
      expect(
          isAtwaterConsistent(
              const Per100g(kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9)),
          isTrue,
          reason: 'Nutella V-OFF row: 25.2+230+278.1 = 533.3');
    });

    test('the 10 kcal floor applies when 25 % is smaller', () {
      // kcal 20 -> 25 % = 5, floor 10 wins: Atwater 30 (diff 10) ok, 30.4 not
      expect(isAtwaterConsistent(carbs(20, 7.5)), isTrue); // 30
      expect(isAtwaterConsistent(carbs(20, 7.6)), isFalse); // 30.4
      // below: Atwater 10 (diff 10) ok, 9.6 (diff 10.4) not
      expect(isAtwaterConsistent(carbs(20, 2.5)), isTrue); // 10
      expect(isAtwaterConsistent(carbs(20, 2.4)), isFalse); // 9.6
    });

    test('at kcal 40 the 25 % and the floor meet at exactly 10', () {
      expect(isAtwaterConsistent(carbs(40, 12.5)), isTrue); // 50
      expect(isAtwaterConsistent(carbs(40, 12.6)), isFalse); // 50.4
    });

    test('above 40 kcal the percentage governs (kcal 400 -> tolerance 100)',
        () {
      expect(isAtwaterConsistent(carbs(400, 125)), isTrue); // 500
      expect(isAtwaterConsistent(carbs(400, 125.5)), isFalse); // 502
      expect(isAtwaterConsistent(carbs(400, 75)), isTrue); // 300
      expect(isAtwaterConsistent(carbs(400, 74.5)), isFalse); // 298
    });

    test('zero kcal: Atwater up to 10 passes, 10.4 fails', () {
      expect(isAtwaterConsistent(carbs(0, 0)), isTrue);
      expect(isAtwaterConsistent(carbs(0, 2.5)), isTrue); // 10
      expect(isAtwaterConsistent(carbs(0, 2.6)), isFalse); // 10.4
    });

    test('protein 4 and fat 9 weights are used', () {
      // 25 g P + 10 g C + 10 g F = 100 + 40 + 90 = 230
      expect(
          isAtwaterConsistent(
              const Per100g(kcal: 230, proteinG: 25, carbsG: 10, fatG: 10)),
          isTrue);
      // fat weighs 9: 10 g fat = 90 kcal ok; 4 per g would be 40
      expect(
          isAtwaterConsistent(
              const Per100g(kcal: 90, proteinG: 0, carbsG: 0, fatG: 10)),
          isTrue);
      expect(
          isAtwaterConsistent(
              const Per100g(kcal: 40, proteinG: 0, carbsG: 0, fatG: 10)),
          isFalse,
          reason: '90 vs 40 differs by 50 > 10');
    });

    test('pure oil row (884 kcal, 100 g fat) is consistent', () {
      expect(isAtwaterConsistent(_oil), isTrue);
    });
  });

  group('applyHiddenOil', () {
    final rice = _item('gen:rice', _rice, MacroRange(80, 100, 150));
    List<CheckItem> chips() => CheckThese.fromCodes(
        [CheckCode.hiddenIngredients, CheckCode.portionUnclear]);

    FoodEntry base() => _entry([rice], checks: chips());

    FoodEntry? apply(FoodEntry e, OilChoice c,
            {FoodSource src = FoodSource.usda}) =>
        applyHiddenOil(e, c,
            oilFoodRef: 'gen:oil',
            oilName: 'Olive oil',
            oilPer100g: _oil,
            oilSource: src);

    test('teaspoon adds exactly 5 g x oil kcal / 100 to the kcal mid', () {
      final b = base();
      final e = apply(b, OilChoice.teaspoon)!;
      final expectedKcal = 5 * _oil.kcal / 100; // 44.2
      expect(e.items.length, 2);
      expect(e.items.last.foodRef, 'gen:oil');
      expect(e.items.last.name, 'Olive oil');
      expect(e.items.last.grams, MacroRange.exact(5));
      expect(e.totals.kcal.mid, closeTo(b.totals.kcal.mid + expectedKcal, 1e-9));
      expect(e.totals.fatG.mid, closeTo(b.totals.fatG.mid + 5, 1e-9));
      // an exact oil portion adds no spread: low/high shift by the same amount
      expect(e.totals.kcal.low, closeTo(b.totals.kcal.low + expectedKcal, 1e-9));
      expect(
          e.totals.kcal.high, closeTo(b.totals.kcal.high + expectedKcal, 1e-9));
    });

    test('tablespoon adds exactly 14 g x oil kcal / 100', () {
      final b = base();
      final e = apply(b, OilChoice.tablespoon)!;
      final expectedKcal = 14 * _oil.kcal / 100; // 123.76
      expect(e.items.last.grams, MacroRange.exact(14));
      expect(e.totals.kcal.mid, closeTo(b.totals.kcal.mid + expectedKcal, 1e-9));
      expect(e.totals.fatG.mid, closeTo(b.totals.fatG.mid + 14, 1e-9));
    });

    test('none adds nothing, totals unchanged, chip still resolved', () {
      final b = base();
      final e = apply(b, OilChoice.none)!;
      expect(e.items.length, 1);
      expect(e.totals, b.totals);
      expect(e.checkThese[0].code, CheckCode.hiddenIngredients);
      expect(e.checkThese[0].resolved, isTrue);
    });

    test('marks hiddenIngredients resolved and leaves other chips alone', () {
      final e = apply(base(), OilChoice.teaspoon)!;
      expect(e.checkThese.length, 2);
      expect(e.checkThese[0].resolved, isTrue);
      expect(e.checkThese[1].code, CheckCode.portionUnclear);
      expect(e.checkThese[1].resolved, isFalse);
    });

    test('a later choice replaces the earlier one instead of stacking', () {
      final b = base();
      final tsp = apply(b, OilChoice.teaspoon)!;
      final tbsp = apply(tsp, OilChoice.tablespoon)!;
      expect(tbsp.items.length, 2);
      expect(tbsp.items.last.grams, MacroRange.exact(14));
      expect(tbsp.totals.kcal.mid,
          closeTo(b.totals.kcal.mid + 14 * _oil.kcal / 100, 1e-9));
      final none = apply(tbsp, OilChoice.none)!;
      expect(none.items.length, 1);
      expect(none.totals, b.totals);
    });

    test('same choice twice is idempotent', () {
      final once = apply(base(), OilChoice.teaspoon)!;
      final twice = apply(once, OilChoice.teaspoon)!;
      expect(twice.items.length, 2);
      expect(twice.totals, once.totals);
    });

    test('a user-edited oil portion (7 g) or a ranged 5 g oil is kept', () {
      final seven = _item('gen:oil', _oil, MacroRange.exact(7));
      final ranged = _item('gen:oil', _oil, MacroRange(3, 5, 8));
      final e = apply(_entry([rice, seven, ranged]), OilChoice.teaspoon)!;
      expect(e.items.length, 4);
      expect(e.items.where((i) => i.grams == MacroRange.exact(7)).length, 1);
      expect(e.items.where((i) => i.grams == MacroRange(3, 5, 8)).length, 1);
    });

    test('a different food with exactly 5 g is not mistaken for added oil',
        () {
      final salt = _item('gen:salt', _oil, MacroRange.exact(5));
      final e = apply(_entry([rice, salt]), OilChoice.teaspoon)!;
      expect(e.items.length, 3);
    });

    test('30 items: any oil amount is refused (null), none is allowed', () {
      final full = _entry([
        for (var i = 0; i < FoodEntry.maxItems; i++)
          _item('gen:f$i', _rice, MacroRange.exact(10)),
      ], checks: chips());
      expect(apply(full, OilChoice.teaspoon), isNull);
      expect(apply(full, OilChoice.tablespoon), isNull);
      final none = apply(full, OilChoice.none);
      expect(none, isNotNull);
      expect(none!.items.length, 30);
    });

    test('29 items plus oil reaches exactly 30 and validates', () {
      final nearFull = _entry([
        for (var i = 0; i < 29; i++)
          _item('gen:f$i', _rice, MacroRange.exact(10)),
      ], checks: chips());
      final e = apply(nearFull, OilChoice.teaspoon)!;
      expect(e.items.length, 30);
      expect(e.validate(), isEmpty);
    });

    test('30 items where one is the earlier oil: re-choice still works', () {
      final full = _entry([
        for (var i = 0; i < 29; i++)
          _item('gen:f$i', _rice, MacroRange.exact(10)),
        _item('gen:oil', _oil, MacroRange.exact(5)),
      ], checks: chips());
      final e = apply(full, OilChoice.tablespoon);
      expect(e, isNotNull);
      expect(e!.items.length, 30);
      expect(e.items.last.grams, MacroRange.exact(14));
    });

    test('oil source defaults to usda and can be overridden', () {
      expect(apply(base(), OilChoice.teaspoon)!.items.last.source,
          FoodSource.usda);
      expect(
          apply(base(), OilChoice.teaspoon, src: FoodSource.user)!
              .items
              .last
              .source,
          FoodSource.user);
    });

    test('without a hiddenIngredients chip the list is unchanged', () {
      final e = applyHiddenOil(
          _entry([rice],
              checks: CheckThese.fromCodes([CheckCode.portionUnclear])),
          OilChoice.teaspoon,
          oilFoodRef: 'gen:oil',
          oilName: 'Olive oil',
          oilPer100g: _oil)!;
      expect(e.checkThese.length, 1);
      expect(e.checkThese.single.resolved, isFalse);
    });
  });
}
