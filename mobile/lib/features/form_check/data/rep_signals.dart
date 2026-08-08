// Rep signals for the movements beyond the squat.
//
// `squatDepthSignal` is the original and the only one until now. It returns a
// raw difference in frame-fraction units — mean hip y minus mean knee y — so
// its thresholds (`topEnter = -0.15`) mean "15% of the FRAME", and what
// fraction of the frame a body occupies is set by how far it stands from the
// phone. Step back a metre and the same squat produces a smaller signal.
//
// That is the same hidden assumption that got the depth and hinge RULES
// withdrawn: an absolute number read out of a 2D projection, where correct and
// incorrect execution overlap. `pose_target.dart` fixed it for MATCHING by
// normalising position and size away. These signals do the same for COUNTING:
// every one is divided by a length taken from the same body in the same frame,
// so a rep counts the same at two metres as at four.
//
// `squatDepthSignal` is deliberately left alone. It is tuned, it ships, and
// the operator has counted reps with it; re-scaling it would invalidate every
// threshold in `RepCounterConfig`'s defaults for no gain today.

import 'dart:math' as math;

import 'pose_landmark.dart';
import 'rep_counter.dart';

/// Mean of the two sides, or null when either is missing or unsure.
///
/// Both sides, not one: from the side the far limb is behind the body and the
/// detector is estimating it, but averaging still beats picking a side blind,
/// because which side faces the camera is not known here.
(double, double)? _mid(PoseFrame f, LandmarkType l, LandmarkType r,
    double minLikelihood) {
  final a = f.landmarks[l], b = f.landmarks[r];
  if (a == null || b == null) return null;
  if (a.likelihood < minLikelihood || b.likelihood < minLikelihood) return null;
  return ((a.x + b.x) / 2, (a.y + b.y) / 2);
}

double _dist((double, double) a, (double, double) b) =>
    math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

/// Shoulder-to-hip distance: the scale every torso-relative signal divides by.
///
/// Null when it is too small to divide by. A body collapsed to a point is the
/// detector failing, and dividing by it would produce an enormous signal that
/// looks exactly like a very fast rep.
double? _torso(PoseFrame f, double minLikelihood) {
  final sh = _mid(f, LandmarkType.leftShoulder, LandmarkType.rightShoulder,
      minLikelihood);
  final hip = _mid(f, LandmarkType.leftHip, LandmarkType.rightHip,
      minLikelihood);
  if (sh == null || hip == null) return null;
  final d = _dist(sh, hip);
  return d < 0.02 ? null : d;
}

/// Curl: how far the wrist has risen towards the shoulder, in torso lengths.
///
/// Arm hanging ≈ -0.6 (wrist well below the elbow), fully curled ≈ +0.5.
/// The elbow is the pivot and is not part of the measurement, deliberately —
/// swinging the elbow forward is the commonest way to fake a curl, and a
/// signal that rewarded it would count the fake.
double? curlSignal(PoseFrame f, double minLikelihood) {
  final torso = _torso(f, minLikelihood);
  if (torso == null) return null;
  final elbow =
      _mid(f, LandmarkType.leftElbow, LandmarkType.rightElbow, minLikelihood);
  final wrist =
      _mid(f, LandmarkType.leftWrist, LandmarkType.rightWrist, minLikelihood);
  if (elbow == null || wrist == null) return null;
  // Image y grows downward, so a rising wrist makes this grow.
  return (elbow.$2 - wrist.$2) / torso;
}

/// Hinge: how upright the torso is, 1.0 standing and 0.0 folded to horizontal.
///
/// Vertical extent of the torso over its true length — a pure ratio, so it
/// says "how far through the hinge" without caring about body size, camera
/// distance, or where in the frame the lifter stands.
double? hingeSignal(PoseFrame f, double minLikelihood) {
  final torso = _torso(f, minLikelihood);
  if (torso == null) return null;
  final sh = _mid(f, LandmarkType.leftShoulder, LandmarkType.rightShoulder,
      minLikelihood);
  final hip =
      _mid(f, LandmarkType.leftHip, LandmarkType.rightHip, minLikelihood);
  if (sh == null || hip == null) return null;
  return (hip.$2 - sh.$2) / torso;
}

/// Lunge: hip height above the knee, in thigh lengths.
///
/// The squat's quantity made scale-free. Standing ≈ +0.9, bottom ≈ 0.0 when
/// the thigh reaches horizontal.
double? lungeSignal(PoseFrame f, double minLikelihood) {
  final hip =
      _mid(f, LandmarkType.leftHip, LandmarkType.rightHip, minLikelihood);
  final knee =
      _mid(f, LandmarkType.leftKnee, LandmarkType.rightKnee, minLikelihood);
  if (hip == null || knee == null) return null;
  final thigh = _dist(hip, knee);
  if (thigh < 0.02) return null;
  return (knee.$2 - hip.$2) / thigh;
}

/// Sit-up: the same verticality as the hinge, read lying down.
///
/// Flat on the floor the torso is nearly horizontal, so this sits near 0;
/// curled up it rises. Shares [hingeSignal]'s definition on purpose — the two
/// movements differ by orientation, not by what is being measured, and one
/// definition cannot drift out of step with itself.
double? situpSignal(PoseFrame f, double minLikelihood) =>
    hingeSignal(f, minLikelihood);

