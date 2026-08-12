import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// The rule behind the primary button's label.
///
/// Asserted directly rather than by reading a label off a pumped page: the
/// question "has this step been touched" is a fact about the draft, and a
/// widget test would only prove that one screen renders one branch of it.
void main() {
  final empty = UserProfile.empty('u');

  group('an untouched draft', () {
    test('answers nothing, on every step the page renders', () {
      for (var i = 0; i < 7; i++) {
        expect(isOnboardingStepAnswered(i, empty), isFalse, reason: 'step $i');
      }
    });

    test('and an index the page does not render is false, not a crash', () {
      // O2 renumbers these. Until then an out-of-range index must degrade to a
      // "Skip" label rather than take the onboarding screen down.
      expect(isOnboardingStepAnswered(7, empty), isFalse);
      expect(isOnboardingStepAnswered(-1, empty), isFalse);
    });
  });

  group('one answer is enough', () {
    // Deliberately the weakest possible answer in each section: every question
    // here is optional and `_submit` sends whatever the draft holds, so this
    // asks "did the user touch it", never "is it complete".

    test('personal — a single field', () {
      final p = empty.copyWith(personal: const PersonalInfo(age: 31));
      expect(isOnboardingStepAnswered(0, p), isTrue);
      expect(isOnboardingStepAnswered(1, p), isFalse,
          reason: 'answering one step must not light up the others');
    });

    test('health — one injury', () {
      final p = empty.copyWith(
        health: const HealthHistory(
          injuries: [Injury(bodyPart: 'верх спины', type: 'strain')],
        ),
      );
      expect(isOnboardingStepAnswered(1, p), isTrue);
    });

    test('health — free text alone counts', () {
      // `otherConcerns` is the field the health screen's own text box writes.
      // Excluding it would show "Skip" to someone who had just typed a
      // paragraph about their back.
      final p = empty.copyWith(
        health: const HealthHistory(otherConcerns: 'shoulder clicks'),
      );
      expect(isOnboardingStepAnswered(1, p), isTrue);
    });

    test('goals — one checkbox, or the sport field', () {
      expect(
        isOnboardingStepAnswered(
            2, empty.copyWith(goals: const FitnessGoals(strength: true))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(2,
            empty.copyWith(goals: const FitnessGoals(specificSport: 'climbing'))),
        isTrue,
      );
    });

    test('goals — an empty sport string is not an answer', () {
      // `GlassTextField` writes '' on the first keystroke-then-delete. Treating
      // that as answered would leave the button on "Next" for a step the user
      // emptied again.
      final p = empty.copyWith(goals: const FitnessGoals(specificSport: ''));
      expect(isOnboardingStepAnswered(2, p), isFalse);
    });

    test('level, lifestyle, equipment, motivation', () {
      expect(
        isOnboardingStepAnswered(
            3, empty.copyWith(level: const FitnessLevel(frequencyPerWeek: 3))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(4,
            empty.copyWith(lifestyle: const Lifestyle(sleepHoursPerNight: 7))),
        isTrue,
      );
      expect(
        isOnboardingStepAnswered(
            5, empty.copyWith(equipment: const EquipmentAccess(hasGymAccess: false))),
        isTrue,
        reason: '"no gym" is an answer; only null means unanswered',
      );
      expect(
        isOnboardingStepAnswered(6,
            empty.copyWith(motivation: const MotivationPrefs(motivation: 'x'))),
        isTrue,
      );
    });
  });
}
