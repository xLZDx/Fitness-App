import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/settings/state/settings_providers.dart';
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

/// Live subscription record for the signed-in user. Emits null when the user
/// is signed out or hasn't started a trial / subscribed yet.
///
/// P1d: `await ref.watch(authUserProvider.future)` rather than
/// `.valueOrNull`. `authUserProvider` is a StreamProvider and has emitted
/// NOTHING on a cold start, where `.valueOrNull` is null and therefore
/// indistinguishable from signed-out — so this provider used to resolve to
/// `Stream.value(null)` for a signed-in paying user, and every entitlement
/// downstream read "free" until auth caught up. Awaiting the first emission
/// removes the window instead of racing it.
final currentSubscriptionProvider = StreamProvider<Subscription?>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  yield* ref.watch(subscriptionRepositoryProvider).watch(user.uid);
});

/// How much the app actually knows about this user's entitlement right now.
///
/// Exists because [effectiveTierProvider] cannot express it. That provider
/// must return a concrete tier for 38 call sites, so "still loading" and
/// "this user has no subscription" both arrive as `free` — which is the right
/// default for LOCKING a feature and the wrong one for OFFERING to sell it.
/// A locked button that unlocks a moment later is a flicker; a paywall shown
/// to somebody who already pays is the product telling a paying customer they
/// have not paid.
enum EntitlementStatus {
  /// Auth or the subscription stream has not answered yet. Lock features if
  /// you must, but do not offer to sell anything.
  resolving,

  /// A real answer, whatever it is. `free` here means free.
  resolved,

  /// The subscription stream failed. The tier fell back to whatever was last
  /// known, which may be stale — say so rather than silently downgrading.
  unavailable,
}

final entitlementStatusProvider = Provider<EntitlementStatus>((ref) {
  // A tier override is a deliberate local answer and needs no network.
  if (ref.watch(allowTierOverrideProvider) &&
      ref.watch(settingsControllerProvider).tierOverride != TierOverride.off) {
    return EntitlementStatus.resolved;
  }
  final sub = ref.watch(currentSubscriptionProvider);
  if (sub.isLoading && !sub.hasValue) return EntitlementStatus.resolving;
  if (sub.hasError) return EntitlementStatus.unavailable;
  return EntitlementStatus.resolved;
});

/// Whether this moment is one where the app may offer to SELL something.
///
/// The one-line form of [EntitlementStatus] for the surfaces that need nothing
/// more than the yes/no: an upsell button, a "become a supporter" CTA, a
/// subtitle claiming which plan the user is on. Every one of those is a
/// statement about the customer, and making it from a `free` that only means
/// "not loaded yet" tells somebody who pays that they do not.
///
/// Deliberately NOT applied to locking. A feature that stays locked for the
/// half-second before the stream answers costs a flicker; unlocking it
/// optimistically would give away paid features to everyone on every cold
/// start. The asymmetry is the whole design — see [EntitlementStatus].
final entitlementResolvedProvider = Provider<bool>(
  (ref) => ref.watch(entitlementStatusProvider) == EntitlementStatus.resolved,
);

/// The tier the rest of the app should gate on. Resolves trial/period
/// expiry server-side in case Firestore hasn't synced the lapse yet.
///
/// Honours [TierOverride] first. That switch is off unless somebody turned it
/// on in Settings, and it exists because there was no way to exercise a paid
/// screen at all: checkout is in Stripe sandbox, which only accepts its own
/// test cards, so trying the app's premium features meant either knowing
/// `4242 4242 4242 4242` by heart or believing the flow was broken.
///
/// Reading it HERE rather than at each gate is what makes it trustworthy: one
/// place decides the tier, so the override cannot leave half the app thinking
/// the user paid and the other half thinking they did not.
/// Whether the tier override is allowed to answer at all.
///
/// A dart-define, not `kReleaseMode`. The two differ in the case that matters:
/// `flutter test` runs in debug, so a `kReleaseMode` guard would be inert in
/// every test and the five assertions in `tier_override_test.dart` would go on
/// passing while proving nothing about the shipped build. A define is the same
/// value in both, and the test command sets it explicitly.
///
/// Default true, deliberately. This is personal-use software and the switch
/// exists because the paid surfaces could not be exercised at all; defaulting
/// it off would restore that. Store builds pass
/// `--dart-define=ALLOW_TIER_OVERRIDE=false`.
const bool kAllowTierOverride =
    bool.fromEnvironment('ALLOW_TIER_OVERRIDE', defaultValue: true);

/// The same value, reachable from a test.
///
/// `bool.fromEnvironment` is resolved by the compiler, so a test cannot flip it
/// and a guard written against the constant alone is one no test can exercise
/// -- the five assertions in `tier_override_test.dart` would pass in a build
/// where the switch works and say nothing about the build where it must not.
/// Production reads the same constant through this provider and behaves
/// identically.
final allowTierOverrideProvider = Provider<bool>((_) => kAllowTierOverride);

final effectiveTierProvider = Provider<SubscriptionTier>((ref) {
  // Guarded at the read site rather than in Settings. A UI-only guard hides the
  // switch and leaves this provider honouring whatever is already in
  // `AppSettings` -- including a value set before the guard shipped, which
  // SharedPreferences keeps across an update.
  //
  // This alone does not fully close it. Debug and release share
  // `applicationId` and release is debug-signed (`android/app/build.gradle`),
  // so a "release" build installs as an UPDATE over a debug one and inherits
  // its preferences. R0's real signing key is what makes the two different
  // installs; until then this is a guard, not a boundary.
  final override = ref.watch(allowTierOverrideProvider)
      ? ref.watch(settingsControllerProvider).tierOverride
      : TierOverride.off;
  switch (override) {
    case TierOverride.standard:
      return SubscriptionTier.standard;
    case TierOverride.celebrity:
      return SubscriptionTier.celebrityTrainer;
    case TierOverride.off:
      break;
  }
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
      // The language the app is in, so the payment sheet is in it too.
      await stripe.startCheckout(
        tier,
        period: period,
        languageCode: ref.read(effectiveLanguageCodeProvider),
      );
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
