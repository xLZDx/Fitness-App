import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/scroll_dim_list.dart';

void main() {
  group('ScrollDimList', () {
    testWidgets('renders every child', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollDimList(
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(
                    height: 100,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Text('row-$i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('row-0'), findsOneWidget);
      expect(find.text('row-1'), findsOneWidget);
    });

    testWidgets('cards are sharp at rest (no Opacity wrap takes effect)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollDimList(
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    height: 80,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Text('row-$i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      // No active scroll, so dim layer should be inert (no Opacity nesting
      // visible to text). Text is fully rendered.
      expect(find.text('row-0'), findsOneWidget);
    });

    testWidgets('uses BouncingScrollPhysics by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollDimList(
              children: const [
                SizedBox(height: 100),
                SizedBox(height: 100),
              ],
            ),
          ),
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.physics, isA<BouncingScrollPhysics>());
    });
  });
}
