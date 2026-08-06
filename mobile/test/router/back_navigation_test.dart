import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/about/about_page.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/login_page.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/donor_wall/donor_wall_page.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/shared/widgets/main_shell.dart';

/// Gate NAV regression tests.
///
/// Detail pages used to be opened with `context.go(...)`, which REPLACES the
/// navigation stack: no back arrow, and the system Back button closed the
/// app. They are now `push`ed, and `MainShell` carries a PopScope fallback so
/// Back on a non-home tab steps to /home instead of exiting.
///
/// NOTE on assertions: for imperative pushes, go_router 16 keeps
/// `currentConfiguration.uri` at the BASE location (verified against
/// go_router 16.1.0 — the pushed page renders while the uri stays put), so
/// pushed pages are asserted through rendered widgets, not through the uri.
void main() {
  group('pushed detail pages (real app router)', () {
    // Same harness as app_router_test.dart.
    Widget buildApp({
      required MockAuthRepository auth,
      required MockProfileRepository profiles,
      void Function(GoRouter)? capture,
    }) {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) {
            ref.onDispose(auth.dispose);
            return auth;
          }),
          profileRepositoryProvider.overrideWith((ref) {
            ref.onDispose(profiles.dispose);
            return profiles;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(appRouterProvider);
            capture?.call(router);
            return MaterialApp.router(
              theme: AppTheme.light(),
              locale: kTestLocale,
              localizationsDelegates: kTestLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            );
          },
        ),
      );
    }

    // Boots the app signed-out: splash hands off to /home, the redirect
    // rewrites to /login. /about and /donors are public, so they can be
    // pushed on top without Firebase or sign-in.
    Future<GoRouter> bootToLogin(WidgetTester tester) async {
      late GoRouter router;
      await tester.pumpWidget(buildApp(
        auth: MockAuthRepository(latency: Duration.zero),
        profiles: MockProfileRepository(latency: Duration.zero),
        capture: (r) => router = r,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LoginPage), findsOneWidget);
      return router;
    }

    testWidgets('pushed page shows a back arrow that pops back to its opener',
        (tester) async {
      final router = await bootToLogin(tester);

      router.push('/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsOneWidget);

      // GlassAppBar must imply the leading BackButton on a pushed page.
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('system back pops a pushed page instead of closing the app',
        (tester) async {
      final router = await bootToLogin(tester);

      router.push('/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsOneWidget);

      // routerDelegate.popRoute() is exactly what the system Back button
      // invokes (via the RootBackButtonDispatcher).
      final handled = await router.routerDelegate.popRoute();
      expect(handled, isTrue,
          reason: 'Back on a pushed page must pop it, not exit the app');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets(
        'converted call site stacks pages: about -> donor wall -> back -> about',
        (tester) async {
      final router = await bootToLogin(tester);

      router.push('/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsOneWidget);

      // Tap the real (converted) call site in about_page.dart, which now
      // pushes /donors instead of replacing the stack with it.
      await tester.scrollUntilVisible(find.text('See our supporter wall'), 200);
      await tester.tap(find.text('See our supporter wall'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(DonorWallPage), findsOneWidget);

      final handled = await router.routerDelegate.popRoute();
      expect(handled, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(DonorWallPage), findsNothing);
      expect(find.byType(AboutPage), findsOneWidget,
          reason: '/donors must sit ON TOP of /about, not replace it');
    });
  });

  group('MainShell root back fallback', () {
    // Minimal router with the app's exact shell shape (ShellRoute wrapping
    // the real MainShell, tab paths replaced by `go`) plus one top-level
    // detail route, so back-button semantics are tested without Firebase.
    GoRouter buildShellRouter() {
      return GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/detail',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('detail-stub'))),
          ),
          ShellRoute(
            builder: (context, state, child) => MainShell(child: child),
            routes: [
              for (final p in [
                '/home',
                '/scan',
                '/workouts',
                '/progress',
                '/profile'
              ])
                GoRoute(
                  path: p,
                  builder: (_, __) =>
                      Scaffold(body: Center(child: Text('stub-$p'))),
                ),
            ],
          ),
        ],
      );
    }

    String pathOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('system back on a non-home tab goes to /home, not out of app',
        (tester) async {
      final router = buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      router.go('/profile');
      await tester.pumpAndSettle();
      expect(pathOf(router), '/profile');
      expect(find.text('stub-/profile'), findsOneWidget);

      final handled = await router.routerDelegate.popRoute();
      expect(handled, isTrue,
          reason: 'Back on a tab must be intercepted by the shell fallback, '
              'not bubble out and close the app');
      await tester.pumpAndSettle();
      expect(pathOf(router), '/home');
      expect(find.text('stub-/home'), findsOneWidget);
    });

    testWidgets('system back on /home bubbles to the system (app may close)',
        (tester) async {
      final router = buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      expect(pathOf(router), '/home');

      final handled = await router.routerDelegate.popRoute();
      expect(handled, isFalse,
          reason: 'On /home nothing intercepts Back: default system '
              'behavior (the app may close)');
      await tester.pumpAndSettle();
      expect(pathOf(router), '/home');
    });

    testWidgets('fallback does not hijack pops of pushed pages', (tester) async {
      final router = buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      router.go('/profile');
      await tester.pumpAndSettle();
      router.push('/detail');
      await tester.pumpAndSettle();
      expect(find.text('detail-stub'), findsOneWidget);

      // First back: pops the pushed page back to its opener tab.
      expect(await router.routerDelegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('detail-stub'), findsNothing);
      expect(find.text('stub-/profile'), findsOneWidget);

      // Second back: nothing left to pop, fallback steps to /home.
      expect(await router.routerDelegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(pathOf(router), '/home');
      expect(find.text('stub-/home'), findsOneWidget);

      // Third back: on /home it bubbles to the system.
      expect(await router.routerDelegate.popRoute(), isFalse);
    });
  });
}
