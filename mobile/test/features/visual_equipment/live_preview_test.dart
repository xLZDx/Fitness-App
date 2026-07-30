import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/visual_equipment/data/live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/live_recognition.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/widgets/live_equipment_preview.dart';

/// Exposes whether anything is listening.
///
/// That is the crux of the black-square defect: the old preview read a getter
/// once, so NOTHING was subscribed to the camera becoming ready, and the
/// placeholder was permanent. Asserting on the subscription tests the actual
/// mechanism rather than a symptom that needs a real camera to observe.
class _ObservableSurface extends ValueNotifier<CameraController?> {
  _ObservableSurface(super.value);
  bool get observed => hasListeners;
}

class _FakeLiveService implements LiveEquipmentService {
  final _ObservableSurface surface = _ObservableSurface(null);
  final StreamController<LiveRecognition> _ctrl =
      StreamController<LiveRecognition>.broadcast();
  int captureCalls = 0;

  @override
  ValueListenable<CameraController?> get cameraSurface => surface;

  @override
  Future<XFile?> captureStill() async {
    captureCalls++;
    return null;
  }

  @override
  Stream<LiveRecognition> recognitions() => _ctrl.stream;

  @override
  bool get isRunning => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void dispose() {
    surface.dispose();
    _ctrl.close();
  }
}

void main() {
  Widget wrap(_FakeLiveService svc) => ProviderScope(
        overrides: [liveEquipmentServiceProvider.overrideWithValue(svc)],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: LiveEquipmentPreview(),
            ),
          ),
        ),
      );

  testWidgets('subscribes to the camera-ready signal', (tester) async {
    final svc = _FakeLiveService();
    addTearDown(svc.dispose);

    expect(svc.surface.observed, isFalse);
    await tester.pumpWidget(wrap(svc));
    await tester.pump();

    // THE regression assertion. Before the fix the preview watched only a plain
    // `Provider` whose value never changes and read `cameraController` as a
    // one-shot field, leaving this false forever — so when `start()` finished
    // opening the camera, nothing in the tree found out.
    expect(svc.surface.observed, isTrue,
        reason: 'nothing is listening for the camera to become ready');
  });

  testWidgets('shows the warming placeholder while there is no camera',
      (tester) async {
    final svc = _FakeLiveService();
    addTearDown(svc.dispose);

    await tester.pumpWidget(wrap(svc));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CameraPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uninitialized controller keeps the placeholder, not a crash',
      (tester) async {
    final svc = _FakeLiveService();
    addTearDown(svc.dispose);
    await tester.pumpWidget(wrap(svc));
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

    svc.surface.value = controller;
    await tester.pump();

    expect(find.byType(CameraPreview), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the mock service satisfies the camera contract without a camera', () {
    final svc = MockLiveEquipmentService();
    addTearDown(svc.dispose);
    expect(svc.cameraSurface.value, isNull);
    expect(svc.captureStill(), completion(isNull));
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
      // The operator asked for capture to stay inside the app. `ImageSource
      // .camera` launches the system camera as a separate activity, so its
      // absence is the mechanical guarantee that it cannot creep back in.
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
  });
}
