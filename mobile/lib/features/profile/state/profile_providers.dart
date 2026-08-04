import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../workouts/state/session_screening_providers.dart';
import '../data/mock_profile_repository.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

/// Backend-agnostic profile provider. Default wires up the in-memory mock;
/// override in tests or for the Firebase-backed implementation.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repo = MockProfileRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// The current user's profile (or null if signed out / not yet created).
final currentProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final repo = ref.watch(profileRepositoryProvider);
  return repo.watch(user.uid);
});

/// True when the signed-in user has completed onboarding. Used by the router.
final isOnboardedProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return profile?.hasCompletedOnboarding ?? false;
});

/// Submit a finalized profile (sets `completedAt`).
final profileSubmitProvider =
    NotifierProvider<ProfileSubmit, AsyncValue<void>>(ProfileSubmit.new);

class ProfileSubmit extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> submit(UserProfile draft) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.save(draft.copyWith(completedAt: DateTime.now()));
      // The injury list may have just changed, and a reminder scheduled
      // before it fires from the OS with no render pass to screen it. This is
      // the only save path in the app, so it is the only place that can catch
      // that. Best-effort: the profile is saved either way, and failing the
      // submit because a notification could not be cancelled would be worse
      // than the stale reminder.
      try {
        await ref.read(sessionReminderReconcilerProvider).reconcile();
      } catch (e) {
        debugPrint('reminder reconcile after profile save failed: $e');
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveDraft(UserProfile draft) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.save(draft);
  }

  /// Saves an edited injury list. The only save path outside onboarding.
  ///
  /// Before this, `ProfileRepository.save()` had exactly two call sites, both
  /// inside `features/onboarding/`, and the one affordance meant to reach them
  /// — "Edit your answers" (`profile_page.dart`) — routes to `/onboarding`,
  /// which `app_router.dart` bounces straight back to `/home` for anyone who
  /// has onboarded. There was no way to change a stored injury at all, which
  /// made the structured region below undeliverable to every existing user.
  ///
  /// It reconciles reminders afterwards for the same reason `submit` does: a
  /// newly-added injury can contraindicate a session whose notification is
  /// already armed in the OS, and this is now the path that can actually
  /// happen.
  Future<void> saveInjuries(List<Injury> injuries) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot edit injuries while signed out');
      }
      final repo = ref.read(profileRepositoryProvider);
      final current = ref.read(currentProfileProvider).valueOrNull ??
          await repo.load(user.uid) ??
          UserProfile.empty(user.uid);
      await repo.save(
        current.copyWith(
          health: current.health.copyWith(injuries: injuries),
        ),
      );
      try {
        await ref.read(sessionReminderReconcilerProvider).reconcile();
      } catch (e) {
        debugPrint('reminder reconcile after injury edit failed: $e');
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
