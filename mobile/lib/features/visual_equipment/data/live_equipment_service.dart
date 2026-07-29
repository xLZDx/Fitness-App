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
  /// Settled readings only. The implementation smooths raw per-frame guesses
  /// so this never flickers between candidates.
  Stream<LiveRecognition> recognitions();

  /// Idempotent: safe to call when already running.
  Future<void> start();

  /// Releases the camera. The camera indicator must go dark after this.
  Future<void> stop();

  /// True between a successful [start] and [stop].
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

  /// Simulate one classified frame.
  void feed(VisualMatch? top) {
    final settled = _smoother.add(top);
    if (settled != null) _ctrl.add(settled);
  }

  Future<void> dispose() => _ctrl.close();
}
