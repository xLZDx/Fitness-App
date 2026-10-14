import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';

const double kAspect = 0.5625;

PoseLandmark _lm(LandmarkType t, double x, double y, [double l = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

PoseFrame frameOf(Map<LandmarkType, PoseLandmark> ls) =>
    PoseFrame(timestampMs: 0, aspectRatio: kAspect, landmarks: ls);

/// A standing adult (same geometry as readiness_evaluator_test.dart).
PoseFrame body({
  double h = 0.75,
  double top = 0.10,
  double cx = kAspect / 2,
  double spread = 1.0,
  double nose = 0.95,
  double ears = 0.95,
  double farSide = 0.95,
}) {
  final shoulderY = top + 0.18 * h;
  final hipY = shoulderY + 0.29 * h;
  final kneeY = shoulderY + 0.52 * h;
  final ankleY = shoulderY + 0.78 * h;
  final sw = 0.115 * h * 1.5 * spread;
  final hw = 0.07 * h * 1.5 * spread;
  final kw = 0.06 * h * 1.5 * spread;
  return frameOf({
    LandmarkType.nose: _lm(LandmarkType.nose, cx, top + 0.05 * h, nose),
    LandmarkType.leftEar:
        _lm(LandmarkType.leftEar, cx - 0.03, top + 0.04 * h, ears),
    LandmarkType.rightEar:
        _lm(LandmarkType.rightEar, cx + 0.03, top + 0.04 * h, ears),
    LandmarkType.leftShoulder:
        _lm(LandmarkType.leftShoulder, cx - sw, shoulderY),
    LandmarkType.rightShoulder:
        _lm(LandmarkType.rightShoulder, cx + sw, shoulderY, farSide),
    LandmarkType.leftHip: _lm(LandmarkType.leftHip, cx - hw, hipY),
    LandmarkType.rightHip: _lm(LandmarkType.rightHip, cx + hw, hipY, farSide),
    LandmarkType.leftKnee: _lm(LandmarkType.leftKnee, cx - kw, kneeY),
    LandmarkType.rightKnee:
        _lm(LandmarkType.rightKnee, cx + kw, kneeY, farSide),
    LandmarkType.leftAnkle: _lm(LandmarkType.leftAnkle, cx - kw, ankleY),
    LandmarkType.rightAnkle:
        _lm(LandmarkType.rightAnkle, cx + kw, ankleY, farSide),
  });
}

PoseFrame frontFrame() => body();
PoseFrame sideFrame() => body(spread: 0.05, farSide: 0.3);
PoseFrame backFrame() => body(nose: 0.1, ears: 0.1);
PoseFrame emptyFrame() => frameOf(const {});

class FakeScanCamera implements ScanCamera {
  final StreamController<PoseFrame> ctrl = StreamController.broadcast();
  final ValueNotifier<bool> low = ValueNotifier(false);
  final ValueNotifier<SessionFacing> face = ValueNotifier(SessionFacing.back);
  int starts = 0;
  int stops = 0;
  int flips = 0;
  int stills = 0;
  Object? startError;

  @override
  Stream<PoseFrame> frames() => ctrl.stream;
  @override
  ValueListenable<bool> get lowLight => low;
  @override
  ValueListenable<SessionFacing> get facing => face;
  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> flip() async {
    flips++;
    face.value = face.value == SessionFacing.back
        ? SessionFacing.front
        : SessionFacing.back;
  }

  @override
  Future<Uint8List?> captureStill() async {
    stills++;
    return Uint8List.fromList([stills, 1, 2, 3]);
  }

  @override
  Widget buildPreview(BuildContext context) =>
      const ColoredBox(key: Key('fake.preview'), color: Colors.grey);
  @override
  Future<void> dispose() async {
    await ctrl.close();
  }
}

class FakeSpeaker implements ScanSpeaker {
  final List<String> said = [];
  int stops = 0;
  @override
  Future<void> say(String text) async => said.add(text);
  @override
  Future<void> stop() async => stops++;
}

class FakeHaptics implements ScanHaptics {
  int ticks = 0, shutters = 0, warns = 0;
  @override
  void tick() => ticks++;
  @override
  void shutter() => shutters++;
  @override
  void warn() => warns++;
}

class FakeScanRepository implements ScanRepository {
  final List<ScanRecord> saved = [];
  @override
  Future<List<ScanRecord>> list() async => List.of(saved.reversed);
  @override
  Future<void> save(ScanRecord r) async => saved.add(r);
  @override
  Future<void> delete(String id) async => saved.removeWhere((r) => r.id == id);
}
