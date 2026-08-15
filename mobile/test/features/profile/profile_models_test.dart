import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

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

  group('HealthHistory.screening round-trips, and refuses to guess', () {
    // The screening map is the only field in this reader whose default is
    // load-bearing: `screen()` blocks on a missing key, so anything this
    // function invents becomes a clearance the user never gave.

    test('answers survive a round trip', () {
      const h = HealthHistory(screening: {
        ParQQuestion.chestPain: false,
        ParQQuestion.prescribedMedication: true,
      });
      final back = HealthHistory.fromJson(h.toJson());
      expect(back.screening, h.screening);
    });

    test('a non-bool value is dropped, not coerced', () {
      // Found by mutation: coercing `v == true` passed every test, because no
      // fixture carried a junk value. A string "yes" would have become false —
      // an answer of "no" to a question the user answered YES to, written by
      // the reader rather than by the user.
      final back = HealthHistory.fromJson({
        'screening': {
          'chestPain': 'yes',
          'prescribedMedication': 1,
          'musculoskeletalProblem': null,
          'medicallySupervisedOnly': true,
        },
      });

      expect(back.screening.containsKey(ParQQuestion.chestPain), isFalse,
          reason: 'a value that is not a bool is not an answer');
      expect(back.screening, {ParQQuestion.medicallySupervisedOnly: true});
      expect(screen(back.screening).decision, SafetyDecision.blocked);
    });

    test('an unknown question name is dropped', () {
      // A question this build does not know about cannot have been asked by
      // this build.
      final back = HealthHistory.fromJson({
        'screening': {'pregnancy': false, 'chestPain': false},
      });
      expect(back.screening, {ParQQuestion.chestPain: false});
    });

    test('a missing or malformed block reads as unanswered', () {
      expect(HealthHistory.fromJson(const {}).screening, isEmpty);
      expect(HealthHistory.fromJson(const {'screening': 'nope'}).screening,
          isEmpty);
      expect(HealthHistory.fromJson(const {'screening': []}).screening,
          isEmpty);
    });

    test('a screened profile is not empty', () {
      // `isEmpty` decides whether the locally stored sensitive block wins over
      // the server copy. A profile whose ONLY content is the screening would
      // have lost that comparison and been overwritten by an unscreened one.
      const h = HealthHistory(screening: {ParQQuestion.chestPain: false});
      expect(h.isEmpty, isFalse);
      expect(HealthHistory.empty.isEmpty, isTrue);
    });
  });
}
