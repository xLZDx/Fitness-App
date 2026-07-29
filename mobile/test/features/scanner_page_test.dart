import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

void main() {
  group('ScannerPage', () {
    testWidgets('leads with machine recognition, QR is the background job',
        (tester) async {
      // MUST pump with the real app theme: it sets button minimumSize to
      // Size.fromHeight(54) (minWidth == infinity), which crashed layout on
      // a Row-placed button while a default-theme test stayed green.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: AppTheme.light(), home: const ScannerPage()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Primary action is recognising a machine from a photo.
      expect(find.byKey(const Key('scan-recognise-camera')), findsOneWidget);
      expect(find.text('Recognise machine'), findsOneWidget);
      expect(find.byKey(const Key('scan-recognise-gallery')), findsOneWidget);
      // QR is described as automatic, not as the thing the user must do.
      expect(find.textContaining('QR stickers are picked up automatically'),
          findsOneWidget);
    });

    testWidgets('renders classifier matches with confidence', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            visualEquipmentServiceProvider.overrideWithValue(
              MockVisualEquipmentService(fixedResults: const [
                VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
                VisualMatch(equipmentId: 'treadmill', confidence: 0.2),
              ]),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const ScannerPage()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Drive the controller directly: tapping the button would open the
      // real platform image picker, which has no test binding.
      final element = tester.element(find.byType(ScannerPage));
      final container = ProviderScope.containerOf(element);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(find.text('Best matches'), findsOneWidget);
      expect(find.text('leg press'), findsOneWidget);
      expect(find.text('80% confidence'), findsOneWidget);
      expect(find.text('treadmill'), findsOneWidget);
    });
  });
}
