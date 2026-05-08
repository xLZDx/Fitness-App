import 'subscription_models.dart';

/// Bridge between the app's [SubscriptionAction] and the Cloud Functions
/// Stripe backend. Production uses [CloudFunctionsStripeService]; the
/// default Riverpod provider injects a mock so tests stay plugin-free.
abstract class StripeCheckoutService {
  /// Asks the backend for a Stripe Checkout URL for [tier] and opens it
  /// (browser / Custom Tab). The webhook updates the Firestore record once
  /// the user completes payment, so callers don't need a return path —
  /// they just listen to `currentSubscriptionProvider`.
  ///
  /// Throws [StripeCheckoutException] when the backend declines or the
  /// URL fails to launch.
  Future<void> startCheckout(SubscriptionTier tier);

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
