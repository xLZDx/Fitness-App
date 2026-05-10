import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/subscription_models.dart';

void main() {
  group('SubscriptionPeriod', () {
    test('seatCount per period', () {
      expect(SubscriptionPeriod.monthly.seatCount, 1);
      expect(SubscriptionPeriod.annual.seatCount, 1);
      expect(SubscriptionPeriod.family2.seatCount, 2);
      expect(SubscriptionPeriod.family4.seatCount, 4);
      expect(SubscriptionPeriod.lifetime.seatCount, 1);
    });

    test('isOneTime is true only for lifetime', () {
      expect(SubscriptionPeriod.monthly.isOneTime, isFalse);
      expect(SubscriptionPeriod.annual.isOneTime, isFalse);
      expect(SubscriptionPeriod.family2.isOneTime, isFalse);
      expect(SubscriptionPeriod.lifetime.isOneTime, isTrue);
    });

    test('display labels', () {
      expect(SubscriptionPeriod.monthly.displayLabel, 'Monthly');
      expect(SubscriptionPeriod.annual.displayLabel, 'Annual');
      expect(SubscriptionPeriod.family2.displayLabel, 'Family · 2 seats');
      expect(SubscriptionPeriod.family4.displayLabel, 'Family · 4 seats');
      expect(SubscriptionPeriod.lifetime.displayLabel, 'Lifetime');
    });
  });

  group('Subscription JSON round-trip with period', () {
    test('annual subscription preserved through toJson/fromJson', () {
      final original = Subscription(
        uid: 'u1',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.active,
        period: SubscriptionPeriod.annual,
        seatCount: 1,
        currentPeriodEndsAt: DateTime.utc(2027, 5, 1),
      );
      final back = Subscription.fromJson('u1', original.toJson());
      expect(back.period, SubscriptionPeriod.annual);
      expect(back.seatCount, 1);
      expect(back.tier, SubscriptionTier.standard);
    });

    test('lifetime subscription has isLifetime=true', () {
      final original = Subscription(
        uid: 'u1',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.active,
        period: SubscriptionPeriod.lifetime,
        isLifetime: true,
      );
      final back = Subscription.fromJson('u1', original.toJson());
      expect(back.isLifetime, isTrue);
      expect(back.period, SubscriptionPeriod.lifetime);
    });

    test('family plan preserves seatedUids list', () {
      final original = Subscription(
        uid: 'owner',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.active,
        period: SubscriptionPeriod.family4,
        seatCount: 4,
        seatedUids: const ['owner', 'spouse', 'kid1'],
      );
      final back = Subscription.fromJson('owner', original.toJson());
      expect(back.seatedUids, ['owner', 'spouse', 'kid1']);
      expect(back.seatCount, 4);
    });

    test('legacy doc with no period field defaults to monthly', () {
      final back = Subscription.fromJson('u1', const {
        'tier': 'standard',
        'status': 'active',
      });
      expect(back.period, SubscriptionPeriod.monthly);
      expect(back.seatCount, 1);
      expect(back.isLifetime, isFalse);
    });
  });
}
