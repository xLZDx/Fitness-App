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

  /// Puts the camera-permission dialog up if it is still askable.
  ///
  /// Separate from [start], and called only when the user just asked for the
  /// camera -- a fresh arrival on the coach screen, or the retry button.
  ///
  /// `CameraSession.start` defaults to NOT requesting, so that a lifecycle
  /// resume cannot shove the system dialog in front of someone who never
  /// asked. That default was right; the bug was that the coach screen had no
  /// path that asked either, so on a phone where the scanner had not already
  /// been used the screen died with `permissionDenied` and no dialog ever
  /// appeared. Reported from a real device, 2026-08-08.
  ///
  /// Kept out of [start] because a caller must be able to bound `start` with
  /// a timeout that catches a hung platform call, and cannot apply that same
  /// bound to a human reading a dialog.
  ///
  /// Returns normally whatever the user decides -- refusal surfaces from the
  /// subsequent [start] as the same `CameraUnavailable` any other refusal
  /// does, so there is one place that renders it.
  Future<void> ensurePermission();

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

  /// Nothing to ask: the fixtures are already in memory.
  @override
  Future<void> ensurePermission() async {}

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
