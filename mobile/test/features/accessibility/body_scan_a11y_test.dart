// T126 / A11Y-16 / I18N-08 (C26, Y-F5, Y-F16): the capture screen and the
// readiness status panel at text scale 2.0 in Russian on a 360x640 phone.
// No overflow, the shutter and the Close control stay on screen and >= 48 dp,
// and the shutter is hit-testable (tapping it starts the manual timer).
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/widgets/setup_status_panel.dart';
import 'package:fitness_app/features/progress_photos/scan/readiness_evaluator.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_capture_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../helpers/test_app.dart';
import '../progress_photos/scan/ui/scan_fakes.dart';

const _ru = Locale('ru');
const _phone = Size(360, 640);

Future<void> _setPhone(WidgetTester tester) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, {required double scale, Locale locale = _ru}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

class _CaptureRig {
  final camera = FakeScanCamera();
  final speaker = FakeSpeaker();
  final haptics = FakeHaptics();
  final scans = FakeScanRepository();
  final photos = MockProgressPhotosRepository();
  int nowMs = 0;

  Future<void> pump(WidgetTester tester,
      {required double scale, Locale locale = _ru}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanCameraProvider.overrideWith((ref) => camera),
        scanSpeakerProvider.overrideWithValue(speaker),
        scanHapticsProvider.overrideWithValue(haptics),
        scanClockProvider.overrideWithValue(() => nowMs),
        scanRepositoryProvider.overrideWithValue(scans),
        progressPhotosRepositoryProvider.overrideWithValue(photos),
      ],
      child: _app(const ScanCaptureScreen(), scale: scale, locale: locale),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// A frame with nobody in it: every readiness row fails or waits.
  Future<void> feedFailing(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      nowMs += 250;
      camera.ctrl.add(emptyFrame());
      await tester.pump();
      await tester.pump();
    }
  }
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  for (final locale in const [_ru, Locale('en')]) {
    testWidgets(
        'capture screen ${locale.languageCode} at text scale 2.0 on 360x640: no overflow, shutter and close usable',
        (tester) async {
      await _setPhone(tester);
      final r = _CaptureRig();
      await r.pump(tester, scale: 2.0, locale: locale);
      await r.feedFailing(tester);

      // No RenderFlex/layout exception was raised while building and updating.
      expect(tester.takeException(), isNull);

      final screen = Offset.zero & _phone;
      final shutter = find.byKey(const Key('scan.shutter'));
      final close = find.byKey(const Key('scan.close'));
      expect(shutter, findsOneWidget);
      expect(close, findsOneWidget);

      // Shutter: fully on screen, >= 48 dp both ways, outside the scroll area.
      final sr = _rect(tester, shutter);
      expect(sr.height, greaterThanOrEqualTo(48));
      expect(sr.width, greaterThanOrEqualTo(48));
      expect(screen.contains(sr.topLeft) && screen.contains(sr.bottomRight - const Offset(.01, .01)),
          isTrue, reason: 'shutter $sr must be inside $screen');
      expect(
          find.descendant(
              of: find.byKey(const Key('scan.panelScroll')),
              matching: shutter),
          findsNothing,
          reason: 'the shutter must not scroll away with the status rows');

      // Close: on screen, >= 48 dp, outside the scroll area.
      final cr = _rect(tester, close);
      expect(cr.width, greaterThanOrEqualTo(48));
      expect(cr.height, greaterThanOrEqualTo(48));
      expect(screen.contains(cr.topLeft), isTrue);
      expect(
          find.descendant(
              of: find.byKey(const Key('scan.panelScroll')), matching: close),
          findsNothing);

      // The status panel is bounded to half the screen height and scrolls.
      final scroll = find.byKey(const Key('scan.panelScroll'));
      expect(_rect(tester, scroll).height, lessThanOrEqualTo(_phone.height * 0.5));

      // Hit-testable: a real tap on the shutter starts the manual timer, which
      // shows the cancel control and disables the shutter.
      expect(find.byKey(const Key('scan.manualCancel')), findsNothing);
      await tester.tap(shutter);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scan.manualCancel')), findsOneWidget,
          reason: 'tap on the shutter did not reach the button');
      expect(tester.takeException(), isNull);

      // With the manual timer shown, the cancel control is also on screen and
      // >= 48 dp, and still no overflow.
      final cancel = _rect(tester, find.byKey(const Key('scan.manualCancel')));
      expect(cancel.height, greaterThanOrEqualTo(48));
      expect(screen.contains(cancel.bottomRight - const Offset(.01, .01)), isTrue);
    });
  }

  testWidgets('the status rows really exceed the bounded panel at 2.0 in RU (the scroll area is exercised)',
      (tester) async {
    await _setPhone(tester);
    final r = _CaptureRig();
    await r.pump(tester, scale: 2.0);
    await r.feedFailing(tester);
    final scrollable = find.descendant(
        of: find.byKey(const Key('scan.panelScroll')),
        matching: find.byType(Scrollable));
    final pos = tester.state<ScrollableState>(scrollable).position;
    expect(pos.maxScrollExtent, greaterThan(0),
        reason: 'if everything fits the overflow guard is not being tested');
    // All four rows are reachable by scrolling.
    for (final n in ['distance', 'lighting', 'position', 'orientation']) {
      final row = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('scan.check.$n.'));
      await tester.ensureVisible(row.first);
      await tester.pump();
      expect(row, findsOneWidget, reason: n);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('scale 1.0 control: the same screen has no overflow either', (tester) async {
    await _setPhone(tester);
    final r = _CaptureRig();
    await r.pump(tester, scale: 1.0);
    await r.feedFailing(tester);
    expect(tester.takeException(), isNull);
    expect(_rect(tester, find.byKey(const Key('scan.shutter'))).height,
        greaterThanOrEqualTo(48));
  });

  group('SetupStatusPanel alone', () {
    ReadinessResult failing() => const ReadinessResult(
        distance: CheckStatus.fail,
        lighting: CheckStatus.fail,
        position: CheckStatus.fail,
        orientation: CheckStatus.fail,
        hint: ReadinessHint.none);

    for (final scale in [1.5, 2.0]) {
      testWidgets('RU at ${scale}x: rows wrap, no overflow on a 360 dp width',
          (tester) async {
        await _setPhone(tester);
        await tester.pumpWidget(_app(
            Scaffold(body: SingleChildScrollView(child: SetupStatusPanel(result: failing()))),
            scale: scale));
        expect(tester.takeException(), isNull);
        for (final n in ['distance', 'lighting', 'position', 'orientation']) {
          final row = find.byKey(Key('scan.check.$n.fail'));
          expect(row, findsOneWidget);
          // Text never wider than the 360 dp screen (it wraps, not clips).
          expect(tester.getRect(row).right, lessThanOrEqualTo(_phone.width));
          // Row text is still the localised failure copy, not empty.
          final t = tester.widget<Text>(
              find.descendant(of: row, matching: find.byType(Text)));
          expect(t.data, isNotEmpty);
          expect(t.data, contains(':'));
        }
      });
    }

    testWidgets('+30 percent longer RU strings at 1.5x still do not overflow',
        (tester) async {
      await _setPhone(tester);
      // The longest failure copy the panel can show, stretched by 30 percent
      // is emulated by a narrower width: 360 / 1.3 = 277 dp.
      await tester.pumpWidget(_app(
          Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 277,
                      child: SingleChildScrollView(
                          child: SetupStatusPanel(result: failing()))))),
          scale: 1.5));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('scan.statusPanel')), findsOneWidget);
    });
  });
}
