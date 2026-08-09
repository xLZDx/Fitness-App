import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/glass.dart';

void main() {
  group('GlassCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(child: Text('inside-card')),
          ),
        ),
      );
      expect(find.text('inside-card'), findsOneWidget);
    });

    // This test used to assert the opposite — that a card ALWAYS carries a
    // BackdropFilter — which is exactly the behaviour that made scrolling
    // crawl: 11 backdrop blurs on the workout page, 7 on home, none of them
    // cacheable. The default is now off and the expensive path is opt-in.
    testWidgets('does not frost the backdrop by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(child: SizedBox(width: 100, height: 100)),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('frosts the backdrop when explicitly asked', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              blur: true,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('an unfrosted card still reads as a surface', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(child: SizedBox(width: 100, height: 100)),
          ),
        ),
      );
      // Losing the frost means the fill carries the separation from the
      // background on its own, so it must be meaningfully opaque.
      //
      // 2026-08-09 (Ф1c): this asserted a `LinearGradient` at alpha > 0.6.
      // The fill is a flat opaque colour now — the prototype's cards are one
      // tone with a hairline border, and a two-stop white gradient at 0.22 is
      // the "glass" its design-system page rules out for regular surfaces.
      // The assertion is kept and tightened rather than dropped: what this
      // test is really for is that the card is a surface, and full opacity is
      // a stronger form of the same claim.
      // Pick the filled box rather than `.first`: Material and the Scaffold
      // contribute DecoratedBoxes of their own.
      final fills = tester
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(GlassCard), matching: find.byType(DecoratedBox)))
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null)
          .toList();
      expect(fills, isNotEmpty, reason: 'the card should have a flat fill');
      expect(fills.first.color!.a, 1.0);
    });

    testWidgets('invokes onTap when pressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassCard(
              onTap: () => taps += 1,
              child: const Text('tap-me'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap-me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('applies a non-null shadow for floating depth',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(child: SizedBox(width: 100, height: 100)),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final dec = container.decoration as BoxDecoration;
      expect(dec.boxShadow, isNotNull);
      expect(dec.boxShadow!.length, greaterThan(0));
    });

    testWidgets('GlassAppBar exposes a 64px preferred height', (tester) async {
      const bar = GlassAppBar(title: 't');
      expect(bar.preferredSize.height, 64);
    });

    testWidgets('FrostedScaffold uses transparent background',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FrostedScaffold(body: Text('body-text')),
        ),
      );
      expect(find.text('body-text'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.transparent);
      expect(scaffold.extendBody, isTrue);
      expect(scaffold.extendBodyBehindAppBar, isTrue);
    });
  });
}
