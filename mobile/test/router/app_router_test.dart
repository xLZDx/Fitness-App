import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

void main() {
  group('resolveRedirect (pure)', () {
    test('splash always passes through', () {
      expect(resolveRedirect(isSignedIn: false, location: '/splash'), isNull);
      expect(resolveRedirect(isSignedIn: true, location: '/splash'), isNull);
    });

    test('login is reachable when signed out, redirects when signed in', () {
      expect(resolveRedirect(isSignedIn: false, location: '/login'), isNull);
      expect(
        resolveRedirect(isSignedIn: true, location: '/login'),
        '/home',
      );
    });

    test('every gated tab redirects to /login when signed out', () {
      for (final p in ['/home', '/scan', '/workouts', '/progress', '/profile']) {
        expect(
          resolveRedirect(isSignedIn: false, location: p),
          '/login',
          reason: 'gated path $p must redirect when signed out',
        );
      }
    });

    test('every gated tab passes through when signed in', () {
      for (final p in ['/home', '/scan', '/workouts', '/progress', '/profile']) {
        expect(
          resolveRedirect(isSignedIn: true, location: p),
          isNull,
          reason: 'gated path $p must be reachable when signed in',
        );
      }
    });
  });

  group('appRouter integration', () {
    Widget buildApp(MockAuthRepository repo,
        {void Function(GoRouter)? capture}) {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) {
            ref.onDispose(repo.dispose);
            return repo;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(appRouterProvider);
            capture?.call(router);
            return MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: router,
            );
          },
        ),
      );
    }

    String pathOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('boots to /splash, redirects unsigned users to /login',
        (tester) async {
      late GoRouter router;
      await tester.pumpWidget(buildApp(
        MockAuthRepository(latency: Duration.zero),
        capture: (r) => router = r,
      ));
      await tester.pump();
      expect(pathOf(router), '/splash');

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(pathOf(router), '/login');
    });
  });
}
