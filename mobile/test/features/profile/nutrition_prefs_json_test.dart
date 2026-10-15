import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';

/// E1 - NutritionPrefs serialisation (design s16.2, ONB-16, D-55).
void main() {
  group('toJson', () {
    test('an empty instance is exactly {schema: 1}', () {
      expect(NutritionPrefs.empty.toJson(), {'schema': 1});
      expect(NutritionPrefs.empty.isEmpty, isTrue);
    });

    test('only the fields the user set are written, by enum name', () {
      final j = NutritionPrefs(
        sexAtBirth: SexAtBirth.female,
        goalDirection: GoalDirection.lose,
        targetBodyFatPct: 18.5,
        typicalDailySteps: 7500,
        mealsPerDay: 4,
        excludedFoods: const ['oats'],
        planOwnership: PlanOwnership.shared,
        healthConnectChoice: HealthConnectChoice.declined,
        completedAt: DateTime.utc(2026, 10, 15, 8, 30),
      ).toJson();
      expect(j, {
        'schema': 1,
        'sexAtBirth': 'female',
        'goalDirection': 'lose',
        'targetBodyFatPct': 18.5,
        'typicalDailySteps': 7500,
        'mealsPerDay': 4,
        'excludedFoods': ['oats'],
        'planOwnership': 'shared',
        'healthConnectChoice': 'declined',
        'completedAt': '2026-10-15T08:30:00.000Z',
      });
    });

    test('an empty excludedFoods list is omitted, a single field leaves the rest absent', () {
      final j = const NutritionPrefs(mealsPerDay: 3).toJson();
      expect(j, {'schema': 1, 'mealsPerDay': 3});
    });
  });

  group('fromJson is tolerant', () {
    test('null, a list, a string and an empty map all read as empty', () {
      expect(NutritionPrefs.fromJson(null), NutritionPrefs.empty);
      expect(NutritionPrefs.fromJson(<dynamic>[]), NutritionPrefs.empty);
      expect(NutritionPrefs.fromJson('x'), NutritionPrefs.empty);
      expect(NutritionPrefs.fromJson(<String, dynamic>{}), NutritionPrefs.empty);
    });

    test('unknown enum names and wrongly typed values degrade to null', () {
      final p = NutritionPrefs.fromJson({
        'sexAtBirth': 'robot',
        'goalDirection': 7,
        'targetBodyFatPct': 'lots',
        'typicalDailySteps': '9000',
        'mealsPerDay': 'three',
        'planOwnership': null,
        'healthConnectChoice': 'maybe',
        'completedAt': 12345,
      });
      expect(p, NutritionPrefs.empty);
    });

    test('mealsPerDay outside 2..6 is read as not answered; the bounds are kept', () {
      expect(NutritionPrefs.fromJson({'mealsPerDay': 1}).mealsPerDay, isNull);
      expect(NutritionPrefs.fromJson({'mealsPerDay': 2}).mealsPerDay, 2);
      expect(NutritionPrefs.fromJson({'mealsPerDay': 6}).mealsPerDay, 6);
      expect(NutritionPrefs.fromJson({'mealsPerDay': 7}).mealsPerDay, isNull);
      expect(NutritionPrefs.fromJson({'mealsPerDay': 0}).mealsPerDay, isNull);
      expect(NutritionPrefs.fromJson({'mealsPerDay': 3.0}).mealsPerDay, 3);
    });

    test('numbers are coerced: int body-fat becomes double, double steps truncate', () {
      final p = NutritionPrefs.fromJson({
        'targetBodyFatPct': 20,
        'typicalDailySteps': 6500.9,
      });
      expect(p.targetBodyFatPct, 20.0);
      expect(p.typicalDailySteps, 6500);
    });

    test('completedAt parses ISO text and an unparsable string is null', () {
      expect(
          NutritionPrefs.fromJson({'completedAt': '2026-10-15T08:30:00.000Z'})
              .completedAt,
          DateTime.utc(2026, 10, 15, 8, 30));
      expect(NutritionPrefs.fromJson({'completedAt': 'not a date'}).completedAt,
          isNull);
    });

    test('excludedFoods: non-strings and blanks dropped, trimmed, 40 chars, at most 20', () {
      final long = 'a' * 60;
      final p = NutritionPrefs.fromJson({
        'excludedFoods': [
          '  peanut butter  ',
          '',
          '   ',
          5,
          null,
          long,
          for (var i = 0; i < 30; i++) 'f$i',
        ],
      });
      expect(p.excludedFoods.first, 'peanut butter');
      expect(p.excludedFoods[1], 'a' * 40);
      expect(p.excludedFoods.length, 20);
      expect(p.excludedFoods[2], 'f0');
      expect(p.excludedFoods.last, 'f17');
    });

    test('excludedFoods that is not a list reads as empty', () {
      expect(NutritionPrefs.fromJson({'excludedFoods': 'peanuts'}).excludedFoods,
          isEmpty);
    });

    test('the parsed excludedFoods list is unmodifiable', () {
      final p = NutritionPrefs.fromJson({'excludedFoods': ['a']});
      expect(() => p.excludedFoods.add('b'), throwsUnsupportedError);
    });
  });

  group('round trip, equality and copyWith', () {
    final full = NutritionPrefs(
      sexAtBirth: SexAtBirth.male,
      goalDirection: GoalDirection.gain,
      targetBodyFatPct: 15,
      typicalDailySteps: 12000,
      mealsPerDay: 5,
      excludedFoods: const ['a', 'b'],
      planOwnership: PlanOwnership.manual,
      healthConnectChoice: HealthConnectChoice.connected,
      completedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    test('fromJson(toJson(x)) == x for every enum value', () {
      expect(NutritionPrefs.fromJson(full.toJson()), full);
      for (final s in SexAtBirth.values) {
        final p = NutritionPrefs(sexAtBirth: s);
        expect(NutritionPrefs.fromJson(p.toJson()), p);
      }
      for (final g in GoalDirection.values) {
        final p = NutritionPrefs(goalDirection: g);
        expect(NutritionPrefs.fromJson(p.toJson()), p);
      }
      for (final o in PlanOwnership.values) {
        final p = NutritionPrefs(planOwnership: o);
        expect(NutritionPrefs.fromJson(p.toJson()), p);
      }
      for (final h in HealthConnectChoice.values) {
        final p = NutritionPrefs(healthConnectChoice: h);
        expect(NutritionPrefs.fromJson(p.toJson()), p);
      }
    });

    test('every single field breaks equality and hashCode agrees when equal', () {
      expect(full, NutritionPrefs.fromJson(full.toJson()));
      expect(full.hashCode, NutritionPrefs.fromJson(full.toJson()).hashCode);
      expect(full, isNot(full.copyWith(sexAtBirth: SexAtBirth.female)));
      expect(full, isNot(full.copyWith(goalDirection: GoalDirection.lose)));
      expect(full, isNot(full.copyWith(targetBodyFatPct: 16)));
      expect(full, isNot(full.copyWith(typicalDailySteps: 1)));
      expect(full, isNot(full.copyWith(mealsPerDay: 2)));
      expect(full, isNot(full.copyWith(excludedFoods: const ['a'])));
      expect(full, isNot(full.copyWith(planOwnership: PlanOwnership.coached)));
      expect(full,
          isNot(full.copyWith(healthConnectChoice: HealthConnectChoice.manual)));
      expect(full, isNot(full.copyWith(completedAt: DateTime.utc(2027))));
    });

    test('isEmpty is false when any single field is set', () {
      expect(const NutritionPrefs(sexAtBirth: SexAtBirth.male).isEmpty, isFalse);
      expect(const NutritionPrefs(goalDirection: GoalDirection.lose).isEmpty,
          isFalse);
      expect(const NutritionPrefs(targetBodyFatPct: 10).isEmpty, isFalse);
      expect(const NutritionPrefs(typicalDailySteps: 0).isEmpty, isFalse);
      expect(const NutritionPrefs(mealsPerDay: 3).isEmpty, isFalse);
      expect(const NutritionPrefs(excludedFoods: ['x']).isEmpty, isFalse);
      expect(const NutritionPrefs(planOwnership: PlanOwnership.coached).isEmpty,
          isFalse);
      expect(
          const NutritionPrefs(healthConnectChoice: HealthConnectChoice.manual)
              .isEmpty,
          isFalse);
      expect(NutritionPrefs(completedAt: DateTime.utc(2026)).isEmpty, isFalse);
    });

    test('copyWith clearTargetBodyFat is the only way to unset the body-fat target', () {
      expect(full.copyWith(clearTargetBodyFat: true).targetBodyFatPct, isNull);
      expect(full.copyWith().targetBodyFatPct, 15);
    });
  });

  group('UserProfile embeds the nutrition block', () {
    test('a fresh profile serialises the block as the minimal {schema: 1}', () {
      expect(const UserProfile(uid: 'u').toJson()['nutrition'], {'schema': 1});
    });

    test('an answered block is carried verbatim by UserProfile.toJson and copyWith', () {
      final p = const UserProfile(uid: 'u').copyWith(
        nutrition: const NutritionPrefs(
            goalDirection: GoalDirection.lose, mealsPerDay: 4),
      );
      expect(p.toJson()['nutrition'],
          {'schema': 1, 'goalDirection': 'lose', 'mealsPerDay': 4});
      expect(p.nutrition.goalDirection, GoalDirection.lose);
    });
  });

  group('DietaryPreference.pescatarian (item 3)', () {
    test('exists, is stored by name, and sits before none', () {
      expect(DietaryPreference.values.map((d) => d.name),
          containsAll(['vegetarian', 'vegan', 'pescatarian', 'none']));
      expect(DietaryPreference.pescatarian.index,
          lessThan(DietaryPreference.none.index));
    });
  });
}
