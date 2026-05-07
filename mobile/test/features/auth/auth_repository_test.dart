import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';

void main() {
  group('MockAuthRepository', () {
    late MockAuthRepository repo;

    setUp(() {
      repo = MockAuthRepository(latency: Duration.zero);
    });

    tearDown(() => repo.dispose());

    test('starts signed out', () {
      expect(repo.currentUser, isNull);
    });

    test('signInAnonymously creates an anonymous user', () async {
      final user = await repo.signInAnonymously();
      expect(user.provider, AuthProvider.anonymous);
      expect(user.uid, hasLength(32));
      expect(repo.currentUser, user);
    });

    test('signInWithGoogle creates a google user with display name + email',
        () async {
      final user = await repo.signInWithGoogle();
      expect(user.provider, AuthProvider.google);
      expect(user.displayName, isNotEmpty);
      expect(user.email, contains('@'));
      expect(repo.currentUser, user);
    });

    test('signOut clears the current user', () async {
      await repo.signInAnonymously();
      expect(repo.currentUser, isNotNull);
      await repo.signOut();
      expect(repo.currentUser, isNull);
    });

    test('authStateChanges replays current value to new subscribers',
        () async {
      await repo.signInAnonymously();
      final first = await repo.authStateChanges().first;
      expect(first?.uid, repo.currentUser!.uid);
    });

    test('authStateChanges emits null after sign out', () async {
      await repo.signInAnonymously();
      final stream = repo.authStateChanges();
      final emissions = <AuthUser?>[];
      final sub = stream.listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repo.signOut();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emissions.last, isNull);
    });
  });
}
