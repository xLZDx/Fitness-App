// T17 missing_inputs_test (ONB-10, PLAN-10 missing list). Each required nutrition
// input is reported individually and in combination, in the order the profile
// flow asks for them; a complete profile reports nothing.
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 15);

const _answered = HealthFlags(
  nutritionGuidance: NutritionGuidanceNeed.none,
  professionalGuidance: ProfessionalGuidanceNeed.none,
);

UserProfile _p({
  HealthFlags flags = _answered,
  int? birthYear = 1985,
  int? storedAge,
  int? heightCm = 180,
  double? weightKg = 80,
  Gender? gender = Gender.male,
  SexAtBirth? sexAtBirth,
  ActivityLevel? activity = ActivityLevel.moderatelyActive,
  FitnessGoals goals = const FitnessGoals(),
  GoalDirection? direction = GoalDirection.maintain,
}) =>
    UserProfile(
      uid: 'u',
      personal: PersonalInfo(
        age: storedAge,
        birthYear: birthYear,
        gender: gender,
        heightCm: heightCm,
        weightCurrentKg: weightKg,
        activityLevel: activity,
      ),
      health: HealthHistory(flags: flags),
      goals: goals,
      nutrition: NutritionPrefs(sexAtBirth: sexAtBirth, goalDirection: direction),
    );

List<NutritionInput> _missing(UserProfile p, {double? weight}) =>
    missingNutritionInputs(p, currentWeightKg: weight, now: _now);

void main() {
  group('a complete profile', () {
    test('reports nothing', () {
      expect(_missing(_p()), isEmpty);
    });
  });

  group('each input individually', () {
    test('nutritionGuidance question unanswered', () {
      expect(
          _missing(_p(
              flags: const HealthFlags(
                  professionalGuidance: ProfessionalGuidanceNeed.none))),
          [NutritionInput.nutritionGuidance]);
    });
    test('professionalGuidance question unanswered', () {
      expect(
          _missing(_p(
              flags: const HealthFlags(
                  nutritionGuidance: NutritionGuidanceNeed.none))),
          [NutritionInput.professionalGuidance]);
    });
    test('birth year (and no legacy stored age)', () {
      expect(_missing(_p(birthYear: null)), [NutritionInput.birthYear]);
    });
    test('a legacy stored age counts as a known age', () {
      expect(_missing(_p(birthYear: null, storedAge: 40)), isEmpty);
    });
    test('height', () {
      expect(_missing(_p(heightCm: null)), [NutritionInput.height]);
    });
    test('weight (profile weight absent and no recent weigh-in)', () {
      expect(_missing(_p(weightKg: null)), [NutritionInput.weight]);
    });
    test('a resolved current weight satisfies a missing profile weight', () {
      expect(_missing(_p(weightKg: null), weight: 79.5), isEmpty);
    });
    test('sex basis: neither gender nor sexAtBirth', () {
      expect(_missing(_p(gender: null)), [NutritionInput.sexBasis]);
    });
    test('sexAtBirth alone is enough; so is gender alone', () {
      expect(_missing(_p(gender: null, sexAtBirth: SexAtBirth.female)), isEmpty);
      expect(_missing(_p(gender: Gender.nonBinary)), isEmpty);
    });
    test('activity level', () {
      expect(_missing(_p(activity: null)), [NutritionInput.activity]);
    });
    test('goal: no explicit direction and no goal signal', () {
      expect(_missing(_p(direction: null)), [NutritionInput.goal]);
    });
    test('goal: a questionnaire goal is a signal, so the goal is not missing', () {
      expect(
          _missing(_p(direction: null, goals: const FitnessGoals(weightLoss: true))),
          isEmpty);
      expect(
          _missing(_p(direction: null, goals: const FitnessGoals(muscleGain: true))),
          isEmpty);
    });
    test('goal: other questionnaire goals are not a signal', () {
      expect(
          _missing(_p(
              direction: null,
              goals: const FitnessGoals(endurance: true, strength: true))),
          [NutritionInput.goal]);
    });
  });

  group('combinations and order', () {
    test('the flow order: safety questions first, then body inputs, then goal', () {
      final p = _p(
        flags: HealthFlags.empty,
        birthYear: null,
        heightCm: null,
        weightKg: null,
        gender: null,
        activity: null,
        direction: null,
      );
      expect(_missing(p), [
        NutritionInput.nutritionGuidance,
        NutritionInput.professionalGuidance,
        NutritionInput.birthYear,
        NutritionInput.height,
        NutritionInput.weight,
        NutritionInput.sexBasis,
        NutritionInput.activity,
        NutritionInput.goal,
      ]);
    });
    test('only the safety questions missing -> exactly those two', () {
      expect(_missing(_p(flags: HealthFlags.empty)),
          [NutritionInput.nutritionGuidance, NutritionInput.professionalGuidance]);
    });
    test('a pair: height + activity', () {
      expect(_missing(_p(heightCm: null, activity: null)),
          [NutritionInput.height, NutritionInput.activity]);
    });
    test('the enum has exactly the eight documented names (they are stable identifiers)', () {
      expect(NutritionInput.values.map((e) => e.name).toList(), [
        'birthYear',
        'height',
        'weight',
        'sexBasis',
        'activity',
        'goal',
        'nutritionGuidance',
        'professionalGuidance',
      ]);
    });
  });

  group('goal derivation', () {
    test('an explicit direction wins over the questionnaire', () {
      expect(
          deriveGoalDirection(_p(
              direction: GoalDirection.gain,
              goals: const FitnessGoals(weightLoss: true))),
          GoalDirection.gain);
    });
    test('weightLoss -> lose, muscleGain -> gain, anything else -> maintain', () {
      expect(
          deriveGoalDirection(
              _p(direction: null, goals: const FitnessGoals(weightLoss: true))),
          GoalDirection.lose);
      expect(
          deriveGoalDirection(
              _p(direction: null, goals: const FitnessGoals(muscleGain: true))),
          GoalDirection.gain);
      expect(
          deriveGoalDirection(
              _p(direction: null, goals: const FitnessGoals(strength: true))),
          GoalDirection.maintain);
      expect(deriveGoalDirection(_p(direction: null)), GoalDirection.maintain);
    });
    test('weightLoss and muscleGain together: lose first (the more cautious order)', () {
      expect(
          deriveGoalDirection(_p(
              direction: null,
              goals: const FitnessGoals(weightLoss: true, muscleGain: true))),
          GoalDirection.lose);
    });
    test('hasGoalSignal', () {
      expect(hasGoalSignal(_p(direction: GoalDirection.lose)), isTrue);
      expect(hasGoalSignal(_p(direction: null)), isFalse);
      expect(
          hasGoalSignal(
              _p(direction: null, goals: const FitnessGoals(muscleGain: true))),
          isTrue);
    });
  });

  group('age for the energy maths', () {
    test('uses the higher bracket (ageAt), the lower BMR; eligibility uses lowestAgeAt', () {
      final p = _p(birthYear: 1985);
      expect(nutritionAgeYears(p, 2026), 41);
      expect(p.personal.lowestAgeAt(2026), 40);
    });
    test('legacy stored age is returned unchanged; unknown stays null', () {
      expect(nutritionAgeYears(_p(birthYear: null, storedAge: 33), 2026), 33);
      expect(nutritionAgeYears(_p(birthYear: null), 2026), isNull);
    });
  });
}
