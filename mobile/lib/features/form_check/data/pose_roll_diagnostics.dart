/// Is the phone rolled? Debug-only diagnosis, Form Coach gate F1 phase 1.
///
/// On the S23, 2026-09-25, a squat facing image-left passed 4/4 and the same
/// squat facing image-right passed 0/4, with equal tracking confidence and the
/// operator reporting equal depth. A camera roll would produce exactly that: it
/// rotates every segment of the body by the same angle in the image, and a
/// profile seen from the other side is the mirror image, so the rotation helps
/// one facing and hurts the other. The app has no tilt handling at all.
///
/// Nothing here changes behaviour. The live screen only calls into this from
/// inside `assert()`, to log numbers that [classifyRoll] turns into a verdict
/// under a rule written down BEFORE the device run (Rosetta plan
/// fitness_app-2026-09-26T10-28-32-483Z-18b1ba, GPT-PM APPROVE).
///
/// **Pinned convention.** Image coordinates, x right, y down. For a vector
/// v = (dx, dy) the angle is atan2(dx, dy) in degrees: 0 is straight down,
/// positive leans toward +x. A horizontal mirror maps a to -a; a rotation of
/// the image by delta maps a to a + delta for every vector alike.
library;

import 'dart:math' as math;

import 'pose_landmark.dart';

/// Joints below this likelihood are not used by any angle here — the same bar
/// the scoring gate uses.
const double kRollMinLikelihood = 0.7;

/// Frames at the top ignored after the lifter arrives there, so the tail of the
/// previous ascent never counts as standing.
const int kStandingSettleFrames = 10;

/// Most recent qualifying standing samples kept per attempt (~2 s at 30 fps).
const int kStandingWindowCapacity = 60;

/// Fewest standing samples an attempt needs before its estimate is used.
const int kStandingMinSamples = 20;

/// Largest frame-to-frame hip-midline movement still called standing still.
const double kStandingStillTolerance = 0.01;

/// Angle of the vector [from] -> [to] under the pinned convention, in degrees.
double segmentAngle((double, double) from, (double, double) to) =>
    math.atan2(to.$1 - from.$1, to.$2 - from.$2) * 180 / math.pi;

/// Midpoint of a left/right pair from the confident sides only: both when both
/// are trusted, the one when only one is, null when neither is.
(double, double)? trustedMidline(
    PoseFrame frame, LandmarkType left, LandmarkType right) {
  final pts = <(double, double)>[
    for (final t in [left, right])
      if (frame.landmarks[t] case final lm?
          when lm.likelihood >= kRollMinLikelihood &&
              !lm.x.isNaN &&
              !lm.y.isNaN)
        (lm.x, lm.y),
  ];
  if (pts.isEmpty) return null;
  final x = pts.fold(0.0, (s, p) => s + p.$1) / pts.length;
  final y = pts.fold(0.0, (s, p) => s + p.$2) / pts.length;
  return (x, y);
}

(double, double)? _shoulders(PoseFrame f) =>
    trustedMidline(f, LandmarkType.leftShoulder, LandmarkType.rightShoulder);
(double, double)? _hips(PoseFrame f) =>
    trustedMidline(f, LandmarkType.leftHip, LandmarkType.rightHip);
(double, double)? _knees(PoseFrame f) =>
    trustedMidline(f, LandmarkType.leftKnee, LandmarkType.rightKnee);
(double, double)? _ankles(PoseFrame f) =>
    trustedMidline(f, LandmarkType.leftAnkle, LandmarkType.rightAnkle);

/// The standing body axis, shoulder midline to ankle midline, or null.
double? standingAxisAngle(PoseFrame frame) {
  final s = _shoulders(frame), a = _ankles(frame);
  return (s == null || a == null) ? null : segmentAngle(s, a);
}

/// Thigh, shank and torso angles of one frame, and which way it faces.
class SegmentAngles {
  const SegmentAngles({
    required this.facing,
    required this.thigh,
    required this.shank,
    required this.torso,
  });

