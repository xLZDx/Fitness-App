// Pure measurement helpers shared by the registry-driven coach pieces:
// `GenericRuleClassifier` (per-frame rules), the hold timer wiring and the rep
// signal built from a registry row. Nothing here keeps state except the small
// hysteresis tracker [CoachSignalBand].
//
// ## Metric grammar (a rule's `metric` string, see [CoachMetric.parse])
//
// | metric                         | value                                            |
// |--------------------------------|--------------------------------------------------|
// | `signal`                       | the spec's own signal value (raw, signed)        |
// | `knee_angle`                   | hip-knee-ankle angle at the knee, degrees        |
// | `hip_angle`                    | shoulder-hip-knee angle at the hip, degrees      |
// | `elbow_angle`                  | shoulder-elbow-wrist angle at the elbow, degrees |
// | `shoulder_angle`               | hip-shoulder-wrist angle at the shoulder, degrees|
// | `angle:a,b,c`                  | angle at `b`, degrees                            |
// | `ratio:a,b`                    | distance a-b over torso length                   |
// | `line:a,b,c`                   | vertical offset of `b` from the line a-c over    |
// |                                | torso length; positive = `b` BELOW the line on  |
// |                                | screen, whichever way the body faces             |
// | `torso_lean`                   | shoulder-hip line off vertical, degrees          |
// | `torso_drift`                  | |torso_lean - lean at first scored frame|        |
// | `wrist_above_shoulder`         | (shoulder.y - wrist.y) / torso                   |
// | `nose_above_wrist`             | (wrist.y - nose.y) / torso                       |
//
// Joint names are exact [LandmarkType] names or side-neutral stems (`knee`),
// resolved to the tracked side. Anything else is an unknown metric: the rule is
// inert (never faults) -- see [CoachMetric.parse] returning null.
//
// A `lineDeviation` SIGNAL (hold exercises such as the plank) is banded on its
// ABSOLUTE value, so `enter`/`exit` read as "within +-enter of the line".

import 'dart:math' as math;

import 'coach_spec.dart';
import 'measured_rep_configs.dart' show jointAngleDeg;
import 'pose_landmark.dart';
import 'pose_scoring_gate.dart';
import 'rep_counter.dart';

/// The landmark for [name] on side [sideIdx] (0 left, 1 right), or null when
/// [name] is unknown. Exact names ignore [sideIdx].
LandmarkType? coachLandmarkOn(String name, int sideIdx) {
  final r = resolveCoachLandmark(name);
  if (r == null) return null;
  return r.length == 1 ? r.first : r[sideIdx];
}

const _torsoJoints = ['shoulder', 'hip'];

enum CoachMetricKind {
  signal,
  angle,
  ratio,
  line,
  torsoLean,
  torsoDrift,
  wristAboveShoulder,
  noseAboveWrist,
}

const _namedAngles = <String, List<String>>{
  'knee_angle': ['hip', 'knee', 'ankle'],
  'hip_angle': ['shoulder', 'hip', 'knee'],
  'elbow_angle': ['shoulder', 'elbow', 'wrist'],
  'shoulder_angle': ['hip', 'shoulder', 'wrist'],
};

/// A parsed rule metric. [joints] are the names the metric reads, torso
/// reference included, so the gate can require exactly those.
class CoachMetric {
  const CoachMetric._(this.kind, this.joints);
  final CoachMetricKind kind;
  final List<String> joints;

  bool get isDrift => kind == CoachMetricKind.torsoDrift;

  /// Null for an unknown metric or an unknown joint name inside it.
  static CoachMetric? parse(String metric, CoachSpec spec) {
    List<String>? named(List<String> joints) =>
        joints.every((j) => resolveCoachLandmark(j) != null) ? joints : null;
    CoachMetric? build(CoachMetricKind k, List<String>? joints) =>
        joints == null ? null : CoachMetric._(k, joints);

    if (metric == 'signal') {
      return CoachMetric._(CoachMetricKind.signal, coachSignalJoints(spec));
    }
    final fixed = _namedAngles[metric];
    if (fixed != null) return CoachMetric._(CoachMetricKind.angle, fixed);
    switch (metric) {
      case 'torso_lean':
        return CoachMetric._(CoachMetricKind.torsoLean, _torsoJoints);
      case 'torso_drift':
        return CoachMetric._(CoachMetricKind.torsoDrift, _torsoJoints);
      case 'wrist_above_shoulder':
        return CoachMetric._(
            CoachMetricKind.wristAboveShoulder, const ['shoulder', 'hip', 'wrist']);
      case 'nose_above_wrist':
        return CoachMetric._(CoachMetricKind.noseAboveWrist,
            const ['shoulder', 'hip', 'wrist', 'nose']);
    }
    final colon = metric.indexOf(':');
    if (colon < 0) return null;
    final head = metric.substring(0, colon);
    final args = metric.substring(colon + 1).split(',').map((e) => e.trim()).toList();
    switch (head) {
      case 'angle':
        return args.length == 3 ? build(CoachMetricKind.angle, named(args)) : null;
      case 'ratio':
        return args.length == 2
            ? build(CoachMetricKind.ratio, named([...args, ..._torsoJoints]))
            : null;
      case 'line':
        return args.length == 3
            ? build(CoachMetricKind.line, named([...args, ..._torsoJoints]))
            : null;
    }
    return null;
  }
}

