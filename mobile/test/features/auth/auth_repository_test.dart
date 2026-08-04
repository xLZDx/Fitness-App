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

    group('guest to Google (L0d)', () {
      // Mirrors FirebaseAuthRepository.signInWithGoogle's link-not-replace
      // fix. That real implementation touches FirebaseAuth.instance and
      // cannot be unit-tested without a fake of the whole plugin surface --
      // this is where the decision logic is actually exercised, and the two
      // must stay in step or the mock stops proving anything real.

      test('keeps the same uid -- this is the whole point', () async {
        final guest = await repo.signInAnonymously();
        final linked = await repo.signInWithGoogle();

        expect(linked.uid, guest.uid,
            reason: 'every Firestore document already written under the '
                'guest uid must still be this user\'s data afterward');
        expect(linked.provider, AuthProvider.google);
      });

      test('a fresh (non-guest) sign-in still gets a new uid, as before',
          () async {
        final user = await repo.signInWithGoogle();
        expect(user.uid, hasLength(32));
      });

      test(
          'colliding with an existing Google account falls back to a new uid, '
          'and the guest uid is not reused', () async {
        // The one honest gap: when the Google identity is already someone's
        // real account elsewhere, linking cannot merge the two. The user
        // correctly ends up in their real account; this device's guest data
        // is not recoverable by this flow, which is why the test asserts the
        // uid is NOT the guest's rather than asserting what it should be.
        final collidingRepo = MockAuthRepository(
          latency: Duration.zero,
          simulateGoogleAccountCollision: true,
        );
        addTearDown(collidingRepo.dispose);

        final guest = await collidingRepo.signInAnonymously();
        final result = await collidingRepo.signInWithGoogle();

        expect(result.uid, isNot(guest.uid));
        expect(result.provider, AuthProvider.google);
      });

      test('authStateChanges reflects the link immediately', () async {
        // Locks in the shape of the fix reviewed alongside this: the real
        // FirebaseAuthRepository switched authStateChanges() to
        // userChanges() because Firebase's own doc says the former does NOT
        // fire on a link event, only sign-in/sign-out -- a guest who linked
        // would otherwise see their stale pre-link self in every reactive
        // surface (router, profile, authUserProvider) for the rest of the
        // session. The mock has no such split to reproduce the bug directly,
        // but this pins the behaviour the app actually depends on so a
        // future change to either implementation has to keep it true.
        await repo.signInAnonymously();
        final emissions = <AuthUser?>[];
        final sub = repo.authStateChanges().listen(emissions.add);
        await Future<void>.delayed(Duration.zero);

        final linked = await repo.signInWithGoogle();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emissions.last?.uid, linked.uid);
        expect(emissions.last?.provider, AuthProvider.google);
      });

      test('signing in fresh after a guest session does not retroactively '
          'claim the old guest uid', () async {
        final firstGuest = await repo.signInAnonymously();
        await repo.signOut();
        final freshUser = await repo.signInWithGoogle();

        expect(freshUser.uid, isNot(firstGuest.uid),
            reason: 'the guest was signed out, not linked, before Google '
                'sign-in -- there is no session left to preserve');
      });
    });
  });
}