  /// +1 when the knee is to image-right of the hip, -1 otherwise.
  final int facing;
  final double thigh; // hip -> knee
  final double shank; // knee -> ankle
  final double torso; // shoulder -> hip
}

/// The segment angles of [frame], or null when a joint is not trusted.
SegmentAngles? segmentAnglesOf(PoseFrame frame) {
  final s = _shoulders(frame), h = _hips(frame);
  final k = _knees(frame), a = _ankles(frame);
  if (s == null || h == null || k == null || a == null) return null;
  return SegmentAngles(
    facing: k.$1 > h.$1 ? 1 : -1,
    thigh: segmentAngle(h, k),
    shank: segmentAngle(k, a),
    torso: segmentAngle(s, h),
  );
}

/// Median, count and range of a set of samples.
class RobustSummary {
  const RobustSummary(
      {required this.median,
      required this.n,
      required this.min,
      required this.max});

  final double median;
  final int n;
  final double min;
  final double max;

  @override
  String toString() => 'median=${median.toStringAsFixed(1)} n=$n '
      'min=${min.toStringAsFixed(1)} max=${max.toStringAsFixed(1)}';
}

/// The robust summary of [samples], or null when there are none.
RobustSummary? robustSummary(List<double> samples) {
  if (samples.isEmpty) return null;
  final s = [...samples]..sort();
  final mid = s.length ~/ 2;
  final median = s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  return RobustSummary(median: median, n: s.length, min: s.first, max: s.last);
}

/// The standing samples of one attempt, frozen when its descent began.
class StandingSnapshot {
  StandingSnapshot(List<double> samples)
      : samples = List.unmodifiable(samples),
        summary = robustSummary(samples);

  final List<double> samples;
  final RobustSummary? summary;

  /// Whether this attempt has enough standing samples to be used at all.
  bool get usable => samples.length >= kStandingMinSamples;
}

/// Collects the standing axis while the lifter stands at the top, and freezes
/// it per attempt.
///
/// The live window only fills at the top, after [kStandingSettleFrames] frames
/// there, from frames whose hip midline moved less than
/// [kStandingStillTolerance] since the previous observed frame. At the start
/// of a descent it is copied into a snapshot and cleared, so the snapshot a
/// completed rep logs is exactly the stance that preceded it — never the next
/// attempt's, never a rejected one's.
class StandingWindow {
  final List<double> _live = [];
  int _topFrames = 0;
  (double, double)? _lastHip;
  StandingSnapshot? _snapshot;

  /// Offer a frame seen while the counter is at the top.
  void onTopFrame(PoseFrame frame) {
    _topFrames++;
    final hip = _hips(frame);
    final previous = _lastHip;
    _lastHip = hip;
    if (_topFrames <= kStandingSettleFrames) return;
    final axis = standingAxisAngle(frame);
    if (axis == null || hip == null || previous == null) return;
    final dx = hip.$1 - previous.$1, dy = hip.$2 - previous.$2;
    if (math.sqrt(dx * dx + dy * dy) >= kStandingStillTolerance) return;
    _live.add(axis);
    if (_live.length > kStandingWindowCapacity) _live.removeAt(0);
  }

  /// The top -> descending transition: freeze this attempt's stance.
  void onDescentStarted() {
    _snapshot = StandingSnapshot(_live);
    _clearLive();
  }

  /// The frozen snapshot of the attempt that just completed, handed over once.
  StandingSnapshot? takeSnapshot() {
    final s = _snapshot;
    _snapshot = null;
    return s;
  }

  /// A rejected attempt or a new set: nothing of it may reach the next rep.
  void reset() {
    _snapshot = null;
    _clearLive();
  }

  /// Samples collected so far at the current top. Visible for tests.
  List<double> get liveSamples => List.unmodifiable(_live);

  void _clearLive() {
    _live.clear();
    _topFrames = 0;
    _lastHip = null;
  }
}

/// One completed rep as the device logged it, for [classifyRoll].
class RollRep {
  const RollRep({
    required this.facing,
    required this.standingMedian,
    required this.thigh,
    required this.shank,
  });

  final int facing;

