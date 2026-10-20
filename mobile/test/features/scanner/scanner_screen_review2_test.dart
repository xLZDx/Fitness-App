import 'dart:async';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/camera/camera_zoom.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_record.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/scanner/state/scan_preview_provider.dart';
import 'package:fitness_app/features/scanner/widgets/machine_thumb.dart';
import 'package:fitness_app/features/scanner/widgets/manual_machine_picker.dart';
import 'package:fitness_app/features/scanner/widgets/rating_marks.dart';
import 'package:fitness_app/features/scanner/widgets/zoom_controls.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_zoom_backend.dart';
import '../../helpers/test_app.dart';

/// Independent review of the scan screen (2026-10-14), part 2: the drag does
/// not rebuild the page, the overlay steps aside for a tall sheet, the manual
/// picker tells loading and failure from "no results", thumbnails decode at
/// their drawn size, touch targets are 44 px, and a quick inactive -> resumed
/// leaves the camera running. Each test fails if its fix is reverted.

/// A session with a real running flag: [start] is a no-op while running (as the
/// real one is) and [stop] can be held open at [gate], which is exactly the
/// window in which a resume used to be swallowed.
class _GatedSession extends CameraSession {
  bool running = false;
  int starts = 0;
  int stops = 0;
  Completer<void>? gate;

  @override
  Future<void> start({bool requestPermission = false}) async {
    starts++;
    if (running) return;
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    running = false;
  }
}

Future<void> _pumpScan(
  WidgetTester tester, {
  required CameraSession session,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = const Size(400, 900);
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
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpWidget(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
  double dpr = 1.0,
}) async {
  tester.view.physicalSize = Size(400 * dpr, 800 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  ));
  await tester.pump();
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(Key(key)));

const EquipmentItem _legPress = EquipmentItem(
  id: 'leg_press',
  name: 'Leg press',
  manufacturer: '',
  category: 'strength',
  description: '',
);

