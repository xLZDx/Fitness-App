import 'stripe_checkout_service.dart';
import 'subscription_models.dart';

/// In-memory `StripeCheckoutService` used as the default provider value
/// and as the test stand-in. Records every call so tests can assert on
/// what the UI triggered without an HTTP round-trip.
class MockStripeCheckoutService implements StripeCheckoutService {
  /// Override to simulate a backend failure.
  Exception? failWith;

  /// Calls observed since construction; cleared by [reset].
  final List<SubscriptionTier> startedCheckouts = [];
  final List<SubscriptionPeriod> checkoutPeriods = [];
  final List<SubscriptionTier> startedTrials = [];
  int portalOpens = 0;

  void reset() {
    startedCheckouts.clear();
    checkoutPeriods.clear();
    startedTrials.clear();
    portalOpens = 0;
    failWith = null;
  }

  @override
  Future<void> startFreeTrial(SubscriptionTier tier) async {
    if (failWith != null) throw failWith!;
    startedTrials.add(tier);
  }

  @override
  Future<void> startCheckout(
    SubscriptionTier tier, {
    SubscriptionPeriod period = SubscriptionPeriod.monthly,
  }) async {
    if (failWith != null) throw failWith!;
    startedCheckouts.add(tier);
    checkoutPeriods.add(period);
  }

  @override
  Future<void> openCustomerPortal() async {
    if (failWith != null) throw failWith!;
    portalOpens++;
  }
}
