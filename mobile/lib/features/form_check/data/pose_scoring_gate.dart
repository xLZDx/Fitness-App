/// Is this frame reliable enough to JUDGE a repetition against a target?
///
/// `evaluateGated` answers a narrower question — can the classifier's own
/// required joints be trusted — and for the squat those are hips and knees. The
/// silhouette score reads more than that (shoulder, hip, knee, ankle), and the
/// targets are authored on the LEFT side only. Measured on an S23, 2026-09-18:
/// a body standing right-side-on, or cropped at the ankles, was scored against
/// joints ML Kit had extrapolated or that were hidden behind the body, the
/// score collapsed, the rep was called missed, and the skeleton stayed red.
///
/// This module says "cannot tell" for such a frame — never "bad form". It picks
/// the better-visible side first, so a right-side-on stance is scored on the
/// limbs the camera actually sees, and then reuses [gatePose] over exactly the
/// scored set so the reason (`lowConfidence`, `outOfFrame`, ...) stays the
/// vocabulary the rest of the screen already turns into a hint.
library;

import 'pose_gate.dart';
import 'pose_landmark.dart';
import 'pose_target.dart';

/// The right-hand counterpart of a left-side joint, or null when the joint has
/// none (the nose) or is not a left-side joint.
LandmarkType? _rightOf(LandmarkType t) => switch (t) {
      LandmarkType.leftShoulder => LandmarkType.rightShoulder,
      LandmarkType.leftElbow => LandmarkType.rightElbow,
      LandmarkType.leftWrist => LandmarkType.rightWrist,
      LandmarkType.leftHip => LandmarkType.rightHip,
      LandmarkType.leftKnee => LandmarkType.rightKnee,
      LandmarkType.leftAnkle => LandmarkType.rightAnkle,
      LandmarkType.leftEar => LandmarkType.rightEar,
      _ => null,
    };

/// The joints [target] actually judges: everything it carries minus what it
/// only draws.
Set<LandmarkType> scoredJointsOf(PoseTarget target) => {
      for (final t in target.joints.keys)
        if (!target.unscoredJoints.contains(t)) t,
    };

/// Which side of the body a frame is scored on.
enum ScoringSide { left, right }

/// A frame prepared for scoring, and which side it came from.
class ScoringFrame {
  const ScoringFrame(this.frame, this.side);

  /// The frame to score. For [ScoringSide.right] the right-hand joints have been
  /// moved into the left slots the target is authored in.
  final PoseFrame frame;
  final ScoringSide side;
}

double _meanLikelihood(PoseFrame frame, Iterable<LandmarkType> types) {
  var sum = 0.0;
  var n = 0;
  for (final t in types) {
    sum += frame.landmarks[t]?.likelihood ?? 0.0;
    n++;
  }
  return n == 0 ? 0.0 : sum / n;
}

/// Choose the better-visible side for [scored] and return the frame to score.
///
/// Compares the mean likelihood of the scored left-side joints with their
/// right-side counterparts (a missing joint counts as 0). The frame is returned
/// unchanged when left is at least as good. Otherwise every scored left joint is
/// replaced by its right counterpart — retyped into the left slot — and a
/// counterpart the detector did not report leaves the slot EMPTY, so the gate
/// reports it as missing rather than quietly scoring the hidden left joint.
///
/// A scored set that already names right-side joints is bilateral: nothing is
/// mapped, because moving one side onto the other would collide with joints the
/// target itself asks for.
ScoringFrame chooseScoringSide(PoseFrame frame, Set<LandmarkType> scored) {
  final pairs = <LandmarkType, LandmarkType>{
    for (final t in scored)
      if (_rightOf(t) case final r?) t: r,
  };
  final bilateral = scored.any((t) => pairs.containsValue(t));
  if (pairs.isEmpty || bilateral) return ScoringFrame(frame, ScoringSide.left);

  final left = _meanLikelihood(frame, pairs.keys);
  final right = _meanLikelihood(frame, pairs.values);
  if (left >= right) return ScoringFrame(frame, ScoringSide.left);

  final mapped = Map<LandmarkType, PoseLandmark>.of(frame.landmarks);
  pairs.forEach((leftType, rightType) {
    final r = frame.landmarks[rightType];
    if (r == null) {
      mapped.remove(leftType);
    } else {
      mapped[leftType] = PoseLandmark(
        type: leftType,
        x: r.x,
        y: r.y,
        z: r.z,
        likelihood: r.likelihood,
        side: LandmarkSide.left,
      );
    }
  });
  return ScoringFrame(
    PoseFrame(
      timestampMs: frame.timestampMs,
      landmarks: mapped,
      aspectRatio: frame.aspectRatio,
      sourceSpace: frame.sourceSpace,
    ),
    ScoringSide.right,
  );
}

/// Can [scoringFrame] be judged against a target that scores [scored]?
///
/// Returns the [PoseGateVerdict], not a bool, so `unitMismatch` (never advise
/// stepping back) stays distinguishable from `outOfFrame` (do).
PoseGateVerdict reliabilityVerdict(
  PoseFrame scoringFrame,
  Set<LandmarkType> scored, {
  PoseGateConfig config = const PoseGateConfig(),
}) =>
    gatePose(scoringFrame, scored, config: config);

/// The one per-frame verdict the screen reads: the classifier's own verdict when
/// it is not ok, otherwise the scoring verdict.
PoseGateVerdict combineGateVerdicts(
  PoseGateVerdict classifier,
  PoseGateVerdict scoring,
) =>
    classifier.isScorable ? scoring : classifier;
