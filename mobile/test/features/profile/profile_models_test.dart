import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';

void main() {
  group('UserProfile', () {
    test('empty profile is not onboarded', () {
      final p = UserProfile.empty('uid-1');
      expect(p.uid, 'uid-1');
      expect(p.hasCompletedOnboarding, isFalse);
      expect(p.personal, PersonalInfo.empty);
      expect(p.health, HealthHistory.empty);
      expect(p.goals, FitnessGoals.empty);
      expect(p.level, FitnessLevel.empty);
      expect(p.lifestyle, Lifestyle.empty);
      expect(p.equipment, EquipmentAccess.empty);
      expect(p.motivation, MotivationPrefs.empty);
    });

    test('hasCompletedOnboarding flips when completedAt is set', () {
      final draft = UserProfile.empty('uid-1');
      final completed = draft.copyWith(completedAt: DateTime(2026, 1, 1));
      expect(completed.hasCompletedOnboarding, isTrue);
    });

    test('copyWith only mutates the requested section', () {
      final p = UserProfile.empty('uid-1');
      final next = p.copyWith(
        personal: const PersonalInfo(age: 30, heightCm: 180),
      );
      expect(next.personal.age, 30);
      expect(next.health, HealthHistory.empty);
      expect(next.uid, p.uid);
    });
  });

  group('PersonalInfo.isComplete', () {
    test('false when any required field is missing', () {
      expect(const PersonalInfo().isComplete, isFalse);
      expect(
        const PersonalInfo(
          age: 30,
          gender: Gender.male,
          heightCm: 180,
          // weightCurrentKg missing
          activityLevel: ActivityLevel.active,
        ).isComplete,
        isFalse,
      );
    });

    test('true when all required fields are present (target weight optional)',
        () {
      expect(
        const PersonalInfo(
          age: 30,
          gender: Gender.male,
          heightCm: 180,
          weightCurrentKg: 78,
          activityLevel: ActivityLevel.active,
        ).isComplete,
        isTrue,
      );
    });
  });

  group('FitnessGoals.hasAny', () {
    test('false when nothing is selected', () {
      expect(const FitnessGoals().hasAny, isFalse);
    });
    test('true when any boolean flag is on', () {
      expect(const FitnessGoals(weightLoss: true).hasAny, isTrue);
      expect(const FitnessGoals(strength: true).hasAny, isTrue);
    });
    test('true when specificSport is set', () {
      expect(const FitnessGoals(specificSport: 'tennis').hasAny, isTrue);
    });
    test('false when specificSport is empty string', () {
      expect(const FitnessGoals(specificSport: '').hasAny, isFalse);
    });
  });

  group('Injury equality', () {
    test('two injuries with the same body part + type are equal', () {
      const a = Injury(bodyPart: 'knee', type: 'meniscus');
      const b = Injury(bodyPart: 'knee', type: 'meniscus');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
