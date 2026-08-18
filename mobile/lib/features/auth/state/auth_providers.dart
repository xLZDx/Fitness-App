import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/auth_user.dart';
import '../data/mock_auth_repository.dart';
import '../data/sign_in_outcome.dart';

/// Backend-agnostic auth provider. The default wires up the in-memory mock;
/// override this one provider in tests or when swapping in Firebase.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = MockAuthRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Live stream of the current user (null = signed out, never throws).
final authUserProvider = StreamProvider<AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges();
});

/// Sign-in / sign-out controller, exposed as [AuthAction].
/// Carries a [GuestUpgrade] rather than `void`, because the screen has
/// something to say when a sign-in succeeded and cost the person their guest
/// history. `null` means no sign-in has happened on this state yet.
final authActionProvider =
    NotifierProvider<AuthAction, AsyncValue<GuestUpgrade?>>(AuthAction.new);

class AuthAction extends Notifier<AsyncValue<GuestUpgrade?>> {
  @override
  AsyncValue<GuestUpgrade?> build() => const AsyncValue.data(null);

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signInAnonymously() async {
    state = const AsyncValue.loading();
    try {
      await _repo.signInAnonymously();
      state = const AsyncValue.data(GuestUpgrade.notAGuest);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      final result = await _repo.signInWithGoogle();
      state = AsyncValue.data(result.guestUpgrade);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await _repo.signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
