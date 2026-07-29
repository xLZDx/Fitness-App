import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;

import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/firebase_auth_repository.dart';

void main() {
  group('FirebaseAuthRepository.signInWithGoogle', () {
    // These exercise the paths that run BEFORE any Firebase call, so they
    // need no Firebase binding. The happy path (credential -> Firebase) is
    // covered by the on-device check, not here.

    test('missing ID token throws an actionable AuthException', () async {
      final repo = FirebaseAuthRepository(null, () async => null);

      await expectLater(
        repo.signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            allOf(contains('ID token'), contains('SHA fingerprint')),
          ),
        ),
      );
    });

    test('user cancellation surfaces as a cancelled message, not a crash',
        () async {
      final repo = FirebaseAuthRepository(null, () async {
        throw const gsi.GoogleSignInException(
          code: gsi.GoogleSignInExceptionCode.canceled,
        );
      });

      await expectLater(
        repo.signInWithGoogle(),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('cancelled'))),
      );
    });

    test('plugin failure keeps the reason instead of swallowing it', () async {
      final repo = FirebaseAuthRepository(null, () async {
        throw const gsi.GoogleSignInException(
          code: gsi.GoogleSignInExceptionCode.unknownError,
          description: 'DEVELOPER_ERROR',
        );
      });

      await expectLater(
        repo.signInWithGoogle(),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(contains('unknownError'), contains('DEVELOPER_ERROR')),
        )),
      );
    });
  });
}
