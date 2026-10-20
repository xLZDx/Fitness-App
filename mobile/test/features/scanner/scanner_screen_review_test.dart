import 'package:camera/camera.dart' show XFile;
import 'package:fitness_app/core/camera/camera_availability.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/scanner/widgets/scan_frame.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/test_app.dart';

/// Independent review of the scan screen (2026-10-14): the shutter without a
/// camera, the pinned header under a large text scale, and short (landscape)
/// windows. Each test fails if its fix is reverted.

/// A session that never opens: [start] throws the given reason until [fixed],
/// and every capture request is counted.
class _CountingSession extends CameraSession {
  _CountingSession(this.reason);

  final CameraUnavailableReason reason;
  bool fixed = false;
  int captures = 0;
  int starts = 0;

  @override
  Future<void> start({bool requestPermission = false}) async {
    starts++;
    if (fixed) return;
    throw CameraUnavailable(reason);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<XFile?> captureStill() async {
    captures++;
    return null;
  }
}

class _QuietSession extends CameraSession {
  @override
  Future<void> start({bool requestPermission = false}) async {}

  @override
  Future<void> stop() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required CameraSession session,
  Size size = const Size(400, 900),
  double textScale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
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
      scanCameraSessionProvider.overrideWithValue(session),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  // Armed from a post-frame callback; the header is measured one frame later.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(Key(key)));

void main() {
  group('the shutter without a camera', () {
    testWidgets('is disabled and a tap captures nothing', (tester) async {
      final session = _CountingSession(CameraUnavailableReason.permissionDenied);
      await _pump(tester, session: session);

      expect(find.text('Camera access needed'), findsOneWidget);
      final shutter = find.byKey(const Key('scan-recognise-camera'));
      expect(tester.widget<HudButton>(shutter).enabled, isFalse,
          reason: 'no camera, no shutter: it must not wait 8 s and then fail');

      await tester.tap(shutter, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(session.captures, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('comes back as soon as the camera does', (tester) async {
      final session = _CountingSession(CameraUnavailableReason.permissionDenied);
      await _pump(tester, session: session);
      final shutter = find.byKey(const Key('scan-recognise-camera'));
      expect(tester.widget<HudButton>(shutter).enabled, isFalse);

      session.fixed = true;
      await tester.tap(find.byKey(const Key('scan-camera-retry')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.widget<HudButton>(shutter).enabled, isTrue);
      await tester.tap(shutter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(session.captures, 1, reason: 'a working camera is asked to shoot');
    });
  });

  group('the pinned header and the text scale', () {
    Future<void> expectReachable(WidgetTester tester) async {
      final Rect sheet = _rect(tester, 'scan-sheet-surface');
      final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final key in const [
        'scan-recognise-camera',
        'scan-recognise-gallery',
        'scan-live-toggle',
        'scan-privacy-strip',
      ]) {
        final Rect r = _rect(tester, key);
        expect(sheet.top <= r.top + 0.5 && r.bottom <= sheet.bottom + 0.5, isTrue,
            reason: '$key ($r) must lie inside the collapsed sheet ($sheet)');
        expect(r.bottom, lessThanOrEqualTo(screen.height + 0.5));
      }
    }

    testWidgets('at the normal scale the header never drops below its floor '
        'and still holds everything', (tester) async {
      await _pump(tester, session: _QuietSession());
      expect(_rect(tester, 'scan-sheet-surface').height,
          greaterThanOrEqualTo(kScanSheetCollapsedPx - 1.5));
      await expectReachable(tester);
    });

    testWidgets('at text scale 2.0 the header grows so nothing is clipped',
        (tester) async {
      await _pump(tester, session: _QuietSession(), textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(_rect(tester, 'scan-sheet-surface').height,
          greaterThan(kScanSheetCollapsedPx + 20),
          reason: 'a fixed 226 px header cannot hold doubled text');
      await expectReachable(tester);
    });

    testWidgets('the upload disclosure is shown in full, never ellipsised',
        (tester) async {
      await _pump(tester, session: _QuietSession(), textScale: 2.0);
      final Text strip =
          tester.widget<Text>(find.byKey(const Key('scan-privacy-strip')));
      expect(strip.maxLines, isNull);
      expect(strip.overflow, isNot(TextOverflow.ellipsis));
      final RenderBox box = tester
          .renderObject<RenderBox>(find.byKey(const Key('scan-privacy-strip')));
      expect(box.size.height, greaterThan(40),
          reason: 'doubled text wraps over several lines instead of truncating');
    });
  });

  group('short screens', () {
    testWidgets('a 340 px tall window keeps the shutter and an aiming frame',
        (tester) async {
      await _pump(tester, session: _QuietSession(), size: const Size(760, 340));
      expect(tester.takeException(), isNull);

      final Rect sheet = _rect(tester, 'scan-sheet-surface');
      for (final key in const [
        'scan-recognise-camera',
        'scan-recognise-gallery',
        'scan-live-toggle',
      ]) {
        final Rect r = _rect(tester, key);
        expect(sheet.contains(r.center), isTrue,
            reason: '$key must be inside the collapsed sheet');
        expect(r.bottom, lessThanOrEqualTo(340.5));
      }
      expect(sheet.height, greaterThanOrEqualTo(kScanSheetCollapsedPx - 1));

      final Rect frame = tester.getRect(find.byType(ScanFrame));
      expect(frame.height, greaterThanOrEqualTo(kScanMinGuideWindowPx - 1),
          reason: 'the insets must leave a real aiming window');
      expect(frame.width, greaterThan(100));
    });

    testWidgets('a normal phone still frames between the title and the sheet',
        (tester) async {
      await _pump(tester, session: _QuietSession());
      final Rect frame = tester.getRect(find.byType(ScanFrame));
      final Rect sheet = _rect(tester, 'scan-sheet-surface');
      expect(frame.bottom, lessThan(sheet.top),
          reason: 'on a tall screen the clamp must not move the frame');
    });
  });
}
