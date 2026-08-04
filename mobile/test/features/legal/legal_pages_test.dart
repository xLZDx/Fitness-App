import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/features/auth/login_page.dart';
import 'package:fitness_app/features/legal/privacy_page.dart';
import 'package:fitness_app/features/legal/terms_page.dart';

/// L0a: Terms and Privacy are real, reachable routes rather than a sentence
/// naming two documents that link nowhere.
///
/// `login_page.dart` has said "By continuing you agree to our Terms and
/// Privacy Policy" since the login screen shipped, with neither word
/// pointing anywhere — the same shape of claim S0a spent two gates removing
/// from the injury filter: a sentence asserting something the product does
/// not actually provide.

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('the routes', () {
    test('are public, so a signed-out user is not bounced to /login', () {
      expect(resolveRedirect(isSignedIn: false, isOnboarded: false, location: '/terms'), isNull);
      expect(resolveRedirect(isSignedIn: false, isOnboarded: false, location: '/privacy'), isNull);
    });
  });

  group('TermsPage', () {
    testWidgets('renders under MaterialApp', (tester) async {
      await tester.pumpWidget(_host(const TermsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(TermsPage), findsOneWidget);
    });

    testWidgets('shows the placeholder notice while the flag is true',
        (tester) async {
      // Hardcoded to `findsOneWidget`, not
      // `kIsPlaceholderContent ? findsOneWidget : findsNothing` -- that form
      // asserts the render against the same flag the widget's own `if` reads,
      // so it passes unconditionally regardless of whether the gate actually
      // works. The 'release readiness' group below is what pins the flag's
      // value; this one is what pins the widget to it.
      await tester.pumpWidget(_host(const TermsPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terms-placeholder-notice')),
          findsOneWidget);
    });
  });

  group('PrivacyPage', () {
    testWidgets('renders under MaterialApp', (tester) async {
      await tester.pumpWidget(_host(const PrivacyPage()));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPage), findsOneWidget);
    });

    testWidgets('shows the placeholder notice while the flag is true',
        (tester) async {
      // See TermsPage's identical test above for why this is hardcoded rather
      // than re-checking the same flag the widget itself reads.
      await tester.pumpWidget(_host(const PrivacyPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-placeholder-notice')),
          findsOneWidget);
    });
  });

  group('release readiness', () {
    // Not a warning that fires forever and gets ignored — a single assertion
    // that names the two flags a real release must have flipped. This is
    // meant to start failing the moment someone flips a flag without also
    // replacing the body, catching a stale "reviewed" claim on real text that
    // never happened.
    test('both content flags agree: this build is not release-ready legally',
        () {
      expect(TermsPage.kIsPlaceholderContent, isTrue,
          reason: 'placeholder legal text must not ship to a store listing '
              'or to anyone but the operator');
      expect(PrivacyPage.kIsPlaceholderContent, isTrue,
          reason: 'placeholder legal text must not ship to a store listing '
              'or to anyone but the operator');
    });
  });

  group('the login footer', () {
    // A minimal router carrying only the three routes this test exercises,
    // rather than the full `appRouterProvider` -- that one redirects through
    // `/splash` and reads live Firebase auth state, neither of which this
    // test needs or can provide.
    Future<void> pumpLogin(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
          GoRoute(path: '/terms', builder: (_, __) => const TermsPage()),
          GoRoute(path: '/privacy', builder: (_, __) => const PrivacyPage()),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names both documents, not a bare sentence', (tester) async {
      await pumpLogin(tester);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('the Terms link opens the real route', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.byKey(const Key('login-terms-link')));
      await tester.pumpAndSettle();
      expect(find.byType(TermsPage), findsOneWidget);
    });

    testWidgets('the Privacy link opens the real route', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.byKey(const Key('login-privacy-link')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPage), findsOneWidget);
    });
  });
}
