import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/feature_gates.dart';
import '../data/mock_subscription_repository.dart';
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

/// Imperative controller for "Start trial" / "Choose tier" / "Cancel"
/// actions. The Notifier surfaces an AsyncValue so the UI can render
/// loading / error states.
final subscriptionActionProvider =
    NotifierProvider<SubscriptionAction, AsyncValue<void>>(
        SubscriptionAction.new);

class SubscriptionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Starts a trial at the requested [tier]. Idempotent — calling twice
  /// re-extends the trial window from now.
  Future<void> startTrial(SubscriptionTier tier) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot start a trial while signed out');
      }
      final repo = ref.read(subscriptionRepositoryProvider);
      final now = DateTime.now();
      await repo.save(Subscription(
        uid: user.uid,
        tier: tier,
        status: SubscriptionStatus.trial,
        trialEndsAt: now.add(trialDuration),
      ));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// "Pay" for a tier. In the mock-first phase this just stamps an
  /// `active` record with a 30-day window; Phase 4B will replace this
  /// with a Stripe checkout return path.
  Future<void> chooseTier(SubscriptionTier tier) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot subscribe while signed out');
      }
      final repo = ref.read(subscriptionRepositoryProvider);
      final now = DateTime.now();
      await repo.save(Subscription(
        uid: user.uid,
        tier: tier,
        status: tier == SubscriptionTier.free
            ? SubscriptionStatus.none
            : SubscriptionStatus.active,
        currentPeriodEndsAt: tier == SubscriptionTier.free
            ? null
            : now.add(const Duration(days: 30)),
      ));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark the subscription as cancelled. The user keeps their tier until
  /// `currentPeriodEndsAt` lapses; `effectiveTier` handles the rollback.
  Future<void> cancel() async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot cancel while signed out');
      }
      final repo = ref.read(subscriptionRepositoryProvider);
      final existing = repo.cached(user.uid);
      if (existing == null) {
        // Nothing to cancel — leave state as data(null).
        state = const AsyncValue.data(null);
        return;
      }
      await repo.save(existing.copyWith(
        status: SubscriptionStatus.cancelled,
      ));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
