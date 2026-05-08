import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress/progress_page.dart';
import '../helpers/test_app.dart';

Future<void> _setLargeSurface(WidgetTester tester) async {
  // The page packs four stat tiles + a chart card + a recent-activity card.
  // The default 800x600 test viewport clips the recent-activity card and
  // ListView won't lazily build it, so set a tall surface for the test.
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('ProgressPage (empty state)', () {
    testWidgets('renders all four stat tiles with zero values',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('Total workouts'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Current streak'), findsOneWidget);
      expect(find.text('Longest'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('0d'), findsNWidgets(2));
    });

    testWidgets('shows Last 8 weeks + Recent activity sections',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('Last 8 weeks'), findsOneWidget);
      expect(find.textContaining('Log a workout'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.textContaining('start your history'), findsOneWidget);
    });
  });
}
