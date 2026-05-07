import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/scroll_dim_list.dart';

void main() {
  group('HomePage', () {
    testWidgets('renders the hero card and primary sections',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('GOOD MORNING'), findsOneWidget);
      expect(find.text('Ready to train?'), findsOneWidget);
      expect(find.text('Scan equipment'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      // Quick stats and Suggestions live below the fold with the new
      // spacing — they're verified by other tests after a scroll.
    });

    testWidgets('shows three quick stat tiles', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
    });

    testWidgets('uses a ScrollDimList for the home content', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      expect(find.byType(ScrollDimList), findsOneWidget);
    });

    testWidgets('renders every suggestion title (cards are not hidden)',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      // First card is in viewport; later cards may need a scroll.
      await tester.scrollUntilVisible(
        find.text('Active recovery'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Upper body power'), findsOneWidget);
      expect(find.text('HIIT cardio burn'), findsOneWidget);
      expect(find.text('Mobility & recovery'), findsOneWidget);
      expect(find.text('Full body strength'), findsOneWidget);
      expect(find.text('Active recovery'), findsOneWidget);
    });

    testWidgets('Scan equipment button navigates to /scan', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      await tester.tap(find.text('Scan equipment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('scan-stub'), findsOneWidget);
    });
  });
}

Widget _buildApp() {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/scan',
          builder: (_, __) => const Scaffold(body: Text('scan-stub'))),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}
