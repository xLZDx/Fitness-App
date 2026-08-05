import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    FirebaseAuth? auth,
    Future<bool> Function(Uri uri)? launcher,
  })  : _functions =
            functions ?? functionsForRegion,
        _auth = auth ?? FirebaseAuth.instance,
        _launcher = launcher ??
            ((uri) =>
                launchUrl(uri, mode: LaunchMode.externalApplication));

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
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

  /// Ensures a usable ID token before any backend call.
  ///
  /// The original problem is real: a user bouncing out to Stripe Checkout in
  /// an external browser and back can return with a token the SDK has not
  /// caught up on, and `cloud_functions` surfaces that as
  /// `firebase_functions/unauthenticated`.
  ///
  /// The original fix was `getIdToken(true)` on every call, which bypasses the
  /// SDK's cache unconditionally. That turned every subscribe, trial, portal
  /// and report tap into two round trips against two different Google
  /// services, one of them a shared token endpoint — on the conversion path,
  /// and concentrated at exactly the moments a promotion sends everyone
  /// through it at once. It also failed the button when the cached token was
  /// still good for another fifty minutes and only the refresh call happened
  /// to fail.
  ///
  /// The cached token is used first now, and [refreshAndRetry] handles the
  /// case the force-refresh existed for: the stale-token error is not guessed
  /// at, it is waited for and then answered.
  Future<void> _requireUser({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StripeCheckoutException('Not signed in.');
    }
    await user.getIdToken(force);
  }

  /// Runs [call], and retries it once with a forced token refresh if it fails
  /// the way a stale token fails.
  ///
  /// One retry, on one error code. Anything broader would be a client that
  /// retries into a backend already under load, which is the failure mode the
  /// absence of any retry in this app currently makes impossible.
  Future<T> _withFreshToken<T>(Future<T> Function() call) async {
    try {
      await _requireUser();
      return await call();
    } on FirebaseFunctionsException catch (e) {
      if (e.code != 'unauthenticated') rethrow;
      await _requireUser(force: true);
      return await call();
    }
  }

  @override
  Future<void> startFreeTrial(SubscriptionTier tier) async {
    try {
      await _withFreshToken(() async {
        await _functions
            .httpsCallable('startFreeTrial')
            .call<Map<String, dynamic>>({'tier': _tierParam(tier)});
      });
    } on Exception catch (e) {
      throw StripeCheckoutException('Could not start trial: $e');
    }
  }

  @override
  Future<void> startCheckout(
    SubscriptionTier tier, {
    SubscriptionPeriod period = SubscriptionPeriod.monthly,
    String? languageCode,
  }) async {
    final result = await _withFreshToken(
      () => _functions
          .httpsCallable('createCheckoutSession')
          .call<Map<String, dynamic>>({
        'tier': _tierParam(tier),
        'period': period.name,
        if (languageCode != null) 'locale': languageCode,
      }),
    );
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
    final result = await _withFreshToken(
      () => _functions
          .httpsCallable('createPortalSession')
          .call<Map<String, dynamic>>(),
    );
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
