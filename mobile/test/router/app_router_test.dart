import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  group('resolveRedirect (pure)', () {
    test('splash always passes through', () {
      expect(
          resolveRedirect(
              isSignedIn: false, isOnboarded: false, location: '/splash'),
          isNull);
      expect(
          resolveRedirect(
              isSignedIn: true, isOnboarded: true, location: '/splash'),
          isNull);
    });

    test('login is reachable when signed out', () {
      expect(
          resolveRedirect(
              isSignedIn: false, isOnboarded: false, location: '/login'),
          isNull);
    });

    test('signed-in user on /login bounces to /home when onboarded', () {
      expect(
        resolveRedirect(
            isSignedIn: true, isOnboarded: true, location: '/login'),
        '/home',
      );
    });

    test('signed-in user on /login bounces to /onboarding when not onboarded',
        () {
      expect(
        resolveRedirect(
            isSignedIn: true, isOnboarded: false, location: '/login'),
        '/onboarding',
      );
    });

    test('every gated tab redirects to /login when signed out', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile',
        '/onboarding'
      ]) {
        expect(
          resolveRedirect(
              isSignedIn: false, isOnboarded: false, location: p),
          '/login',
          reason: 'gated path $p must redirect when signed out',
        );
      }
    });

    test('signed-in but not onboarded → forced into /onboarding', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile'
      ]) {
        expect(
          resolveRedirect(
              isSignedIn: true, isOnboarded: false, location: p),
          '/onboarding',
          reason: '$p should redirect to /onboarding while not onboarded',
        );
      }
    });

    test('signed-in and onboarded passes through every tab', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile'
      ]) {
        expect(
          resolveRedirect(isSignedIn: true, isOnboarded: true, location: p),
          isNull,
        );
      }
    });

    test('onboarded user landing on /onboarding is bounced to /home', () {
      expect(
        resolveRedirect(
            isSignedIn: true, isOnboarded: true, location: '/onboarding'),
        '/home',
      );
    });
  });

  group('appRouter integration', () {
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
              routerConfig: router,
            );
          },
        ),
      );
    }

    String pathOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('boots to /splash, then redirects unsigned users to /login',
        (tester) async {
      late GoRouter router;
      await tester.pumpWidget(buildApp(
        auth: MockAuthRepository(latency: Duration.zero),
        profiles: MockProfileRepository(latency: Duration.zero),
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
