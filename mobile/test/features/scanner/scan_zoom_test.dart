import 'dart:async';

import 'package:fitness_app/core/camera/camera_zoom.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/widgets/zoom_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_zoom_backend.dart';

Future<CameraZoom> zoomWith(FakeZoomBackend b, {double initial = 1.0}) async {
  final z = CameraZoom();
  await z.attach(b, initial: initial);
  return z;
}

void main() {
  group('presets follow the device range', () {
    test('an ultra-wide phone (min 0.6, max 10) offers all six', () async {
      final z = await zoomWith(FakeZoomBackend(0.6, 10));
      expect(CameraZoom.presetsFor(z.state.value!), [0.6, 1, 2, 3, 5, 10]);
    });

    test('a 1..4x phone offers only 1, 2 and 3 -- no 0.6, 5 or 10', () async {
      final z = await zoomWith(FakeZoomBackend(1, 4));
      expect(CameraZoom.presetsFor(z.state.value!), [1, 2, 3]);
    });

    test('0.6x needs a device minimum of 0.6 or less', () async {
      // 0.7 is wider than 1x but not wide enough to honour a 0.6x label.
      final z = await zoomWith(FakeZoomBackend(0.7, 10));
      expect(CameraZoom.presetsFor(z.state.value!).contains(0.6), isFalse);
      final z2 = await zoomWith(FakeZoomBackend(0.5, 8));
      expect(CameraZoom.presetsFor(z2.state.value!), [0.6, 1, 2, 3, 5]);
      // A device reporting 0.5999 still counts as 0.6.
      final z3 = await zoomWith(FakeZoomBackend(0.5999, 10));
      expect(CameraZoom.presetsFor(z3.state.value!).first, 0.6);
    });

    test('the active preset is the one the level sits on, none in between',
        () async {
      final z = await zoomWith(FakeZoomBackend(0.6, 10));
      expect(CameraZoom.activePreset(z.state.value!), 1);
      await z.setLevel(2.04);
      expect(CameraZoom.activePreset(z.state.value!), 2);
      await z.setLevel(2.6);
      expect(CameraZoom.activePreset(z.state.value!), isNull);
    });

    test('labels read like a camera app', () {
      expect(CameraZoom.label(0.6), '0.6x');
      expect(CameraZoom.label(1), '1x');
      expect(CameraZoom.label(2.5), '2.5x');
    });
  });

  group('setting zoom', () {
    test('is clamped to the device limits both ways', () async {
      final b = FakeZoomBackend(1, 4);
      final z = await zoomWith(b);
      expect(await z.setLevel(20), 4);
      expect(await z.setLevel(0.1), 1);
      expect(b.requested, [4, 1],
          reason: 'the camera must never be handed an out-of-range level');
      expect(z.state.value!.current, 1);
    });

    test('reset goes to 1x, or the nearest the device allows', () async {
      final b = FakeZoomBackend(0.6, 10);
      final z = await zoomWith(b);
      await z.setLevel(5);
      await z.reset();
      expect(b.requested.last, 1.0);
      expect(z.state.value!.current, 1.0);
    });

    test('nothing happens without a camera', () async {
      final z = CameraZoom();
      expect(z.state.value, isNull);
      expect(await z.setLevel(2), isNull);
      final b = FakeZoomBackend(1, 4);
      await z.attach(b);
      z.detach();
      expect(z.state.value, isNull);
      expect(await z.setLevel(2), isNull);
      expect(b.requested, isEmpty);
    });

    test('a pinch produces many levels; only the latest waits behind the '
        'one in flight', () async {
      final b = FakeZoomBackend(1, 10, delay: const Duration(milliseconds: 20));
      final z = await zoomWith(b);
      final Future<void> first = z.requestLevel(1.5);
      for (final l in [1.6, 1.8, 2.0, 2.4, 3.0]) {
        unawaited(z.requestLevel(l));
      }
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(b.requested.first, 1.5);
      expect(b.requested.last, 3.0, reason: 'the final level must win');
      expect(b.requested.length, lessThanOrEqualTo(3),
          reason: 'intermediate levels are dropped, not queued');
    });
  });

  group('ZoomControls', () {
    Future<void> pumpControls(WidgetTester tester, CameraZoom z) =>
        tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Center(child: ZoomControls(zoom: z))),
        ));

    testWidgets('an ultra-wide device shows 0.6 1 2 3 5 10 and the label',
        (tester) async {
      final z = await zoomWith(FakeZoomBackend(0.6, 10));
      await pumpControls(tester, z);
      for (final k in ['0.6', '1', '2', '3', '5', '10']) {
        expect(find.byKey(Key('scan-zoom-$k')), findsOneWidget, reason: k);
      }
      expect(tester.widget<Text>(find.byKey(const Key('scan-zoom-label'))).data,
          '1x');
    });

    testWidgets('a 1..4x device shows only the presets it can really do',
        (tester) async {
      final z = await zoomWith(FakeZoomBackend(1, 4));
      await pumpControls(tester, z);
      for (final k in ['1', '2', '3']) {
        expect(find.byKey(Key('scan-zoom-$k')), findsOneWidget, reason: k);
      }
      for (final k in ['0.6', '5', '10']) {
        expect(find.byKey(Key('scan-zoom-$k')), findsNothing, reason: k);
      }
    });

    testWidgets('tapping a preset zooms the camera, moves the highlight and '
        'the label', (tester) async {
      final b = FakeZoomBackend(0.6, 10);
      final z = await zoomWith(b);
      await pumpControls(tester, z);

      bool highlighted(String k) {
        final box = tester
            .widget<Container>(find.descendant(
                of: find.byKey(Key('scan-zoom-$k')),
                matching: find.byType(Container)))
            .decoration as BoxDecoration;
        return box.shape == BoxShape.circle;
      }

      expect(highlighted('1'), isTrue);
      expect(highlighted('3'), isFalse);

      await tester.tap(find.byKey(const Key('scan-zoom-3')));
      await tester.pump();
      await tester.pump();
      expect(b.requested, [3.0]);
      expect(highlighted('3'), isTrue);
      expect(highlighted('1'), isFalse, reason: 'exactly one active preset');
      expect(tester.widget<Text>(find.byKey(const Key('scan-zoom-label'))).data,
          '3x');

      await tester.tap(find.byKey(const Key('scan-zoom-0.6')));
      await tester.pump();
      await tester.pump();
      expect(b.requested.last, 0.6);
      expect(tester.widget<Text>(find.byKey(const Key('scan-zoom-label'))).data,
          '0.6x');
    });

    testWidgets('draws nothing while no camera is open, or a fixed-zoom one',
        (tester) async {
      await pumpControls(tester, CameraZoom());
      expect(find.byKey(const Key('scan-zoom-label')), findsNothing);
      final fixed = await zoomWith(FakeZoomBackend(1, 1));
      await pumpControls(tester, fixed);
      expect(find.byKey(const Key('scan-zoom-1')), findsNothing);
    });
  });

  group('ZoomPinchLayer', () {
    Future<(CameraZoom, FakeZoomBackend)> pumpLayer(WidgetTester tester,
        {double min = 1, double max = 4}) async {
      final b = FakeZoomBackend(min, max);
      final z = await zoomWith(b);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZoomPinchLayer(
            zoom: z,
            child: const SizedBox.expand(key: Key('pinch-area')),
          ),
        ),
      ));
      return (z, b);
    }

    Future<void> pinch(WidgetTester tester, double fromHalf, double toHalf) async {
      final c = tester.getCenter(find.byKey(const Key('pinch-area')));
      final g1 = await tester.startGesture(c - Offset(fromHalf, 0));
      final g2 = await tester.startGesture(c + Offset(fromHalf, 0));
      await tester.pump();
      await g1.moveTo(c - Offset(toHalf, 0));
      await g2.moveTo(c + Offset(toHalf, 0));
      await tester.pump();
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();
    }

    testWidgets('spreading two fingers zooms in by the pinch ratio',
        (tester) async {
      final (z, b) = await pumpLayer(tester);
      await pinch(tester, 50, 100);
      expect(b.requested, isNotEmpty);
      expect(b.requested.last, closeTo(2.0, 0.15));
      expect(z.state.value!.current, closeTo(2.0, 0.15));
    });

    testWidgets('a huge pinch stops at the device maximum', (tester) async {
      final (z, b) = await pumpLayer(tester);
      await pinch(tester, 20, 300);
      expect(b.requested.last, 4.0);
      expect(z.state.value!.current, 4.0);
      expect(b.requested.every((l) => l >= 1 && l <= 4), isTrue);
    });

    testWidgets('pinching in cannot go below the device minimum',
        (tester) async {
      final (z, b) = await pumpLayer(tester);
      await pinch(tester, 200, 10);
      expect(b.requested.last, 1.0);
      expect(z.state.value!.current, 1.0);
    });

    testWidgets('a one-finger drag does not zoom', (tester) async {
      final (_, b) = await pumpLayer(tester);
      await tester.dragFrom(
          tester.getCenter(find.byKey(const Key('pinch-area'))), const Offset(0, 200));
      await tester.pump();
      expect(b.requested, isEmpty);
    });
  });
}
