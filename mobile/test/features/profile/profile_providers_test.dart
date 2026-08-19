import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  group('profile providers', () {
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

    test('currentProfileProvider returns null when signed out', () async {
      // A listener keeps the StreamProvider alive long enough for it to emit.
      container.listen(currentProfileProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentProfileProvider).valueOrNull, isNull);
    });

    test('isOnboardedProvider is false for fresh users', () async {
      final user = await auth.signInAnonymously();
      await profiles.save(UserProfile.empty(user.uid));
      // pump
      await Future<void>.delayed(Duration.zero);
      // Read once so the StreamProvider subscribes.
      container.listen(currentProfileProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(isOnboardedProvider), isFalse);
    });

    test('ProfileSubmit.submit stamps completedAt and persists', () async {
      final user = await auth.signInAnonymously();
      final draft = UserProfile.empty(user.uid).copyWith(
        personal: const PersonalInfo(age: 31),
      );

      await container.read(profileSubmitProvider.notifier).submit(draft);

      final saved = await profiles.load(user.uid);
      expect(saved, isNotNull);
      expect(saved!.hasCompletedOnboarding, isTrue);
      expect(saved.personal.age, 31);
      expect(container.read(profileSubmitProvider), isA<AsyncData<void>>());
    });

    test(
        'currentProfileProvider stays loading during the auth-restore '
        'window, never a false null (MVP-1)', () async {
      // A directly-controlled StreamController models a genuine cold start
      // (no emission until the real session resolves) -- MockAuthRepository
      // replays its current user synchronously on listen, which never
      // reproduces this window.
      final authStream = StreamController<AuthUser?>.broadcast();
      addTearDown(authStream.close);
      final localContainer = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => authStream.stream),
        profileRepositoryProvider.overrideWith((ref) {
          ref.onDispose(profiles.dispose);
          return profiles;
        }),
      ]);
      addTearDown(localContainer.dispose);

      final sub = localContainer.listen(currentProfileProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final duringRestore = localContainer.read(currentProfileProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out (no profile)');

      const uid = 'carol';
      await profiles.save(UserProfile.empty(uid).copyWith(
        personal: const PersonalInfo(age: 40),
      ));
      authStream.add(const AuthUser(uid: uid, displayName: 'Carol'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final resolved = localContainer.read(currentProfileProvider).valueOrNull;
      expect(resolved, isNotNull);
      expect(resolved!.personal.age, 40);
    });

    test('ProfileSubmit.saveDraft persists without setting completedAt',
        () async {
      final user = await auth.signInAnonymously();
      final draft = UserProfile.empty(user.uid).copyWith(
        personal: const PersonalInfo(age: 22),
      );

      await container.read(profileSubmitProvider.notifier).saveDraft(draft);

      final saved = await profiles.load(user.uid);
      expect(saved, isNotNull);
      expect(saved!.hasCompletedOnboarding, isFalse);
      expect(saved.personal.age, 22);
    });
  });
}
