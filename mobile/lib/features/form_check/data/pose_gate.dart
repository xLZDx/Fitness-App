/// Is this frame worth scoring at all?
///
/// Written after the operator's 2026-07-31 report: the form coach counted
/// **6 reps with errors from a selfie of a face**, then repeated a safety
/// warning every 1.2 seconds until the page was closed.
///
/// The likely mechanism — stated as the explanation that fits the symptom, not
/// as a measured fact — is that BlazePose is a single-person, full-body model:
/// when only a face is in frame it does not omit the hips, knees and ankles, it
/// **extrapolates** them. Before this gate, nothing anywhere asked "is there
/// actually a body here?": `form_classifier.dart` checked only for `null`, and
/// the only likelihood floor in the pipeline (`rep_counter.dart`) covered four
/// joints of one exercise.
///
/// So this module answers one question and returns one of two kinds of answer:
/// **"score it"** or **"cannot tell"** — never "bad form". A coach that says
/// nothing is recoverable; a coach that invents a fault destroys trust in every
/// real fault it will ever report.
///
/// Thresholds here are opening values chosen from the failure they must catch,
/// not measured on a device fleet — and they are expressed in whatever unit the
/// landmarks arrive in, which as of this writing is **not settled** (the plugin
/// documents image space; the incident above is arithmetically inconsistent with
/// image space). Do not tune them until the diagnostic in
/// `pose_unit_probe.dart` has been read off a real device.
library;

import 'dart:math' as math;

import 'pose_landmark.dart';

/// Why a frame cannot be scored, or [PoseGateVerdict.ok] when it can.
///
/// [priority] rather than declaration order decides which reason is reported
/// when several rules are blocked at once. Declaration order used to carry that
/// meaning implicitly, in a different file from the code that depended on it —
/// so reordering these for readability silently changed behaviour.
enum PoseGateVerdict {
  /// Usable: every joint the rule needs is present, confident and in frame.
  ok(priority: 0),

  /// A joint the rule needs was not reported at all.
  missingJoints(priority: 1),

  /// Joints are reported but the detector is guessing — the signature of a
  /// body that is not really in the picture.
  lowConfidence(priority: 2),

  /// Joints sit on or past the frame edge: the body is cropped, so any measure
  /// taken from them is against a boundary, not a limb.
  outOfFrame(priority: 3),

  /// The torso is too small to be a real one at this framing — what a face
  /// close-up collapses to once the hips are extrapolated.
  implausibleGeometry(priority: 4);

  const PoseGateVerdict({required this.priority});

  /// Lower wins when several rules are blocked for different reasons. Reporting
  /// "no body" beats reporting "held at an odd angle" when both are true.
  final int priority;

  bool get isScorable => this == PoseGateVerdict.ok;
}

/// Tuning for [gatePose]. Defaults are opening values; see the library doc for
/// why they are not presented as measured truth.
class PoseGateConfig {
  const PoseGateConfig({
    this.minLikelihood = 0.7,
    this.edgeMargin = 0.02,
    this.minTorsoSpan = 0.10,
  })  : assert(minLikelihood > 0 && minLikelihood <= 1),
        assert(edgeMargin >= 0 && edgeMargin < 0.5),
        assert(minTorsoSpan >= 0 && minTorsoSpan < 1);

  /// Per-joint confidence floor.
  ///
  /// Deliberately higher than the 0.5 used by `RepCounterConfig`: 0.5 is
  /// reasonable for a joint that is genuinely in shot but briefly occluded, and
  /// far too low for a joint the model has invented off-frame.
  final double minLikelihood;

  /// How close to the frame edge a joint may sit before the body counts as
  /// cropped.
  final double edgeMargin;

  /// Minimum shoulder-to-hip **distance** before the torso is believable.
  ///
  /// Distance, not vertical separation. The first version of this check
  /// compared `|hipY - shoulderY|`, which is only a torso for a standing
  /// person: in a plank or lying on a bench the shoulders and hips sit at
  /// nearly the same height, so it scored 0.03 and rejected the frame as
  /// impossible. That disabled `PushupAlignmentClassifier` — one of the three
  /// shipped rules — and would have rejected every supine exercise. A gate
  /// built to stop false alarms had turned itself into a false silence.
  final double minTorsoSpan;
}

/// Decide whether [frame] can be scored for a rule that reads [required].
///
/// Two kinds of check, deliberately separated:
///
/// * **Per-rule** — presence, confidence and framing of the joints this rule
///   actually reads. A rule cannot be trusted to notice its own inputs were
///   invented, so this runs before it does.
/// * **Frame-level** — is there a plausible human here at all. Computed from
///   whatever torso landmarks the *frame* carries, NOT from [required].
///
/// That separation is the fix for a real defect: `SquatDepthClassifier` used to
/// declare both shoulders purely so the torso check would run, and the gate then
/// edge-checked them like inputs — so a squat framed with the shoulders near the
/// top of frame returned [PoseGateVerdict.outOfFrame] and depth was never
/// scored. A rule that never reads shoulders was being blocked by shoulders.
PoseGateVerdict gatePose(
  PoseFrame frame,
  Set<LandmarkType> required, {
  PoseGateConfig config = const PoseGateConfig(),
}) {
  for (final type in required) {
    final lm = frame.landmarks[type];
    if (lm == null) return PoseGateVerdict.missingJoints;
    if (lm.likelihood < config.minLikelihood) {
      return PoseGateVerdict.lowConfidence;
    }
  }

  final lo = config.edgeMargin;
  final hi = 1.0 - config.edgeMargin;
  for (final type in required) {
    final lm = frame.landmarks[type]!;
    if (lm.x <= lo || lm.x >= hi || lm.y <= lo || lm.y >= hi) {
      return PoseGateVerdict.outOfFrame;
    }
  }

  if (!_torsoIsPlausible(frame, config)) {
    return PoseGateVerdict.implausibleGeometry;
  }

  return PoseGateVerdict.ok;
}

/// Frame-level sanity: is the torso big enough to belong to a real person.
///
/// Returns true when the frame does not carry enough torso landmarks to judge —
/// "cannot tell" must never become "reject".
bool _torsoIsPlausible(PoseFrame frame, PoseGateConfig config) {
  final shoulder = _midpoint(frame, const [
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
  ], config.minLikelihood);
  final hip = _midpoint(frame, const [
    LandmarkType.leftHip,
    LandmarkType.rightHip,
  ], config.minLikelihood);
  if (shoulder == null || hip == null) return true;

  final dx = hip.$1 - shoulder.$1;
  final dy = hip.$2 - shoulder.$2;
  return math.sqrt(dx * dx + dy * dy) >= config.minTorsoSpan;
}

/// Mean (x, y) of whichever of [types] are present and confident, or null.
(double, double)? _midpoint(
  PoseFrame frame,
  List<LandmarkType> types,
  double minLikelihood,
) {
  var sumX = 0.0;
  var sumY = 0.0;
  var n = 0;
  for (final t in types) {
    final lm = frame.landmarks[t];
    if (lm == null || lm.likelihood < minLikelihood) continue;
    sumX += lm.x;
    sumY += lm.y;
    n++;
  }
  return n == 0 ? null : (sumX / n, sumY / n);
}
