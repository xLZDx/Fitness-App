import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_profile_flow_page.dart';
import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/onboarding/widgets/nutrition_inputs.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// E2 pure/state tests: ONB-01/02/03/13/15/16 and the C11 sheet list.
void main() {
  final empty = UserProfile.empty('u');

  HealthFlags flags({
    ProfessionalGuidanceNeed? pro,
    NutritionGuidanceNeed? nut,
    Set<FoodAllergen> allergens = const {},
  }) =>
      HealthFlags(
        professionalGuidance: pro,
        nutritionGuidance: nut,
        foodAllergens: allergens,
      );

  group('ONB-01/ONB-13 order (D-75: safety questions precede nutrition)', () {
    test('the exact order is the design sequence', () {
      expect(kOnboardingOrder.sublist(kOnboardingOrder.length - 6), [
        OnboardingStep.personal,
        OnboardingStep.lifestyle,
        OnboardingStep.healthFlags,
        OnboardingStep.nutrition,
        OnboardingStep.screening,
        OnboardingStep.preview,
      ]);
    });

    test('nutrition appears exactly once and every enum value is in the order',
        () {
      expect(
          kOnboardingOrder.where((s) => s == OnboardingStep.nutrition), hasLength(1));
      expect(kOnboardingOrder.toSet(), OnboardingStep.values.toSet());
      expect(kOnboardingOrder, hasLength(OnboardingStep.values.length));
      expect(OnboardingStep.values, contains(OnboardingStep.nutrition));
    });

    test('healthFlags (both safety questions) strictly precedes nutrition', () {
      final h = kOnboardingOrder.indexOf(OnboardingStep.healthFlags);
      final n = kOnboardingOrder.indexOf(OnboardingStep.nutrition);
      final s = kOnboardingOrder.indexOf(OnboardingStep.screening);
      expect(h, lessThan(n));
      expect(n, lessThan(s));
      expect(n, h + 1, reason: 'straight after the health questions');
    });

    test('every step answers without throwing on an empty profile', () {
      for (final s in OnboardingStep.values) {
        expect(() => isOnboardingStepAnswered(s, empty), returnsNormally);
      }
    });
  });

  group('ONB-02 isOnboardingStepAnswered(nutrition)', () {
    bool answered(UserProfile p) =>
        isOnboardingStepAnswered(OnboardingStep.nutrition, p);

    test('unanswered for empty prefs and no allergens', () {
      expect(answered(empty), isFalse);
    });

    final each = <String, NutritionPrefs>{
      'sexAtBirth': const NutritionPrefs(sexAtBirth: SexAtBirth.female),
      'goalDirection': const NutritionPrefs(goalDirection: GoalDirection.lose),
      'targetBodyFatPct': const NutritionPrefs(targetBodyFatPct: 18),
      'typicalDailySteps': const NutritionPrefs(typicalDailySteps: 4000),
      'mealsPerDay': const NutritionPrefs(mealsPerDay: 4),
      'excludedFoods': const NutritionPrefs(excludedFoods: ['mushrooms']),
      'planOwnership':
          const NutritionPrefs(planOwnership: PlanOwnership.shared),
      'healthConnectChoice':
          const NutritionPrefs(healthConnectChoice: HealthConnectChoice.manual),
      'completedAt': NutritionPrefs(completedAt: DateTime.utc(2026, 10, 15)),
    };
    each.forEach((name, prefs) {
      test('answered when only $name is set', () {
        expect(answered(empty.copyWith(nutrition: prefs)), isTrue);
      });
    });

    test('answered by an allergen chip alone', () {
      final p = empty.copyWith(
        health: HealthHistory(
          flags: flags(allergens: {FoodAllergen.peanuts}),
        ),
      );
      expect(answered(p), isTrue);
    });

    test('the two safety answers alone do NOT answer the nutrition step', () {
      final p = empty.copyWith(
        health: HealthHistory(
          flags: flags(
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none),
        ),
      );
      expect(answered(p), isFalse);
      // ...but they do answer the health-flags step.
      expect(isOnboardingStepAnswered(OnboardingStep.healthFlags, p), isTrue);
    });

    test('answering nutrition does not light up other steps', () {
      final p = empty.copyWith(
          nutrition: const NutritionPrefs(mealsPerDay: 3));
      for (final s in OnboardingStep.values) {
        if (s == OnboardingStep.nutrition || s == OnboardingStep.preview) {
          continue;
        }
        expect(isOnboardingStepAnswered(s, p), isFalse, reason: s.name);
      }
    });

    test('resume lands on the nutrition step when everything before it is answered',
        () {
      // Every step before nutrition answered, nutrition itself untouched.
      var p = empty.copyWith(
        goals: const FitnessGoals(strength: true),
        level: const FitnessLevel(frequencyPerWeek: 3),
        equipment: const EquipmentAccess(hasGymAccess: true),
        schedule: const TrainingSchedule(daysPerWeek: 3),
        health: HealthHistory(
          otherConcerns: 'none',
          flags: const HealthFlags(
            bloodPressure: BloodPressureStatus.noKnownIssue,
            professionalGuidance: ProfessionalGuidanceNeed.none,
            nutritionGuidance: NutritionGuidanceNeed.none,
          ),
        ),
        motivation: const MotivationPrefs(motivation: 'x'),
        personal: const PersonalInfo(age: 31),
        lifestyle: const Lifestyle(sleepHoursPerNight: 7),
      );
      final idx = onboardingResumeIndex(p);
      expect(kOnboardingOrder[idx], OnboardingStep.nutrition);
      p = p.copyWith(nutrition: const NutritionPrefs(mealsPerDay: 3));
      expect(kOnboardingOrder[onboardingResumeIndex(p)],
          OnboardingStep.screening);
    });
  });

  group('nutritionSafetyClear (D-75 lock-out predicate)', () {
    test('clear only for none/none', () {
      expect(
          nutritionSafetyClear(flags(
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none)),
          isTrue);
    });

    test('reported on either answer is not clear', () {
      expect(
          nutritionSafetyClear(flags(
              pro: ProfessionalGuidanceNeed.reported,
              nut: NutritionGuidanceNeed.none)),
          isFalse);
      expect(
          nutritionSafetyClear(flags(
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.reported)),
          isFalse);
      expect(
          nutritionSafetyClear(flags(
              pro: ProfessionalGuidanceNeed.reported,
              nut: NutritionGuidanceNeed.reported)),
          isFalse);
    });

    test('unanswered (null) is not clear, alone or with one none', () {
      expect(nutritionSafetyClear(const HealthFlags()), isFalse);
      expect(
          nutritionSafetyClear(flags(pro: ProfessionalGuidanceNeed.none)),
          isFalse);
      expect(nutritionSafetyClear(flags(nut: NutritionGuidanceNeed.none)),
          isFalse);
    });
  });

  group('ONB-09/ONB-10 sheet list from missingNutritionInputs', () {
    final now = DateTime(2026, 6, 1);

    UserProfile complete() => empty.copyWith(
          personal: const PersonalInfo(
            birthYear: 1990,
            heightCm: 175,
            weightCurrentKg: 80,
            activityLevel: ActivityLevel.active,
            gender: Gender.male,
          ),
          goals: const FitnessGoals(weightLoss: true),
          health: HealthHistory(
            flags: flags(
                pro: ProfessionalGuidanceNeed.none,
                nut: NutritionGuidanceNeed.none),
          ),
        );

    test('a complete profile misses nothing and needs only the food sheet', () {
      final missing = missingNutritionInputs(complete(), now: now);
      expect(missing, isEmpty);
      expect(nutritionProfileSheets(missing), [NutritionProfileSheet.food]);
    });

    test('only safety missing -> safety then food (no body sheet)', () {
      final p = complete().copyWith(health: HealthHistory.empty);
      final missing = missingNutritionInputs(p, now: now);
      expect(missing, [
        NutritionInput.nutritionGuidance,
        NutritionInput.professionalGuidance,
      ]);
      expect(nutritionProfileSheets(missing),
          [NutritionProfileSheet.safety, NutritionProfileSheet.food]);
    });

    test('one safety question missing is enough for the safety sheet', () {
      final p = complete().copyWith(
        health: HealthHistory(
            flags: flags(pro: ProfessionalGuidanceNeed.none)),
      );
      final missing = missingNutritionInputs(p, now: now);
      expect(missing, [NutritionInput.nutritionGuidance]);
      expect(nutritionProfileSheets(missing),
          [NutritionProfileSheet.safety, NutritionProfileSheet.food]);
    });

    test('only a body input missing -> body then food (no safety sheet)', () {
      final p = complete().copyWith(
          personal: const PersonalInfo(
              birthYear: 1990,
              weightCurrentKg: 80,
              activityLevel: ActivityLevel.active,
              gender: Gender.male));
      final missing = missingNutritionInputs(p, now: now);
      expect(missing, [NutritionInput.height]);
      expect(nutritionProfileSheets(missing),
          [NutritionProfileSheet.body, NutritionProfileSheet.food]);
    });

    test('a missing goal alone selects the body sheet', () {
      final p = complete().copyWith(goals: const FitnessGoals());
      final missing = missingNutritionInputs(p, now: now);
      expect(missing, [NutritionInput.goal]);
      expect(nutritionProfileSheets(missing),
          [NutritionProfileSheet.body, NutritionProfileSheet.food]);
    });

    test('everything missing -> all three sheets in safety, body, food order',
        () {
      final missing = missingNutritionInputs(empty, now: now);
      expect(missing, containsAll(NutritionInput.values));
      expect(nutritionProfileSheets(missing), [
        NutritionProfileSheet.safety,
        NutritionProfileSheet.body,
        NutritionProfileSheet.food,
      ]);
    });

    test('the safety questions are listed before every body input', () {
      final missing = missingNutritionInputs(empty, now: now);
      expect(missing.indexOf(NutritionInput.nutritionGuidance),
          lessThan(missing.indexOf(NutritionInput.birthYear)));
      expect(missing.indexOf(NutritionInput.professionalGuidance),
          lessThan(missing.indexOf(NutritionInput.height)));
    });

    test('NutritionProfileSheet has exactly the three design sheets', () {
      expect(NutritionProfileSheet.values,
          [NutritionProfileSheet.safety, NutritionProfileSheet.body,
            NutritionProfileSheet.food]);
    });
  });

  group('steps buckets (ONB-06)', () {
    test('midpoints are exactly 2500/4000/6500/9500/12500', () {
      expect(kStepsBucketMidpoints, [2500, 4000, 6500, 9500, 12500]);
    });

    test('each midpoint falls in its own bucket', () {
      for (var i = 0; i < kStepsBucketMidpoints.length; i++) {
        expect(stepsBucketIndex(kStepsBucketMidpoints[i]), i);
      }
    });

    test('bucket edges: <3k, 3-5k, 5-8k, 8-11k, 11k+', () {
      expect(stepsBucketIndex(0), 0);
      expect(stepsBucketIndex(2999), 0);
      expect(stepsBucketIndex(3000), 1);
      expect(stepsBucketIndex(4999), 1);
      expect(stepsBucketIndex(5000), 2);
      expect(stepsBucketIndex(7999), 2);
      expect(stepsBucketIndex(8000), 3);
      expect(stepsBucketIndex(10999), 3);
      expect(stepsBucketIndex(11000), 4);
      expect(stepsBucketIndex(40000), 4);
    });
  });

  group('DietaryPreference.pescatarian (ONB-07)', () {
    test('exists and is stored by name; round-trips through Lifestyle', () {
      expect(DietaryPreference.values, contains(DietaryPreference.pescatarian));
      expect(DietaryPreference.pescatarian.name, 'pescatarian');
      final p = empty.copyWith(
          lifestyle:
              const Lifestyle(diet: [DietaryPreference.pescatarian]));
      final json = p.toJson();
      expect(json['lifestyle']['diet'], ['pescatarian']);
      expect(DietaryPreference.values.byName('pescatarian'),
          DietaryPreference.pescatarian);
    });

    test('pescatarian sits before none (none stays last)', () {
      expect(DietaryPreference.values.last, DietaryPreference.none);
      expect(DietaryPreference.values.indexOf(DietaryPreference.pescatarian),
          DietaryPreference.values.length - 2);
    });

    test('pescatarian alone answers the lifestyle step', () {
      final p = empty.copyWith(
          lifestyle: const Lifestyle(diet: [DietaryPreference.pescatarian]));
      expect(isOnboardingStepAnswered(OnboardingStep.lifestyle, p), isTrue);
    });
  });

  group('ONB-16 device-only excluded foods and allergens', () {
    final p = empty.copyWith(
      nutrition: const NutritionPrefs(
          excludedFoods: ['peanut butter', 'celiac bread'],
          mealsPerDay: 4,
          goalDirection: GoalDirection.lose),
      health: HealthHistory(
        flags: flags(
            pro: ProfessionalGuidanceNeed.none,
            nut: NutritionGuidanceNeed.none,
            allergens: {FoodAllergen.peanuts, FoodAllergen.gluten}),
      ),
    );

    test('stripSensitive removes excludedFoods and keeps the other prefs', () {
      final stripped = stripSensitive(p);
      expect(stripped.nutrition.excludedFoods, isEmpty);
      expect(stripped.nutrition.mealsPerDay, 4);
      expect(stripped.nutrition.goalDirection, GoalDirection.lose);
    });

    test('the server JSON (stripped) never contains excludedFoods or text', () {
      final json = stripSensitive(p).toJson();
      expect((json['nutrition'] as Map).containsKey('excludedFoods'), isFalse);
      final text = json.toString();
      expect(text, isNot(contains('peanut butter')));
      expect(text, isNot(contains('celiac bread')));
    });

    test('allergens and both safety answers do not reach the server payload',
        () {
      final json = stripSensitive(p).toJson();
      final flagsJson = (json['health'] as Map)['flags'] as Map;
      // The blanked flags keep their (null/empty) keys; what matters is that
      // no answer value survives.
      expect(flagsJson['professionalGuidance'], isNull);
      expect(flagsJson['nutritionGuidance'], isNull);
      expect(flagsJson['foodAllergens'] ?? const [], isEmpty);
      final text = json.toString();
      expect(text, isNot(contains('peanuts')));
      expect(text, isNot(contains('gluten')));
      expect(text, isNot(contains('reported')));
    });

    test('the unstripped toJson DOES carry the foods (so stripping is what '
        'protects them, not an accident of the model)', () {
      expect(p.toJson().toString(), contains('peanut butter'));
    });

    test('extractSensitive/mergeSensitive keep the foods on the device side',
        () {
      final s = extractSensitive(p);
      expect(s.excludedFoods, ['peanut butter', 'celiac bread']);
      final merged = mergeSensitive(stripSensitive(p), s);
      expect(merged.nutrition.excludedFoods, ['peanut butter', 'celiac bread']);
      expect(merged.health.flags.foodAllergens,
          {FoodAllergen.peanuts, FoodAllergen.gluten});
    });
  });

  group('ONB-03/draft notifier (updateNutrition, markNutritionCompleted)', () {
    late ProviderContainer container;
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() {
      auth = MockAuthRepository(latency: Duration.zero);
      profiles = MockProfileRepository(latency: Duration.zero);
      container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWith((ref) {
          ref.onDispose(auth.dispose);
          return auth;
        }),
        profileRepositoryProvider.overrideWith((ref) {
          ref.onDispose(profiles.dispose);
          return profiles;
        }),
      ]);
      addTearDown(container.dispose);
    });

    Future<String> signIn() async {
      final user = await auth.signInAnonymously();
      container.listen(authUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      return user.uid;
    }

    test('updateNutrition keeps every other draft field', () async {
      await signIn();
      final n = container.read(questionnaireDraftProvider.notifier);
      n.updatePersonal((p) => p.copyWith(heightCm: 180));
      n.updateNutrition((x) => x.copyWith(mealsPerDay: 5));
      final d = container.read(questionnaireDraftProvider);
      expect(d.nutrition.mealsPerDay, 5);
      expect(d.personal.heightCm, 180);
    });

    test('markNutritionCompleted stamps once and keeps the first timestamp',
        () async {
      await signIn();
      final n = container.read(questionnaireDraftProvider.notifier);
      expect(container.read(questionnaireDraftProvider).nutrition.completedAt,
          isNull);
      final first = DateTime.utc(2026, 10, 1, 8);
      n.markNutritionCompleted(first);
      expect(container.read(questionnaireDraftProvider).nutrition.completedAt,
          first);
      n.markNutritionCompleted(DateTime.utc(2027, 1, 1));
      expect(container.read(questionnaireDraftProvider).nutrition.completedAt,
          first,
          reason: 'idempotent: a later pass must not move the stamp');
    });

    test('markNutritionCompleted does not touch the profile completedAt',
        () async {
      final uid = await signIn();
      final done = DateTime.utc(2026, 9, 1);
      await profiles.save(UserProfile.empty(uid).copyWith(completedAt: done));
      container.invalidate(questionnaireDraftProvider);
      final n = container.read(questionnaireDraftProvider.notifier);
      n.markNutritionCompleted(DateTime.utc(2026, 10, 15));
      final d = container.read(questionnaireDraftProvider);
      expect(d.completedAt, done);
      expect(d.hasCompletedOnboarding, isTrue);
    });

    test('saveDraft after the stamp keeps the profile completedAt in the store',
        () async {
      final uid = await signIn();
      final done = DateTime.utc(2026, 9, 1);
      await profiles.save(UserProfile.empty(uid)
          .copyWith(completedAt: done, personal: const PersonalInfo(age: 40)));
      container.invalidate(questionnaireDraftProvider);
      final n = container.read(questionnaireDraftProvider.notifier);
      n.updateNutrition((x) => x.copyWith(mealsPerDay: 4));
      n.markNutritionCompleted(DateTime.utc(2026, 10, 15));
      await n.saveDraft();
      final stored = profiles.cached(uid)!;
      expect(stored.completedAt, done);
      expect(stored.personal.age, 40, reason: 'unrelated fields survive');
      expect(stored.nutrition.mealsPerDay, 4);
      expect(stored.nutrition.completedAt, DateTime.utc(2026, 10, 15));
    });

    test('a goal default is derived from the questionnaire goals only when a '
        'signal exists', () {
      final lose = empty.copyWith(goals: const FitnessGoals(weightLoss: true));
      final gain = empty.copyWith(goals: const FitnessGoals(muscleGain: true));
      final other = empty.copyWith(goals: const FitnessGoals(strength: true));
      expect(hasGoalSignal(lose) && deriveGoalDirection(lose) == GoalDirection.lose,
          isTrue);
      expect(hasGoalSignal(gain) && deriveGoalDirection(gain) == GoalDirection.gain,
          isTrue);
      expect(hasGoalSignal(other), isFalse,
          reason: 'no signal: nothing is pre-selected');
      expect(deriveGoalDirection(other), GoalDirection.maintain);
      expect(
          deriveGoalDirection(
              lose.copyWith(nutrition: const NutritionPrefs(goalDirection: GoalDirection.gain))),
          GoalDirection.gain,
          reason: 'an explicit answer beats the derived default');
    });
  });

  group('NutritionPrefs excluded-food limits (ONB-04/ONB-06)', () {
    test('limits are 20 items of 40 characters', () {
      expect(NutritionPrefs.maxExcludedFoods, 20);
      expect(NutritionPrefs.maxExcludedFoodChars, 40);
    });

    test('fromJson caps at 20 items and 40 characters, trims, drops blanks', () {
      final raw = {
        'excludedFoods': [
          for (var i = 0; i < 25; i++) 'food$i',
        ],
      };
      expect(NutritionPrefs.fromJson(raw).excludedFoods, hasLength(20));
      final long = 'x' * 41;
      final cut = NutritionPrefs.fromJson({
        'excludedFoods': [long, '   ', '  ok  ', 7]
      }).excludedFoods;
      expect(cut, ['x' * 40, 'ok']);
    });
  });
}
