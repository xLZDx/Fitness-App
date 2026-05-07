import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress/progress_page.dart';
import '../helpers/test_app.dart';

void main() {
  group('ProgressPage', () {
    testWidgets('renders all four stat tiles', (tester) async {
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('Total workouts'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Current streak'), findsOneWidget);
      expect(find.text('Longest'), findsOneWidget);
    });

    testWidgets('shows the trends section header and placeholder',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('Trends'), findsOneWidget);
      expect(find.textContaining('Charts will appear'), findsOneWidget);
    });
  });
}