  /// Null when the rep's standing window was not usable.
  final double? standingMedian;
  final double thigh;
  final double shank;
}

enum RollVerdict { confirmed, refuted, inconclusive }

/// The verdict and the numbers behind it.
class RollClassification {
  const RollClassification(this.verdict,
      {this.delta, this.thighDiff, this.shankDiff, this.rawThighDiff,
       this.rawShankDiff});

  final RollVerdict verdict;
  final double? delta;
  final double? thighDiff;
  final double? shankDiff;
  final double? rawThighDiff;
  final double? rawShankDiff;

  @override
  String toString() => '${verdict.name} delta=${delta?.toStringAsFixed(1)} '
      'thighDiff=${thighDiff?.toStringAsFixed(1)} '
      'shankDiff=${shankDiff?.toStringAsFixed(1)} '
      'rawThighDiff=${rawThighDiff?.toStringAsFixed(1)} '
      'rawShankDiff=${rawShankDiff?.toStringAsFixed(1)}';
}

/// The pre-registered decision rule, applied to usable reps only.
///
/// INCONCLUSIVE when either facing has fewer than 2 usable reps. Otherwise the
/// roll is delta = (rL + rR) / 2, the mean of the two facings' median standing
/// axes — a body lean flips sign with facing and cancels, a roll does not.
/// Each segment angle is normalised as n = f * (a - delta). CONFIRMED when
/// |delta| >= 5, and after that normalisation the two facings' mean thigh AND
/// mean shank differ by <= 5, and with delta forced to 0 at least one of them
/// differs by > 5 — so the roll explains an asymmetry that is really there.
RollClassification classifyRoll(List<RollRep> reps) {
  final usable = [for (final r in reps) if (r.standingMedian != null) r];
  final left = [for (final r in usable) if (r.facing < 0) r];
  final right = [for (final r in usable) if (r.facing > 0) r];
  if (left.length < 2 || right.length < 2) {
    return const RollClassification(RollVerdict.inconclusive);
  }
  double medianOf(List<RollRep> rs) =>
      robustSummary([for (final r in rs) r.standingMedian!])!.median;
  final delta = (medianOf(left) + medianOf(right)) / 2;

  double diff(double Function(RollRep) seg, double d) {
    double mean(List<RollRep> rs) =>
        rs.fold(0.0, (s, r) => s + r.facing * (seg(r) - d)) / rs.length;
    return (mean(left) - mean(right)).abs();
  }

  final thighDiff = diff((r) => r.thigh, delta);
  final shankDiff = diff((r) => r.shank, delta);
  final rawThighDiff = diff((r) => r.thigh, 0);
  final rawShankDiff = diff((r) => r.shank, 0);
  final confirmed = delta.abs() >= 5 &&
      thighDiff <= 5 &&
      shankDiff <= 5 &&
      (rawThighDiff > 5 || rawShankDiff > 5);
  return RollClassification(
    confirmed ? RollVerdict.confirmed : RollVerdict.refuted,
    delta: delta,
    thighDiff: thighDiff,
    shankDiff: shankDiff,
    rawThighDiff: rawThighDiff,
    rawShankDiff: rawShankDiff,
  );
}

/// The `[rep] segments` debug line: the frozen stance and the deepest frame.
String debugSegmentsLine(StandingSnapshot? standing, PoseFrame? deepest) {
  final seg = deepest == null ? null : segmentAnglesOf(deepest);
  final st = standing?.summary;
  final usable = standing?.usable ?? false;
  final raw = standing == null
      ? '[]'
      : '[${standing.samples.map((v) => v.toStringAsFixed(1)).join(',')}]';
  final segText = seg == null
      ? 'segments=unavailable'
      : 'f=${seg.facing} thigh=${seg.thigh.toStringAsFixed(1)} '
          'shank=${seg.shank.toStringAsFixed(1)} '
          'torso=${seg.torso.toStringAsFixed(1)}';
  return 'segments $segText standing=${st ?? "none"} '
      '${usable ? "usable" : "insufficient"} raw=$raw';
}
