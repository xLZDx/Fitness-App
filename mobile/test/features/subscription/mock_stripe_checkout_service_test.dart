import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/mock_stripe_checkout_service.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';

void main() {
  group('MockStripeCheckoutService', () {
    late MockStripeCheckoutService svc;

    setUp(() => svc = MockStripeCheckoutService());

    test('startFreeTrial records the requested tier', () async {
      await svc.startFreeTrial(SubscriptionTier.standard);
      await svc.startFreeTrial(SubscriptionTier.celebrityTrainer);
      expect(svc.startedTrials, [
        SubscriptionTier.standard,
        SubscriptionTier.celebrityTrainer,
      ]);
    });

    test('startCheckout records the requested tier', () async {
      await svc.startCheckout(SubscriptionTier.standard);
      await svc.startCheckout(SubscriptionTier.celebrityTrainer);
      expect(svc.startedCheckouts, [
        SubscriptionTier.standard,
        SubscriptionTier.celebrityTrainer,
      ]);
    });

    test('openCustomerPortal increments the call counter', () async {
      await svc.openCustomerPortal();
      await svc.openCustomerPortal();
      expect(svc.portalOpens, 2);
    });

    test('failWith surfaces from both methods', () async {
      svc.failWith = Exception('declined');

      expect(
        () => svc.startCheckout(SubscriptionTier.standard),
        throwsException,
      );
      expect(() => svc.openCustomerPortal(), throwsException);
    });

    test('reset clears observed calls + failure', () async {
      svc.failWith = Exception('declined');
      svc.startedCheckouts.add(SubscriptionTier.standard);
      svc.startedTrials.add(SubscriptionTier.standard);
      svc.portalOpens = 3;

      svc.reset();

      expect(svc.failWith, isNull);
      expect(svc.startedCheckouts, isEmpty);
      expect(svc.startedTrials, isEmpty);
      expect(svc.portalOpens, 0);
    });
  });
}
