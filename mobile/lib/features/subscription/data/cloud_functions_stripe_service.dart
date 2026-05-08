import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import 'stripe_checkout_service.dart';
import 'subscription_models.dart';

/// Production implementation. Calls the `createCheckoutSession` /
/// `createPortalSession` Cloud Functions, then opens the returned URL in
/// an external browser (Custom Tab on Android, SFSafariViewController on
/// iOS — both managed by `url_launcher`).
class CloudFunctionsStripeService implements StripeCheckoutService {
  CloudFunctionsStripeService({
    FirebaseFunctions? functions,
    Future<bool> Function(Uri uri)? launcher,
  })  : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _launcher = launcher ??
            ((uri) =>
                launchUrl(uri, mode: LaunchMode.externalApplication));

  final FirebaseFunctions _functions;
  final Future<bool> Function(Uri uri) _launcher;

  String _tierParam(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.standard:
        return 'standard';
      case SubscriptionTier.celebrityTrainer:
        return 'celebrityTrainer';
      case SubscriptionTier.free:
        throw StripeCheckoutException(
          'Free tier does not require Stripe checkout.',
        );
    }
  }

  @override
  Future<void> startFreeTrial(SubscriptionTier tier) async {
    final callable = _functions.httpsCallable('startFreeTrial');
    try {
      await callable.call<Map<String, dynamic>>({
        'tier': _tierParam(tier),
      });
    } on Exception catch (e) {
      throw StripeCheckoutException('Could not start trial: $e');
    }
  }

  @override
  Future<void> startCheckout(SubscriptionTier tier) async {
    final callable = _functions.httpsCallable('createCheckoutSession');
    final result = await callable.call<Map<String, dynamic>>({
      'tier': _tierParam(tier),
    });
    final url = result.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StripeCheckoutException('Backend returned no checkout URL.');
    }
    final ok = await _launcher(Uri.parse(url));
    if (!ok) {
      throw StripeCheckoutException(
        'Could not open the Stripe checkout page.',
      );
    }
  }

  @override
  Future<void> openCustomerPortal() async {
    final callable = _functions.httpsCallable('createPortalSession');
    final result = await callable.call<Map<String, dynamic>>();
    final url = result.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StripeCheckoutException('Backend returned no portal URL.');
    }
    final ok = await _launcher(Uri.parse(url));
    if (!ok) {
      throw StripeCheckoutException(
        'Could not open the Stripe customer portal.',
      );
    }
  }
}
