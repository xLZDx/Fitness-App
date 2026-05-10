import 'subscription_models.dart';

/// Bridge between the app's [SubscriptionAction] and the Cloud Functions
/// subscription backend. Production uses [CloudFunctionsStripeService];
/// the default Riverpod provider injects a mock so tests stay
/// plugin-free.
///
/// The name is historical — Stripe is one of three backend operations
/// the service brokers (the trial-start path doesn't touch Stripe at
/// all). It still goes through this service because Firestore rules deny
/// client writes to the subscription doc, so any state change has to
/// route through a server handler.
abstract class StripeCheckoutService {
  /// Asks the backend to record a 14-day trial for [tier]. The Cloud
  /// Function writes the subscription doc; the StreamProvider chain
  /// emits the new state seconds later.
  ///
  /// Throws [StripeCheckoutException] when the backend declines (e.g.
  /// the user already used their trial).
  Future<void> startFreeTrial(SubscriptionTier tier);

  /// Asks the backend for a Stripe Checkout URL for [tier] + [period]
  /// and opens it (browser / Custom Tab). The webhook updates the
  /// Firestore record once the user completes payment, so callers don't
  /// need a return path — they just listen to
  /// `currentSubscriptionProvider`.
  ///
  /// [period] defaults to monthly so existing call sites stay green.
  ///
  /// Throws [StripeCheckoutException] when the backend declines or the
  /// URL fails to launch.
  Future<void> startCheckout(
    SubscriptionTier tier, {
    SubscriptionPeriod period = SubscriptionPeriod.monthly,
  });

  /// Opens the Stripe Customer Portal so the user can change plan or
  /// cancel. Behaviour mirrors [startCheckout].
  Future<void> openCustomerPortal();
}

class StripeCheckoutException implements Exception {
  StripeCheckoutException(this.message);
  final String message;
  @override
  String toString() => 'StripeCheckoutException: $message';
}
