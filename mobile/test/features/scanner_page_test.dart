import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/scanner/scanner_page.dart';
import '../helpers/test_app.dart';

void main() {
  group('ScannerPage', () {
    testWidgets('shows scanner placeholder copy and recent scans tile',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const ScannerPage()));
      await tester.pump();

      expect(find.text('Scan'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      expect(find.text('Camera scanner coming up'), findsOneWidget);
      expect(find.text('Recent scans'), findsOneWidget);
    });

    testWidgets('has a scrollable body so the layout cannot overflow',
        (tester) async {
      await tester.pumpWidget(testHarness(child: const ScannerPage()));
      await tester.pump();
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
