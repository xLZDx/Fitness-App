import 'dart:async';

import 'package:camera/camera.dart' show CameraController, XFile;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'live_recognition.dart';
import 'visual_equipment_match.dart';

/// Continuous, hands-free equipment recognition: point the camera and the
/// machine identifies itself, no shutter press.
///
/// Deliberately mirrors [PoseDetectorService] (form_check) — same start/stop
/// lifecycle, same broadcast-stream shape — because that pattern already
/// survives the camera-plugin quirks on real devices.
abstract class LiveEquipmentService {
  /// Settled readings only. The implementation smooths raw per-frame guesses
  /// so this never flickers between candidates.
  Stream<LiveRecognition> recognitions();

  /// Idempotent: safe to call when already running.
  Future<void> start();

  /// Releases the camera. The camera indicator must go dark after this.
  Future<void> stop();

  /// True between a successful [start] and [stop].
  bool get isRunning;

  /// The camera surface to render, or null while there is none.
  ///
  /// A [ValueListenable] rather than a plain getter, because "the camera has
  /// become ready" is precisely the signal the preview needs and a getter
  /// cannot deliver it. The controller field flips from null part-way through
  /// an async `start()`, which is invisible to Riverpod and to the widget tree:
  /// the preview built once, saw null, and sat on its placeholder forever —
  /// the black square the operator reported. Watching this fixes it at the
  /// source instead of relying on some unrelated rebuild to come along.
  ///
  /// Implementations without a camera return a permanently-null notifier, which
  /// is why the preview widget no longer has to downcast to a concrete type.
  ValueListenable<CameraController?> get cameraSurface;

  /// Takes a still photo through the SAME camera session the preview shows.
  ///
  /// This is what keeps "recognise a machine" inside the app: the alternative
  /// was `ImagePicker(source: camera)`, which launches the system camera as a
  /// separate activity. Returns null when no camera is available.
  Future<XFile?> captureStill();
}

/// Test double: no camera, no ML Kit. Push frames in, assert what comes out.
class MockLiveEquipmentService implements LiveEquipmentService {
  MockLiveEquipmentService({RecognitionSmoother? smoother})
      : _smoother = smoother ?? RecognitionSmoother(window: 3);

  final RecognitionSmoother _smoother;
  final StreamController<LiveRecognition> _ctrl =
      StreamController<LiveRecognition>.broadcast();
  bool _running = false;

  /// Always null: there is no camera in tests. The preview renders its
  /// placeholder, which is what widget tests expect.
  final ValueNotifier<CameraController?> _surface =
      ValueNotifier<CameraController?>(null);

  @override
  Stream<LiveRecognition> recognitions() => _ctrl.stream;

  @override
  bool get isRunning => _running;

  @override
  ValueListenable<CameraController?> get cameraSurface => _surface;

  @override
  Future<XFile?> captureStill() async => null;

  @override
  Future<void> start() async => _running = true;

  @override
  Future<void> stop() async {
    _running = false;
    _smoother.reset();
  }

  /// Simulate one classified frame.
  void feed(VisualMatch? top) {
    final settled = _smoother.add(top);
    if (settled != null) _ctrl.add(settled);
  }

  Future<void> dispose() async {
    _surface.dispose();
    await _ctrl.close();
  }
}
