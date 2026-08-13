import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/steps/step_barriers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// O7 — the barriers screen.
///
/// The one rule with teeth is that "nothing stops me" cannot coexist with a
/// barrier. Everything else on the screen is a plain multi-select.
void main() {
  group('"nothing, really" is exclusive', () {
    test('picking it clears whatever was selected before', () {
      final result = resolveBarrierSelection(
        {TrainingBarrier.time, TrainingBarrier.none},
        {TrainingBarrier.time},
      );
      expect(result, [TrainingBarrier.none]);
    });

    test('naming a barrier afterwards drops it', () {
      final result = resolveBarrierSelection(
        {TrainingBarrier.none, TrainingBarrier.machineUse},
        {TrainingBarrier.none},
      );
      expect(result, [TrainingBarrier.machineUse]);
    });

    test('de-selecting one chip does not silently drop another', () {
      // The case a naive "strip `none` whenever anything else is set" rule gets
      // wrong: nothing was ADDED here, so nothing should be removed on the
      // user's behalf.
      final result = resolveBarrierSelection(
        {TrainingBarrier.time},
        {TrainingBarrier.time, TrainingBarrier.consistency},
      );
      expect(result, [TrainingBarrier.time]);
    });

    test('clearing everything leaves an empty answer, not "none"', () {
      // "Nothing stops me" and "has not answered" are different facts, and the
      // screen must never turn the second into the first.
      expect(resolveBarrierSelection({}, {TrainingBarrier.time}), isEmpty);
    });
  });

  group('selection order', () {
    test('is the enum order, whatever order the chips were tapped', () {
      final tappedBackwards = resolveBarrierSelection(
        {TrainingBarrier.discomfort, TrainingBarrier.exerciseChoice},
        {TrainingBarrier.discomfort},
      );
      expect(tappedBackwards,
          [TrainingBarrier.exerciseChoice, TrainingBarrier.discomfort]);
    });
  });

  group('the barriers step', () {
    test('a barrier alone marks it answered', () {
      const p = UserProfile(
        uid: 'u',
        motivation: MotivationPrefs(barriers: [TrainingBarrier.time]),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.barriers, p), isTrue);
    });

    test('the free-text box still counts — it was not removed', () {
      const p = UserProfile(
        uid: 'u',
        motivation: MotivationPrefs(motivation: 'работа'),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.barriers, p), isTrue);
    });

    test('an untouched screen is not answered', () {
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.barriers, const UserProfile(uid: 'u')),
        isFalse,
      );
    });

    test('barriers round-trip through serialisation', () {
      const p = UserProfile(
        uid: 'u',
        motivation: MotivationPrefs(
          barriers: [TrainingBarrier.machineUse, TrainingBarrier.techniqueDoubt],
        ),
      );
      final json = p.toJson()['motivation'] as Map<String, dynamic>;
      expect(json['barriers'], ['machineUse', 'techniqueDoubt']);
    });
  });
}
