import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/scanner/scanner_page.dart';

void main() {
  group('ScannerPage', () {
    testWidgets('renders the scan-guide overlay copy', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ScannerPage()),
        ),
      );
      await tester.pump();

      expect(find.text('Point at any equipment QR'), findsOneWidget);
      expect(find.textContaining('exercises tuned to your profile'),
          findsOneWidget);
    });
  });
}
