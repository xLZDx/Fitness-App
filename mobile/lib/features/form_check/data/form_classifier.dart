import 'dart:math' as math;

import 'pose_gate.dart';
import 'pose_landmark.dart';
import 'pose_scoring_gate.dart' show chooseScoringSide;

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

  /// The repetition never reached the shape on screen. Emitted by the
  /// silhouette match rather than by a per-frame rule.
  silhouetteMissed,

  /// The trunk folded far forward at depth, which is how a rounded back shows
  /// up from the side (see [SquatBackClassifier]).
  squatBackRounding,

  /// A completed repetition never reached target depth, or a started one came
  /// back up without reaching the counting depth.
  squatDepthShallow,

  /// Sentinel for feedback produced by a data-driven registry rule
  /// (`GenericRuleClassifier`). The wording is NOT a function of this key: it
  /// is [FormFeedback.cueId], resolved by `registryCueText`. Kept last so the
  /// ordinal of every legacy key is unchanged. [formCueText] returns an empty
  /// string for it on purpose -- a registry cue that reached a key-only
  /// resolver is never spoken rather than spoken wrongly.
  registry,
}

/// Result of a single rule running on a single frame.
class FormFeedback {
  const FormFeedback({
    required this.rule,
    required this.severity,
    required this.cueKey,
    this.metric,
    this.cueId,
    this.advisory = false,
    this.repScoped = false,
  });

  /// True for a cue that is already paced by the repetition: the controller
  /// speaks at most one per completed (or rejected) rep. `CueGate` then skips
  /// its stopwatch filters (same-cue repeat window, minimum gap) for it.
  ///
  /// Why: with those filters on top of the per-rep pacing, only the FIRST of
  /// several identical rep-end cues was spoken -- "shallow squat" on reps 2..N
  /// was written on the banner and never said (operator, real phone,
  /// 2026-10-14). Per-frame cues keep the stopwatch filters.
  final bool repScoped;

  /// This feedback, marked as paced by the repetition. See [repScoped].
  FormFeedback asRepScoped() => FormFeedback(
        rule: rule,
        severity: severity,
        cueKey: cueKey,
        metric: metric,
        cueId: cueId,
        advisory: advisory,
        repScoped: true,
      );

  /// Registry cue id (see `registry_cue_text.dart`), set only when [cueKey] is
  /// [FormCueKey.registry]. Null for every legacy rule.
  final String? cueId;

  /// True for beta/advisory registry rows: shown on screen, never spoken, never
  /// counted against a rep. Always severity 0 -- enforced by the producer
  /// (`GenericRuleClassifier`) and by `CueGate.peek`, which refuses to speak an
  /// advisory row whatever its severity says.
  final bool advisory;

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

  /// The joint this rule's measurement is centred on, or null when it has no
  /// single one.
  ///
  /// G8. The design reference marks the offending joint with a pulsing dashed
  /// ring — «сустав с ошибкой — пунктирный круг r=26, `4 6`, пульсация 1.1 s»
  /// (`core/design/reference/full_handoff_v1/README.md`, section 8). Nothing in
  /// [requiredLandmarks] says WHICH of those joints is the offending one: it is
  /// a set, and a rule reading three joints to compute one angle has all three
  /// in it while only one of them is the vertex the angle turns on. That vertex
  /// is the answer, and only the rule knows it.
  ///
  /// Null is honest and is not a gap: a rule comparing two heights has no
  /// vertex, and the ring simply is not drawn.
  LandmarkType? get faultVertex => null;

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

  /// Whether this rule is entitled to fault a repetition at all.
  ///
  /// Required, not defaulted, because the honest answer differs per rule and a
  /// default would let a new rule inherit someone else's. Two of the three
  /// shipped rules answer `false`: they report a measurement at severity 0 and
  /// are explicitly forbidden from raising an alarm, for reasons written at
  /// each of them.
  ///
  /// It exists because "no rule complained" and "no rule was allowed to
  /// complain" are the same silence, and the coach used to render both as a
  /// green *rep clean*. With the silhouette withdrawn in avatar mode and squat
  /// coached only by a severity-0 rule, every repetition came back faultless —
  /// the same defect the operator reported once before as *"все повторения
  /// правильные даже если я неправильно делаю"*. A verdict needs to know
  /// whether anything was in a position to disagree with it.
  bool get canFault;

