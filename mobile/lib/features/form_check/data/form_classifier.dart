import 'dart:math' as math;

import 'pose_gate.dart';
import 'pose_landmark.dart';

/// Identifies every cue a rule can emit.
///
/// Until 2026-07-31 these were English sentences baked into the classifiers,
/// which is how "Half-rep. Lighten the bar and hit depth." reached a Russian
/// screen — and was spoken there, because the voice coach at that time read the
/// same field verbatim. The classifiers are pure Dart with no `BuildContext`,
/// so they cannot localise; they name the cue and the UI/speech boundary
/// resolves it (see `cue_text.dart`).
///
/// A key is also better gate identity than a sentence: `CueGate` suppresses a
/// repeat by comparing to the last cue, and "is this the same fault" must not
/// depend on which language it is rendered in.
///
/// The switch in `cue_text.dart` is the only place a key becomes words. With
/// Strings that switch needs a catch-all arm, so a typo in a new rule's key
/// compiles, resolves to `''`, and is silently never spoken — a classifier that
/// correctly detects a dangerous position and then says nothing. With an enum
/// the analyser refuses to build until every value has a case.
enum FormCueKey {
  squatDepthGood,
  squatDepthAlmost,
  squatDepthHalf,
  deadliftHipHingeShallow,
  deadliftHipHingeDeep,
  pushupAlignStraight,
  pushupAlignTuck,
  pushupAlignSagging,
}

/// Result of a single rule running on a single frame.
class FormFeedback {
  const FormFeedback({
    required this.rule,
    required this.severity,
    required this.cueKey,
    this.metric,
  });

  /// Stable id (e.g. "squat.depth", "pushup.alignment").
  ///
  /// Internal — never render it. It leaked to the user as
  /// "Ошибки: squat.depth, deadlift.back_angle" until 2026-07-31;
  /// `formRuleName` in `cue_text.dart` is what turns it into words.
  final String rule;

  /// 0 = good, 1 = nudge ("just a bit deeper"), 2 = stop ("save your back").
  final int severity;

  /// Which cue to say — not the sentence itself.
  final FormCueKey cueKey;

  /// Optional numeric metric the rule reasoned over (angle in degrees,
  /// ratio, etc.) — surfaced in the post-set summary.
  final double? metric;
}

/// Pure rule-based classifier. Keeps the runtime light enough to run on
/// commodity Android (the marketing line vs Tempo's TrueDepth-only Move).
abstract class FormClassifier {
  String get rule;

  /// Joints this rule reads, and **only** those.
  ///
  /// Declared rather than discovered so the frame can be gated (see [gatePose])
  /// before the rule runs — a rule cannot be trusted to notice that its own
  /// inputs were invented.
  ///
  /// Do not add joints here to make a gate check fire: everything in this set is
  /// also required to be inside the frame. Declaring shoulders that the rule
  /// never reads is what made a squat filmed with the shoulders near the top of
  /// frame return "out of frame" and never get its depth scored. Frame-level
  /// sanity checks belong to the frame, not to the rule.
  Set<LandmarkType> get requiredLandmarks;

  FormFeedback? evaluate(PoseFrame frame);
}

/// Squat depth — flags partial reps when hip never drops below knee.
class SquatDepthClassifier implements FormClassifier {
  @override
  String get rule => 'squat.depth';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftHip,
        LandmarkType.rightHip,
        LandmarkType.leftKnee,
        LandmarkType.rightKnee,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final lHip = frame.landmarks[LandmarkType.leftHip];
    final rHip = frame.landmarks[LandmarkType.rightHip];
    final lKnee = frame.landmarks[LandmarkType.leftKnee];
    final rKnee = frame.landmarks[LandmarkType.rightKnee];
    if (lHip == null || rHip == null || lKnee == null || rKnee == null) {
      return null;
    }
    final hipY = (lHip.y + rHip.y) / 2;
    final kneeY = (lKnee.y + rKnee.y) / 2;
    // Image y grows downward; "below knee" means hipY > kneeY.
    final ratio = hipY - kneeY;
    if (ratio >= 0) {
      return FormFeedback(
        rule: rule,
        severity: 0,
        cueKey: FormCueKey.squatDepthGood,
        metric: ratio,
      );
    }
    if (ratio > -0.04) {
      return FormFeedback(
        rule: rule,
        severity: 1,
        cueKey: FormCueKey.squatDepthAlmost,
        metric: ratio,
      );
    }
    return FormFeedback(
      rule: rule,
      severity: 2,
      cueKey: FormCueKey.squatDepthHalf,
      metric: ratio,
    );
  }
}

