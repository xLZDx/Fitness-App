import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/profile/profile_page.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

void main() {
  group('ProfilePage', () {
    testWidgets('renders the guest header and primary menu items',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('Guest user'), findsOneWidget);
      expect(find.text('Health questionnaire'), findsOneWidget);
      expect(find.text('Connected devices'), findsOneWidget);
      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('Sign out tile navigates to /login', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('login-stub'), findsOneWidget);
    });
  });
}

Widget _buildApp() {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('login-stub'))),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}