/// Overhead press: wrist height above the shoulder, in arm lengths.
///
/// Racked at the shoulder ≈ 0.0, locked out overhead ≈ +1.0. Divided by the
/// arm rather than the torso so the number reads as "fraction of the press
/// completed" for a long-armed and a short-armed lifter alike.
double? overheadPressSignal(PoseFrame f, double minLikelihood) {
  final sh = _mid(f, LandmarkType.leftShoulder, LandmarkType.rightShoulder,
      minLikelihood);
  final elbow =
      _mid(f, LandmarkType.leftElbow, LandmarkType.rightElbow, minLikelihood);
  final wrist =
      _mid(f, LandmarkType.leftWrist, LandmarkType.rightWrist, minLikelihood);
  if (sh == null || elbow == null || wrist == null) return null;
  final arm = _dist(sh, elbow) + _dist(elbow, wrist);
  if (arm < 0.04) return null;
  return (sh.$2 - wrist.$2) / arm;
}

/// Thresholds for a signal that RISES into the "bottom" phase, like the squat.
///
/// [RepCounter]'s ladder is named for the squat: `top` is where the signal is
/// low, `bottom` where it is high. A movement whose signal falls as it
/// progresses — the lunge, the hinge — is handed to [_falling] below instead
/// of having the state machine rewritten.
/// Every threshold below is derived from the AUTHORED SHAPES, not guessed.
///
/// The first draft was reasoned about — "a curl probably runs from about -0.45
/// to +0.3" — and `rep_signals_test.dart` failed four of five configs on the
/// spot. The numbers now bracket the values the targets in `pose_target.dart`
/// actually produce, and that test recomputes them on every run, so editing a
/// shape without revisiting its thresholds fails rather than silently
/// producing a counter that never advances.
///
/// Measured: arm hanging -0.589, fully curled +0.552.
const _curlConfig = RepCounterConfig(
  topEnter: -0.50,
  topExit: -0.35,
  bottomExit: 0.30,
  bottomEnter: 0.45,
  minRepDurationMs: 700,
);

/// Measured: racked at the shoulder -0.112, locked out overhead +1.000.
const _overheadPressConfig = RepCounterConfig(
  topEnter: -0.08,
  topExit: 0.05,
  bottomExit: 0.75,
  bottomEnter: 0.88,
  minRepDurationMs: 700,
);

/// Measured: lying flat 0.119, curled up 0.644.
const _situpConfig = RepCounterConfig(
  topEnter: 0.16,
  topExit: 0.25,
  bottomExit: 0.50,
  bottomEnter: 0.58,
  minRepDurationMs: 800,
);

/// Wraps a signal that FALLS as the movement progresses, so the existing
/// rising-signal state machine can drive it unchanged.
///
/// Negating is the whole trick, and it is worth doing here rather than adding
/// a direction flag to [RepCounter]: the counter's hysteresis, minimum
/// duration and likelihood handling are the parts that took the tuning, and
/// none of them care which way the number runs.
RepSignalExtractor _falling(RepSignalExtractor inner) =>
    (f, minLikelihood) {
      final v = inner(f, minLikelihood);
      return v == null ? null : -v;
    };

/// Measured after negation: standing -0.994, folded to the bottom -0.563.
const _hingeConfig = RepCounterConfig(
  topEnter: -0.95,
  topExit: -0.88,
  bottomExit: -0.68,
  bottomEnter: -0.60,
  minRepDurationMs: 800,
);

/// Measured after negation: standing -1.000, bottom of the lunge -0.707.
///
/// The narrowest band of the five, because a lunge moves the hip through less
/// of a thigh length than a squat does. Widening it would count a knee dip as
/// a rep.
const _lungeConfig = RepCounterConfig(
  topEnter: -0.96,
  topExit: -0.90,
  bottomExit: -0.78,
  bottomEnter: -0.72,
  minRepDurationMs: 800,
);

/// Signal and thresholds for each movement the coach can count.
///
/// One table, so a movement cannot be offered with a shape but no counter —
/// the failure `formCoachSupports` exists to prevent.
const Map<String, (RepSignalExtractor, RepCounterConfig)> kRepSignalsByTag = {
  'curl': (curlSignal, _curlConfig),
  'overhead_press': (overheadPressSignal, _overheadPressConfig),
  'situp': (situpSignal, _situpConfig),
};

/// The falling-signal movements, kept separate because their extractors are
/// built rather than named and so cannot sit in a const map.
final Map<String, (RepSignalExtractor, RepCounterConfig)>
    kFallingRepSignalsByTag = {
  'hinge': (_falling(hingeSignal), _hingeConfig),
  'lunge': (_falling(lungeSignal), _lungeConfig),
};

/// Everything countable, in one lookup.
Map<String, (RepSignalExtractor, RepCounterConfig)> get repSignalsByTag => {
      ...kRepSignalsByTag,
      ...kFallingRepSignalsByTag,
    };
