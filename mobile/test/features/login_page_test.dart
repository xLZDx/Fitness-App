import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/auth/login_page.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

void main() {
  group('LoginPage', () {
    testWidgets('renders welcome copy and the two sign-in buttons',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('Terms and Privacy Policy'), findsOneWidget);
    });

    testWidgets('Continue button navigates to /home', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('Continue with Google also navigates to /home',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('home-stub'), findsOneWidget);
    });
  });
}

Widget _buildApp() {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
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