  FormFeedback? evaluate(PoseFrame frame);
}

/// A classifier that keeps state across frames (hysteresis, streaks) and can
/// be asked to forget it -- at a new set. Separate from [FormClassifier] for the
/// same reason as [FrameSelectingClassifier]: test doubles `implement` that
/// interface and a new abstract member would break every one of them.
abstract interface class ResettableClassifier {
  void reset();
}

/// A classifier that must be gated and evaluated on a frame of its own choosing
/// rather than on the raw one -- today only `GenericRuleClassifier`, which maps
/// the better-visible body side into the left slots so that a side view filmed
/// from the right is judged instead of being refused for a hidden left leg.
///
/// A separate interface rather than a new member of [FormClassifier]: that
/// interface is `implements`-ed by test doubles, and a new abstract member
/// would break every one of them.
abstract interface class FrameSelectingClassifier {
  /// The frame to run the gate on and to hand to [FormClassifier.evaluate].
  /// Must be idempotent: `frameFor(frameFor(f))` behaves like `frameFor(f)`.
  PoseFrame frameFor(PoseFrame raw);
}

/// Squat depth. **Reports; never warns.** Same reason as the hinge rule below,
/// found the same way: on a real device, on a real body.
///
/// The rule compares `hipY` with `kneeY` in image space and calls the rep
/// shallow when the hip does not get under the knee. That comparison is not a
/// property of the squat — it is a property of where the phone is standing.
/// A phone on the floor looking up, a phone at hip height, and a phone at chest
/// height see three different hip-to-knee relationships at the *same* depth,
/// because the projection changes. Nothing in the pipeline knows the camera's
/// pose, so nothing can correct for it.
///
/// Operator report, 2026-07-31, with video: eight consecutive squats scored
/// "0 clean, 8 with errors", the coach saying "half rep, lighten the bar and
/// sit deeper" — verbatim response: *"ниже уже некуда было"*. There was no
/// deeper to go. The phone was low and close; at that angle the hip never
/// crosses the knee in the picture no matter how deep the squat is.
///
/// A threshold cannot fix this, in the same way and for the same reason the
/// deadlift rule could not be retuned: the fault and the correct execution are
/// not separable in the signal available. What separates them is knowing the
/// target pose, which is what the silhouette match is being built to provide.
/// Until it exists this rule contributes its metric to the rep record and says
/// nothing.
class SquatDepthClassifier
    implements FormClassifier, FrameSelectingClassifier {
  @override
  String get rule => 'squat.depth';

  /// One side only, in the left slots (2026-10-14). Seen side-on, the far hip and
  /// knee are hidden behind the body and the detector only infers them, so
  /// requiring both sides refused the frame -- and with it the rep count -- for
  /// the very view the coach asks for. [frameFor] maps the better-visible side
  /// into these slots.
  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
      };

  @override
  PoseFrame frameFor(PoseFrame raw) =>
      chooseScoringSide(raw, requiredLandmarks).frame;

  /// False: every arm of [evaluate] returns severity 0, deliberately.
  @override
  bool get canFault => false;

  /// None. This rule compares two heights rather than turning an angle on a
  /// joint, so there is no vertex to ring — and it cannot fault anyway.
  @override
  LandmarkType? get faultVertex => null;

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final hip = frame.landmarks[LandmarkType.leftHip];
    final knee = frame.landmarks[LandmarkType.leftKnee];
    if (hip == null || knee == null) return null;
    // Image y grows downward; "below knee" means hipY > kneeY.
    final ratio = hip.y - knee.y;
    // Severity 0 in every arm, deliberately. The thresholds below still choose
    // WHICH observation to record, but none of them is entitled to raise an
    // alarm, because the quantity they compare is camera-dependent.
    return FormFeedback(
      rule: rule,
      severity: 0,
      cueKey: ratio >= 0
          ? FormCueKey.squatDepthGood
          : ratio > -0.04
              ? FormCueKey.squatDepthAlmost
              : FormCueKey.squatDepthHalf,
      metric: ratio,
    );
  }
}

