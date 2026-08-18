import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';

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
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {
    signOutCalls.add(null);
    if (_throwOnSignOut) throw StateError('sign-out plugin failed');
  }
}

class _ThrowingWipe implements LocalDataWipe {
  @override
  Future<void> wipe(String uid) async => throw StateError('disk locked');
}

void main() {
  test('a successful deletion wipes this device too, with the right uid',
      () async {
    // A1. Before this, "delete my account" was server-only: the health blob,
    // the progress photos and the photo key all survived on the phone, and
    // the next account signed in on the same device could read them.
    final service = MockAccountDeletionService();
    final authRepo = _RecordingAuthRepo();
    final wipe = RecordingLocalDataWipe();
    final container = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      localDataWipeProvider.overrideWithValue(wipe),
      authRepositoryProvider.overrideWithValue(authRepo),
    ]);
    addTearDown(container.dispose);

    await container.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(wipe.wiped, ['u1']);
    expect(container.read(accountDeletionActionProvider).hasError, isFalse);
  });

  test('a failed deletion wipes nothing on the device', () async {
    // The account still exists and is still usable. Wiping its photos here
    // would destroy data belonging to a live account because a network call
    // failed.
    final service = MockAccountDeletionService()
      ..failWith = const AccountDeletionException('boom');
    final authRepo = _RecordingAuthRepo();
    final wipe = RecordingLocalDataWipe();
    final container = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      localDataWipeProvider.overrideWithValue(wipe),
      authRepositoryProvider.overrideWithValue(authRepo),
    ]);
    addTearDown(container.dispose);

    await container.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(wipe.wiped, isEmpty);
    expect(authRepo.signOutCalls, isEmpty);
    expect(container.read(accountDeletionActionProvider).hasError, isTrue);
  });

  test('a wipe that throws does not report the deletion as failed', () async {
    // A locked file on one phone is not "your account was not deleted".
    final service = MockAccountDeletionService();
    final authRepo = _RecordingAuthRepo();
    final container = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      localDataWipeProvider.overrideWithValue(_ThrowingWipe()),
      authRepositoryProvider.overrideWithValue(authRepo),
    ]);
    addTearDown(container.dispose);

    await container.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(container.read(accountDeletionActionProvider).hasError, isFalse);
    expect(authRepo.signOutCalls, hasLength(1));
  });

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
