/// Head-region geometry for on-device face blurring (design s9, D-4). Pure
/// Dart, no Flutter imports; the pixels are handled in `state/blur_service.dart`.
///
/// FAIL CLOSED: when the head region cannot be established the verdict says so
/// and nothing may be uploaded.
library;

import 'dart:math' as math;

import '../../form_check/data/pose_landmark.dart';

/// Axis-aligned rectangle in the isotropic frame space of `PoseFrame` (both
/// axes divided by the image height; x runs over `[0, aspectRatio]`, y over
/// `[0, 1]`).
class FrameRect {
  const FrameRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  /// The rectangle in pixels of an image of the given size: frame space is
  /// scaled by the image height on both axes.
  PixelRect toPixels({required int imageWidth, required int imageHeight}) {
    int clampX(double v) => v.round().clamp(0, imageWidth).toInt();
    int clampY(double v) => v.round().clamp(0, imageHeight).toInt();
    return PixelRect(
      clampX(left * imageHeight),
      clampY(top * imageHeight),
      clampX(right * imageHeight),
      clampY(bottom * imageHeight),
    );
  }
}

class PixelRect {
  const PixelRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

enum FaceRegionFailure {
  /// No pose landmarks at all (manual shutter without a detected body).
  noLandmarks,

  /// Neither a head landmark with a usable size reference nor shoulders plus
  /// ankles: the head box cannot be sized.
  cannotSize,
}

/// The verdict: a region to blur, or a fail-closed refusal.
class FaceRegionVerdict {
  const FaceRegionVerdict.region(FrameRect this.region) : failure = null;
  const FaceRegionVerdict.failClosed(FaceRegionFailure this.failure)
      : region = null;

  final FrameRect? region;
  final FaceRegionFailure? failure;

  /// True when the head region was established.
  bool get safe => region != null;
}

/// Tunables of the geometry [OWN] (design s9 steps 1-3).
abstract final class FaceRegionConfig {
  static const double minLikelihood = 0.3;
  static const double radiusFromHeadSpread = 1.35;
  static const double radiusFromShoulders = 0.40;
  static const double halfSideOfRadius = 1.5;
  static const double extraUpOfRadius = 0.3;
  static const double marginFraction = 0.15;
  static const double torsoToShoulderWidth = 0.45;

  /// Crown estimate when no head landmark exists (back view), as in
  /// `ReadinessConfig`: height from the shoulder-to-ankle span.
  static const double shoulderToAnkleOfHeight = 0.78;
  static const double crownAboveShoulderOfHeight = 0.10;
  static const double crownHalfSideOfHeight = 0.14;
}

const _headTypes = [
  LandmarkType.nose,
  LandmarkType.leftEar,
  LandmarkType.rightEar,
];

/// Computes the blur region for [frame] (the shutter frame's landmarks).
FaceRegionVerdict computeFaceRegion(PoseFrame? frame) {
  if (frame == null || frame.landmarks.isEmpty) {
    return const FaceRegionVerdict.failClosed(FaceRegionFailure.noLandmarks);
  }
  final lm = frame.landmarks;
  PoseLandmark? usable(LandmarkType t) {
    final p = lm[t];
    return p != null && p.likelihood >= FaceRegionConfig.minLikelihood
        ? p
        : null;
  }

  final head = [
    for (final t in _headTypes)
      if (usable(t) != null) usable(t)!,
  ];
  final ls = usable(LandmarkType.leftShoulder);
  final rs = usable(LandmarkType.rightShoulder);

  FrameRect clamp(double cx, double cy, double half, double up) {
    final h = half * (1 + FaceRegionConfig.marginFraction);
    final topExtra = up * (1 + FaceRegionConfig.marginFraction);
    return FrameRect(
      math.max(0.0, cx - h),
      math.max(0.0, cy - h - topExtra),
      math.min(frame.aspectRatio, cx + h),
      math.min(1.0, cy + h),
    );
  }

  if (head.isNotEmpty) {
    final cx = head.fold<double>(0, (a, p) => a + p.x) / head.length;
    final cy = head.fold<double>(0, (a, p) => a + p.y) / head.length;
    var spread = 0.0;
    for (final p in head) {
      spread = math.max(spread, _dist(cx, cy, p.x, p.y));
    }
    final s = _shoulderWidth(lm, ls, rs);
    final r = math.max(
      FaceRegionConfig.radiusFromHeadSpread * spread,
      FaceRegionConfig.radiusFromShoulders * (s ?? 0),
    );
    if (r <= 0) {
      return const FaceRegionVerdict.failClosed(FaceRegionFailure.cannotSize);
    }
    return FaceRegionVerdict.region(clamp(
      cx,
      cy,
      FaceRegionConfig.halfSideOfRadius * r,
      FaceRegionConfig.extraUpOfRadius * r,
    ));
  }

  // No head landmarks (typical back view): crown estimate from the shoulder
  // line and the ankles.
  final la = usable(LandmarkType.leftAnkle);
  final ra = usable(LandmarkType.rightAnkle);
  if (ls == null || rs == null || (la == null && ra == null)) {
    return const FaceRegionVerdict.failClosed(FaceRegionFailure.cannotSize);
  }
  final shoulderMidX = (ls.x + rs.x) / 2;
  final shoulderMidY = (ls.y + rs.y) / 2;
  final ankleY = la != null && ra != null
      ? (la.y + ra.y) / 2
      : (la ?? ra!).y;
  final span = ankleY - shoulderMidY;
  if (span <= 0) {
    return const FaceRegionVerdict.failClosed(FaceRegionFailure.cannotSize);
  }
  final height = span / FaceRegionConfig.shoulderToAnkleOfHeight;
  return FaceRegionVerdict.region(clamp(
    shoulderMidX,
    shoulderMidY - FaceRegionConfig.crownAboveShoulderOfHeight * height,
    FaceRegionConfig.crownHalfSideOfHeight * height,
    0,
  ));
}

/// Shoulder width, or `0.45 * torso length` when exactly one shoulder is
/// hidden and a same-side hip is known; null when neither works.
double? _shoulderWidth(
  Map<LandmarkType, PoseLandmark> lm,
  PoseLandmark? ls,
  PoseLandmark? rs,
) {
  if (ls != null && rs != null) return _dist(ls.x, ls.y, rs.x, rs.y);
  final shoulder = ls ?? rs;
  if (shoulder == null) return null;
  final hip = shoulder == ls ? lm[LandmarkType.leftHip] : lm[LandmarkType.rightHip];
  if (hip == null || hip.likelihood < FaceRegionConfig.minLikelihood) {
    return null;
  }
  return FaceRegionConfig.torsoToShoulderWidth *
      _dist(shoulder.x, shoulder.y, hip.x, hip.y);
}

double _dist(double x1, double y1, double x2, double y2) {
  final dx = x1 - x2;
  final dy = y1 - y2;
  return math.sqrt(dx * dx + dy * dy);
}
