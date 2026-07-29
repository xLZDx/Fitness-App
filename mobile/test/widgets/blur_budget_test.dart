import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

import 'package:fitness_app/shared/widgets/glass.dart';

/// Guards the frame budget for backdrop blur.
///
/// `BackdropFilter` reads back the composited backdrop, blurs it, and cannot be
/// cached — it is among the most expensive things a Flutter frame can contain.
/// Cards used to switch it on unconditionally, so a scroll on the workout page
/// composited 11 of them per frame (measured with this same counting technique)
/// plus the app bar's and nav bar's, and the operator reported the whole app
/// crawling while scrolling.
///
/// The rule these tests pin: repeated content carries no blur, non-repeating
/// chrome may.
void main() {
  Widget cards(int n) => testHarness(
        child: ListView(
          children: [
            for (var i = 0; i < n; i++)
              const GlassCard(child: SizedBox(height: 90, child: Text('c'))),
          ],
        ),
      );

  testWidgets('a page full of cards composites no backdrop blur',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(cards(11));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing,
        reason: 'this is the workout page card count; each blur here costs a '
            'full-surface read-back that cannot be cached');
  });

  testWidgets('blur stays available for non-repeating chrome', (tester) async {
    await tester.pumpWidget(testHarness(
      child: const GlassCard(
        blur: true,
        child: SizedBox(height: 60, child: Text('chrome')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('the app bar keeps its frost', (tester) async {
    await tester.pumpWidget(testHarness(
      child: const FrostedScaffold(
        appBar: GlassAppBar(title: 'Title'),
        body: Text('body'),
      ),
    ));
    await tester.pumpAndSettle();

    // One fixed blur for the chrome is affordable; N per scrolled card is not.
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
