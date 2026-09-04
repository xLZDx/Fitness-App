import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';

/// The Scan screen's production controls row (gallery + live toggle),
/// rendered in the language the app ships in.
///
/// ## Why this test is in Russian
///
/// The strip this row replaced overflowed by 12 pixels on a real device and
/// no host test saw it, because `test/helpers/test_app.dart` pins `en` for
/// every widget test — a deliberate choice that keeps assertions readable and
/// stops a Russian copy tweak from breaking a test that is not about
/// translation. It also means the suite measures every layout against the
/// SHORTEST strings the app has.
///
/// "From gallery" and "Live" are short. Production pins `ru` (`lib/main.dart`),
/// where they are "Из галереи" and "Живой режим". So the overflow was visible
/// to every actual user and to none of the host tests, and it took the device
/// walk to find it.
///
/// This one is pinned in `ru` on purpose. It is not a translation test — it is
/// a layout test, and Russian is simply the widest real input the row gets.
/// SCAN-G1 moved the controls from a scrim strip over the camera to a row
/// under the reference's primary button (`ScanControlsRow`); the contract --
/// fits at 320, toggle keeps its size, label ellipsises -- is unchanged.
Widget _harness({required Locale locale, required Size size}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: SizedBox(
            width: size.width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ScanControlsRow(
                onGallery: () {},
                live: false,
                onLive: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // 320 is the narrowest width Android still ships (a 4" device at mdpi), and
  // the emulator this was caught on is far wider — so passing here is a
  // stronger claim than "it fits on a Pixel".
  for (final width in const [320.0, 360.0, 411.0]) {
    testWidgets('the scan controls row fits at ${width.toInt()}px in Russian',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        locale: const Locale('ru'),
        size: Size(width, 800),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'a RenderFlex overflow here is what shipped to every '
              'Russian-speaking user');
    });
  }

  testWidgets('and still fits in English', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      size: const Size(320, 800),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the toggle keeps its full size while the label ellipsises',
      (tester) async {
    // The half that makes the fix a fix rather than a squeeze. A Switch
    // compressed to fit is a control that is hard to hit; a shortened label is
    // still readable.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      locale: const Locale('ru'),
      size: const Size(320, 800),
    ));
    await tester.pump();

    final sw = tester.getSize(find.byKey(const Key('scan-live-toggle')));
    expect(sw.width, greaterThan(40),
        reason: 'a Switch squeezed below its intrinsic width is not tappable');
    expect(find.byKey(const Key('scan-recognise-gallery')), findsOneWidget,
        reason: 'the gallery path is still offered at the narrowest width');
  });
}
