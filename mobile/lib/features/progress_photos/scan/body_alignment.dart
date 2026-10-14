/// Aligns two photos of the same pose for a before/after comparison.
///
/// Pure geometry on 2D keypoints; no pixels. [BodyAlignment.align] finds the
/// least-squares similarity transform (uniform scale, rotation, translation;
/// Umeyama / Procrustes closed form) that maps photo B's keypoints onto photo
/// A's, so the UI can draw B over A (slider, ghost overlay, side by side).
///
/// This is a visual aid only. It produces a transform and a fit-quality score,
/// never any statement about the body.
///
/// Mirroring is NOT handled here: a selfie-camera shot compared with a rear
/// camera shot is a mirror image and the caller must un-mirror the keypoints
/// (flip x and swap left/right) before aligning. A pure similarity transform
/// has no reflection, by design: silently reflecting would hide a left/right
/// mix-up.
library;

import 'dart:math' as math;

/// Keypoints used for alignment, in a pose-independent naming.
enum BodyKeypoint {
  head,
  leftShoulder,
  rightShoulder,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

class Point2 {
  const Point2(this.x, this.y);
  final double x;
  final double y;

  bool get isFinite => x.isFinite && y.isFinite;
}

/// `p -> s * R(rotation) * p + (tx, ty)`.
class SimilarityTransform {
  const SimilarityTransform({
    required this.scale,
    required this.rotation,
    required this.tx,
    required this.ty,
  });

  static const identity =
      SimilarityTransform(scale: 1, rotation: 0, tx: 0, ty: 0);

  final double scale;

  /// Radians, counter-clockwise in a y-up frame (clockwise on screen, y down).
  final double rotation;
  final double tx;
  final double ty;

  Point2 apply(Point2 p) {
    final c = math.cos(rotation) * scale;
    final s = math.sin(rotation) * scale;
    return Point2(c * p.x - s * p.y + tx, s * p.x + c * p.y + ty);
  }
}

enum AlignmentFailure {
  none,

  /// Fewer shared keypoints than [AlignmentConfig.minKeypoints] (after outlier
  /// rejection).
  tooFewKeypoints,

  /// Non-finite input, or all shared points of one photo coincide.
  degenerate,

  /// A transform was found but its scale or rotation is implausible for two
  /// photos of the same pose; refusing beats a wild overlay.
  implausible,
}

class AlignmentConfig {
  const AlignmentConfig({
    this.minKeypoints = 4,
    this.outlierFraction = 0.12,
    this.maxResidualFraction = 0.25,
    this.minScale = 0.25,
    this.maxScale = 4.0,
    this.maxRotationRad = 0.8,
  }) : assert(minKeypoints >= 2);

  final int minKeypoints;

  /// A point whose residual exceeds this fraction of A's spread is an outlier
  /// candidate (worst one dropped, refit, repeated while enough points remain).
  final double outlierFraction;

  /// Residual (as a fraction of A's spread) at which quality reaches 0.
  final double maxResidualFraction;
  final double minScale;
  final double maxScale;
  final double maxRotationRad;
}

class AlignmentResult {
  const AlignmentResult._({
    required this.failure,
    this.transform,
    this.quality = 0,
    this.used = const [],
    this.rejected = const [],
  });

  final AlignmentFailure failure;

  /// Maps B onto A. Null when [failure] != none.
  final SimilarityTransform? transform;

  /// 0..1; 1 = B's keypoints land exactly on A's. Scaled down by the share of
  /// shared keypoints that had to be rejected as outliers. Meaningless (0) on
  /// failure.
  final double quality;

  final List<BodyKeypoint> used;
  final List<BodyKeypoint> rejected;

  bool get isUsable => failure == AlignmentFailure.none && transform != null;
}

class BodyAlignment {
  const BodyAlignment._();

