import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/subscription/data/feature_gates.dart';
import 'package:fitness_app/features/subscription/data/mock_subscription_repository.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

ProviderContainer _container({
  required MockSubscriptionRepository repo,
  AuthUser? user,
}) =>
    ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
      authUserProvider.overrideWith((_) => Stream.value(user)),
    ]);

void main() {
  group('currentSubscriptionProvider', () {
    test('emits null when signed out', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      expect(await container.read(currentSubscriptionProvider.future), isNull);
    });

    test('streams the signed-in user record', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 5)),
      ));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final out = await container.read(currentSubscriptionProvider.future);
      expect(out, isNotNull);
      expect(out!.tier, SubscriptionTier.standard);
      expect(out.status, SubscriptionStatus.trial);
    });
  });

  group('effectiveTierProvider + featureAccessProvider', () {
    test('signed-out user resolves to free + locked premium features',
        () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      // Settle the subscription stream to data(null) so the providers
      // depending on it are stable.
      await container.read(currentSubscriptionProvider.future);

      expect(container.read(effectiveTierProvider), SubscriptionTier.free);
      expect(
        container.read(featureAccessProvider(AppFeature.workoutScheduling)),
        isFalse,
      );
      expect(
        container.read(featureAccessProvider(AppFeature.basicLogging)),
        isTrue,
      );
    });

    test('active trial unlocks the chosen tier', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 3)),
      ));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      await container.read(currentSubscriptionProvider.future);

      expect(container.read(effectiveTierProvider),
          SubscriptionTier.celebrityTrainer);
      expect(
        container.read(featureAccessProvider(AppFeature.aiCoach)),
        isTrue,
      );
    });
  });

  group('subscriptionActionProvider', () {
    test('startTrial writes a trial record with a trialEndsAt window',
        () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final before = DateTime.now();
      await container
          .read(subscriptionActionProvider.notifier)
          .startTrial(SubscriptionTier.standard);
      final after = DateTime.now();

      final saved = repo.cached('alice');
      expect(saved, isNotNull);
      expect(saved!.tier, SubscriptionTier.standard);
      expect(saved.status, SubscriptionStatus.trial);
      expect(saved.trialEndsAt, isNotNull);
      // Trial ends ~14 days from now.
      expect(
        saved.trialEndsAt!.difference(before).inDays,
        greaterThanOrEqualTo(13),
      );
      expect(
        saved.trialEndsAt!.difference(after).inDays,
        lessThanOrEqualTo(14),
      );
    });

    test('chooseTier on a paid tier writes active + 30-day window', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.celebrityTrainer);

      final saved = repo.cached('alice')!;
      expect(saved.status, SubscriptionStatus.active);
      expect(saved.tier, SubscriptionTier.celebrityTrainer);
      expect(saved.currentPeriodEndsAt, isNotNull);
    });

    test('chooseTier on free clears the period and stamps none', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.free);

      final saved = repo.cached('alice')!;
      expect(saved.tier, SubscriptionTier.free);
      expect(saved.status, SubscriptionStatus.none);
      expect(saved.currentPeriodEndsAt, isNull);
    });

    test('cancel marks the existing record as cancelled', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.active,
        currentPeriodEndsAt: DateTime.now().add(const Duration(days: 10)),
      ));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container.read(subscriptionActionProvider.notifier).cancel();

      final saved = repo.cached('alice')!;
      expect(saved.status, SubscriptionStatus.cancelled);
      expect(saved.tier, SubscriptionTier.standard);
      // The 10-day window remains until period end.
      expect(saved.currentPeriodEndsAt, isNotNull);
    });

    test('cancel is a no-op when there is no existing record', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container.read(subscriptionActionProvider.notifier).cancel();

      expect(container.read(subscriptionActionProvider).hasValue, isTrue);
      expect(repo.cached('alice'), isNull);
    });

    test('errors when no user is signed in', () async {
      final repo = MockSubscriptionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(subscriptionActionProvider.notifier)
          .startTrial(SubscriptionTier.standard);

      final state = container.read(subscriptionActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    });
  });
}
