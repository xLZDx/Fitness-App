// T19 nutrition_inputs_test (PLAN-10, PLAN-24). The ONE definition of current
// weight and the resolution of a profile into numeric inputs.
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 15, 9);

WeightEntry _w(Duration ago, double kg, {WeightSource s = WeightSource.manual}) =>
    WeightEntry(at: _now.subtract(ago), kg: kg, source: s);

UserProfile _p({
  double? weightKg = 80,
  int? heightCm = 180,
  int? birthYear = 1985,
  Gender? gender = Gender.male,
  SexAtBirth? sexAtBirth,
  ActivityLevel? activity = ActivityLevel.moderatelyActive,
  FitnessGoals goals = const FitnessGoals(),
  int? steps,
  double? targetWeight,
  double? targetBf,
  GoalDirection? direction,
  HealthFlags flags = HealthFlags.empty,
}) =>
    UserProfile(
      uid: 'u',
      personal: PersonalInfo(
        birthYear: birthYear,
        gender: gender,
        heightCm: heightCm,
        weightCurrentKg: weightKg,
        weightTargetKg: targetWeight,
        activityLevel: activity,
      ),
      health: HealthHistory(flags: flags),
      goals: goals,
      nutrition: NutritionPrefs(
        sexAtBirth: sexAtBirth,
        typicalDailySteps: steps,
        targetBodyFatPct: targetBf,
        goalDirection: direction,
      ),
    );

