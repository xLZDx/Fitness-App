// C24 label_draft_test (FOOD-15 client half, FOOD-16): parseLabelDraft is the
// validator of the confirmation sheet (name, 0..1000 values, decimal comma,
// optional positive serving); the per-serving to per-100 g path used by the
// label page is LabelScale with hand-computed numbers; a Russian label reading
// (Cyrillic units already normalised by the server) parses and scales.
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/label_scale.dart';
import 'package:fitness_app/features/food_diary/label_scan_page.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter_test/flutter_test.dart';

LabelDraft? _draft({
  String name = 'Oat bar',
  String kcal = '400',
  String protein = '10',
  String carbs = '60',
  String fat = '12',
  String serving = '',
}) =>
    parseLabelDraft(
        name: name,
        kcal: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        serving: serving);

void main() {
  group('parseLabelDraft accepts', () {
    test('plain values', () {
      final d = _draft()!;
      expect(d.name, 'Oat bar');
      expect(d.per100g.kcal, 400);
      expect(d.per100g.proteinG, 10);
      expect(d.per100g.carbsG, 60);
      expect(d.per100g.fatG, 12);
      expect(d.servingG, isNull);
    });

    test('decimal comma and surrounding spaces', () {
      final d = _draft(
          name: '  Bar  ',
          kcal: ' 412,5 ',
          protein: '12,5',
          carbs: '0,5',
          fat: '3,25',
          serving: ' 40,5 ')!;
      expect(d.name, 'Bar');
      expect(d.per100g.kcal, 412.5);
      expect(d.per100g.proteinG, 12.5);
      expect(d.per100g.carbsG, 0.5);
      expect(d.per100g.fatG, 3.25);
      expect(d.servingG, 40.5);
    });

    test('a Cyrillic product name', () {
      final d = _draft(name: 'Гречневая каша', kcal: '343')!;
      expect(d.name, 'Гречневая каша');
    });

    test('the bounds 0 and 1000 are inclusive', () {
      final lo = _draft(kcal: '0', protein: '0', carbs: '0', fat: '0')!;
      expect(lo.per100g.kcal, 0);
      final hi = _draft(kcal: '1000', protein: '1000', carbs: '1000', fat: '1000')!;
      expect(hi.per100g.fatG, 1000);
    });

    test('name of 80 characters is the longest', () {
      expect(_draft(name: 'n' * 80), isNotNull);
    });

    test('a serving up to 100000 g', () {
      expect(_draft(serving: '100000')!.servingG, 100000);
    });
  });

  group('parseLabelDraft refuses (null)', () {
    final cases = <String, LabelDraft? Function()>{
      'empty name': () => _draft(name: ''),
      'blank name': () => _draft(name: '   '),
      'name of 81 characters': () => _draft(name: 'n' * 81),
      'empty kcal': () => _draft(kcal: ''),
      'empty protein': () => _draft(protein: ''),
      'empty carbs': () => _draft(carbs: ' '),
      'empty fat': () => _draft(fat: ''),
      'non-numeric kcal': () => _draft(kcal: 'abc'),
      'unit typed in the field': () => _draft(kcal: '400 kcal'),
      'negative kcal': () => _draft(kcal: '-1'),
      'negative fat': () => _draft(fat: '-0,1'),
      'kcal 1000.1': () => _draft(kcal: '1000.1'),
      'protein 1001': () => _draft(protein: '1001'),
      'NaN': () => _draft(kcal: 'NaN'),
      'Infinity': () => _draft(carbs: 'Infinity'),
      'serving zero': () => _draft(serving: '0'),
      'serving negative': () => _draft(serving: '-5'),
      'serving text': () => _draft(serving: 'one'),
      'serving over 100000': () => _draft(serving: '100001'),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(e.value(), isNull));
    }
  });

  group('per-serving label scaled to per 100 g (hand-computed)', () {
    const perServing = Per100g(kcal: 200, proteinG: 5, carbsG: 30, fatG: 6);

    test('40 g serving -> x2.5', () {
      final r = LabelScale.toPer100g(perServing, 40);
      expect(r.isOk, isTrue);
      expect(r.values!.kcal, closeTo(500, 1e-9));
      expect(r.values!.proteinG, closeTo(12.5, 1e-9));
      expect(r.values!.carbsG, closeTo(75, 1e-9));
      expect(r.values!.fatG, closeTo(15, 1e-9));
    });

    test('the scaled values pass the confirmation validator', () {
      final v = LabelScale.toPer100g(perServing, 40).values!;
      final d = _draft(
          kcal: v.kcal.toString(),
          protein: v.proteinG.toString(),
          carbs: v.carbsG.toString(),
          fat: v.fatG.toString(),
          serving: '40');
      expect(d, isNotNull);
      expect(d!.servingG, 40);
    });

    test('a missing, zero or negative serving never divides', () {
      for (final s in [null, 0.0, -10.0, double.nan, double.infinity]) {
        final r = LabelScale.toPer100g(perServing, s);
        expect(r.isOk, isFalse, reason: 'serving $s');
        expect(r.values, isNull);
        expect(r.issue, CheckCode.scaleMissing);
      }
    });
  });

  group('Russian label reading', () {
    test('per-serving JSON with a serving weight parses and scales', () {
      // The server already mapped "ккал", "белки", "жиры", "углеводы".
      final reading = parseLabelReading({
        'perServing': {'kcal': 171.5, 'proteinG': 5.4, 'carbsG': 30, 'fatG': 2.5},
        'servingG': 50,
        'checkCodes': ['labelAmbiguous'],
      });
      expect(reading.per100g, isNull);
      expect(reading.servingG, 50);
      expect(reading.checkCodes, contains(CheckCode.labelAmbiguous));
      final r = LabelScale.toPer100g(reading.perServing!, reading.servingG);
      expect(r.values!.kcal, closeTo(343, 1e-9));
      expect(r.values!.proteinG, closeTo(10.8, 1e-9));
      expect(r.values!.carbsG, closeTo(60, 1e-9));
      expect(r.values!.fatG, closeTo(5, 1e-9));
    });

    test('nothing readable gives no values at all', () {
      final reading = parseLabelReading({'checkCodes': ['scaleMissing']});
      expect(reading.per100g, isNull);
      expect(reading.perServing, isNull);
    });

    test('negative or non-finite numbers are dropped, not trusted', () {
      final reading = parseLabelReading({
        'per100g': {'kcal': -5, 'proteinG': 1, 'carbsG': 1, 'fatG': 1},
      });
      expect(reading.per100g, isNull);
    });
  });
}
