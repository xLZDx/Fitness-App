import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';

void main() {
  group('AuthAction', () {
    late ProviderContainer container;
    late MockAuthRepository repo;

    setUp(() {
      repo = MockAuthRepository(latency: Duration.zero);
      container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);
    });

    test('starts in idle (data null) state', () {
      final value = container.read(authActionProvider);
      expect(value, const AsyncValue<GuestUpgrade?>.data(null));
    });

    test('signInAnonymously transitions data → loading → data', () async {
      final states = <AsyncValue<GuestUpgrade?>>[];
      container.listen<AsyncValue<GuestUpgrade?>>(
        authActionProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container.read(authActionProvider.notifier).signInAnonymously();

      expect(states.first, isA<AsyncData<void>>());
      expect(states.any((s) => s.isLoading), isTrue);
      expect(states.last, isA<AsyncData<void>>());
      expect(repo.currentUser?.provider, AuthProvider.anonymous);
    });

    test('signInWithGoogle ends in data state with a google user', () async {
      await container.read(authActionProvider.notifier).signInWithGoogle();
      expect(repo.currentUser?.provider, AuthProvider.google);
      expect(container.read(authActionProvider), isA<AsyncData<void>>());
    });

    test('signOut clears the current user', () async {
      await container.read(authActionProvider.notifier).signInAnonymously();
      expect(repo.currentUser, isNotNull);

      await container.read(authActionProvider.notifier).signOut();
      expect(repo.currentUser, isNull);
    });

    test('errors from the repo bubble up as AsyncError', () async {
      final failing = _FailingAuth();
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWith((ref) => failing),
      ]);
      addTearDown(c.dispose);

      await c.read(authActionProvider.notifier).signInAnonymously();
      expect(c.read(authActionProvider), isA<AsyncError<void>>());
    });
  });
}

class _FailingAuth implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();
  @override
  AuthUser? get currentUser => null;
  @override
  Future<AuthUser> signInAnonymously() async =>
      throw const AuthException('boom');
  @override
  Future<SignInResult> signInWithGoogle() async =>
      throw const AuthException('boom');
  @override
  Future<void> signOut() async {}
}
