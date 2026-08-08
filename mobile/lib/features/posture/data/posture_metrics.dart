// R10 -- live posture signals, read against `measured_posture_config.dart`.
//
// Mirrors `rep_signals.dart`'s shape: pure functions, `PoseFrame ->
// double?`, normalised by a body-scale distance so the number does not
// depend on how far the user stands from the phone.

import 'dart:math' as math;

import '../../form_check/data/pose_landmark.dart';

(double, double)? _mid(PoseFrame f, LandmarkType l, LandmarkType r,
    double minLikelihood) {
  final a = f.landmarks[l], b = f.landmarks[r];
  if (a == null || b == null) return null;
  if (a.likelihood < minLikelihood || b.likelihood < minLikelihood) {
    return null;
  }
  return ((a.x + b.x) / 2, (a.y + b.y) / 2);
}

double _dist((double, double) a, (double, double) b) =>
    math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

/// Shoulder asymmetry: positive means the RIGHT shoulder sits higher.
///
/// Image y grows downward (`pose_landmark.dart`'s own documented contract),
/// the opposite of the Human3.6M axis `measured_posture_config.dart` was
/// measured against, where a larger value is higher. `left.y - right.y` is
/// what flips the sign back to the same "positive = right higher"
/// convention the measured ranges use -- get this backwards and every
/// "right shoulder low" cue points at the wrong shoulder.
double? shoulderAsymmetrySignal(PoseFrame f, double minLikelihood) {
  final l = f.landmarks[LandmarkType.leftShoulder];
  final r = f.landmarks[LandmarkType.rightShoulder];
  if (l == null || r == null) return null;
  if (l.likelihood < minLikelihood || r.likelihood < minLikelihood) {
    return null;
  }
  final width = _dist((l.x, l.y), (r.x, r.y));
  if (width < 0.02) return null;
  return (l.y - r.y) / width;
}

/// Pelvis tilt: same sign convention as [shoulderAsymmetrySignal] --
/// positive means the right hip sits higher.
double? pelvisTiltSignal(PoseFrame f, double minLikelihood) {
  final l = f.landmarks[LandmarkType.leftHip];
  final r = f.landmarks[LandmarkType.rightHip];
  if (l == null || r == null) return null;
  if (l.likelihood < minLikelihood || r.likelihood < minLikelihood) {
    return null;
  }
  final width = _dist((l.x, l.y), (r.x, r.y));
  if (width < 0.02) return null;
  return (l.y - r.y) / width;
}

/// Forward head: ear midpoint's horizontal offset from the shoulder
/// midpoint, divided by torso length (shoulder-to-hip distance -- the same
/// scale reference `rep_signals.dart`'s `_torso` uses).
///
/// **Untested sign convention.** This assumes the side-on framing Form
/// Check already asks for elsewhere (`formcheckStandSideOn`), facing the
/// same direction the measured range's dataset happened to face. Nothing
/// in this codebase has verified that assumption against a live device --
/// get the facing direction wrong and the sign flips, which would point a
/// "leaning forward" cue at someone leaning back. Named here rather than
/// silently assumed correct; see `core/plans/PLAN_R10_POSTURE_2026-08-08.md`.
double? forwardHeadSignal(PoseFrame f, double minLikelihood) {
  final ears = _mid(f, LandmarkType.leftEar, LandmarkType.rightEar,
      minLikelihood);
  final shoulders = _mid(f, LandmarkType.leftShoulder,
      LandmarkType.rightShoulder, minLikelihood);
  final hips =
      _mid(f, LandmarkType.leftHip, LandmarkType.rightHip, minLikelihood);
  if (ears == null || shoulders == null || hips == null) return null;
  final torso = _dist(shoulders, hips);
  if (torso < 0.02) return null;
  return (ears.$1 - shoulders.$1) / torso;
}