void main() {
  group('the sheet drag', () {
    testWidgets('does not rebuild the page on every frame', (tester) async {
      var builds = 0;
      await _pumpScan(tester, session: _GatedSession(), overrides: [
        scanPreviewBuilderProvider.overrideWithValue((session) {
          builds++;
          return const SizedBox.expand();
        }),
      ]);
      final int before = builds;
      expect(before, greaterThan(0));
      final double collapsed = _rect(tester, 'scan-sheet-surface').height;

      final TestGesture drag = await tester
          .startGesture(tester.getCenter(find.byKey(const Key('scan-sheet-handle'))));
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(0, -24));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_rect(tester, 'scan-sheet-surface').height,
          greaterThan(collapsed + 100),
          reason: 'the sheet really moved');
      expect(builds, before,
          reason: 'twelve drag frames must not rebuild the screen');
      await drag.up();
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('the zoom/live overlay rides above the sheet and steps aside '
        'when the sheet is tall', (tester) async {
      await _pumpScan(tester, session: _GatedSession());
      expect(find.byKey(const Key('scan-over-sheet')), findsOneWidget);
      expect(_rect(tester, 'scan-over-sheet').bottom,
          lessThanOrEqualTo(_rect(tester, 'scan-sheet-surface').top + 0.5));

      await tester.fling(find.byKey(const Key('scan-sheet-handle')),
          const Offset(0, -900), 2000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('scan-over-sheet')), findsNothing,
          reason: 'on a tall sheet it would cover the title and history button');
      expect(find.byKey(const Key('scan-history-open')), findsOneWidget);

      await tester.fling(find.byKey(const Key('scan-sheet-handle')),
          const Offset(0, 900), 2000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('scan-over-sheet')), findsOneWidget);
    });
  });

  group('the manual machine picker', () {
    Future<void> pumpPicker(
        WidgetTester tester, Future<List<EquipmentItem>> Function() load) {
      return _pumpWidget(
        tester,
        const SizedBox(
            width: 400, height: 700, child: ManualMachinePicker()),
        overrides: [
          equipmentListProvider.overrideWith((ref) => load()),
          equipmentAliasIndexProvider
              .overrideWith((ref) => Completer<EquipmentAliasIndex>().future),
          equipmentHeroImageProvider.overrideWith((ref, id) async => null),
        ],
      );
    }

    testWidgets('shows a spinner while the catalogue loads, not "no results"',
        (tester) async {
      final Completer<List<EquipmentItem>> slow = Completer<List<EquipmentItem>>();
      await pumpPicker(tester, () => slow.future);
      expect(find.byKey(const Key('scan-manual-loading')), findsOneWidget);
      expect(find.byKey(const Key('scan-manual-empty')), findsNothing);

      slow.complete(const <EquipmentItem>[_legPress]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scan-manual-loading')), findsNothing);
      expect(find.byKey(const Key('scan-manual-pick-leg_press')), findsOneWidget);
    });

    testWidgets('a failed load says so and Retry loads again', (tester) async {
      var calls = 0;
      await pumpPicker(tester, () async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return const <EquipmentItem>[_legPress];
      });
      await tester.pump();
      expect(find.byKey(const Key('scan-manual-error')), findsOneWidget);
      expect(find.byKey(const Key('scan-manual-empty')), findsNothing,
          reason: 'a load failure is not an empty search');

      await tester.tap(find.byKey(const Key('scan-manual-retry')));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.byKey(const Key('scan-manual-error')), findsNothing);
      expect(find.byKey(const Key('scan-manual-pick-leg_press')), findsOneWidget);
    });

    testWidgets('a search that matches nothing still says "no machine matches"',
        (tester) async {
      await pumpPicker(tester, () async => const <EquipmentItem>[_legPress]);
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('scan-manual-search')), 'zzzz');
      await tester.pump();
      expect(find.byKey(const Key('scan-manual-empty')), findsOneWidget);
    });
  });

  group('machine thumbnails', () {
    testWidgets('are decoded at the drawn size times the pixel ratio',
        (tester) async {
      await _pumpWidget(
        tester,
        const MachineThumb(equipmentId: 'leg_press', size: 52),
        dpr: 2.0,
        overrides: [
          equipmentHeroImageProvider
              .overrideWith((ref, id) async => 'assets/missing_poster.jpg'),
        ],
      );
      await tester.pump();
      final Image image = tester.widget<Image>(
          find.byKey(const Key('machine-thumb-image-leg_press')));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 104,
          reason: '52 logical px x 2.0 device pixel ratio');
    });
  });

  group('touch targets', () {
    testWidgets('the OK / NOT OK marks are 44 x 44', (tester) async {
      await _pumpWidget(
        tester,
        RatingMarks(
          equipmentId: 'leg_press',
          rating: null,
          onChanged: (CandidateRating? _) {},
        ),
      );
      for (final k in const ['scan-rate-ok-leg_press', 'scan-rate-notok-leg_press']) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
      }
    });

    testWidgets('every zoom chip is at least 44 x 44 and nothing overflows',
        (tester) async {
      final CameraZoom z = CameraZoom();
      await z.attach(FakeZoomBackend(0.6, 10), initial: 1.0);
      await _pumpWidget(tester, ZoomControls(zoom: z));
      for (final k in const ['0.6', '1', '2', '3', '5', '10']) {
        final Size s = tester.getSize(find.byKey(Key('scan-zoom-$k')));
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('arm / disarm lifecycle', () {
    testWidgets('a resume that lands while the camera is still being released '
        'leaves the camera running', (tester) async {
      final session = _GatedSession();
      await _pumpScan(tester, session: session);
      expect(session.running, isTrue);
      expect(session.starts, 1);

      session.gate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 20));
      expect(session.stops, 1, reason: 'the release is in flight, held open');

      // The user is back before the release finished (a shade pulled down, a
      // permission dialog): the old code's start() hit "already running".
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 20));
      session.gate!.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(session.running, isTrue,
          reason: 'foreground again, so the camera must be open');
      expect(session.starts, 2, reason: 'the resume start ran after the stop');
    });

    testWidgets('inactive then resumed in the same instant ends with the '
        'camera open', (tester) async {
      final session = _GatedSession();
      await _pumpScan(tester, session: session);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(session.running, isTrue);
    });

    testWidgets('a plain background still releases the camera', (tester) async {
      final session = _GatedSession();
      await _pumpScan(tester, session: session);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(session.running, isFalse);
    });
  });
}
