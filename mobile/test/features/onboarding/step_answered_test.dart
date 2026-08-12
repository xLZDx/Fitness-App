import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart'
    show ProgrammeGoal;

/// The rule behind the primary button's label, and behind where a returning
/// user lands.
///
/// Asserted directly rather than by reading a label off a pumped page: both
/// questions are facts about the draft, and a widget test would only prove that
/// one screen renders one branch of them.
void main() {
  final empty = UserProfile.empty('u');

  group('the order', () {
    test('holds every section exactly once', () {
      // The list IS the flow, and a section dropped from it is a question the
      // app silently stops asking -- with the data still in the model, so
      // nothing else goes red.
      expect(kOnboardingOrder.toSet(), OnboardingStep.values.toSet());
      expect(kOnboardingOrder, hasLength(OnboardingStep.values.length));
    });

    test('opens on the goal, per the design', () {
      // `App.tsx` step 1/9 is "Цель и уровень". The pre-O2 flow opened on
      // height and weight, which asks a person to measure themselves before
      // being told what it is for. O3 merged goal and level into that one
      // screen, so there is nothing at index 1 to assert about any more.
      expect(kOnboardingOrder.first, OnboardingStep.goalAndLevel);
    });
  });

  group('an untouched draft', () {
    test('answers nothing, on every section', () {
      for (final step in OnboardingStep.values) {
        expect(isOnboardingStepAnswered(step, empty), isFalse,
            reason: step.name);
      }
    });
  });

  group('one answer is enough', () {
    // Deliberately the weakest possible answer in each section: every question
    // here is optional and `_submit` sends whatever the draft holds, so this
    // asks "did the user touch it", never "is it complete".

    test('personal — a single field', () {
      final p = empty.copyWith(personal: const PersonalInfo(age: 31));
      expect(isOnboardingStepAnswered(OnboardingStep.personal, p), isTrue);
      expect(isOnboardingStepAnswered(OnboardingStep.health, p), isFalse,
          reason: 'answering one section must not light up the others');
    });

    test('health — one injury', () {
      final p = empty.copyWith(
        health: const HealthHistory(
          injuries: [Injury(bodyPart: 'верх спины', type: 'strain')],
        ),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.health, p), isTrue);
    });

    test('health — free text alone counts', () {
      // `otherConcerns` is the field the health screen's own text box writes.
      // Excluding it would show "Skip" to someone who had just typed a
      // paragraph about their back.
      final p = empty.copyWith(
        health: const HealthHistory(otherConcerns: 'shoulder clicks'),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.health, p), isTrue);
    });

    test('goal and level — the primary goal alone', () {
      // The design's own first answer. Before O3 this field did not exist and
      // the only way to answer the screen was the multi-select below it.
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.goalAndLevel,
            empty.copyWith(
                goals: const FitnessGoals(primary: ProgrammeGoal.endurance))),
        isTrue,
      );
    });

    test('goal and level — a secondary checkbox, or the sport field', () {
      expect(
        isOnboardingStepAnswered(OnboardingStep.goalAndLevel,
            empty.copyWith(goals: const FitnessGoals(strength: true))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.goalAndLevel,
            empty.copyWith(
                goals: const FitnessGoals(specificSport: 'climbing'))),
        isTrue,
      );
    });

    test('goal and level — the level half alone also counts', () {
      // Two former screens share one now, so either half answers it. Requiring
      // both would put "Skip" on a button that would throw away the goal the
      // user had just picked.
      expect(
        isOnboardingStepAnswered(OnboardingStep.goalAndLevel,
            empty.copyWith(level: const FitnessLevel(frequencyPerWeek: 3))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.goalAndLevel,
            empty.copyWith(
                level: const FitnessLevel(tier: FitnessTier.never))),
        isTrue,
        reason: '"never trained" is an answer, not an absence of one',
      );
    });

    test('goal and level — an empty sport string is not an answer', () {
      // `GlassTextField` writes '' on the first keystroke-then-delete. Treating
      // that as answered would leave the button on "Next" for a step the user
      // emptied again.
      final p = empty.copyWith(goals: const FitnessGoals(specificSport: ''));
      expect(isOnboardingStepAnswered(OnboardingStep.goalAndLevel, p), isFalse);
    });

    test('lifestyle, equipment, motivation', () {
      expect(
        isOnboardingStepAnswered(OnboardingStep.lifestyle,
            empty.copyWith(lifestyle: const Lifestyle(sleepHoursPerNight: 7))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.equipment,
            empty.copyWith(
                equipment: const EquipmentAccess(hasGymAccess: false))),
        isTrue,
        reason: '"no gym" is an answer; only null means unanswered',
      );
      expect(
        isOnboardingStepAnswered(OnboardingStep.motivation,
            empty.copyWith(motivation: const MotivationPrefs(motivation: 'x'))),
        isTrue,
      );
    });
  });

  group('where a returning user lands', () {
    test('an untouched draft opens at the beginning', () {
      expect(onboardingResumeIndex(empty), 0);
    });

    test('answering the first screen moves the resume point past it', () {
      final p = empty.copyWith(goals: const FitnessGoals(strength: true));
      expect(onboardingResumeIndex(p), 1);
    });

    test('the FIRST gap, not the furthest screen reached', () {
      // Someone who skipped the opening screen and answered their equipment
      // should come back to the opening screen. Resuming at the furthest point
      // would bury the one screen still missing behind the ones already done.
      final p =
          empty.copyWith(equipment: const EquipmentAccess(hasGymAccess: true));
      expect(onboardingResumeIndex(p), 0,
          reason: 'goalAndLevel is index 0 and is still empty');
    });

    test('a fully answered draft lands on the last screen, not past it', () {
      final full = empty.copyWith(
        goals: const FitnessGoals(strength: true),
        level: const FitnessLevel(frequencyPerWeek: 3),
        equipment: const EquipmentAccess(hasGymAccess: true),
        health: const HealthHistory(otherConcerns: 'none'),
        motivation: const MotivationPrefs(motivation: 'x'),
        personal: const PersonalInfo(age: 31),
        lifestyle: const Lifestyle(sleepHoursPerNight: 7),
      );
      expect(onboardingResumeIndex(full), kOnboardingOrder.length - 1,
          reason: 'so they land on Done rather than being bounced out');
    });

    test('the index is always renderable', () {
      // The value is fed straight to `PageController.jumpToPage`. An
      // off-by-one here is a crash on open, not a cosmetic slip.
      for (final p in [
        empty,
        empty.copyWith(goals: const FitnessGoals(strength: true)),
        empty.copyWith(lifestyle: const Lifestyle(stressLevel: 4)),
      ]) {
        final i = onboardingResumeIndex(p);
        expect(i, greaterThanOrEqualTo(0));
        expect(i, lessThan(kOnboardingOrder.length));
      }
    });
  });
}
