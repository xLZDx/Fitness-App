import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/equipment_identity_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

/// Silent-failure review (P2.G4, this gate): confirms the fix for a real,
/// confirmed unbounded-growth bug -- `_classify` used to only ever remove a
/// superseded scanId's `scanIdImagePathProvider` entry via the explicit
/// `_scanAgain()` event, but the gallery button (unlike the camera capture
/// button) is never gated behind that event, so repeated gallery picks with
/// no intervening "Scan again" tap grew the map by one entry per pick for
/// the lifetime of the app process. See `scanner_page.dart`'s own
/// `_classify` doc comment for the fix.
///
/// Answers the gallery pick with a DIFFERENT path each call, so two
/// successive picks are provably two different scans rather than a retry.
class _SequencedImagePicker extends ImagePickerPlatform {
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    return XFile('/tmp/picked-$calls.jpg');
  }
}

/// Answers every classification with no matches -- irrelevant to this test,
/// which only cares about `scanIdImagePathProvider`'s map, never the
/// recognition result itself.
class _EmptyMatchService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      const [];
}

void main() {
  testWidgets(
    'two gallery picks with no intervening "Scan again" leave only the latest scanId registered',
    (tester) async {
      final picker = _SequencedImagePicker();
      final previousPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = picker;
      addTearDown(() => ImagePickerPlatform.instance = previousPicker);

      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(
            path: '/scan',
            builder: (_, __) => const Scaffold(
              backgroundColor: Colors.transparent,
              body: ScannerPage(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          visualEquipmentServiceProvider.overrideWithValue(_EmptyMatchService()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pump();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(ScannerPage)));

      Future<void> tapGallery() async {
        final gallery = find.byKey(const Key('scan-recognise-gallery'));
        await tester.scrollUntilVisible(gallery, 120);
        await tester.tap(gallery);
        await tester.pump();
        await tester.pump();
      }

      await tapGallery();
      expect(picker.calls, 1);
      final afterFirst = container.read(scanIdImagePathProvider);
      expect(afterFirst.length, 1, reason: 'first scan registers exactly one entry');

      // Deliberately no "Scan again" tap here -- the whole point of this test
      // is the path that skips it.
      await tapGallery();
      expect(picker.calls, 2);
      final afterSecond = container.read(scanIdImagePathProvider);
      expect(
        afterSecond.length,
        1,
        reason: 'a second fresh scan must supersede the first, not accumulate '
            'alongside it',
      );
      expect(
        afterSecond.values.single,
        '/tmp/picked-2.jpg',
        reason: 'the surviving entry must be the LATEST scan, not the first',
      );
    },
  );
}
