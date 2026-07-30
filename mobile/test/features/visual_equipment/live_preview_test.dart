import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/features/visual_equipment/widgets/live_equipment_preview.dart';

/// Exposes whether anything is listening.
///
/// That is the crux of the black-square defect: the old preview read a getter
/// once, so NOTHING was subscribed to the camera becoming ready and the
/// placeholder was permanent. Asserting on the subscription tests the actual
/// mechanism rather than a symptom that needs a real camera to observe.
class _ObservableSurface extends ValueNotifier<CameraController?> {
  _ObservableSurface(super.value);
  bool get observed => hasListeners;
}

/// A session whose surface the test drives by hand. Subclassing rather than
/// reimplementing keeps the widget's contract honest — it is the real type.
class _FakeSession extends CameraSession {
  final _ObservableSurface fakeSurface = _ObservableSurface(null);

  @override
  ValueListenable<CameraController?> get surface => fakeSurface;
}

void main() {
  Widget wrap(CameraSession session) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: LiveEquipmentPreview(session: session),
          ),
        ),
      );

  testWidgets('subscribes to the camera-ready signal', (tester) async {
    final session = _FakeSession();
    addTearDown(session.fakeSurface.dispose);

    expect(session.fakeSurface.observed, isFalse);
    await tester.pumpWidget(wrap(session));
    await tester.pump();

    // THE regression assertion. Before the fix the preview watched a plain
    // `Provider` whose value never changes and read the controller as a one-shot
    // field, leaving this false forever — so when the camera finished opening,
    // nothing in the tree found out.
    expect(session.fakeSurface.observed, isTrue,
        reason: 'nothing is listening for the camera to become ready');
  });

  testWidgets('shows the warming placeholder while there is no camera',
      (tester) async {
    final session = _FakeSession();
    addTearDown(session.fakeSurface.dispose);

    await tester.pumpWidget(wrap(session));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CameraPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uninitialized controller keeps the placeholder, not a crash',
      (tester) async {
    final session = _FakeSession();
    addTearDown(session.fakeSurface.dispose);
    await tester.pumpWidget(wrap(session));
    await tester.pump();

    // Constructed, never initialized — CameraPreview would throw on one of
    // these, so the guard has to hold before the value flips.
    final controller = CameraController(
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      ResolutionPreset.low,
    );
    addTearDown(() async {
      try {
        await controller.dispose();
      } catch (_) {
        // No platform side to release in a host test.
      }
    });

    session.fakeSurface.value = controller;
    await tester.pump();

    expect(find.byType(CameraPreview), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('CameraSession', () {
    test('holds no camera until started', () {
      // This is what lets widget tests pump the Scan page without a device and
      // without a mock: an unstarted session is inert.
      final session = CameraSession();
      expect(session.surface.value, isNull);
      expect(session.isRunning, isFalse);
      expect(session.lastFrameAt, isNull);
    });

    test('facing is explicit, and defaults to the back camera', () {
      expect(CameraSession().facing, SessionFacing.back);
      expect(CameraSession(facing: SessionFacing.front).facing,
          SessionFacing.front);
    });

    test('stop on a session that never started is harmless', () async {
      final session = CameraSession();
      await session.stop();
      expect(session.isRunning, isFalse);
    });

    test('captureStill without a camera returns null rather than throwing',
        () async {
      final session = CameraSession();
      expect(
        await session.captureStill().timeout(const Duration(seconds: 1),
            onTimeout: () => null),
        isNull,
      );
    });
  });

  group('no system-camera hand-off anywhere', () {
    /// Source with `//` comments removed — a comment explaining why the system
    /// camera was removed names it, and must not read as a violation.
    String code(String src) => src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    test('ImageSource.camera does not appear in lib/', () {
      // Capture must stay inside the app. `ImageSource.camera` launches the
      // system camera as a separate activity, so its absence is the mechanical
      // guarantee that it cannot creep back in.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (code(f.readAsStringSync()).contains('ImageSource.camera')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('gallery picking is still available', () {
      // The other half of the same rule: only the CAMERA source was the
      // problem. Losing gallery import would be a silent feature regression.
      final scanner =
          File('lib/features/scanner/scanner_page.dart').readAsStringSync();
      expect(scanner.contains('ImageSource.gallery'), isTrue);
    });

    test('only CameraSession opens a camera', () {
      // The defect this prevents is architectural: two recognition services
      // each built their own CameraController, so the preview had to downcast a
      // detector to draw a viewfinder, and the frame-format handling existed
      // twice.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('camera_session.dart')) continue;
        if (code(f.readAsStringSync()).contains('CameraController(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('no raw-bytes classification path anywhere', () {
      // The retired /recognise page fed encoded JPEG through
      // InputImage.fromBytes with hardcoded 640x480 NV21 metadata; on-device
      // ML Kit rejected it with InputImageConverterError (operator screenshot
      // 2026-07-30). Only the file route decodes format + EXIF correctly, so
      // a bytes-based classify API must not come back.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = code(f.readAsStringSync());
        if (src.contains('classifyBytes') ||
            src.contains('classify(imageBytes')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('mobile_scanner is gone', () {
      // It was a second camera stack: it held the device whenever live mode was
      // off, and every handover was a stop, a 250ms sleep, and a hope.
      expect(File('pubspec.yaml').readAsStringSync().contains('mobile_scanner'),
          isFalse);
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (code(f.readAsStringSync()).contains('mobile_scanner')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
