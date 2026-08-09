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

/// The card's fill, whichever form it takes.
///
/// 2026-08-09 (Ф1c): a card's default fill is a flat `color` now, not a
/// `LinearGradient`, so a helper that only looked for `gradient != null` found
/// nothing and every test using it failed on the helper rather than on its own
/// assertion. Both shapes are returned because `gradient` is still the answer
/// when a caller passes one explicitly.
BoxDecoration _fillOf(WidgetTester t) {
  // The one that has a fill, not simply the first: GlassCard's outer Container
  // also carries a BoxDecoration, for the drop shadow, and it has no fill.
  final boxes = t
      .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(GlassCard), matching: find.byType(DecoratedBox)))
      .map((b) => b.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.gradient != null || d.color != null);
  expect(boxes, hasLength(1), reason: 'expected exactly one filled surface');
  return boxes.first;
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a floating card is opaque', (t) async {
    await t.pumpWidget(_host(const GlassCard(floating: true, child: Text('x'))));
    expect(_fillOf(t).color?.a, 1.0,
        reason: 'a sheet must not show the page through it');
  });

  testWidgets('an ordinary card is opaque too', (t) async {
    // 2026-08-09 (Ф1c): this test asserted the OPPOSITE — that a non-floating
    // card stays translucent — on the reasoning that "the look is the point of
    // the design everywhere else". That reasoning was wrong about the design.
    //
    // The prototype's own design-system page lists where glass may be used
    // (camera overlays, floating controls, modal sheets, temporary status
    // overlays) and marks three things it must NOT be used on: "Scrolling
    // cards", "Exercise list items", "Regular surfaces". An ordinary GlassCard
    // is all three. Translucency also made the surface colour unstable —
    // white over an olive-tinted backdrop is a different colour than white
    // over black, so the same card read differently on every screen.
    //
    // Kept rather than deleted: the invariant is still worth pinning, it just
    // points the other way now. Deleting it would leave nothing asserting that
    // cards have a fill at all.
    await t.pumpWidget(_host(const GlassCard(child: Text('x'))));
    expect(_fillOf(t).color?.a, 1.0);
  });

  testWidgets('an explicit gradient still wins', (t) async {
    await t.pumpWidget(_host(const GlassCard(
      floating: true,
      gradient: LinearGradient(colors: [Colors.red, Colors.blue]),
      child: Text('x'),
    )));
    expect((_fillOf(t).gradient! as LinearGradient).colors,
        [Colors.red, Colors.blue]);
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
