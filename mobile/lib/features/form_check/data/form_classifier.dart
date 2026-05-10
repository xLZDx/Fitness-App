import 'dart:math' as math;

import 'pose_landmark.dart';

/// Result of a single rule running on a single frame.
class FormFeedback {
  const FormFeedback({
    required this.rule,
    required this.severity,
    required this.cue,
    this.metric,
  });

  /// Stable id (e.g. "squat.depth", "deadlift.back_angle").
  final String rule;

  /// 0 = good, 1 = nudge ("just a bit deeper"), 2 = stop ("save your back").
  final int severity;

  /// One-line spoken cue. Coaches in voice-only mode read this verbatim.
  final String cue;

  /// Optional numeric metric the rule reasoned over (angle in degrees,
  /// ratio, etc.) — surfaced in the post-set summary.
  final double? metric;
}

/// Pure rule-based classifier. Keeps the runtime light enough to run on
/// commodity Android (the marketing line vs Tempo's TrueDepth-only Move).
abstract class FormClassifier {
  String get rule;
  FormFeedback? evaluate(PoseFrame frame);
}

/// Squat depth — flags partial reps when hip never drops below knee.
class SquatDepthClassifier implements FormClassifier {
  @override
  String get rule => 'squat.depth';

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
        cue: 'Good depth. Drive up.',
        metric: ratio,
      );
    }
    if (ratio > -0.04) {
      return FormFeedback(
        rule: rule,
        severity: 1,
        cue: 'Almost there — sink a touch lower.',
        metric: ratio,
      );
    }
    return FormFeedback(
      rule: rule,
      severity: 2,
      cue: 'Half-rep. Lighten the bar and hit depth.',
      metric: ratio,
    );
  }
}

/// Deadlift back angle — flags excessive lumbar flexion (rounding).
class DeadliftBackAngleClassifier implements FormClassifier {
  @override
  String get rule => 'deadlift.back_angle';

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final shoulder = frame.landmarks[LandmarkType.leftShoulder];
    final hip = frame.landmarks[LandmarkType.leftHip];
    final knee = frame.landmarks[LandmarkType.leftKnee];
    if (shoulder == null || hip == null || knee == null) return null;
    final torsoAngleDeg = _angleDeg(shoulder, hip, knee);
    if (torsoAngleDeg >= 165) {
      return FormFeedback(
        rule: rule,
        severity: 0,
        cue: 'Spine looks neutral.',
        metric: torsoAngleDeg,
      );
    }
    if (torsoAngleDeg >= 150) {
      return FormFeedback(
        rule: rule,
        severity: 1,
        cue: 'Tighten your back — chest up.',
        metric: torsoAngleDeg,
      );
    }
    return FormFeedback(
      rule: rule,
      severity: 2,
      cue: 'Stop — back is rounding under load.',
      metric: torsoAngleDeg,
    );
  }
}

/// Push-up scapular stability — flags shoulder collapse / sagging hips.
class PushupAlignmentClassifier implements FormClassifier {
  @override
  String get rule => 'pushup.alignment';

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
        cue: 'Plank line is straight.',
        metric: straightnessAngle,
      );
    }
    if (straightnessAngle >= 155) {
      return FormFeedback(
        rule: rule,
        severity: 1,
        cue: 'Tuck your hips — keep one straight line.',
        metric: straightnessAngle,
      );
    }
    return FormFeedback(
      rule: rule,
      severity: 2,
      cue: 'Hips are sagging. Brace your core.',
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

/// Convenience runner: evaluate every registered classifier against the
/// latest frame and return the highest-severity feedback (so we don't
/// drown the user with cues).
FormFeedback? worstFeedback(
  Iterable<FormClassifier> classifiers,
  PoseFrame frame,
) {
  FormFeedback? worst;
  for (final c in classifiers) {
    final f = c.evaluate(frame);
    if (f == null) continue;
    if (worst == null || f.severity > worst.severity) {
      worst = f;
    }
  }
  return worst;
}