/// Hip-hinge depth. **Reports; never warns.**
///
/// This rule used to be called `deadlift.back_angle` and spoke "Stop — back is
/// rounding under load" at severity 2. It could not have been doing that job:
/// BlazePose has no thoracic or lumbar landmark at any configuration, so
/// shoulder→hip is a single straight segment and spinal curvature is not
/// observable at all. What `_angleDeg(shoulder, hip, knee)` actually measures is
/// **hip flexion** — how far the lifter has hinged.
///
/// Measured, with the old 150° threshold:
///
/// | position | angle | old verdict |
/// |---|---|---|
/// | standing at lockout | 180.0° | neutral |
/// | correct Romanian deadlift, bottom | 82.9° | **"stop, back is rounding"** |
/// | genuinely rounded back, same depth | 77.7° | "stop, back is rounding" |
///
/// 5.2° separates correct technique from the fault, both far below the
/// threshold: the two classes overlap by construction, so no retune separates
/// them, and a correct lifter was being told to stop. Worse than a wrong cue is
/// what a wrong cue teaches — a user who learns the coach cries wolf mutes it,
/// and the next genuine warning is emitted but functionally invisible.
///
/// So this rule now reports hinge depth at severity 0 and speaks no warning.
/// It stays because the metric is real and useful in the rep record; it is
/// honest about what that metric is.
class DeadliftHipHingeClassifier implements FormClassifier {
  @override
  String get rule => 'deadlift.hip_hinge';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final shoulder = frame.landmarks[LandmarkType.leftShoulder];
    final hip = frame.landmarks[LandmarkType.leftHip];
    final knee = frame.landmarks[LandmarkType.leftKnee];
    if (shoulder == null || hip == null || knee == null) return null;
    final torsoAngleDeg = _angleDeg(shoulder, hip, knee);
    // Severity 0 in both arms, deliberately: this rule has nothing it is
    // entitled to warn about. CueGate's minSeverity is 1, so neither cue is
    // ever spoken — they exist for the on-screen card and the rep record.
    return FormFeedback(
      rule: rule,
      severity: 0,
      cueKey: torsoAngleDeg >= 165
          ? FormCueKey.deadliftHipHingeShallow
          : FormCueKey.deadliftHipHingeDeep,
      metric: torsoAngleDeg,
    );
  }
}

/// Push-up scapular stability — flags shoulder collapse / sagging hips.
class PushupAlignmentClassifier implements FormClassifier {
  @override
  String get rule => 'pushup.alignment';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftAnkle,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final shoulder = frame.landmarks[LandmarkType.leftShoulder];
    final hip = frame.landmarks[LandmarkType.leftHip];
    final ankle = frame.landmarks[LandmarkType.leftAnkle];
    if (shoulder == null || hip == null || ankle == null) return null;
    final straightnessAngle = _angleDeg(shoulder, hip, ankle);
    if (straightnessAngle >= 168) {
      return FormFeedback(
        rule: rule,
        severity: 0,
        cueKey: FormCueKey.pushupAlignStraight,
        metric: straightnessAngle,
      );
    }
    if (straightnessAngle >= 155) {
      return FormFeedback(
        rule: rule,
        severity: 1,
        cueKey: FormCueKey.pushupAlignTuck,
        metric: straightnessAngle,
      );
    }
    return FormFeedback(
      rule: rule,
      severity: 2,
      cueKey: FormCueKey.pushupAlignSagging,
      metric: straightnessAngle,
    );
  }
}

