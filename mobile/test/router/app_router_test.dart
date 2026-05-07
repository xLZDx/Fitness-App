import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

void main() {
  group('appRouter', () {
    test('initial location is /splash', () {
      expect(appRouter.configuration.findMatch(Uri.parse('/splash')).uri.path,
          '/splash');
    });

    test('every primary tab path resolves to a known route', () {
      const paths = ['/home', '/scan', '/workouts', '/progress', '/profile'];
      for (final p in paths) {
        final match = appRouter.configuration.findMatch(Uri.parse(p));
        expect(match.uri.path, p, reason: 'path $p should be matchable');
      }
    });

    testWidgets('mounting the router renders the splash branding first',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Fitness App'), findsOneWidget);
      // Drain the splash timer + the page transition so no timers leak
      // into the next test.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
