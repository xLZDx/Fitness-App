import 'dart:convert';
import 'dart:io';

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

  group('the sign-in config the build actually ships', () {
    // WHY THESE READ REAL FILES
    //
    // Google sign-in failed on two consecutive builds with
    // `[28444] Developer console is not set up correctly`. That message is
    // what Credential Manager says for an unregistered signing fingerprint,
    // so the fingerprint is what got registered — twice, correctly, with no
    // effect. The actual cause was that `serverClientId` named project
    // `1007678328591` while the shipped `google-services.json` is project
    // `988522745882`: a token was being requested for an audience belonging
    // to a project this app is not part of.
    //
    // Nothing could catch that, because the two values live in different
    // files, in different languages, and only meet on a phone. These tests
    // are the place they meet on a laptop. They read the real config rather
    // than a fixture, since a fixture would have agreed with the constant
    // while the shipped file disagreed — which is precisely the failure.
    final config = File('android/app/google-services.json');
    final gradle = File('android/app/build.gradle');

    // The config is gitignored, so a fresh clone legitimately lacks it. Skip
    // with a reason rather than fail: a red suite that means "you have not
    // downloaded a file" trains people to ignore red suites. On the machine
    // that builds APKs — the only machine where this can be wrong — the file
    // is there and these run.
    final skipReason = config.existsSync()
        ? null
        : 'android/app/google-services.json is absent (gitignored); '
            'run flutterfire configure to fetch it.';

    Map<String, dynamic> readConfig() =>
        jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;

    /// Every `client_type: 3` (web) id in the config, deduplicated.
    Set<String> webClientIds() => {
          for (final c in readConfig()['client'] as List)
            for (final o in (c['oauth_client'] as List? ?? const []))
              if (o['client_type'] == 3) o['client_id'] as String,
        };

    test('serverClientId is the web client of the shipped config', () {
      expect(
        webClientIds(),
        contains(FirebaseAuthRepository.serverClientId),
        reason: 'FirebaseAuthRepository.serverClientId names a project the '
            'shipped google-services.json knows nothing about. Google sign-in '
            'will fail with "[28444] Developer console is not set up '
            'correctly" on every device. Copy the client_type 3 client_id '
            'out of android/app/google-services.json.',
      );
    }, skip: skipReason);

    test('the config carries an Android client for the id we actually build',
        () {
      // The web client alone is not enough: Credential Manager also needs an
      // Android OAuth client registered against this exact package name AND
      // the certificate that signed the APK. `applicationId` is read from
      // build.gradle rather than hardcoded here, so renaming the app moves
      // this assertion with it instead of quietly checking the old name.
      final applicationId = RegExp(r'applicationId\s*=\s*"([^"]+)"')
          .firstMatch(gradle.readAsStringSync())
          ?.group(1);
      expect(applicationId, isNotNull,
          reason: 'could not find applicationId in android/app/build.gradle');

      final androidClients = [
        for (final c in readConfig()['client'] as List)
          if (c['client_info']['android_client_info']['package_name'] ==
              applicationId)
            for (final o in (c['oauth_client'] as List? ?? const []))
              if (o['client_type'] == 1) o,
      ];

      expect(androidClients, isNotEmpty,
          reason: 'google-services.json has no client_type 1 (Android) OAuth '
              'client for $applicationId. Add the SHA-1 of the signing key in '
              'the Firebase console and re-download the config.');
      for (final client in androidClients) {
        expect(client['android_info']?['certificate_hash'], isNotNull,
            reason: 'an Android OAuth client without a certificate_hash '
                'authorises nothing');
      }
    }, skip: skipReason);
  });
}
