import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/glass_nav_bar.dart';

const _items = [
  GlassNavItem(
    icon: Icons.home_outlined,
    iconSelected: Icons.home_rounded,
    label: 'Home',
    gradient: [Color(0xFFFF6FB5), Color(0xFF8A5BFF)],
  ),
  GlassNavItem(
    icon: Icons.qr_code_scanner_outlined,
    iconSelected: Icons.qr_code_scanner,
    label: 'Scan',
    gradient: [Color(0xFF8A5BFF), Color(0xFF3DC8FF)],
  ),
  GlassNavItem(
    icon: Icons.person_outline,
    iconSelected: Icons.person,
    label: 'Profile',
    gradient: [Color(0xFFFFB37C), Color(0xFFFF6FB5)],
  ),
];

Widget _harness(int selectedIndex, ValueChanged<int> onSelect) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 320, height: 100),
      bottomNavigationBar: GlassNavBar(
        items: _items,
        selectedIndex: selectedIndex,
        onSelect: onSelect,
      ),
    ),
  );
}

void main() {
  group('GlassNavBar', () {
    testWidgets('renders a label for every item', (tester) async {
      await tester.pumpWidget(_harness(0, (_) {}));
      for (final item in _items) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('uses the selected icon for the selected index',
        (tester) async {
      await tester.pumpWidget(_harness(1, (_) {}));
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('calls onSelect with the tapped tab index', (tester) async {
      int? selected;
      await tester.pumpWidget(_harness(0, (i) => selected = i));
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(selected, 2);
    });
  });
}
