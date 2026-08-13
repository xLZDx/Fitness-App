import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// O5 — the schedule screen.
///
/// The screen itself is three chip rows and is not what can go wrong. What can
/// go wrong is the two derivations underneath it: the coarse duration bucket
/// the rest of the app still reads, and the step-answered rule that decides
/// which screen a returning user lands on. Both are asserted here directly,
/// without pumping a widget.
void main() {
  group('TrainingSchedule.durationBucket', () {
    // The whole reason minutes are stored instead of the bucket: 45 is named in
    // TWO buckets, so a bucket-only answer cannot say which one was meant.
    test('45 minutes lands in m30to45, the bucket named for containing it', () {
      expect(
        const TrainingSchedule(sessionMinutes: 45).durationBucket,
        WorkoutDuration.m30to45,
      );
    });

    test('60 minutes lands in m45to60 for the same reason', () {
      expect(
        const TrainingSchedule(sessionMinutes: 60).durationBucket,
        WorkoutDuration.m45to60,
      );
    });

    test('the three unambiguous options map as written', () {
      expect(const TrainingSchedule(sessionMinutes: 30).durationBucket,
          WorkoutDuration.m15to30);
      expect(const TrainingSchedule(sessionMinutes: 75).durationBucket,
          WorkoutDuration.over60);
      expect(const TrainingSchedule(sessionMinutes: 90).durationBucket,
          WorkoutDuration.over60);
    });

    test('an unanswered schedule derives nothing rather than a default', () {
      // A default here would be indistinguishable from a real answer of the
      // same value, which is the failure `hasGymAccess` was written to avoid.
      expect(TrainingSchedule.empty.durationBucket, isNull);
    });
  });

  group('the schedule is not the current-frequency field', () {
    test('planned days and current frequency are stored separately', () {
      const profile = UserProfile(
        uid: 'u',
        level: FitnessLevel(frequencyPerWeek: 2),
        schedule: TrainingSchedule(daysPerWeek: 5),
      );
      // "Trains twice, intends five" has to stay readable as two facts. Folding
      // them into one field loses the ramp a plan generator would size.
      expect(profile.level.frequencyPerWeek, 2);
      expect(profile.schedule.daysPerWeek, 5);
    });
  });

  group('isOnboardingStepAnswered', () {
    test('any one of the three answers marks the schedule step touched', () {
      for (final p in <UserProfile>[
        const UserProfile(uid: 'u', schedule: TrainingSchedule(daysPerWeek: 3)),
        const UserProfile(
            uid: 'u', schedule: TrainingSchedule(sessionMinutes: 45)),
        const UserProfile(
            uid: 'u',
            schedule: TrainingSchedule(preferredWeekdays: [DateTime.monday])),
      ]) {
        expect(isOnboardingStepAnswered(OnboardingStep.schedule, p), isTrue);
      }
    });

    test('an untouched schedule is not answered', () {
      expect(
        isOnboardingStepAnswered(
            OnboardingStep.schedule, const UserProfile(uid: 'u')),
        isFalse,
      );
    });

    test('a derived duration no longer marks the BARRIERS step answered', () {
      // The regression this guards: the duration bucket is now written as a
      // side effect of answering the schedule. If motivation still counted it,
      // answering one screen would silently mark a different one done and the
      // resume point would skip past a screen the user never saw.
      const p = UserProfile(
        uid: 'u',
        motivation: MotivationPrefs(preferredDuration: WorkoutDuration.m30to45),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.barriers, p), isFalse);
    });

    test('the schedule step sits right after equipment in the flow', () {
      expect(
        kOnboardingOrder.indexOf(OnboardingStep.schedule),
        kOnboardingOrder.indexOf(OnboardingStep.equipment) + 1,
      );
    });
  });

  group('QuestionnaireDraft.updateSchedule', () {
    ProviderContainer makeContainer() {
      final repo = MockProfileRepository(latency: Duration.zero);
      final container = ProviderContainer(overrides: [
        profileRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('keeps the coarse bucket in step with the exact minutes', () {
      final container = makeContainer();
      final notifier = container.read(questionnaireDraftProvider.notifier);

      notifier.updateSchedule((s) => s.copyWith(sessionMinutes: 45));

      final state = container.read(questionnaireDraftProvider);
      expect(state.schedule.sessionMinutes, 45);
      // The bucket is what `suggestion_builder.dart:135` reads. Leaving it null
      // would make every existing reader see "no preference" for a user who
      // just stated one.
      expect(state.motivation.preferredDuration, WorkoutDuration.m30to45);
    });

    test('re-answering moves the bucket too, it does not stick', () {
      final container = makeContainer();
      final notifier = container.read(questionnaireDraftProvider.notifier);

      notifier.updateSchedule((s) => s.copyWith(sessionMinutes: 30));
      notifier.updateSchedule((s) => s.copyWith(sessionMinutes: 90));

      expect(
        container.read(questionnaireDraftProvider).motivation.preferredDuration,
        WorkoutDuration.over60,
      );
    });

    test('answering only the days leaves an existing bucket alone', () {
      final container = makeContainer();
      final notifier = container.read(questionnaireDraftProvider.notifier);

      // A profile that predates O5 can carry a bucket and no minutes. Blanking
      // it because the user touched a different control on the screen would
      // discard an answer they gave and never revisited.
      notifier.updateMotivation(
          (m) => m.copyWith(preferredDuration: WorkoutDuration.under15));
      notifier.updateSchedule((s) => s.copyWith(daysPerWeek: 4));

      final state = container.read(questionnaireDraftProvider);
      expect(state.schedule.daysPerWeek, 4);
      expect(state.schedule.sessionMinutes, isNull);
      expect(state.motivation.preferredDuration, WorkoutDuration.under15);
    });
  });

  group('serialisation', () {
    test('the schedule survives a round trip through toJson', () {
      const profile = UserProfile(
        uid: 'u',
        schedule: TrainingSchedule(
          daysPerWeek: 4,
          sessionMinutes: 75,
          preferredWeekdays: [DateTime.monday, DateTime.thursday],
        ),
      );
      final json = profile.toJson()['schedule'] as Map<String, dynamic>;
      expect(json['daysPerWeek'], 4);
      expect(json['sessionMinutes'], 75);
      expect(json['preferredWeekdays'], [DateTime.monday, DateTime.thursday]);
    });

    test('a profile with no schedule still serialises the block', () {
      // Written as nulls rather than omitted: a reader that expects the key can
      // tell "not answered" from "this app version does not have the field".
      final json =
          const UserProfile(uid: 'u').toJson()['schedule'] as Map<String, dynamic>;
      expect(json.containsKey('daysPerWeek'), isTrue);
      expect(json['daysPerWeek'], isNull);
      expect(json['preferredWeekdays'], isEmpty);
    });
  });
}
