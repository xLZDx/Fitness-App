// T94 label_scale_test (FOOD-16). Expected numbers are worked by hand.
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/label_scale.dart';
import 'package:flutter_test/flutter_test.dart';

const _perServing = Per100g(kcal: 150, proteinG: 6, carbsG: 18, fatG: 6);

void expectPer(Per100g actual, Per100g expected) {
  expect(actual.kcal, closeTo(expected.kcal, 1e-9));
  expect(actual.proteinG, closeTo(expected.proteinG, 1e-9));
  expect(actual.carbsG, closeTo(expected.carbsG, 1e-9));
  expect(actual.fatG, closeTo(expected.fatG, 1e-9));
}

void main() {
  group('toPer100g', () {
    test('30 g serving: x100/30', () {
      final r = LabelScale.toPer100g(_perServing, 30);
      expect(r.isOk, isTrue);
      expect(r.issue, isNull);
      expectPer(r.values!,
          const Per100g(kcal: 500, proteinG: 20, carbsG: 60, fatG: 20));
    });

    test('100 g serving is the identity', () {
      final r = LabelScale.toPer100g(_perServing, 100);
      expect(r.values, _perServing);
    });

    test('250 g serving scales down (x0.4)', () {
      final r = LabelScale.toPer100g(_perServing, 250);
      expectPer(r.values!,
          const Per100g(kcal: 60, proteinG: 2.4, carbsG: 7.2, fatG: 2.4));
    });

    test('tiny serving (0.5 g) scales up x200', () {
      final r = LabelScale.toPer100g(
          const Per100g(kcal: 1, proteinG: 0.1, carbsG: 0.2, fatG: 0),
          0.5);
      expectPer(r.values!,
          const Per100g(kcal: 200, proteinG: 20, carbsG: 40, fatG: 0));
    });

    test('all-zero label stays all zero', () {
      final r = LabelScale.toPer100g(
          const Per100g(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0), 33);
      expect(r.isOk, isTrue);
      expect(r.values!.kcal, 0);
    });
  });

  group('toPerServing', () {
    test('per 100 g -> 30 g serving (x0.3)', () {
      final r = LabelScale.toPerServing(
          const Per100g(kcal: 500, proteinG: 20, carbsG: 60, fatG: 20), 30);
      expect(r.isOk, isTrue);
      expectPer(r.values!, _perServing);
    });

    test('250 g serving (x2.5)', () {
      final r = LabelScale.toPerServing(
          const Per100g(kcal: 60, proteinG: 2.4, carbsG: 7.2, fatG: 2.4), 250);
      expectPer(r.values!,
          const Per100g(kcal: 150, proteinG: 6, carbsG: 18, fatG: 6));
    });
  });

  group('exact inverse', () {
    for (final g in <double>[0.5, 1, 7.3, 30, 33.3, 100, 250, 1234.5]) {
      test('per serving -> per 100 g -> per serving at $g g', () {
        final there = LabelScale.toPer100g(_perServing, g);
        final back = LabelScale.toPerServing(there.values!, g);
        expectPer(back.values!, _perServing);
      });
      test('per 100 g -> per serving -> per 100 g at $g g', () {
        const p = Per100g(kcal: 412, proteinG: 11.5, carbsG: 63, fatG: 9.25);
        final there = LabelScale.toPerServing(p, g);
        final back = LabelScale.toPer100g(there.values!, g);
        expectPer(back.values!, p);
      });
    }
  });

  group('unusable serving weight never divides', () {
    final bad = <String, double?>{
      'null': null,
      'zero': 0,
      'negative zero': -0.0,
      'negative': -30,
      'NaN': double.nan,
      'infinity': double.infinity,
      'negative infinity': double.negativeInfinity,
    };
    bad.forEach((label, g) {
      test('toPer100g with $label -> scaleMissing', () {
        final r = LabelScale.toPer100g(_perServing, g);
        expect(r.isOk, isFalse);
        expect(r.values, isNull);
        expect(r.issue, CheckCode.scaleMissing);
      });
      test('toPerServing with $label -> scaleMissing', () {
        final r = LabelScale.toPerServing(_perServing, g);
        expect(r.isOk, isFalse);
        expect(r.values, isNull);
        expect(r.issue, CheckCode.scaleMissing);
      });
    });

    test('smallest positive serving is still usable and finite', () {
      final r = LabelScale.toPer100g(
          const Per100g(kcal: 1, proteinG: 0, carbsG: 0, fatG: 0), 1e-3);
      expect(r.isOk, isTrue);
      expect(r.values!.kcal, closeTo(1e5, 1e-6));
      expect(r.values!.kcal.isFinite, isTrue);
    });

    test('max finite serving does not overflow', () {
      final r = LabelScale.toPer100g(_perServing, 1e300);
      expect(r.isOk, isTrue);
      expect(r.values!.kcal.isFinite, isTrue);
    });
  });

  test('ok result carries no issue, missing result carries no values', () {
    const ok = LabelScaleResult.ok(_perServing);
    const missing = LabelScaleResult.missing();
    expect(ok.isOk, isTrue);
    expect(ok.issue, isNull);
    expect(missing.isOk, isFalse);
    expect(missing.values, isNull);
    expect(missing.issue, CheckCode.scaleMissing);
  });
}
