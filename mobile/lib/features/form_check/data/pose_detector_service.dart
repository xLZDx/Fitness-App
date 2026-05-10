import 'dart:async';

import 'pose_landmark.dart';

/// Boundary between rule-based form check (pure) and the underlying
/// MediaPipe pose-detection model. Implementations:
///   - [MockPoseDetectorService] feeds pre-recorded frame fixtures.
///   - MlKitPoseDetectorService wraps `google_mlkit_pose_detection`.
abstract class PoseDetectorService {
  /// Stream of pose frames. Emits at the rate the underlying detector
  /// supports (~10–15 Hz on mid-range Android, capped at 30 Hz).
  Stream<PoseFrame> frames();

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// In-memory replay of canned frames. Used for tests + the demo path
/// when the device has no camera (emulator, web).
class MockPoseDetectorService implements PoseDetectorService {
  MockPoseDetectorService(this._fixtures);
  final List<PoseFrame> _fixtures;

  final StreamController<PoseFrame> _ctrl =
      StreamController<PoseFrame>.broadcast();
  bool _running = false;

  @override
  Stream<PoseFrame> frames() => _ctrl.stream;

  @override
  Future<void> start() async {
    _running = true;
    for (final f in _fixtures) {
      if (!_running) break;
      _ctrl.add(f);
      await Future<void>.delayed(const Duration(milliseconds: 33));
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  Future<void> dispose() async {
    await _ctrl.close();
  }
}