/// Names of the rules of [spec] whose metric the engine cannot evaluate. Empty
/// for a healthy row; the content package asserts this over the shipped
/// registry so a typo cannot ship as a rule that silently never fires.
List<String> unsupportedCoachMetrics(CoachSpec spec) => [
      for (final r in spec.rules)
        if (CoachMetric.parse(r.metric, spec) == null) '${spec.id}.${r.id}',
    ];

/// Joints the signal reads, torso reference included for normalised kinds.
List<String> coachSignalJoints(CoachSpec spec) => [
      ...spec.signal.joints,
      if (spec.signal.normalizeTorso) ..._torsoJoints,
    ];

/// Every joint the spec reads (signal and all supported rule metrics), as
/// names. Unsupported metrics contribute nothing.
Set<String> coachSpecJointNames(CoachSpec spec) => {
      ...coachSignalJoints(spec),
      for (final r in spec.rules) ...?CoachMetric.parse(r.metric, spec)?.joints,
    };

/// [coachSpecJointNames] resolved to landmarks on [sideIdx].
Set<LandmarkType> coachSpecLandmarks(CoachSpec spec, int sideIdx) => {
      for (final n in coachSpecJointNames(spec))
        if (coachLandmarkOn(n, sideIdx) case final t?) t,
    };

/// Left-slot landmarks, plus right too under [CoachSidePolicy.both]: what the
/// gate must see for this spec.
Set<LandmarkType> coachRequiredLandmarks(CoachSpec spec) => {
      ...coachSpecLandmarks(spec, 0),
      if (spec.sidePolicy == CoachSidePolicy.both)
        ...coachSpecLandmarks(spec, 1),
    };

/// The frame to score: for [CoachSidePolicy.bestVisible] the better-visible
/// side is moved into the left slots (`chooseScoringSide`); otherwise as is.
/// Idempotent.
PoseFrame coachFrameFor(CoachSpec spec, PoseFrame raw) {
  if (spec.sidePolicy != CoachSidePolicy.bestVisible) return raw;
  return chooseScoringSide(raw, coachSpecLandmarks(spec, 0)).frame;
}

double? _dist(PoseLandmark a, PoseLandmark b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)).toDouble();

PoseLandmark? _lm(PoseFrame f, String name, int side, double minLikelihood) {
  final t = coachLandmarkOn(name, side);
  if (t == null) return null;
  final l = f.landmarks[t];
  if (l == null || l.likelihood < minLikelihood) return null;
  return l;
}

double? _torso(PoseFrame f, int side, double minLikelihood) {
  final s = _lm(f, 'shoulder', side, minLikelihood);
  final h = _lm(f, 'hip', side, minLikelihood);
  if (s == null || h == null) return null;
  final d = _dist(s, h)!;
  return d < 1e-6 ? null : d;
}

double? _angle(PoseFrame f, List<String> j, int side, double minL) {
  final a = _lm(f, j[0], side, minL);
  final b = _lm(f, j[1], side, minL);
  final c = _lm(f, j[2], side, minL);
  if (a == null || b == null || c == null) return null;
  return jointAngleDeg(a, b, c);
}

double? _line(PoseFrame f, List<String> j, int side, double minL) {
  final a = _lm(f, j[0], side, minL);
  final b = _lm(f, j[1], side, minL);
  final c = _lm(f, j[2], side, minL);
  final torso = _torso(f, side, minL);
  if (a == null || b == null || c == null || torso == null) return null;
  final dx = c.x - a.x;
  if (dx.abs() < 1e-6) return null; // a vertical line has no "below"
  final yOnLine = a.y + (b.x - a.x) * (c.y - a.y) / dx;
  return (b.y - yOnLine) / torso;
}

/// The spec's signal on [view] (already side-selected) for [side], or null when
/// a joint is missing or under [minLikelihood].
double? coachSignalValue(CoachSpec spec, PoseFrame view,
    {int side = 0, double minLikelihood = 0.5}) {
  final s = spec.signal;
  switch (s.kind) {
    case CoachSignalKind.angle:
      return _angle(view, s.joints, side, minLikelihood);
    case CoachSignalKind.ratio:
      final a = _lm(view, s.joints[0], side, minLikelihood);
      final b = _lm(view, s.joints[1], side, minLikelihood);
      final torso = _torso(view, side, minLikelihood);
      if (a == null || b == null || torso == null) return null;
      return _dist(a, b)! / torso;
    case CoachSignalKind.lineDeviation:
      return _line(view, s.joints, side, minLikelihood);
  }
}

