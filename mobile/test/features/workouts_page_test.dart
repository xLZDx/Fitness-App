import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/scroll_dim_list.dart';
import '../helpers/test_app.dart';

void main() {
  group('WorkoutsPage', () {
    testWidgets('renders all five filter chips with For you selected',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const WorkoutsPage()));
      await tester.pump();

      for (final f in ['For you', 'Strength', 'Cardio', 'Mobility', 'Yoga']) {
        expect(find.text(f), findsOneWidget);
      }
    });

    testWidgets('shows a ScrollDimList for the workout list',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const WorkoutsPage()));
      await tester.pump();
      expect(find.byType(ScrollDimList), findsOneWidget);
    });

    testWidgets('changing filter updates the visible card title',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const WorkoutsPage()));
      await tester.pump();

      // Default filter is "For you" — first card is "Push day".
      expect(find.text('Push day'), findsOneWidget);

      await tester.tap(find.text('Cardio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      // Cardio filter's first card is "HIIT burn".
      expect(find.text('HIIT burn'), findsOneWidget);
    });
  });
}