void main() {
  group('resolveCurrentWeight (PLAN-10, D-72)', () {
    test('a weigh-in within 14 days wins over the profile weight', () {
      final r = resolveCurrentWeight(
        entries: [_w(const Duration(days: 3), 85)],
        profileWeightKg: 80,
        now: _now,
      )!;
      expect(r.kg, 85);
      expect(r.stale, isFalse);
    });
    test('a weigh-in 15 days old is ignored: profile weight, flagged stale', () {
      final r = resolveCurrentWeight(
        entries: [_w(const Duration(days: 15), 85)],
        profileWeightKg: 80,
        now: _now,
      )!;
      expect(r.kg, 80);
      expect(r.stale, isTrue);
    });
    test('exactly 14 days is still fresh; 14 days and a minute is stale', () {
      expect(
          resolveCurrentWeight(
                  entries: [_w(const Duration(days: 14), 85)],
                  profileWeightKg: 80,
                  now: _now)!
              .stale,
          isFalse);
      expect(
          resolveCurrentWeight(
                  entries: [_w(const Duration(days: 14, minutes: 1), 85)],
                  profileWeightKg: 80,
                  now: _now)!
              .stale,
          isTrue);
    });
    test('the NEWEST entry within the window wins, not the largest or the first', () {
      final r = resolveCurrentWeight(
        entries: [
          _w(const Duration(days: 10), 90),
          _w(const Duration(days: 1), 82),
          _w(const Duration(days: 5), 95),
        ],
        profileWeightKg: 80,
        now: _now,
      )!;
      expect(r.kg, 82);
    });
    test('no entries and no profile weight -> null', () {
      expect(
          resolveCurrentWeight(entries: const [], profileWeightKg: null, now: _now),
          isNull);
    });
    test('a fresh entry works even without a profile weight', () {
      final r = resolveCurrentWeight(
        entries: [_w(const Duration(hours: 2), 79)],
        profileWeightKg: null,
        now: _now,
      )!;
      expect(r.kg, 79);
      expect(r.stale, isFalse);
    });
    test('a scan-sourced entry counts like a manual one', () {
      final r = resolveCurrentWeight(
        entries: [_w(const Duration(days: 1), 81, s: WeightSource.scan)],
        profileWeightKg: 80,
        now: _now,
      )!;
      expect(r.kg, 81);
    });
  });

  group('NutritionInputs.resolve', () {
    test('a complete profile resolves every input', () {
      final res = NutritionInputs.resolve(
        _p(
          sexAtBirth: SexAtBirth.female,
          steps: 6500,
          targetWeight: 72,
          targetBf: 24,
          direction: GoalDirection.lose,
        ),
        now: _now,
        weightEntries: [_w(const Duration(days: 2), 85)],
      );
      expect(res.isComplete, isTrue);
      expect(res.missing, isEmpty);
      final i = res.inputs!;
      expect(i.weightKg, 85);
      expect(i.heightCm, 180.0);
      expect(i.ageYears, 41); // 2026 - 1985 (the higher bracket, lower BMR)
      expect(i.sex, SexBasis.female); // sexAtBirth beats gender male
      expect(i.activityLevel, ActivityLevel.moderatelyActive);
      expect(i.goal, GoalDirection.lose);
      expect(i.typicalSteps, 6500);
      expect(i.weightStale, isFalse);
      expect(i.weightTargetKg, 72);
      expect(i.targetBodyFatPct, 24);
    });
    test('BMI is computed from the RESOLVED weight, not the profile weight', () {
      final res = NutritionInputs.resolve(
        _p(weightKg: 60),
        now: _now,
        weightEntries: [_w(const Duration(days: 1), 90)],
      );
      expect(res.inputs!.bmi, closeTo(90 / 3.24, 1e-9));
    });
    test('a stale weight is flagged', () {
      final res = NutritionInputs.resolve(
        _p(),
        now: _now,
        weightEntries: [_w(const Duration(days: 15), 99)],
      );
      expect(res.inputs!.weightKg, 80);
      expect(res.inputs!.weightStale, isTrue);
    });
    test('Health platform median steps beat the self-reported bucket', () {
      final res = NutritionInputs.resolve(_p(steps: 4000),
          now: _now, healthMedianSteps: 9100);
      expect(res.inputs!.typicalSteps, 9100);
      final self = NutritionInputs.resolve(_p(steps: 4000), now: _now);
      expect(self.inputs!.typicalSteps, 4000);
      final none = NutritionInputs.resolve(_p(), now: _now);
      expect(none.inputs!.typicalSteps, isNull);
    });
    test('the goal derives from the questionnaire when none was chosen', () {
      final res = NutritionInputs.resolve(
          _p(goals: const FitnessGoals(muscleGain: true)),
          now: _now);
      expect(res.inputs!.goal, GoalDirection.gain);
      expect(NutritionInputs.resolve(_p(), now: _now).inputs!.goal,
          GoalDirection.maintain);
    });
    test('sex falls back to gender; non-binary gives the unspecified basis', () {
      expect(NutritionInputs.resolve(_p(), now: _now).inputs!.sex, SexBasis.male);
      expect(
          NutritionInputs.resolve(_p(gender: Gender.nonBinary), now: _now)
              .inputs!
              .sex,
          SexBasis.unspecified);
    });
  });

  group('needsProfile lists exactly the missing names', () {
    test('nothing missing -> complete', () {
      expect(NutritionInputs.resolve(_p(), now: _now).isComplete, isTrue);
    });
    test('height only', () {
      final r = NutritionInputs.resolve(_p(heightCm: null), now: _now);
      expect(r.inputs, isNull);
      expect(r.missing, [NutritionInput.height]);
    });
    test('weight only: no profile weight and no entries', () {
      final r = NutritionInputs.resolve(_p(weightKg: null), now: _now);
      expect(r.missing, [NutritionInput.weight]);
    });
    test('weight present only as a recent weigh-in is NOT missing', () {
      final r = NutritionInputs.resolve(_p(weightKg: null),
          now: _now, weightEntries: [_w(const Duration(days: 2), 80)]);
      expect(r.isComplete, isTrue);
    });
    test('weight present only as a STALE weigh-in IS missing', () {
      final r = NutritionInputs.resolve(_p(weightKg: null),
          now: _now, weightEntries: [_w(const Duration(days: 20), 80)]);
      expect(r.missing, [NutritionInput.weight]);
    });
    test('birth year, sex basis and activity', () {
      expect(
          NutritionInputs.resolve(_p(birthYear: null), now: _now).missing,
          [NutritionInput.birthYear]);
      expect(
          NutritionInputs.resolve(_p(gender: null), now: _now).missing,
          [NutritionInput.sexBasis]);
      expect(
          NutritionInputs.resolve(_p(activity: null), now: _now).missing,
          [NutritionInput.activity]);
    });
    test('several at once, in flow order', () {
      final r = NutritionInputs.resolve(
          _p(birthYear: null, heightCm: null, weightKg: null, gender: null, activity: null),
          now: _now);
      expect(r.missing, [
        NutritionInput.birthYear,
        NutritionInput.height,
        NutritionInput.weight,
        NutritionInput.sexBasis,
        NutritionInput.activity,
      ]);
    });
    test('the safety questions and the goal never block the numeric inputs', () {
      // flags empty (both questions unanswered) and no goal signal: the
      // eligibility gate, not this resolver, decides who sees numbers.
      final r = NutritionInputs.resolve(_p(), now: _now);
      expect(r.isComplete, isTrue);
      expect(r.missing, isEmpty);
    });
  });
}
