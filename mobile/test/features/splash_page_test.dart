import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/splash/splash_page.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../helpers/test_app.dart';

void main() {
  group('SplashPage', () {
    testWidgets('renders branding immediately', (tester) async {
      await tester.pumpWidget(_router(initial: '/splash'));
      await tester.pump();
      expect(find.text('Fitness App'), findsOneWidget);
      expect(find.text('Scan. Train. Progress.'), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center), findsOneWidget);
      // Drain the auto-navigation timer so it doesn't leak into the next test.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('hands off after the splash delay', (tester) async {
      await tester.pumpWidget(_router(initial: '/splash'));
      await tester.pump();
      expect(find.text('home-stub'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));

      // Splash's post-frame callback navigates to /home; the auth-aware
      // redirect will rewrite to /login in production. Here we just
      // assert the hand-off happened.
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets(
        'does not hand off while auth is still genuinely restoring, '
        'even past the normal dwell time', (tester) async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);

      await tester.pumpWidget(_router(initial: '/splash', auth: auth.stream));
      await tester.pump();

      // Well past the old fixed 1300ms+600ms dwell -- under the old
      // fixed-timer behaviour this would already have navigated regardless
      // of auth state, which is exactly the router-redirect race this fix
      // exists to close (a real signed-in user reached here would be bounced
      // to /login by `resolveRedirect` reading `currentUser` as still-null).
      // Two separate pumps, matching the settle pattern the "hands off after
      // the splash delay" test above already needs -- a single big pump can
      // fire the navigation call without giving the destination route a
      // frame to actually render, which would make this assertion pass for
      // the wrong reason.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('home-stub'), findsNothing,
          reason: 'auth has not resolved yet -- must not navigate on a '
              'fixed timer regardless of auth state');

      auth.add(const AuthUser(uid: 'alice', displayName: 'Alice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets(
        'proceeds anyway after the safety timeout if auth never resolves, '
        'rather than stranding the user on a black screen', (tester) async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);

      await tester.pumpWidget(_router(initial: '/splash', auth: auth.stream));
      await tester.pump();

      // Never emits into `auth` -- simulates a hung/broken restore. Two
      // separate pumps past the safety timeout, for the same settling
      // reason as the test above.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('home-stub'), findsOneWidget,
          reason: 'a stream that never resolves must not strand the user '
              'on the splash screen forever');
    });

    testWidgets(
        'reduce motion skips the logo fade/scale straight to its end state',
        (tester) async {
      // Purely decorative entrance -- under reduce motion the logo should
      // already be fully opaque and at its settled scale on the very first
      // frame, with no animated build-up.
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _router(initial: '/splash'),
      ));
      await tester.pump();

      // Scoped to an ancestor of the logo icon, and `.first` (the nearest
      // one) taken deliberately: `AppTheme`'s own page-route transition also
      // wraps its child in a `FadeTransition`/`ScaleTransition`, so a bare
      // `find.byType` here matches two of each.
      final fade = tester.widget<FadeTransition>(find
          .ancestor(
            of: find.byIcon(Icons.fitness_center),
            matching: find.byType(FadeTransition),
          )
          .first);
      expect(fade.opacity.value, 1.0);
      final scale = tester.widget<ScaleTransition>(find
          .ancestor(
            of: find.byIcon(Icons.fitness_center),
            matching: find.byType(ScaleTransition),
          )
          .first);
      expect(scale.scale.value, 1.0);

      // Drain the auto-navigation timer so it doesn't leak into the next test.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}

Widget _router({required String initial, Stream<AuthUser?>? auth}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home-stub'))),
    ],
  );
  return ProviderScope(
    overrides: [
      if (auth != null) authUserProvider.overrideWith((ref) => auth),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}
