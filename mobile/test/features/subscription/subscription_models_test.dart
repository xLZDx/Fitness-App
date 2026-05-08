import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/subscription_models.dart';

void main() {
  group('Subscription', () {
    final sub = Subscription(
      uid: 'u1',
      tier: SubscriptionTier.standard,
      status: SubscriptionStatus.trial,
      trialEndsAt: DateTime.utc(2026, 5, 22),
    );

    test('toJson/fromJson round-trips losslessly', () {
      final restored = Subscription.fromJson('u1', sub.toJson());
      expect(restored, sub);
    });

    test('toJson omits null timestamps', () {
      final empty = Subscription.emptyFor('u1');
      final json = empty.toJson();
      expect(json.containsKey('trialEndsAt'), isFalse);
      expect(json.containsKey('currentPeriodEndsAt'), isFalse);
      expect(json['tier'], 'free');
      expect(json['status'], 'none');
    });

    test('fromJson defaults unknown enums to free/none', () {
      final s = Subscription.fromJson('u1', const {
        'tier': 'mystery',
        'status': 'mystery',
      });
      expect(s.tier, SubscriptionTier.free);
      expect(s.status, SubscriptionStatus.none);
    });

    test('copyWith respects clearTrial / clearPeriod flags', () {
      final cleared = sub.copyWith(clearTrial: true);
      expect(cleared.trialEndsAt, isNull);
      expect(cleared.tier, sub.tier);
    });
  });

  group('effectiveTier', () {
    final base = DateTime(2026, 5, 8, 12);

    test('null subscription resolves to free', () {
      expect(effectiveTier(null, now: base), SubscriptionTier.free);
    });

    test('empty subscription resolves to free', () {
      expect(
        effectiveTier(Subscription.emptyFor('u'), now: base),
        SubscriptionTier.free,
      );
    });

    test('active trial keeps the chosen tier', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.trial,
        trialEndsAt: base.add(const Duration(days: 3)),
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.standard);
    });

    test('lapsed trial drops to free regardless of stored tier', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.trial,
        trialEndsAt: base.subtract(const Duration(days: 1)),
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.free);
    });

    test('active paid period keeps tier', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.active,
        currentPeriodEndsAt: base.add(const Duration(days: 5)),
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.celebrityTrainer);
    });

    test('cancelled but inside the paid period keeps tier', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.cancelled,
        currentPeriodEndsAt: base.add(const Duration(days: 5)),
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.standard);
    });

    test('cancelled past the period drops to free', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.cancelled,
        currentPeriodEndsAt: base.subtract(const Duration(days: 1)),
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.free);
    });

    test('expired status always drops to free', () {
      final sub = Subscription(
        uid: 'u',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.expired,
      );
      expect(effectiveTier(sub, now: base), SubscriptionTier.free);
    });
  });
}
