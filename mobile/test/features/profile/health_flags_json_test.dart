import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/safety/data/health_flags.dart';

/// E1 - HealthFlags nutrition fields: wire shape and tolerant reading
/// (D-70, ONB-05, PRIV-16).
void main() {
  group('toJson omits the two nutrition keys unless answered (D-70)', () {
    test('empty flags carry the five legacy keys, all null/empty, and nothing else', () {
      final j = HealthFlags.empty.toJson();
      expect(j.keys.toSet(), {
        'restrictions',
        'bloodPressure',
        'surgery',
        'clinicianAdvice',
        'professionalGuidance',
      });
      expect(j['restrictions'], isEmpty);
      expect(j['bloodPressure'], isNull);
      expect(j['professionalGuidance'], isNull);
    });

    test('an answered guidance writes its generic name, an empty allergen set writes nothing', () {
      final j = const HealthFlags(
              nutritionGuidance: NutritionGuidanceNeed.reported)
          .toJson();
      expect(j['nutritionGuidance'], 'reported');
      expect(j.containsKey('foodAllergens'), isFalse);
      expect(
          const HealthFlags(nutritionGuidance: NutritionGuidanceNeed.none)
              .toJson()['nutritionGuidance'],
          'none');
    });

    test('allergens are written as a list of enum names', () {
      final j = const HealthFlags(
        foodAllergens: {FoodAllergen.peanuts, FoodAllergen.treeNuts},
      ).toJson();
      expect(j['foodAllergens'], unorderedEquals(['peanuts', 'treeNuts']));
      expect(j.containsKey('nutritionGuidance'), isFalse);
    });
  });

  group('the closed EU-14 allergen list', () {
    test('has exactly the 14 names', () {
      expect(FoodAllergen.values.map((a) => a.name).toSet(), {
        'gluten',
        'crustaceans',
        'eggs',
        'fish',
        'peanuts',
        'soy',
        'milk',
        'treeNuts',
        'celery',
        'mustard',
        'sesame',
        'sulphites',
        'lupin',
        'molluscs',
      });
      expect(FoodAllergen.values, hasLength(14));
    });

    test('NutritionGuidanceNeed has none and reported only (no "prefer not to say")', () {
      expect(NutritionGuidanceNeed.values.map((v) => v.name), ['none', 'reported']);
    });
  });

  group('fromJson is tolerant and fail-closed', () {
    test('a legacy block without the new keys reads as unanswered nutrition', () {
      final f = HealthFlags.fromJson({
        'restrictions': <String>[],
        'bloodPressure': null,
        'surgery': null,
        'clinicianAdvice': null,
        'professionalGuidance': null,
      });
      expect(f.nutritionGuidance, isNull);
      expect(f.foodAllergens, isEmpty);
      expect(f, HealthFlags.empty);
    });

    test('non-map input reads as empty', () {
      expect(HealthFlags.fromJson(null), HealthFlags.empty);
      expect(HealthFlags.fromJson('x'), HealthFlags.empty);
      expect(HealthFlags.fromJson(<dynamic>[]), HealthFlags.empty);
    });

    test('an unknown guidance name is DROPPED to null, never defaulted to none', () {
      expect(
          HealthFlags.fromJson({'nutritionGuidance': 'maybe'}).nutritionGuidance,
          isNull);
      expect(HealthFlags.fromJson({'nutritionGuidance': 3}).nutritionGuidance,
          isNull);
    });

    test('unknown allergen names are dropped, known ones kept, non-list ignored', () {
      final f = HealthFlags.fromJson({
        'foodAllergens': ['peanuts', 'kryptonite', 5, null, 'milk', 'peanuts'],
      });
      expect(f.foodAllergens, {FoodAllergen.peanuts, FoodAllergen.milk});
      expect(HealthFlags.fromJson({'foodAllergens': 'peanuts'}).foodAllergens,
          isEmpty);
    });

    test('parsed allergen set is unmodifiable', () {
      final f = HealthFlags.fromJson({'foodAllergens': ['eggs']});
      expect(() => f.foodAllergens.add(FoodAllergen.soy), throwsUnsupportedError);
    });

    test('toJson/fromJson round trip keeps every answer', () {
      const f = HealthFlags(
        restrictions: {MovementRestriction.overhead},
        bloodPressure: BloodPressureStatus.diagnosedHigh,
        surgery: SurgeryStatus.underRestrictions,
        clinicianAdvice: ClinicianExerciseAdvice.limitsGiven,
        professionalGuidance: ProfessionalGuidanceNeed.reported,
        nutritionGuidance: NutritionGuidanceNeed.reported,
        foodAllergens: {FoodAllergen.gluten, FoodAllergen.sesame},
      );
      expect(HealthFlags.fromJson(f.toJson()), f);
    });
  });

  group('semantics', () {
    test('only the guidance answer makes the questions "answered"; allergens alone do not', () {
      expect(HealthFlags.empty.isUnanswered, isTrue);
      expect(
          const HealthFlags(nutritionGuidance: NutritionGuidanceNeed.none)
              .isUnanswered,
          isFalse);
      expect(const HealthFlags(foodAllergens: {FoodAllergen.eggs}).isUnanswered,
          isTrue);
    });

    test('allergens alone make the flags non-empty', () {
      expect(HealthFlags.empty.isEmpty, isTrue);
      expect(const HealthFlags(foodAllergens: {FoodAllergen.eggs}).isEmpty,
          isFalse);
      expect(
          const HealthFlags(nutritionGuidance: NutritionGuidanceNeed.none)
              .isEmpty,
          isFalse);
    });

    test('copyWith sets and keeps the new fields', () {
      const base = HealthFlags(nutritionGuidance: NutritionGuidanceNeed.none);
      final next = base.copyWith(foodAllergens: {FoodAllergen.fish});
      expect(next.nutritionGuidance, NutritionGuidanceNeed.none);
      expect(next.foodAllergens, {FoodAllergen.fish});
      final flipped =
          next.copyWith(nutritionGuidance: NutritionGuidanceNeed.reported);
      expect(flipped.nutritionGuidance, NutritionGuidanceNeed.reported);
      expect(flipped.foodAllergens, {FoodAllergen.fish});
    });

    test('equality and hashCode ignore allergen insertion order', () {
      const a = HealthFlags(foodAllergens: {FoodAllergen.milk, FoodAllergen.soy});
      const b = HealthFlags(foodAllergens: {FoodAllergen.soy, FoodAllergen.milk});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