double _angleDeg(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final ab = math.atan2(a.y - b.y, a.x - b.x);
  final cb = math.atan2(c.y - b.y, c.x - b.x);
  var deg = (ab - cb) * 180 / math.pi;
  if (deg < 0) deg = -deg;
  if (deg > 180) deg = 360 - deg;
  return deg;
}

/// What a whole classifier set made of one frame.
///
/// Invariant, asserted rather than merely intended: `verdict == ok` exactly when
/// [feedback] is non-empty. Without it a caller could build "scorable but
/// nothing to say" (the UI shows no cue and no hint — the user cannot tell
/// working from broken) or "blocked but here is a fault" (a cue rendered from a
/// frame the gate rejected).
class GatedEvaluation {
  GatedEvaluation({required this.feedback, required this.verdict})
      : assert(
          (verdict == PoseGateVerdict.ok) == feedback.isNotEmpty,
          'verdict must be ok exactly when feedback is non-empty',
        );

  /// Feedback from the rules whose inputs passed [gatePose]. Empty when the
  /// frame was not scorable at all.
  final List<FormFeedback> feedback;

  /// [PoseGateVerdict.ok] when at least one rule could run; otherwise the most
  /// fundamental reason none could, so the UI can say something specific
  /// ("step back" vs "hold still") instead of going quiet.
  final PoseGateVerdict verdict;

  bool get scorable => verdict.isScorable;

  /// Highest-severity feedback, so the user gets one cue rather than three.
  FormFeedback? get worst {
    FormFeedback? worst;
    for (final f in feedback) {
      if (worst == null || f.severity > worst.severity) worst = f;
    }
    return worst;
  }
}

/// Run every classifier that the frame can actually support.
///
/// This replaced a bare loop that called `evaluate` unconditionally. The
/// difference is the whole 2026-07-31 defect: a rule handed invented joints
/// returns confident nonsense, and nothing downstream — not the rep counter,
/// not the voice gate — is in a position to tell that apart from real bad form.
GatedEvaluation evaluateGated(
  Iterable<FormClassifier> classifiers,
  PoseFrame frame, {
  PoseGateConfig config = const PoseGateConfig(),
}) {
  final feedback = <FormFeedback>[];
  PoseGateVerdict? worstBlock;

  for (final c in classifiers) {
    final verdict = gatePose(frame, c.requiredLandmarks, config: config);
    if (!verdict.isScorable) {
      // Lower priority = more fundamental problem. Reporting "no body" beats
      // reporting "held at a strange angle" when both are true. Priority is an
      // explicit field on the enum, not its declaration order, so reordering
      // the values for readability cannot silently change which hint the user
      // is shown.
      if (worstBlock == null || verdict.priority < worstBlock.priority) {
        worstBlock = verdict;
      }
      continue;
    }
    final f = c.evaluate(frame);
    if (f != null) feedback.add(f);
  }

  if (feedback.isNotEmpty) {
    return GatedEvaluation(
      feedback: feedback,
      verdict: PoseGateVerdict.ok,
    );
  }
  return GatedEvaluation(
    feedback: const [],
    verdict: worstBlock ?? PoseGateVerdict.missingJoints,
  );
}

/// Convenience runner: evaluate every registered classifier against the
/// latest frame and return the highest-severity feedback (so we don't
/// drown the user with cues). Gated — see [evaluateGated].
FormFeedback? worstFeedback(
  Iterable<FormClassifier> classifiers,
  PoseFrame frame, {
  PoseGateConfig config = const PoseGateConfig(),
}) =>
    evaluateGated(classifiers, frame, config: config).worst;