  /// Transform that maps [b] onto [a]. Keypoints present in only one photo are
  /// ignored.
  static AlignmentResult align(
    Map<BodyKeypoint, Point2> a,
    Map<BodyKeypoint, Point2> b, {
    AlignmentConfig config = const AlignmentConfig(),
  }) {
    final shared = [
      for (final k in BodyKeypoint.values)
        if (a.containsKey(k) && b.containsKey(k)) k,
    ];
    if (shared.any((k) => !a[k]!.isFinite || !b[k]!.isFinite)) {
      return const AlignmentResult._(failure: AlignmentFailure.degenerate);
    }
    if (shared.length < config.minKeypoints) {
      return const AlignmentResult._(failure: AlignmentFailure.tooFewKeypoints);
    }

    final used = List<BodyKeypoint>.of(shared);
    final rejected = <BodyKeypoint>[];
    _Fit? fit;
    while (true) {
      fit = _fit([for (final k in used) a[k]!], [for (final k in used) b[k]!]);
      if (fit == null) {
        return const AlignmentResult._(failure: AlignmentFailure.degenerate);
      }
      if (used.length <= config.minKeypoints) break;
      var worst = 0;
      for (var i = 1; i < fit.residuals.length; i++) {
        if (fit.residuals[i] > fit.residuals[worst]) worst = i;
      }
      if (fit.residuals[worst] <= config.outlierFraction * fit.spread) break;
      rejected.add(used.removeAt(worst));
    }

    final t = fit.transform;
    if (t.scale < config.minScale ||
        t.scale > config.maxScale ||
        t.rotation.abs() > config.maxRotationRad) {
      return AlignmentResult._(
        failure: AlignmentFailure.implausible,
        used: used,
        rejected: rejected,
      );
    }

    final rms = math.sqrt(
      fit.residuals.map((r) => r * r).reduce((s, v) => s + v) /
          fit.residuals.length,
    );
    final fitQuality =
        (1 - (rms / fit.spread) / config.maxResidualFraction).clamp(0.0, 1.0);
    final quality = fitQuality * used.length / shared.length;
    return AlignmentResult._(
      failure: AlignmentFailure.none,
      transform: t,
      quality: quality,
      used: used,
      rejected: rejected,
    );
  }

  /// Closed-form 2D similarity fit of [bp] onto [ap]; null if degenerate.
  static _Fit? _fit(List<Point2> ap, List<Point2> bp) {
    final n = ap.length;
    var amx = 0.0, amy = 0.0, bmx = 0.0, bmy = 0.0;
    for (var i = 0; i < n; i++) {
      amx += ap[i].x;
      amy += ap[i].y;
      bmx += bp[i].x;
      bmy += bp[i].y;
    }
    amx /= n;
    amy /= n;
    bmx /= n;
    bmy /= n;

    // dot = sum(b' . a'), cross = sum(b' x a'), bVar = sum|b'|^2, aVar likewise.
    var dot = 0.0, cross = 0.0, bVar = 0.0, aVar = 0.0;
    for (var i = 0; i < n; i++) {
      final ax = ap[i].x - amx, ay = ap[i].y - amy;
      final bx = bp[i].x - bmx, by = bp[i].y - bmy;
      dot += bx * ax + by * ay;
      cross += bx * ay - by * ax;
      bVar += bx * bx + by * by;
      aVar += ax * ax + ay * ay;
    }
    final spread = math.sqrt(aVar / n);
    if (spread < 1e-9 || bVar < 1e-12) return null;

    final rotation = math.atan2(cross, dot);
    final scale = (math.cos(rotation) * dot + math.sin(rotation) * cross) / bVar;
    if (!(scale > 0) || !scale.isFinite) return null;

    final c = math.cos(rotation) * scale;
    final s = math.sin(rotation) * scale;
    final tx = amx - (c * bmx - s * bmy);
    final ty = amy - (s * bmx + c * bmy);
    final transform = SimilarityTransform(
      scale: scale,
      rotation: rotation,
      tx: tx,
      ty: ty,
    );
    final residuals = [
      for (var i = 0; i < n; i++)
        () {
          final m = transform.apply(bp[i]);
          return math.sqrt(math.pow(m.x - ap[i].x, 2) + math.pow(m.y - ap[i].y, 2));
        }(),
    ];
    return _Fit(transform, residuals, spread);
  }
}

class _Fit {
  _Fit(this.transform, this.residuals, this.spread);
  final SimilarityTransform transform;
  final List<double> residuals;

  /// RMS distance of A's points from their centroid: the length scale used to
  /// normalise residuals.
  final double spread;
}
