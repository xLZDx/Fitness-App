import 'dart:async';

import 'live_recognition.dart';
import 'visual_equipment_match.dart';

/// Continuous, hands-free equipment recognition: point the camera and the
/// machine identifies itself, no shutter press.
///
/// Deliberately mirrors [PoseDetectorService] (form_check) — same start/stop
/// lifecycle, same broadcast-stream shape — because that pattern already
/// survives the camera-plugin quirks on real devices.
abstract class LiveEquipmentService {
  /// Smoothed readings. `settled == true` means the majority vote passed its
  /// agreement + confidence bars; `settled == false` is the current leader,
  /// emitted so the UI can show progress instead of a bare spinner. Consumers
  /// that ACT on a reading (history, navigation) must check `settled`.
  Stream<LiveRecognition> recognitions();

  /// Idempotent: safe to call when already running.
  Future<void> start();

  /// Releases the camera. The camera indicator must go dark after this.
  Future<void> stop();

  /// True between a successful [start] and [stop].
  ///
  /// Note what is NOT here: the camera. A detector used to own its
  /// `CameraController` and expose it so the preview could downcast the service
  /// to draw a viewfinder. Camera ownership lives in `CameraSession` now, and
  /// the preview depends on that directly.
  bool get isRunning;
}

/// Test double: no camera, no ML Kit. Push frames in, assert what comes out.
class MockLiveEquipmentService implements LiveEquipmentService {
  MockLiveEquipmentService({RecognitionSmoother? smoother})
      : _smoother = smoother ?? RecognitionSmoother(window: 3);

  final RecognitionSmoother _smoother;
  final StreamController<LiveRecognition> _ctrl =
      StreamController<LiveRecognition>.broadcast();
  bool _running = false;

  @override
  Stream<LiveRecognition> recognitions() => _ctrl.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async => _running = true;

  @override
  Future<void> stop() async {
    _running = false;
    _smoother.reset();
  }

  /// Simulate one classified frame. Mirrors the real service: a settled
  /// reading when the vote passes its bars, else the tentative leader.
  void feed(VisualMatch? top) {
    final reading = _smoother.add(top) ?? _smoother.tentative;
    if (reading != null) _ctrl.add(reading);
  }

  Future<void> dispose() => _ctrl.close();
}
