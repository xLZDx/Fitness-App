import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

class _RecordingAuthRepo implements AuthRepository {
  final signOutCalls = <void>[];
  final bool _throwOnSignOut;
  _RecordingAuthRepo({bool throwOnSignOut = false})
      : _throwOnSignOut = throwOnSignOut;

  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(uid: 'u1', displayName: 'U'));
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'u1', displayName: 'U');
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<AuthUser> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {
    signOutCalls.add(null);
    if (_throwOnSignOut) throw StateError('sign-out plugin failed');
  }
}

void main() {
  test('a successful deletion signs the local client out', () async {
    final service = MockAccountDeletionService();
    final authRepo = _RecordingAuthRepo();
    final container = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      authRepositoryProvider.overrideWithValue(authRepo),
    ]);
    addTearDown(container.dispose);

    await container.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(service.callCount, 1);
    expect(authRepo.signOutCalls, hasLength(1));
    expect(container.read(accountDeletionActionProvider).hasError, isFalse);
  });

  test('a failed deletion never reaches sign-out', () async {
    final service = MockAccountDeletionService()
      ..failWith = const AccountDeletionException('boom');
    final authRepo = _RecordingAuthRepo();
    final container = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      authRepositoryProvider.overrideWithValue(authRepo),
    ]);
    addTearDown(container.dispose);

    await container.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(authRepo.signOutCalls, isEmpty,
        reason: 'the account was not deleted -- signing the user out of a '
            'still-existing account would be its own, different bug');
    expect(container.read(accountDeletionActionProvider).hasError, isTrue);
  });

  test(
    'a sign-out failure after a successful deletion is swallowed, not '
    'reported as the deletion having failed',
    () async {
      // The account IS gone at this point. Surfacing a client-side sign-out
      // hiccup as an AccountDeletionAction error would read as "your account
      // was not deleted", which is false and worse than the truth.
      final service = MockAccountDeletionService();
      final authRepo = _RecordingAuthRepo(throwOnSignOut: true);
      final container = ProviderContainer(overrides: [
        accountDeletionServiceProvider.overrideWithValue(service),
        authRepositoryProvider.overrideWithValue(authRepo),
      ]);
      addTearDown(container.dispose);

      await container
          .read(accountDeletionActionProvider.notifier)
          .deleteAccount();

      expect(service.callCount, 1);
      expect(authRepo.signOutCalls, hasLength(1));
      expect(container.read(accountDeletionActionProvider).hasError, isFalse,
          reason: 'the deletion itself succeeded');
    },
  );
}
