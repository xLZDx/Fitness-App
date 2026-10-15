// T12 energy_math_test (PLAN-01, PLAN-02, PLAN-03, SAFE-08 floor edge cases,
// FOOD unit helpers + Atwater). Every expected number is derived by hand from
// the published formulas (Mifflin-St Jeor 1990; PAL multipliers), never copied
// from the implementation.
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile({
  Gender? gender,
  SexAtBirth? sexAtBirth,
}) =>
    UserProfile(
      uid: 'u',
      personal: PersonalInfo(gender: gender),
      nutrition: NutritionPrefs(sexAtBirth: sexAtBirth),
    );

void main() {
  group('BMR (Mifflin-St Jeor)', () {
    test('V-BMR-M: male 80 kg 180 cm 30 y = 800 + 1125 - 150 + 5 = 1780', () {
      expect(
        bmr(weightKg: 80, heightCm: 180, ageYears: 30, sex: SexBasis.male),
        1780.0,
      );
    });
    test('V-BMR-F: female 60 kg 165 cm 30 y = 600 + 1031.25 - 150 - 161', () {
      expect(
        bmr(weightKg: 60, heightCm: 165, ageYears: 30, sex: SexBasis.female),
        1320.25,
      );
    });
    test('V-BMR-U: unspecified 80/180/30 uses the midpoint constant -78', () {
      expect(
        bmr(
            weightKg: 80,
            heightCm: 180,
            ageYears: 30,
            sex: SexBasis.unspecified),
        1697.0,
      );
    });
    test('V-FLOOR-F inputs: female 50 kg 155 cm 40 y = 1107.75', () {
      expect(
        bmr(weightKg: 50, heightCm: 155, ageYears: 40, sex: SexBasis.female),
        1107.75,
      );
    });
    test('V-FLOOR-M inputs: male 100 kg 190 cm 25 y = 2067.5', () {
      expect(
        bmr(weightKg: 100, heightCm: 190, ageYears: 25, sex: SexBasis.male),
        2067.5,
      );
    });
    test('each extra year lowers BMR by exactly 5; each kg raises it by 10', () {
      final a = bmr(
          weightKg: 70, heightCm: 170, ageYears: 30, sex: SexBasis.male);
      expect(
          bmr(weightKg: 70, heightCm: 170, ageYears: 31, sex: SexBasis.male),
          a - 5);
      expect(
          bmr(weightKg: 71, heightCm: 170, ageYears: 30, sex: SexBasis.male),
          a + 10);
      expect(
          bmr(weightKg: 70, heightCm: 171, ageYears: 30, sex: SexBasis.male),
          a + 6.25);
    });
    test('sex constants differ by exactly 166 (male vs female) and sit midway', () {
      double f(SexBasis s) =>
          bmr(weightKg: 70, heightCm: 170, ageYears: 30, sex: s);
      expect(f(SexBasis.male) - f(SexBasis.female), 166);
      expect(f(SexBasis.unspecified), (f(SexBasis.male) + f(SexBasis.female)) / 2);
      // (5 + -161) / 2 = -78, so the unspecified constant IS the midpoint.
      expect(f(SexBasis.unspecified) - f(SexBasis.female), 83);
    });
  });

  group('sex basis resolution', () {
    test('sexAtBirth wins over gender', () {
      expect(
        resolveSexBasis(
            _profile(gender: Gender.female, sexAtBirth: SexAtBirth.male)),
        SexBasis.male,
      );
      expect(
        resolveSexBasis(
            _profile(gender: Gender.male, sexAtBirth: SexAtBirth.female)),
        SexBasis.female,
      );
      expect(
        resolveSexBasis(
            _profile(gender: Gender.male, sexAtBirth: SexAtBirth.unspecified)),
        SexBasis.unspecified,
      );
    });
    test('falls back to gender male/female', () {
      expect(resolveSexBasis(_profile(gender: Gender.male)), SexBasis.male);
      expect(resolveSexBasis(_profile(gender: Gender.female)), SexBasis.female);
    });
    test('non-binary and prefer-not-to-say fall to unspecified (-78)', () {
      expect(resolveSexBasis(_profile(gender: Gender.nonBinary)),
          SexBasis.unspecified);
      expect(resolveSexBasis(_profile(gender: Gender.preferNotToSay)),
          SexBasis.unspecified);
    });
    test('nothing answered = null (the input is missing, not guessed)', () {
      expect(resolveSexBasis(_profile()), isNull);
    });
  });

  group('BMI', () {
    test('80 kg / 180 cm = 24.691...', () {
      expect(bmiOf(80, 180)!, closeTo(24.6914, 1e-4));
    });
    test('non-positive input is null', () {
      expect(bmiOf(0, 180), isNull);
      expect(bmiOf(80, 0), isNull);
      expect(bmiOf(-1, 180), isNull);
    });
  });

  group('activity factors (PLAN-02)', () {
    test('the four questionnaire levels map to 1.2 / 1.375 / 1.55 / 1.725', () {
      expect(activityFactorFor(ActivityLevel.sedentary), 1.2);
      expect(activityFactorFor(ActivityLevel.moderatelyActive), 1.375);
      expect(activityFactorFor(ActivityLevel.active), 1.55);
      expect(activityFactorFor(ActivityLevel.veryActive), 1.725);
    });
    test('1.9 is never produced by any level or any steps count', () {
      for (final l in ActivityLevel.values) {
        expect(activityFactorFor(l), lessThan(1.9));
      }
      for (final s in [0, 4999, 5000, 7499, 7500, 9999, 10000, 50000]) {
        expect(stepsFactorFor(s), lessThan(1.9));
      }
    });
    test('steps band boundaries are exact', () {
      expect(stepsFactorFor(0), 1.2);
      expect(stepsFactorFor(4999), 1.2);
      expect(stepsFactorFor(5000), 1.375);
      expect(stepsFactorFor(7499), 1.375);
      expect(stepsFactorFor(7500), 1.55);
      expect(stepsFactorFor(9999), 1.55);
      expect(stepsFactorFor(10000), 1.725);
      expect(stepsFactorFor(30000), 1.725);
    });
    test('combined factor is the LOWER of questionnaire and steps', () {
      // questionnaire `active` (1.55) + steps 4000 (1.2) -> 1.2.
      expect(
          combinedActivityFactor(
              level: ActivityLevel.active, typicalSteps: 4000),
          1.2);
      // questionnaire sedentary (1.2) + steps 12000 (1.725) -> 1.2.
      expect(
          combinedActivityFactor(
              level: ActivityLevel.sedentary, typicalSteps: 12000),
          1.2);
      // equal bands stay.
      expect(
          combinedActivityFactor(
              level: ActivityLevel.moderatelyActive, typicalSteps: 6000),
          1.375);
      // steps lower than the questionnaire by one band.
      expect(
          combinedActivityFactor(
              level: ActivityLevel.veryActive, typicalSteps: 8000),
          1.55);
    });
    test('only one source: that one; neither: null', () {
      expect(combinedActivityFactor(level: ActivityLevel.active), 1.55);
      expect(combinedActivityFactor(typicalSteps: 10000), 1.725);
      expect(combinedActivityFactor(), isNull);
    });
  });

  group('TDEE (PLAN-03)', () {
    test('TDEE = BMR * factor exactly (1780 * 1.375 = 2447.5)', () {
      expect(tdee(1780, 1.375), 2447.5);
    });
    test('V-FLOOR-F: 1107.75 * 1.2 = 1329.3', () {
      expect(tdee(1107.75, 1.2), closeTo(1329.3, 1e-9));
    });
    test('the function has no exercise-calorie parameter (D-29)', () {
      // Same BMR and factor, nothing else can enter: a second call is equal.
      expect(tdee(1500, 1.55), tdee(1500, 1.55));
      expect(tdee(1500, 1.55), 2325.0);
    });
  });

  group('calorie floor (SAFE-08)', () {
    test('V-FLOOR-F: female floor is the absolute 1200 (BMR 1107.75 rounds 1108)', () {
      expect(calorieFloor(1107.75, SexBasis.female), 1200);
    });
    test('V-FLOOR-M: relative floor beats the absolute 1500 (2067.5 -> 2068)', () {
      expect(calorieFloor(2067.5, SexBasis.male), 2068);
    });
    test('male BMR 1499 / 1500 / 1501: floor 1500 / 1500 / 1501', () {
      expect(calorieFloor(1499, SexBasis.male), 1500);
      expect(calorieFloor(1500, SexBasis.male), 1500);
      expect(calorieFloor(1501, SexBasis.male), 1501);
    });
    test('rounding of the BMR: 1500.4 -> 1500, 1500.5 -> 1501', () {
      expect(calorieFloor(1500.4, SexBasis.male), 1500);
      expect(calorieFloor(1500.5, SexBasis.male), 1501);
    });
    test('unspecified uses the male absolute 1500', () {
      expect(calorieFloor(1200, SexBasis.unspecified), 1500);
      expect(calorieFloor(1700, SexBasis.unspecified), 1700);
    });
    test('female: BMR 1199 / 1200 / 1201 -> 1200 / 1200 / 1201', () {
      expect(calorieFloor(1199, SexBasis.female), 1200);
      expect(calorieFloor(1200, SexBasis.female), 1200);
      expect(calorieFloor(1201, SexBasis.female), 1201);
    });
  });

  group('rounding helpers', () {
    test('roundToStep rounds half away from zero', () {
      expect(roundToStep(1807.5, 10), 1810);
      expect(roundToStep(2107.5, 10), 2110);
      expect(roundToStep(1804.9, 10), 1800);
      expect(roundToStep(15, 10), 20);
      expect(roundToStep(-15, 10), -20);
      expect(roundToStep(7250, 500), 7500);
      expect(roundToStep(7249.9, 500), 7000);
    });
    test('floorToStep / ceilToStep', () {
      expect(floorToStep(2447.5, 10), 2440);
      expect(floorToStep(2440, 10), 2440);
      expect(ceilToStep(1897.5, 10), 1900);
      expect(ceilToStep(1900, 10), 1900);
      expect(ceilToStep(1900.01, 10), 1910);
    });
  });

  group('unit helpers', () {
    test('V-OFF: the kcal field wins over kJ (539, not 2252 / 4.184 = 538.2)', () {
      expect(resolveKcal(kcal: 539, kj: 2252), 539);
    });
    test('kJ is converted only when kcal is absent', () {
      // 2252 / 4.184 = 538.2409 (scratch division; the map's 538.2 is rounded).
      expect(resolveKcal(kj: 2252)!, closeTo(538.2409, 1e-3));
      expect(resolveKcal(kj: 4.184), closeTo(1.0, 1e-12));
    });
    test('neither -> null', () {
      expect(resolveKcal(), isNull);
    });
    test('kJ <-> kcal factor 4.184 both ways', () {
      expect(kKjPerKcal, 4.184);
      expect(kjFromKcal(100), closeTo(418.4, 1e-9));
      expect(kcalFromKj(418.4), closeTo(100, 1e-9));
    });
    test('salt = sodium x 2.5 and back', () {
      expect(saltGFromSodiumG(1.2), closeTo(3.0, 1e-12));
      expect(sodiumGFromSaltG(3.0), closeTo(1.2, 1e-12));
    });
  });

  group('Atwater consistency (V-ATWATER)', () {
    bool ok(double kcal, {double p = 0, double c = 0, double f = 0}) =>
        isAtwaterConsistent(kcal: kcal, proteinG: p, carbsG: c, fatG: f);

    test('atwaterKcal is 4P + 4C + 9F', () {
      expect(atwaterKcal(proteinG: 10, carbsG: 20, fatG: 5), 40 + 80 + 45);
    });
    test('kcal 100: implied 125 accepted (exactly +25 %), 126 flagged', () {
      expect(ok(100, c: 31.25), isTrue); // 4 * 31.25 = 125
      expect(ok(100, c: 31.5), isFalse); // 126
    });
    test('kcal 100: implied 75 accepted (exactly -25 %), 74 flagged', () {
      expect(ok(100, c: 18.75), isTrue); // 75
      expect(ok(100, c: 18.5), isFalse); // 74
    });
    test('small energies use the 10 kcal floor: kcal 20 tolerates +-10', () {
      expect(ok(20, c: 7.5), isTrue); // 30
      expect(ok(20, c: 7.6), isFalse); // 30.4
      expect(ok(20, c: 2.5), isTrue); // 10
      expect(ok(20, c: 2.4), isFalse); // 9.6
    });
    test('zero energy with zero macros is consistent; macros without energy are not', () {
      expect(ok(0), isTrue);
      expect(ok(0, f: 2), isFalse); // 18 kcal implied against a 10 kcal floor
    });
  });
}
