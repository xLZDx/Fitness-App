// T92 check_these_test (FOOD-20, data part). Expected resolutions are the
// design s17.10 mapping written out by hand.
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('closed code list', () {
    test('there are exactly 11 codes with these names', () {
      expect(CheckCode.values.map((c) => c.name).toList(), [
        'portionUnclear',
        'hiddenIngredients',
        'liquidUnknown',
        'cookingMethod',
        'multipleItems',
        'brandUnknown',
        'foodNotMatched',
        'lowConfidenceItem',
        'labelAmbiguous',
        'dataInconsistent',
        'scaleMissing',
      ]);
    });

    test('each code has its concrete resolution', () {
      const expected = {
        CheckCode.portionUnclear: CheckResolution.adjustPortion,
        CheckCode.hiddenIngredients: CheckResolution.chooseOilAmount,
        CheckCode.liquidUnknown: CheckResolution.chooseLiquid,
        CheckCode.cookingMethod: CheckResolution.chooseCookingMethod,
        CheckCode.multipleItems: CheckResolution.reviewItems,
        CheckCode.brandUnknown: CheckResolution.pickAnotherFood,
        CheckCode.foodNotMatched: CheckResolution.pickAnotherFood,
        CheckCode.lowConfidenceItem: CheckResolution.pickAnotherFood,
        CheckCode.labelAmbiguous: CheckResolution.editLabelNumbers,
        CheckCode.dataInconsistent: CheckResolution.editLabelNumbers,
        CheckCode.scaleMissing: CheckResolution.enterServingWeight,
      };
      expect(expected.length, CheckCode.values.length);
      for (final c in CheckCode.values) {
        expect(c.resolution, expected[c], reason: c.name);
      }
    });

    test('tryParse accepts every code name and nothing else', () {
      for (final c in CheckCode.values) {
        expect(CheckCode.tryParse(c.name), c);
      }
      expect(CheckCode.tryParse('PortionUnclear'), isNull);
      expect(CheckCode.tryParse(' portionUnclear'), isNull);
      expect(CheckCode.tryParse('please call 555-0100'), isNull);
      expect(CheckCode.tryParse(''), isNull);
      expect(CheckCode.tryParse(null), isNull);
      expect(CheckCode.tryParse(3), isNull);
      expect(CheckCode.tryParse(CheckCode.portionUnclear), isNull);
    });
  });

  test('OilChoice grams are none 0, teaspoon 5, tablespoon 14', () {
    expect(OilChoice.none.grams, 0);
    expect(OilChoice.teaspoon.grams, 5);
    expect(OilChoice.tablespoon.grams, 14);
    expect(OilChoice.values.length, 3);
  });

  group('CheckItem', () {
    test('defaults to unresolved; resolve() flips only the flag', () {
      const a = CheckItem(code: CheckCode.cookingMethod);
      expect(a.resolved, isFalse);
      final b = a.resolve();
      expect(b.resolved, isTrue);
      expect(b.code, CheckCode.cookingMethod);
      expect(a.resolved, isFalse, reason: 'original is immutable');
    });

    test('toJson has exactly code and resolved', () {
      expect(const CheckItem(code: CheckCode.scaleMissing).toJson(),
          {'code': 'scaleMissing', 'resolved': false});
      expect(
          const CheckItem(code: CheckCode.scaleMissing, resolved: true)
              .toJson(),
          {'code': 'scaleMissing', 'resolved': true});
    });

    test('tryFromJson round-trips and is strict about resolved', () {
      final it = CheckItem.tryFromJson({'code': 'liquidUnknown', 'resolved': true});
      expect(it!.code, CheckCode.liquidUnknown);
      expect(it.resolved, isTrue);
      expect(CheckItem.tryFromJson({'code': 'liquidUnknown'})!.resolved, isFalse);
      expect(
          CheckItem.tryFromJson({'code': 'liquidUnknown', 'resolved': 'true'})!
              .resolved,
          isFalse);
      expect(
          CheckItem.tryFromJson({'code': 'liquidUnknown', 'resolved': 1})!
              .resolved,
          isFalse);
    });

    test('tryFromJson returns null for unknown code or non-map', () {
      expect(CheckItem.tryFromJson({'code': 'madeUp'}), isNull);
      expect(CheckItem.tryFromJson({'resolved': true}), isNull);
      expect(CheckItem.tryFromJson('portionUnclear'), isNull);
      expect(CheckItem.tryFromJson(null), isNull);
    });
  });

  group('CheckThese.fromCodes', () {
    test('keeps first-occurrence order and de-duplicates', () {
      final l = CheckThese.fromCodes([
        CheckCode.cookingMethod,
        CheckCode.portionUnclear,
        CheckCode.cookingMethod,
        CheckCode.portionUnclear,
      ]);
      expect(l.map((c) => c.code).toList(),
          [CheckCode.cookingMethod, CheckCode.portionUnclear]);
      expect(l.every((c) => !c.resolved), isTrue);
    });

    test('caps at 8 chips: exactly 8 kept, 9th dropped', () {
      expect(CheckThese.maxChips, 8);
      final l = CheckThese.fromCodes(CheckCode.values);
      expect(l.length, 8);
      expect(l.map((c) => c.code).toList(),
          CheckCode.values.take(8).toList());
      expect(CheckThese.fromCodes(CheckCode.values.take(8)).length, 8);
      expect(CheckThese.fromCodes(CheckCode.values.take(7)).length, 7);
    });

    test('empty input gives an empty list', () {
      expect(CheckThese.fromCodes(const []), isEmpty);
    });

    test('duplicates do not consume cap slots', () {
      final codes = [
        for (final c in CheckCode.values.take(7)) ...[c, c],
        CheckCode.values[7],
        CheckCode.values[8],
      ];
      final l = CheckThese.fromCodes(codes);
      expect(l.map((c) => c.code).toList(),
          CheckCode.values.take(8).toList());
    });
  });

  group('CheckThese.parseList', () {
    test('non-list input gives an empty list', () {
      expect(CheckThese.parseList(null), isEmpty);
      expect(CheckThese.parseList('x'), isEmpty);
      expect(CheckThese.parseList({'code': 'portionUnclear'}), isEmpty);
    });

    test('drops unknown codes and non-map rows, keeps order', () {
      final l = CheckThese.parseList([
        {'code': 'madeUp', 'resolved': true},
        'portionUnclear',
        {'code': 'cookingMethod'},
        null,
        {'code': 'liquidUnknown', 'resolved': true},
      ]);
      expect(l.map((c) => c.code).toList(),
          [CheckCode.cookingMethod, CheckCode.liquidUnknown]);
      expect(l.map((c) => c.resolved).toList(), [false, true]);
    });

    test('duplicate collapses to one chip and resolved wins', () {
      final a = CheckThese.parseList([
        {'code': 'cookingMethod', 'resolved': false},
        {'code': 'cookingMethod', 'resolved': true},
      ]);
      expect(a.length, 1);
      expect(a.single.resolved, isTrue);
      final b = CheckThese.parseList([
        {'code': 'cookingMethod', 'resolved': true},
        {'code': 'cookingMethod', 'resolved': false},
      ]);
      expect(b.single.resolved, isTrue);
    });

    test('caps at 8 distinct codes after dropping unknown ones', () {
      final rows = <Object?>[
        {'code': 'madeUp'},
        for (final c in CheckCode.values) {'code': c.name},
      ];
      final l = CheckThese.parseList(rows);
      expect(l.length, 8);
      expect(l.map((c) => c.code).toList(),
          CheckCode.values.take(8).toList());
    });
  });

  group('markResolved / unresolved', () {
    final base = CheckThese.fromCodes([
      CheckCode.hiddenIngredients,
      CheckCode.portionUnclear,
    ]);

    test('marks only the target code', () {
      final r = CheckThese.markResolved(base, CheckCode.hiddenIngredients);
      expect(r[0].code, CheckCode.hiddenIngredients);
      expect(r[0].resolved, isTrue);
      expect(r[1].code, CheckCode.portionUnclear);
      expect(r[1].resolved, isFalse);
      expect(base[0].resolved, isFalse, reason: 'input list not mutated');
    });

    test('an absent code leaves the list unchanged', () {
      final r = CheckThese.markResolved(base, CheckCode.scaleMissing);
      expect(r.map((c) => c.resolved).toList(), [false, false]);
      expect(r.length, 2);
    });

    test('empty list stays empty', () {
      expect(CheckThese.markResolved(const [], CheckCode.scaleMissing),
          isEmpty);
    });

    test('unresolved lists only chips still open', () {
      final r = CheckThese.markResolved(base, CheckCode.hiddenIngredients);
      expect(CheckThese.unresolved(r).map((c) => c.code).toList(),
          [CheckCode.portionUnclear]);
      expect(CheckThese.unresolved(
              CheckThese.markResolved(r, CheckCode.portionUnclear)),
          isEmpty);
      expect(CheckThese.unresolved(base).length, 2);
    });
  });
}