/// A rule metric on [view] for [side]. [driftBaseline] is only read for
/// `torso_drift`. Null when not measurable.
double? coachMetricValue(CoachSpec spec, CoachMetric m, PoseFrame view,
    {int side = 0, double minLikelihood = 0.5, double? driftBaseline}) {
  switch (m.kind) {
    case CoachMetricKind.signal:
      return coachSignalValue(spec, view,
          side: side, minLikelihood: minLikelihood);
    case CoachMetricKind.angle:
      return _angle(view, m.joints, side, minLikelihood);
    case CoachMetricKind.ratio:
      final a = _lm(view, m.joints[0], side, minLikelihood);
      final b = _lm(view, m.joints[1], side, minLikelihood);
      final torso = _torso(view, side, minLikelihood);
      if (a == null || b == null || torso == null) return null;
      return _dist(a, b)! / torso;
    case CoachMetricKind.line:
      return _line(view, m.joints, side, minLikelihood);
    case CoachMetricKind.torsoLean:
    case CoachMetricKind.torsoDrift:
      final lean = coachTorsoLeanDeg(view, side, minLikelihood);
      if (lean == null) return null;
      if (m.kind == CoachMetricKind.torsoLean) return lean;
      return driftBaseline == null ? 0 : (lean - driftBaseline).abs();
    case CoachMetricKind.wristAboveShoulder:
      final s = _lm(view, 'shoulder', side, minLikelihood);
      final w = _lm(view, 'wrist', side, minLikelihood);
      final torso = _torso(view, side, minLikelihood);
      if (s == null || w == null || torso == null) return null;
      return (s.y - w.y) / torso;
    case CoachMetricKind.noseAboveWrist:
      final n = _lm(view, 'nose', side, minLikelihood);
      final w = _lm(view, 'wrist', side, minLikelihood);
      final torso = _torso(view, side, minLikelihood);
      if (n == null || w == null || torso == null) return null;
      return (w.y - n.y) / torso;
  }
}

/// Shoulder-hip line off vertical, degrees (0 upright, 90 horizontal).
double? coachTorsoLeanDeg(PoseFrame view, int side, double minLikelihood) {
  final s = _lm(view, 'shoulder', side, minLikelihood);
  final h = _lm(view, 'hip', side, minLikelihood);
  if (s == null || h == null) return null;
  return math.atan2((s.x - h.x).abs(), (h.y - s.y).abs()) * 180 / math.pi;
}

/// Hysteresis band over the spec signal: becomes active past `enter`, inactive
/// past `exit`, otherwise keeps its state. A null reading keeps the state.
class CoachSignalBand {
  CoachSignalBand(this.signal);
  final CoachSignal signal;
  bool _active = false;
  bool get active => _active;

  /// [value] as banded: absolute for a `lineDeviation` signal.
  double bandValue(double value) =>
      signal.kind == CoachSignalKind.lineDeviation ? value.abs() : value;

  bool update(double? value) {
    if (value == null) return _active;
    final v = bandValue(value);
    if (signal.direction == CoachSignalDirection.falling) {
      if (v < signal.enter) _active = true;
      if (v > signal.exit) _active = false;
    } else {
      if (v > signal.enter) _active = true;
      if (v < signal.exit) _active = false;
    }
    return _active;
  }

  void reset() => _active = false;
}

/// Rep signal and thresholds for a registry row that counts reps, or null for
/// `hold` / `off` rows. Same sign convention as `MeasuredRepConfig`: the
/// counter wants a signal that RISES into the active phase, so a `falling`
/// registry signal is negated. The top (rest) band sits a quarter of the
/// enter-exit span beyond `exit`, so a lifter at rest is "at the top".
(RepSignalExtractor, RepCounterConfig)? coachRepSignal(CoachSpec spec) {
  if (spec.counting.mode != CoachCountingMode.reps) return null;
  final s = spec.signal;
  final falling = s.direction == CoachSignalDirection.falling;
  final margin = (s.exit - s.enter).abs() * 0.25;
  final config = falling
      ? RepCounterConfig(
          topEnter: -(s.exit + margin),
          topExit: -s.exit,
          bottomExit: -s.exit + 0.001,
          bottomEnter: -s.enter,
        )
      : RepCounterConfig(
          topEnter: s.exit - margin,
          topExit: s.exit,
          bottomExit: s.exit + 0.001,
          bottomEnter: s.enter,
        );
  final slots = coachSpecLandmarks(spec, 0);
  double? extract(PoseFrame frame, double minLikelihood) {
    final view = spec.sidePolicy == CoachSidePolicy.bestVisible
        ? chooseScoringSide(frame, slots).frame
        : frame;
    var v = coachSignalValue(spec, view, minLikelihood: minLikelihood);
    if (v == null && spec.sidePolicy == CoachSidePolicy.both) {
      v = coachSignalValue(spec, view, side: 1, minLikelihood: minLikelihood);
    }
    if (v == null) return null;
    if (s.kind == CoachSignalKind.lineDeviation) v = v.abs();
    return falling ? -v : v;
  }

  return (extract, config);
}
