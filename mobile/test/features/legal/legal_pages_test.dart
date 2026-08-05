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
///
/// P0 finished the job: the bodies are real documents now, generated from
/// `scripts/legal/legal_text.py` into both the .arb files and the two public
/// URLs Google Play requires. This file's assertions moved with them — from
/// "the placeholder flag is still true" to statements about the rendered text,
/// because the flag was only ever a proxy for what the text says.

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

  /// Reads every `Text`/`Text.rich` on screen back as one string, so an
  /// assertion can be made about the document rather than about a widget tree
  /// whose shape is an implementation detail of [LegalBody].
  String renderedText(WidgetTester tester) {
    final buffer = StringBuffer();
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      buffer.writeln(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    return buffer.toString();
  }

  group('TermsPage', () {
    testWidgets('renders under MaterialApp', (tester) async {
      await tester.pumpWidget(_host(const TermsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(TermsPage), findsOneWidget);
    });

    testWidgets('renders the real document, not a stub', (tester) async {
      await tester.pumpWidget(_host(const TermsPage()));
      await tester.pumpAndSettle();
      final text = renderedText(tester);
      expect(find.byKey(const Key('terms-last-updated')), findsOneWidget);
      // Headings prove `LegalBody` actually parsed the `## ` markup rather
      // than dumping one undifferentiated blob.
      expect(text, contains('What this app is, and what it is not'));
      expect(text, contains('Subscriptions and payment'));
      expect(text.length, greaterThan(2000));
    });

    testWidgets('states the two claims S0b removed, in their corrected form',
        (tester) async {
      // These are the regression this file exists for now. Both sentences are
      // corrections of claims the app used to make and could not support: the
      // catalog was never physiotherapist-reviewed (`app_en.arb:267` had
      // already been fixed to say so while `:1353` still claimed otherwise),
      // and there is no 501(c)(3) and no fiscal sponsor, so a subscription was
      // never a tax-deductible donation. A future edit that softens either one
      // back toward the marketing version fails here rather than reaching a
      // store listing.
      await tester.pumpWidget(_host(const TermsPage()));
      await tester.pumpAndSettle();
      final text = renderedText(tester);
      expect(text, contains('has not been reviewed by a physiotherapist'));
      expect(text, contains('not tax-deductible donations'));
      expect(text, contains('no nonprofit status'));
    });
  });

  group('PrivacyPage', () {
    testWidgets('renders under MaterialApp', (tester) async {
      await tester.pumpWidget(_host(const PrivacyPage()));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPage), findsOneWidget);
    });

    testWidgets('renders the real document, not a stub', (tester) async {
      await tester.pumpWidget(_host(const PrivacyPage()));
      await tester.pumpAndSettle();
      final text = renderedText(tester);
      expect(find.byKey(const Key('privacy-last-updated')), findsOneWidget);
      expect(text, contains('What is collected'));
      expect(text, contains('Your rights'));
      expect(text.length, greaterThan(2000));
    });

    testWidgets('discloses the disclosures that cost something to make',
        (tester) async {
      // A privacy policy is easy to write favourably. These three lines are
      // the ones a template would have omitted or buried, and each is a fact
      // about this code: the scanner really does upload the frame
      // (`gemini_equipment_service.dart:37-48`), the supporter wall really is
      // world-readable (`firestore.rules:55`), and deletion really is
      // unrecoverable (`index.ts:1169-1207`). Asserting them here means the
      // policy cannot quietly lose them.
      await tester.pumpWidget(_host(const PrivacyPage()));
      await tester.pumpAndSettle();
      final text = renderedText(tester);
      expect(text, contains("sent to Google's Gemini"));
      expect(text, contains('Other people may be in shot'));
      expect(text, contains('It is irreversible'));
    });
  });

  group('release readiness', () {
    // Replaces a pair of `kIsPlaceholderContent` assertions. Those pinned a
    // boolean; this pins the artifact the boolean was standing in for, which
    // is what a stale flag could always have lied about.
    testWidgets('neither document still says it is a placeholder',
        (tester) async {
      for (final page in <Widget>[const TermsPage(), const PrivacyPage()]) {
        await tester.pumpWidget(_host(page));
        await tester.pumpAndSettle();
        final text = renderedText(tester).toLowerCase();
        expect(text, isNot(contains('placeholder')),
            reason: 'placeholder legal text must not ship to a store listing');
        expect(text, isNot(contains('pending the operator')));
      }
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
