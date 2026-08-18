import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/subscription/data/feature_gates.dart';
import 'package:fitness_app/features/subscription/data/mock_stripe_checkout_service.dart';
import 'package:fitness_app/features/subscription/data/mock_subscription_repository.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

class _Container {
  _Container({
    required this.container,
    required this.repo,
    required this.stripe,
  });
  final ProviderContainer container;
  final MockSubscriptionRepository repo;
  final MockStripeCheckoutService stripe;
}

_Container _setup({AuthUser? user}) {
  final repo = MockSubscriptionRepository(latency: Duration.zero);
  final stripe = MockStripeCheckoutService();
  final container = ProviderContainer(overrides: [
    subscriptionRepositoryProvider.overrideWithValue(repo),
    stripeCheckoutServiceProvider.overrideWithValue(stripe),
    authUserProvider.overrideWith((_) => Stream.value(user)),
  ]);
  return _Container(container: container, repo: repo, stripe: stripe);
}

void main() {
  group('currentSubscriptionProvider', () {
    test('emits null when signed out', () async {
      final s = _setup(user: null);
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);

      await s.container.read(authUserProvider.future);
      expect(
        await s.container.read(currentSubscriptionProvider.future),
        isNull,
      );
    });

    test('streams the signed-in user record', () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 5)),
      ));

      await s.container.read(authUserProvider.future);
      final out =
          await s.container.read(currentSubscriptionProvider.future);
      expect(out, isNotNull);
      expect(out!.tier, SubscriptionTier.standard);
      expect(out.status, SubscriptionStatus.trial);
    });
  });

  group('effectiveTierProvider + featureAccessProvider', () {
    test('signed-out user resolves to free + locked premium features',
        () async {
      final s = _setup(user: null);
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);

      await s.container.read(authUserProvider.future);
      await s.container.read(currentSubscriptionProvider.future);

      expect(s.container.read(effectiveTierProvider), SubscriptionTier.free);
      expect(
        s.container.read(featureAccessProvider(AppFeature.workoutScheduling)),
        isFalse,
      );
      expect(
        s.container.read(featureAccessProvider(AppFeature.basicLogging)),
        isTrue,
      );
    });

    test('active trial unlocks the chosen tier', () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 3)),
      ));

      await s.container.read(authUserProvider.future);
      await s.container.read(currentSubscriptionProvider.future);

      expect(s.container.read(effectiveTierProvider),
          SubscriptionTier.celebrityTrainer);
      expect(
        s.container.read(featureAccessProvider(AppFeature.aiCoach)),
        isTrue,
      );
    });
  });

  group('subscriptionActionProvider', () {
    test('startTrial delegates to the backend service (no client write)',
        () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.container.read(authUserProvider.future);

      await s.container
          .read(subscriptionActionProvider.notifier)
          .startTrial(SubscriptionTier.standard);

      // The Cloud Function writes the trial record server-side; the
      // local repo stays empty until the StreamProvider picks up the
      // server emission.
      expect(s.stripe.startedTrials, [SubscriptionTier.standard]);
      expect(s.repo.cached('alice'), isNull);
      expect(
        s.container.read(subscriptionActionProvider).hasValue,
        isTrue,
      );
    });

    test('chooseTier on a paid tier delegates to Stripe (no local write)',
        () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.container.read(authUserProvider.future);

      await s.container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.celebrityTrainer);

      // Stripe handed the URL launch — webhook will mirror state later.
      expect(s.stripe.startedCheckouts, [SubscriptionTier.celebrityTrainer]);
      // No client-side write for paid tiers.
      expect(s.repo.cached('alice'), isNull);
      expect(
        s.container.read(subscriptionActionProvider).hasValue,
        isTrue,
      );
    });

    test('a refused checkout surfaces as an error, never as success', () async {
      // The state layer is where a refusal could be lost most quietly: set
      // `AsyncValue.data(null)` in the catch and the card shows nothing at
      // all, so a guest who tapped Subscribe watches the button spin and
      // settle with no subscription and no explanation. The screen's copy
      // tests cannot see this -- they start from an error that already
      // exists.
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.container.read(authUserProvider.future);
      s.stripe.failWith = Exception('backend refused');

      await s.container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.celebrityTrainer);

      final action = s.container.read(subscriptionActionProvider);
      expect(action.hasError, isTrue,
          reason: 'a refused checkout reported as success');
      expect(action.hasValue, isFalse);
      expect(s.repo.cached('alice'), isNull,
          reason: 'a failed checkout must not grant anything locally');
    });

    test('chooseTier on free is a no-op (use the portal to downgrade)',
        () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.container.read(authUserProvider.future);

      await s.container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.free);

      expect(s.stripe.startedCheckouts, isEmpty);
      // Firestore rules forbid client writes; nothing should land
      // locally either.
      expect(s.repo.cached('alice'), isNull);
      expect(
        s.container.read(subscriptionActionProvider).hasValue,
        isTrue,
      );
    });

    test('chooseTier surfaces stripe failures as AsyncValue errors',
        () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      s.stripe.failWith = Exception('boom');
      await s.container.read(authUserProvider.future);

      await s.container
          .read(subscriptionActionProvider.notifier)
          .chooseTier(SubscriptionTier.standard);

      final state = s.container.read(subscriptionActionProvider);
      expect(state.hasError, isTrue);
    });

    test('cancel opens the customer portal (no local write)', () async {
      final s = _setup(
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.repo.save(Subscription(
        uid: 'alice',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.active,
        currentPeriodEndsAt: DateTime.now().add(const Duration(days: 10)),
      ));
      await s.container.read(authUserProvider.future);

      await s.container.read(subscriptionActionProvider.notifier).cancel();

      expect(s.stripe.portalOpens, 1);
      // Status stays untouched until the webhook fires
      // customer.subscription.deleted.
      final saved = s.repo.cached('alice')!;
      expect(saved.status, SubscriptionStatus.active);
    });

    test('errors when no user is signed in', () async {
      final s = _setup(user: null);
      addTearDown(s.repo.dispose);
      addTearDown(s.container.dispose);
      await s.container.read(authUserProvider.future);

      await s.container
          .read(subscriptionActionProvider.notifier)
          .startTrial(SubscriptionTier.standard);

      final state = s.container.read(subscriptionActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    });
  });
}
