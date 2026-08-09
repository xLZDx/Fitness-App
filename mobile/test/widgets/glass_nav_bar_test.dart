import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/glass_nav_bar.dart';
import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

const _items = [
  GlassNavItem(icon: Icons.grid_view_outlined, label: 'Home'),
  GlassNavItem(icon: Icons.radio_button_checked, label: 'Scan', raised: true),
  GlassNavItem(icon: Icons.person_outline, label: 'Profile'),
];

Widget _harness(int selectedIndex, ValueChanged<int> onSelect,
    {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.dark(),
    home: Scaffold(
      body: const SizedBox(width: 320, height: 100),
      bottomNavigationBar: GlassNavBar(
        items: _items,
        selectedIndex: selectedIndex,
        onSelect: onSelect,
      ),
    ),
  );
}

Color _iconColour(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color!;

void main() {
  group('GlassNavBar', () {
    testWidgets('renders a label for every item', (tester) async {
      await tester.pumpWidget(_harness(0, (_) {}));
      for (final item in _items) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('marks the selection with colour, not with a second glyph',
        (tester) async {
      // The old bar swapped every tab between an outlined and a filled icon and
      // slid a gradient pill under the selected one. The design does neither:
      // one glyph per tab, and the accent is the whole signal.
      await tester.pumpWidget(_harness(0, (_) {}));

      const dark = AppSemanticColors.dark;
      expect(_iconColour(tester, Icons.grid_view_outlined), dark.accentPrimary);
      expect(_iconColour(tester, Icons.person_outline), dark.textSecondary);

      final label = tester.widget<Text>(find.text('Home'));
      expect(label.style?.color, dark.accentPrimary);
    });

    testWidgets('paints no gradient anywhere', (tester) async {
      // The regression guard for the selected-tab pill. It was an aurora pair
      // per tab, and the aurora gradients are the thing Ф1 removed.
      await tester.pumpWidget(_harness(1, (_) {}));

      final decorated = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(DecoratedBox),
      ));
      expect(decorated, isNotEmpty);
      for (final box in decorated) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.gradient, isNull);
        }
      }
    });

    testWidgets('lifts the raised tab out of the bar, and only that tab',
        (tester) async {
      await tester.pumpWidget(_harness(0, (_) {}));

      final bar = tester.getRect(find.byType(GlassNavBar));
      final circle = tester.getRect(find
          .descendant(
            of: find.byType(OverflowBox),
            matching: find.byType(DecoratedBox),
          )
          .first);

      // Drawn at full size even though its slot in the column is 18px shorter.
      expect(circle.height, GlassNavBar.circleSize);
      expect(circle.top, lessThan(bar.top));

      // Its neighbours stay inside the bar — the lift is one element's, not the
      // row's.
      expect(tester.getRect(find.byIcon(Icons.grid_view_outlined)).top,
          greaterThan(bar.top));
    });

    testWidgets('calls onSelect with the tapped tab index', (tester) async {
      int? selected;
      await tester.pumpWidget(_harness(0, (i) => selected = i));
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(selected, 2);
    });

    testWidgets('the raised tab answers taps at the top of its circle',
        (tester) async {
      // Two things could have left a dead cap on the app's most prominent
      // control: lifting the circle with a `Transform` (paints high, hit box
      // stays put), or letting each tab shrink to its own content (ink region
      // starts below the bar's top edge). This taps the circle itself, near
      // its top, rather than its centre — the centre passes either way.
      int? selected;
      await tester.pumpWidget(_harness(0, (i) => selected = i));

      final bar = tester.getRect(find.byType(GlassNavBar));
      final circle = tester.getRect(find
          .descendant(
            of: find.byType(OverflowBox),
            matching: find.byType(DecoratedBox),
          )
          .first);
      await tester.tapAt(Offset(circle.center.dx, bar.top + 2));
      await tester.pump();
      expect(selected, 1);
    });

    testWidgets('renders under a bare MaterialApp', (tester) async {
      // Shared chrome, and its tokens are read nullably for this reason. Ф1b
      // shipped `context.colors` here — a getter ending in `!` — and every
      // widget test that pumped a themeless app died before layout.
      await tester.pumpWidget(_harness(0, (_) {}, theme: ThemeData()));
      expect(tester.takeException(), isNull);
      expect(find.text('Scan'), findsOneWidget);
    });
  });
}
