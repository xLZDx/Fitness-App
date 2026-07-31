import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/glass.dart';

/// A sheet has to be a surface, not a tint.
///
/// Operator, on the day-3 donation sheet: *"поздравление с 3 днем просто
/// наезжает и не читается"*. Its heading rendered directly on top of
/// "Восстановление за сегодня", "Шаги 834" and a stats row, and none of the
/// three could be read. The barrier behind it was not the problem — text over
/// dimmed text is still text over text.
///
/// The cause was systemic rather than local: every bottom sheet in the app is
/// `showModalBottomSheet(backgroundColor: Colors.transparent)` wrapping a
/// `GlassCard`, and a GlassCard is white at 0.22 alpha in dark mode. Inside a
/// page that reads as a surface, because the app controls what is behind it.
/// A sheet opens over whatever happened to be on screen.

Gradient _fillOf(WidgetTester t) {
  // The one with a gradient, not simply the first: GlassCard's outer Container
  // also carries a BoxDecoration, for the drop shadow, and it has no fill.
  final boxes = t
      .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(GlassCard), matching: find.byType(DecoratedBox)))
      .map((b) => b.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.gradient != null);
  expect(boxes, hasLength(1), reason: 'expected exactly one filled surface');
  return boxes.first.gradient!;
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a floating card is opaque', (t) async {
    await t.pumpWidget(_host(const GlassCard(floating: true, child: Text('x'))));
    for (final c in (_fillOf(t) as LinearGradient).colors) {
      expect(c.a, 1.0, reason: 'a sheet must not show the page through it');
    }
  });

  testWidgets('an ordinary card is still translucent', (t) async {
    // The look is the point of the design everywhere else; this fix must not
    // turn the whole app into flat panels.
    await t.pumpWidget(_host(const GlassCard(child: Text('x'))));
    final colours = (_fillOf(t) as LinearGradient).colors;
    expect(colours.every((c) => c.a < 1.0), isTrue);
  });

  testWidgets('an explicit gradient still wins', (t) async {
    await t.pumpWidget(_host(const GlassCard(
      floating: true,
      gradient: LinearGradient(colors: [Colors.red, Colors.blue]),
      child: Text('x'),
    )));
    expect((_fillOf(t) as LinearGradient).colors, [Colors.red, Colors.blue]);
  });

  test('every transparent-backed sheet uses a floating card', () {
    // A source scan, because the failure is invisible at runtime until someone
    // opens the sheet over a busy page and reads it. Adding the ninth sheet by
    // copying one of the eight is exactly how this comes back.
    // Two pages open a sheet whose BODY lives in another file, so the card
    // this is asking about is not in the same source. Both open the plate and
    // warm-up calculators, and both of those are marked floating where they
    // are defined. Named rather than pattern-matched, so adding a third has to
    // be a deliberate edit here.
    const bodyLivesElsewhere = {
      'equipment_detail_page.dart',
      'workout_player_page.dart',
    };

    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (bodyLivesElsewhere.any(f.path.endsWith)) continue;
      final src = f.readAsStringSync();
      if (!src.contains('showModalBottomSheet')) continue;
      if (!src.contains('backgroundColor: Colors.transparent')) continue;
      if (src.contains('GlassCard(') && !src.contains('floating: true')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'sheets whose card would show the page through it: $offenders');
  });
}
