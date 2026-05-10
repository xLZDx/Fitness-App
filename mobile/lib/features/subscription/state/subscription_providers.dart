import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/feature_gates.dart';
import '../data/mock_stripe_checkout_service.dart';
import '../data/mock_subscription_repository.dart';
import '../data/stripe_checkout_service.dart';
import '../data/subscription_models.dart';
import '../data/subscription_repository.dart';

/// Length of the trial offered by [SubscriptionAction.startTrial].
const trialDuration = Duration(days: 14);

/// Persistence provider — defaults to in-memory mock; overridden in
/// `main.dart` with the Firestore-backed impl.
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  final repo = MockSubscriptionRepository();
  ref.onDispose(() {
    if (repo is MockSubscriptionRepository) repo.dispose();
  });
  return repo;
});

/// Stripe checkout bridge — defaults to a mock so unit tests don't need
/// `cloud_functions` or `url_launcher`. `main.dart` overrides this with
/// `CloudFunctionsStripeService`.
final stripeCheckoutServiceProvider =
    Provider<StripeCheckoutService>((ref) {
  return MockStripeCheckoutService();
});

/// Live subscription record for the signed-in user. Emits null while the
/// user is signed out or hasn't started a trial / subscribed yet.
final currentSubscriptionProvider = StreamProvider<Subscription?>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final repo = ref.watch(subscriptionRepositoryProvider);
  return repo.watch(user.uid);
});

/// The tier the rest of the app should gate on. Resolves trial/period
/// expiry server-side in case Firestore hasn't synced the lapse yet.
final effectiveTierProvider = Provider<SubscriptionTier>((ref) {
  final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
  return effectiveTier(sub);
});

/// Convenience provider used by feature widgets:
///   ref.watch(featureAccessProvider(AppFeature.workoutScheduling))
final featureAccessProvider = Provider.family<bool, AppFeature>((ref, feature) {
  final tier = ref.watch(effectiveTierProvider);
  return canAccess(tier, feature);
});

/// UI-only state — the period the picker is currently displaying. Reset
/// every time the page is rebuilt; not persisted.
final selectedPeriodProvider =
    StateProvider<SubscriptionPeriod>((_) => SubscriptionPeriod.monthly);

/// Imperative controller for "Start trial" / "Choose tier" / "Cancel"
/// actions. The Notifier surfaces an AsyncValue so the UI can render
/// loading / error states.
final subscriptionActionProvider =
    NotifierProvider<SubscriptionAction, AsyncValue<void>>(
        SubscriptionAction.new);

class SubscriptionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Starts a trial at the requested [tier]. Routes through the
  /// `startFreeTrial` Cloud Function because Firestore rules deny client
  /// writes to the subscription doc — the server is the only writer.
  /// The Cloud Function rejects a second trial-start (one trial per
  /// account).
  Future<void> startTrial(SubscriptionTier tier) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot start a trial while signed out');
      }
      final stripe = ref.read(stripeCheckoutServiceProvider);
      await stripe.startFreeTrial(tier);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Hand off to Stripe Checkout. The Cloud Function returns a hosted
  /// payment URL, [StripeCheckoutService] launches it in the browser,
  /// and the webhook updates `users/{uid}/subscription/main` once
  /// payment succeeds — at which point the StreamProvider chain emits
  /// the new tier and the UI updates.
  ///
  /// Picking [SubscriptionTier.free] short-circuits Stripe entirely
  /// and just clears any local record (handy for "downgrade to free"
  /// from the management page).
  Future<void> chooseTier(
    SubscriptionTier tier, {
    SubscriptionPeriod period = SubscriptionPeriod.monthly,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot subscribe while signed out');
      }
      if (tier == SubscriptionTier.free) {
        state = const AsyncValue.data(null);
        return;
      }
      final stripe = ref.read(stripeCheckoutServiceProvider);
      await stripe.startCheckout(tier, period: period);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Open the Stripe Customer Portal so the user can cancel or change
  /// plan. The webhook fires `customer.subscription.deleted` and the
  /// stream auto-updates — we don't need to mirror anything locally.
  Future<void> cancel() async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot cancel while signed out');
      }
      final stripe = ref.read(stripeCheckoutServiceProvider);
      await stripe.openCustomerPortal();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
