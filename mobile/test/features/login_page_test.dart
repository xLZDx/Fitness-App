import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/login_page.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

void main() {
  group('LoginPage', () {
    testWidgets('renders welcome copy and both sign-in buttons',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      // Was `find.textContaining('Terms and Privacy Policy')`, which asserted
      // the old shape: one sentence naming two documents that led nowhere.
      // L0a split it into two real links (see legal_pages_test.dart for the
      // navigation coverage); the words survive as two separate Text widgets,
      // which is why the joined phrase no longer appears as one string.
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('Continue triggers anonymous sign-in', (tester) async {
      final repo = _RecordingMockAuth();
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      await tester.tap(find.text('Continue'));
      await tester.pump(); // start
      await tester.pump(const Duration(milliseconds: 300)); // settle

      expect(repo.anonymousCalls, 1);
      expect(repo.googleCalls, 0);
      expect(repo.currentUser, isNotNull);
      expect(repo.currentUser!.provider, AuthProvider.anonymous);
    });

    testWidgets('Continue with Google triggers Google sign-in',
        (tester) async {
      final repo = _RecordingMockAuth();
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.googleCalls, 1);
      expect(repo.anonymousCalls, 0);
      expect(repo.currentUser?.provider, AuthProvider.google);
    });

    testWidgets('buttons are disabled while signing in', (tester) async {
      final repo = _SlowMockAuth();
      await tester.pumpWidget(_app(repo: repo));
      await tester.pump();

      await tester.tap(find.text('Continue'));
      await tester.pump(); // begin loading
      await tester.pump(const Duration(milliseconds: 50));

      // The Continue button swaps its label out for a spinner mid-flight.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      // Drain the slow mock so the test ends cleanly.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}

Widget _app({AuthRepository? repo}) {
  return ProviderScope(
    overrides: [
      if (repo != null)
        authRepositoryProvider.overrideWith((ref) => repo),
    ],
    child: const MaterialApp(
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LoginPage(),
    ),
  );
}

class _RecordingMockAuth extends MockAuthRepository {
  _RecordingMockAuth() : super(latency: const Duration(milliseconds: 50));
  int anonymousCalls = 0;
  int googleCalls = 0;

  @override
  Future<AuthUser> signInAnonymously() {
    anonymousCalls += 1;
    return super.signInAnonymously();
  }

  @override
  Future<AuthUser> signInWithGoogle() {
    googleCalls += 1;
    return super.signInWithGoogle();
  }
}

class _SlowMockAuth extends MockAuthRepository {
  _SlowMockAuth() : super(latency: const Duration(seconds: 1));
}
