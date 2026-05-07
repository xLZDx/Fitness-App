import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
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
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveDraft(UserProfile draft) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.save(draft);
  }
}
