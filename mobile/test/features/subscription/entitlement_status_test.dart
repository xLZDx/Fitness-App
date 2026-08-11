import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/data/subscription_repository.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

/// P1d — the difference between "you have no plan" and "we do not know yet".
///
/// `effectiveTierProvider` must return a concrete tier for 38 call sites, so
/// loading, error and genuinely-free all arrive as `free`. That is the right
/// default for LOCKING a feature and the wrong one for OFFERING to sell one:
/// a locked button that unlocks a moment later is a flicker, while a paywall
/// shown to somebody who already pays is the product telling a paying
/// customer they have not paid.

/// Auth that never emits, i.e. a cold start mid-flight.
class _PendingAuth implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  AuthUser? get currentUser => null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SignedInAuth implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(uid: 'u1', displayName: 'U'));

  @override
  AuthUser? get currentUser => const AuthUser(uid: 'u1', displayName: 'U');

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A subscription store whose stream the test drives by hand.
class _ControlledSubs implements SubscriptionRepository {
  final controller = StreamController<Subscription?>.broadcast();

  @override
  Stream<Subscription?> watch(String uid) => controller.stream;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _ControlledSubs subs;

  ProviderContainer containerWith(AuthRepository auth) {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      subscriptionRepositoryProvider.overrideWithValue(subs),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => subs = _ControlledSubs());
  tearDown(() => subs.controller.close());

  test('a cold start is "resolving", not "free"', () async {
    // The exact defect: `.valueOrNull` on a StreamProvider that has not
    // emitted is null, which used to be indistinguishable from signed-out,
    // which resolved to the free tier and showed the paywall.
    final c = containerWith(_PendingAuth());

    expect(c.read(entitlementStatusProvider), EntitlementStatus.resolving);
  });

  test('still resolving while auth is known but the plan has not arrived',
      () async {
    final c = containerWith(_SignedInAuth());
    c.listen(currentSubscriptionProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    expect(c.read(entitlementStatusProvider), EntitlementStatus.resolving);
  });

  test('a delivered plan resolves, and the tier is the paid one', () async {
    final c = containerWith(_SignedInAuth());
    c.listen(currentSubscriptionProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    subs.controller.add(Subscription(
      uid: 'u1',
      tier: SubscriptionTier.standard,
      status: SubscriptionStatus.active,
      currentPeriodEndsAt: DateTime.now().add(const Duration(days: 30)),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(entitlementStatusProvider), EntitlementStatus.resolved);
    expect(c.read(effectiveTierProvider), SubscriptionTier.standard);
  });

  test('a genuinely free user resolves to free, and that is a real answer',
      () async {
    // The case that MUST still show the plan picker. If this went to
    // `resolving`, the fix would have broken the product's only sales page.
    final c = containerWith(_SignedInAuth());
    c.listen(currentSubscriptionProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    subs.controller.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(entitlementStatusProvider), EntitlementStatus.resolved);
    expect(c.read(effectiveTierProvider), SubscriptionTier.free);
  });

  test('a failed stream is "unavailable", never a silent downgrade', () async {
    final c = containerWith(_SignedInAuth());
    c.listen(currentSubscriptionProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    subs.controller.addError(StateError('firestore unavailable'));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(entitlementStatusProvider), EntitlementStatus.unavailable);
  });

  test('an error after a known plan keeps the plan, and says it is stale',
      () async {
    // The worst version of the bug: a paying user goes offline for a moment
    // and the app both downgrades them AND offers to sell them what they
    // already have.
    final c = containerWith(_SignedInAuth());
    c.listen(currentSubscriptionProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    subs.controller.add(Subscription(
      uid: 'u1',
      tier: SubscriptionTier.celebrityTrainer,
      status: SubscriptionStatus.active,
      currentPeriodEndsAt: DateTime.now().add(const Duration(days: 30)),
    ));
    await Future<void>.delayed(Duration.zero);
    subs.controller.addError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(entitlementStatusProvider), EntitlementStatus.unavailable);
    expect(c.read(effectiveTierProvider), SubscriptionTier.celebrityTrainer,
        reason: 'a transient read failure must not revoke a paid tier');
  });
}
