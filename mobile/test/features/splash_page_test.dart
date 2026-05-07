import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/splash/splash_page.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

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
  });
}

Widget _router({required String initial}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home-stub'))),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}