/// Squat back position: flags a trunk folded far forward at depth, the
/// side-view signature of a rounded back.
///
/// **What this does and does not measure.** BlazePose has no spinal landmark
/// (see [DeadliftHipHingeClassifier]), so curvature itself is not observable.
/// The shoulder-to-hip line IS, and its angle off vertical is stable under
/// camera height and distance because both points sit in one image plane. A
/// sustained lean beyond [leanEnterDeg] while the hips are low is the
/// observable proxy for "chest dropped, back rounding" and is named honestly
/// in the explanation text. Front-on, a forward lean runs toward the camera
/// and shows no sideways offset, so this rule stays silent there rather than
/// guessing.
///
/// Thresholds are `PRODUCT_HEURISTIC`: a normal back squat bottoms out at
/// roughly 30-55 degrees off vertical, so the rule starts at 60 and releases at
/// 50. It only runs once the hip is within [minDepthRatio] of the knee in torso
/// lengths (not while standing or bending to reach the phone), and it needs
/// [minFaultFrames] consecutive bad frames to fire so one jittery frame cannot
/// speak (hysteresis against flicker).
class SquatBackClassifier
    implements FormClassifier, FrameSelectingClassifier, ResettableClassifier {
  static const leanEnterDeg = 60.0;
  static const leanExitDeg = 50.0;
  static const minFaultFrames = 5;

  /// (hipY - kneeY) / torso at or above which the lifter counts as squatting.
  /// -0.5 is a thigh about 25 degrees above horizontal for average proportions.
  static const minDepthRatio = -0.5;

  /// Longest gap between two evaluated frames over which the streak survives.
  /// `evaluateGated` simply does not call [evaluate] on frames it drops
  /// (unscorable, low confidence), so "consecutive" is checked on the frame
  /// clock: 3 bad frames, a dropout, then 2 bad frames is NOT 5 in a row.
  static const maxFrameGapMs = 250;

  int _badFrames = 0;
  bool _faulting = false;
  int? _lastTimestampMs;

  /// Forget the streak and the latched fault (new set).
  @override
  void reset() {
    _badFrames = 0;
    _faulting = false;
    _lastTimestampMs = null;
  }

  @override
  String get rule => 'squat.back';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
      };

  @override
  bool get canFault => true;

  /// The hip: the trunk-to-thigh angle turns on it.
  @override
  LandmarkType? get faultVertex => LandmarkType.leftHip;

  /// Side-on, the better-visible side is the one that is judged, mapped into the
  /// left slots (same helper the rep-shape scoring uses).
  @override
  PoseFrame frameFor(PoseFrame raw) =>
      chooseScoringSide(raw, requiredLandmarks).frame;

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final last = _lastTimestampMs;
    if (last != null && frame.timestampMs - last > maxFrameGapMs) _reset();
    _lastTimestampMs = frame.timestampMs;
    final shoulder = frame.landmarks[LandmarkType.leftShoulder];
    final hip = frame.landmarks[LandmarkType.leftHip];
    final knee = frame.landmarks[LandmarkType.leftKnee];
    if (shoulder == null || hip == null || knee == null) {
      _reset();
      return null;
    }
    final torso = math.sqrt(math.pow(shoulder.x - hip.x, 2) +
        math.pow(shoulder.y - hip.y, 2));
    if (torso < 1e-6) {
      _reset();
      return null;
    }
    if ((hip.y - knee.y) / torso < minDepthRatio) {
      _reset();
      return null;
    }
    final leanDeg = math.atan2((shoulder.x - hip.x).abs(),
            (hip.y - shoulder.y).abs()) *
        180 /
        math.pi;
    if (_faulting) {
      if (leanDeg < leanExitDeg) _reset();
    } else if (leanDeg >= leanEnterDeg) {
      if (++_badFrames >= minFaultFrames) _faulting = true;
    } else {
      _badFrames = 0;
    }
    if (!_faulting) return null;
    return FormFeedback(
      rule: rule,
      severity: 2,
      cueKey: FormCueKey.squatBackRounding,
      metric: leanDeg,
    );
  }

  void _reset() {
    _badFrames = 0;
    _faulting = false;
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

  /// False: this rule reports hinge depth and is entitled to warn about
  /// nothing, for the reason set out above.
  @override
  bool get canFault => false;

  /// The hip: `_angleDeg(shoulder, hip, knee)` turns on it. Recorded for
  /// completeness — this rule never faults, so the ring is unreachable from it.
  @override
  LandmarkType? get faultVertex => LandmarkType.leftHip;

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

  /// True, and the only rule that answers so: it reaches severity 2 and is
  /// therefore the one shipped rule that can both fail a repetition and be
  /// spoken aloud.
  @override
  bool get canFault => true;

  /// The hip: `_angleDeg(shoulder, hip, ankle)` turns on it, and it is where a
  /// sag or a pike actually happens. The one reachable value in the app.
  @override
  LandmarkType? get faultVertex => LandmarkType.leftHip;

  /// Shoulder-hip-ankle angle at or above which the body is one line.
  ///
  /// G7 named these. They were bare literals inside [evaluate], which was fine
  /// while nothing but the rule itself needed them and stopped being fine the
  /// moment the screen started explaining WHAT the lifter is being measured
  /// against: a target retyped into a translated sentence is a target that
  /// drifts from the rule silently, and a wrong number in an explanation is
  /// worse than no explanation.
  static const straightMinDeg = 168.0;

  /// Below this the hips are sagging rather than merely untucked.
  static const tuckMinDeg = 155.0;

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    final shoulder = frame.landmarks[LandmarkType.leftShoulder];
    final hip = frame.landmarks[LandmarkType.leftHip];
    final ankle = frame.landmarks[LandmarkType.leftAnkle];
    if (shoulder == null || hip == null || ankle == null) return null;
    final straightnessAngle = _angleDeg(shoulder, hip, ankle);
    if (straightnessAngle >= straightMinDeg) {
      return FormFeedback(
        rule: rule,
        severity: 0,
        cueKey: FormCueKey.pushupAlignStraight,
        metric: straightnessAngle,
      );
    }
    if (straightnessAngle >= tuckMinDeg) {
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
/// Invariant, asserted rather than merely intended: feedback only ever comes
/// from a frame the gate accepted. A cue rendered from a rejected frame is a
/// confident statement about a body the detector could not see.
///
/// The converse is NOT an invariant, and asserting it was a mistake worth
/// recording. "Scorable with nothing to say" is the normal state of a rule set
/// that only speaks up when something is wrong, and pinning `ok == hasFeedback`
/// forced the opposite: every quiet frame had to be labelled unreadable, which
/// the controller then dropped before the rep counter. The screen would have
/// blamed the user's framing for a count that had stopped because their form
/// was fine. The distinction the old comment worried about — working versus
/// broken — is the UI's to draw, and it draws it from the verdict plus the rep
/// state, not from the presence of a complaint.
class GatedEvaluation {
  GatedEvaluation({required this.feedback, required this.verdict})
      : assert(
          feedback.isEmpty || verdict == PoseGateVerdict.ok,
          'feedback may only come from a frame the gate accepted',
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
  var somethingScoredIt = false;

  for (final c in classifiers) {
    final view = c is FrameSelectingClassifier
        ? (c as FrameSelectingClassifier).frameFor(frame)
        : frame;
    final verdict = gatePose(view, c.requiredLandmarks, config: config);
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
    somethingScoredIt = true;
    final f = c.evaluate(view);
    if (f != null) feedback.add(f);
  }

  // No rules at all. There is no joint list to gate against, but the
  // frame-level checks — the unit contract and torso plausibility — read the
  // whole frame and still apply, and the caller still has to be told whether
  // this frame can be trusted. Answering "missing joints" here would silently
  // stop rep counting for any movement that ships without per-frame rules,
  // which is the direction the coach is moving: the silhouette judges the rep,
  // not a running commentary on every frame.
  if (classifiers.isEmpty) {
    return GatedEvaluation(
      feedback: const [],
      verdict: gatePose(frame, const <LandmarkType>{}, config: config),
    );
  }

  // A rule ran and had nothing to say. That is a READABLE frame with no fault,
  // and it used to be reported as `missingJoints` — the same answer as "there
  // is no body in the picture". The controller drops every unscorable frame
  // before the rep counter sees it, so a classifier that stays quiet on a good
  // repetition would stop the count dead, with the screen blaming the user's
  // framing. Every shipped rule currently returns a severity-0 observation on
  // every frame, which is the only reason this has not been visible.
  if (somethingScoredIt) {
    return GatedEvaluation(feedback: feedback, verdict: PoseGateVerdict.ok);
  }

  // Unreachable: a non-empty rule set in which nothing scored means every rule
  // was blocked, and each of those assigned `worstBlock`.
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
