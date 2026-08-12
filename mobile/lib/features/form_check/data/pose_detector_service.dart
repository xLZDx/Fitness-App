import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../../../core/camera/camera_session.dart' show SessionFacing;
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

  /// Which way the camera behind this detector points.
  ValueListenable<SessionFacing> get facing;

  /// Point the camera the other way.
  ///
  /// Selfie framing cannot get far enough away for a full-body view unless the
  /// phone is propped up. The back camera aimed at a mirror can, which is what
  /// this is for — posture in particular, where every measurement is a line
  /// through the whole body and a frame that stops at the ribs yields none of
  /// them.
  Future<void> flipCamera();
}

/// Satisfies the two camera controls for a detector that HAS no camera.
///
/// A mixin rather than concrete bodies on [PoseDetectorService] itself,
/// because every implementation in this codebase uses `implements` — which in
/// Dart inherits the interface and none of the bodies. Written as defaults on
/// the abstract class they would have compiled and then failed at every one of
/// the five call sites, which is exactly what the analyzer said when this was
/// tried that way first.
///
/// The answers are truthful rather than stubbed: a replay of canned frames
/// really does point one fixed way, and really has nothing to switch.
mixin NoCameraControls implements PoseDetectorService {
  @override
  ValueListenable<SessionFacing> get facing => _fixedFacing;

  @override
  Future<void> flipCamera() async {}
}

/// Never mutated, so one instance across every camera-less implementation is
/// not shared mutable state.
final ValueNotifier<SessionFacing> _fixedFacing =
    ValueNotifier<SessionFacing>(SessionFacing.front);

/// In-memory replay of canned frames. Used for tests + the demo path
/// when the device has no camera (emulator, web).
class MockPoseDetectorService with NoCameraControls implements PoseDetectorService {
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
