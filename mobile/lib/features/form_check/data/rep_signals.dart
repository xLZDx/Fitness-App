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
// `squatDepthSignal` itself is still unchanged (tests and `RepCounterConfig`'s
// defaults are written against it), but since 2026-10-14 the LIVE squat no
// longer counts with it: it was phone-height and distance dependent and flaky
// on a real device. See `squatBodyRelativeSignal` below.

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

/// The shoulder-to-shoulder distance, or null when a shoulder is unusable.
///
/// The one body length a hinge does not shorten. Used as the reference that
/// tells a foreshortened torso from a folded one — see [hingeSignal].
double? _shoulderWidth(PoseFrame f, double minLikelihood) {
  final a = f.landmarks[LandmarkType.leftShoulder];
  final b = f.landmarks[LandmarkType.rightShoulder];
  if (a == null || b == null) return null;
  if (a.likelihood < minLikelihood || b.likelihood < minLikelihood) return null;
  return _dist((a.x, a.y), (b.x, b.y));
}

/// Hinge: how upright the torso is, 1.0 standing and 0.0 folded to horizontal.
///
/// Vertical extent of the torso over its true length — a pure ratio, so it
/// says "how far through the hinge" without caring about body size, camera
/// distance, or where in the frame the lifter stands.
///
/// ## Why it refuses a front-on frame
///
/// Both halves of that ratio are measured on the image. Filmed from the side a
/// hinge rotates the torso across the frame, the numerator collapses and the
/// denominator does not, and the signal says what it should. Filmed from the
/// FRONT the same hinge rotates the torso AWAY from the camera: the numerator
/// and the denominator foreshorten together, the ratio stays near 1.0, and the
/// signal reports a lifter standing bolt upright while they are folded to
/// horizontal. Not noise — a confident wrong answer, which is worse.
///
/// [_shoulderWidth] is the discriminator because it is the one length a hinge
/// does not change. Side-on it is small and the torso towers over it; front-on
/// it is large, and a foreshortened torso falls below it. So when the torso is
/// shorter than the shoulders are wide, the camera is not in a position to see
/// this movement and the answer is null.
///
/// Null, not a guess. The rep counter holds its phase on a null frame and
/// counts it as unobserved, so a hinge performed front-on produces a rep that
/// reports as unjudged rather than as clean — which is the true statement.
double? hingeSignal(PoseFrame f, double minLikelihood) {
  final torso = _torso(f, minLikelihood);
  if (torso == null) return null;
  final shoulders = _shoulderWidth(f, minLikelihood);
  if (shoulders != null && torso < shoulders) return null;
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

/// Squat depth, body-relative: hip height below the knee in TORSO lengths.
///
/// 2026-10-14. The original [squatDepthSignal] is a raw difference in frame
/// fractions, so the same squat read differently at different phone heights and
/// distances ("flaky" on a real phone). This divides the hip-minus-knee height by
/// the shoulder-to-hip length taken from the same body in the same frame, the
/// way every other movement in this file does. Standing sits near -0.8 .. -1.1,
/// parallel (hip at knee height) at 0, below parallel positive.
///
/// The torso is the reference rather than the thigh on purpose: seen side-on
/// both are rigid in the image plane, but front-on the thigh foreshortens as the
/// knees travel toward the camera (its image length collapses at depth and the
/// ratio would jump), while the torso stays nearly constant.
///
/// Side-on, the far hip/knee are inferred by the detector, so each side is
/// measured on its own and the sides are combined weighted by confidence; a
/// side whose shoulder, hip or knee is below [minLikelihood] is ignored, and a
/// view with only the near side visible is accepted. Null when no side has all
/// three joints.
double? squatBodyRelativeSignal(PoseFrame f, double minLikelihood) {
  var sum = 0.0;
  var weight = 0.0;
  const sides = [
    (LandmarkType.leftShoulder, LandmarkType.leftHip, LandmarkType.leftKnee),
    (LandmarkType.rightShoulder, LandmarkType.rightHip, LandmarkType.rightKnee),
  ];
  for (final (s, h, k) in sides) {
    final sh = f.landmarks[s], hip = f.landmarks[h], knee = f.landmarks[k];
    if (sh == null || hip == null || knee == null) continue;
    final conf = math.min(sh.likelihood, math.min(hip.likelihood, knee.likelihood));
    if (conf < minLikelihood) continue;
    final torso = _dist((sh.x, sh.y), (hip.x, hip.y));
    if (torso < 0.02) continue;
    sum += conf * (hip.y - knee.y) / torso;
    weight += conf;
  }
  return weight == 0 ? null : sum / weight;
}

/// Per-leg depth in the same torso-relative unit as [squatBodyRelativeSignal],
/// or null unless BOTH sides (shoulders, hips, knees) were genuinely seen. The
/// confidence bar and the reason are those of [squatSideDepths].
SideDepths? squatBodyRelativeSideDepths(PoseFrame f, double minLikelihood) {
  final lS = f.landmarks[LandmarkType.leftShoulder];
  final rS = f.landmarks[LandmarkType.rightShoulder];
  final lH = f.landmarks[LandmarkType.leftHip];
  final rH = f.landmarks[LandmarkType.rightHip];
  final lK = f.landmarks[LandmarkType.leftKnee];
  final rK = f.landmarks[LandmarkType.rightKnee];
  if (lS == null || rS == null || lH == null || rH == null || lK == null ||
      rK == null) {
    return null;
  }
  for (final j in [lS, rS, lH, rH, lK, rK]) {
    if (j.likelihood < minLikelihood) return null;
  }
  final torso = _dist(((lS.x + rS.x) / 2, (lS.y + rS.y) / 2),
      ((lH.x + rH.x) / 2, (lH.y + rH.y) / 2));
  if (torso < 0.02) return null;
  return SideDepths(
      left: (lH.y - lK.y) / torso, right: (rH.y - rK.y) / torso);
}

/// Depth, in [squatBodyRelativeSignal] units, the coach asks the squat to reach:
/// the thigh within about 12 degrees of horizontal (hip at most 0.2 torso
/// lengths above the knee). Deliberately lenient of parallel (0): the detector's
/// hip is the joint centre, above the hip crease, and the operator was once told
/// to go lower when there was nowhere lower to go. A `PRODUCT_HEURISTIC`.
const double kSquatFullDepthSignal = -0.20;

/// Thresholds for [squatBodyRelativeSignal]. Standing is near -0.8 to -1.1, so
/// the top gate sits at -0.57; a rep is ACCEPTED once the thigh is about 20
/// degrees off horizontal (-0.30) and judged shallow below
/// [kSquatFullDepthSignal]. Bands: top -0.57/-0.47 and bottom -0.40/-0.30, 0.10
/// wide, i.e. about 2.5 percent of frame height for a torso spanning a quarter of
/// the frame, a few times ML Kit's jitter. Derived from the authored shapes
/// (`squat.top` -0.78, `squat.bottom` +0.16 in this unit) and re-checked by
/// `squat_body_relative_signal_test.dart`.
const squatBodyRelativeConfig = RepCounterConfig(
  topEnter: -0.57,
  topExit: -0.47,
  bottomExit: -0.40,
  bottomEnter: -0.30,
  fullDepthSignal: kSquatFullDepthSignal,
);

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
