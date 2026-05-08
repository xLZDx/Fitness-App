import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  group('QuestionnaireDraft', () {
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

    test('builds an empty draft when no profile has been saved yet', () async {
      final user = await auth.signInAnonymously();
      // Materialise the auth stream so the draft sees the uid.
      container.listen(authUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      final draft = container.read(questionnaireDraftProvider);
      expect(draft.uid, user.uid);
      expect(draft.hasCompletedOnboarding, isFalse);
      expect(draft.personal, PersonalInfo.empty);
    });

    test('hydrates from a cached profile if one exists', () async {
      final user = await auth.signInAnonymously();
      await profiles.save(UserProfile.empty(user.uid).copyWith(
        personal: const PersonalInfo(age: 42),
      ));
      container.listen(authUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      final draft = container.read(questionnaireDraftProvider);
      expect(draft.personal.age, 42);
    });

    test('saveDraft persists the current state without completing it',
        () async {
      final user = await auth.signInAnonymously();
      container.listen(authUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      container
          .read(questionnaireDraftProvider.notifier)
          .updatePersonal((p) => p.copyWith(age: 25));

      await container.read(questionnaireDraftProvider.notifier).saveDraft();

      final stored = await profiles.load(user.uid);
      expect(stored, isNotNull);
      expect(stored!.personal.age, 25);
      expect(stored.hasCompletedOnboarding, isFalse);
    });

    test('section update helpers only mutate that section', () async {
      await auth.signInAnonymously();
      container.listen(authUserProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      container.read(questionnaireDraftProvider.notifier)
        ..updatePersonal((p) => p.copyWith(age: 30))
        ..updateGoals((g) => g.copyWith(weightLoss: true))
        ..updateLevel((s) => s.copyWith(frequencyPerWeek: 4));

      final s = container.read(questionnaireDraftProvider);
      expect(s.personal.age, 30);
      expect(s.goals.weightLoss, isTrue);
      expect(s.level.frequencyPerWeek, 4);
      expect(s.health, HealthHistory.empty);
    });
  });
}
