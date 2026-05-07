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

    testWidgets('uses a BackdropFilter for glass blur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(child: SizedBox(width: 100, height: 100)),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
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
