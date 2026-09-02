// GF.1 — Form coach rep counting.
//
// Turns the per-frame pose stream into a rep count. Pure and synchronous:
// no camera, no timers, no wall clock — every decision is a function of the
// scalar signal plus the timestamp carried on the [PoseFrame]. That is what
// makes a 40-rep set reproducible in a unit test.
//
// The hard problem is not "detect a squat", it is "do not count noise as a
// rep". A landmark that jitters by a percent of frame height around a single
// threshold would flip a naive comparator dozens of times per second. Three
// defences, all configurable in [RepCounterConfig]:
//
//   1. Hysteresis — entering and leaving a phase use *different* thresholds,
//      so a signal has to travel a real distance to advance the machine.
//   2. A minimum rep duration — a lap of the whole phase ladder faster than a
//      human can move is discarded, not counted.
//   3. A likelihood floor — frames whose joints the detector is unsure about
//      are dropped before they reach the machine at all.

import 'form_classifier.dart';
import 'pose_landmark.dart';

/// Where the lifter is in the movement.
///
/// A rep is one full lap: [top] -> [descending] -> [bottom] -> [ascending]
/// -> [top]. Anything that does not complete the lap is not a rep.
enum RepPhase { top, descending, bottom, ascending }

/// What [RepCounter.update] is reporting.
enum RepEventKind {
  /// The machine advanced to a new [RepPhase]. No rep was counted.
  phaseChanged,

  /// A full lap completed and passed the noise filters. [RepEvent.rep] holds
  /// the quality record.
  repCompleted,

  /// A lap was started but thrown away. See [RepEvent.rejectReason].
  repRejected,
}

/// Why an in-flight rep was discarded.
enum RepRejectReason {
  /// Returned to the top without ever reaching depth — a partial rep.
  incomplete,

  /// Completed the lap faster than [RepCounterConfig.minRepDurationMs].
  /// Bodies do not move that fast; landmark glitches do.
  tooFast,

  /// Still in flight after [RepCounterConfig.maxRepDurationMs] — the lifter
  /// stopped part-way through and the machine was left holding a repetition
  /// that was never going to end.
  ///
  /// Measured on an S23 on 2026-09-02: the last "repetition" of a set ran to
  /// 980 observed frames, roughly 33 seconds, against a set whose real reps
  /// averaged 1.9s of tempo. It completed, was scored against the target it
  /// had never been in (peak match 0.072), and told the lifter they had not
  /// reached the shape — of a repetition they had stopped performing half a
  /// minute earlier.
  abandoned,
}

/// Extracts the single scalar the state machine tracks, or null when the
/// frame is unusable (joints missing, or below [minLikelihood]).
///
/// Injectable so the same machine can drive a press or a curl later — only
/// the signal changes, the noise handling does not.
typedef RepSignalExtractor = double? Function(
  PoseFrame frame,
  double minLikelihood,
);

/// Squat depth signal: mean hip y minus mean knee y, in the same units and
/// the same sign convention as [SquatDepthClassifier].
///
/// Image y grows downward, so the value *rises* as the lifter descends:
/// roughly -0.20 standing tall, ~0.00 at or below parallel.
///
/// Returns null unless all four joints are present and each clears
/// [minLikelihood] — a hip the detector is guessing at is worse than no hip,
/// because it looks like real movement.
double? squatDepthSignal(PoseFrame frame, double minLikelihood) {
  final lHip = frame.landmarks[LandmarkType.leftHip];
  final rHip = frame.landmarks[LandmarkType.rightHip];
  final lKnee = frame.landmarks[LandmarkType.leftKnee];
  final rKnee = frame.landmarks[LandmarkType.rightKnee];
  if (lHip == null || rHip == null || lKnee == null || rKnee == null) {
    return null;
  }
  if (lHip.likelihood < minLikelihood ||
      rHip.likelihood < minLikelihood ||
      lKnee.likelihood < minLikelihood ||
      rKnee.likelihood < minLikelihood) {
    return null;
  }
  final hipY = (lHip.y + rHip.y) / 2;
  final kneeY = (lKnee.y + rKnee.y) / 2;
  return hipY - kneeY;
}

/// One frame's depth measured down each leg separately.
///
/// The whole-body [squatDepthSignal] averages the two hips and the two knees,
/// which is exactly the right thing for counting a rep and exactly the wrong
/// thing for noticing that one leg is doing more of the work than the other:
/// the average is identical whether the lifter is square or listing.
class SideDepths {
  const SideDepths({required this.left, required this.right});

  /// Left hip y minus left knee y — same units and sign convention as
  /// [squatDepthSignal], so it rises as that side descends.
  final double left;

  final double right;
}

/// Extracts per-side depth, or null when the frame cannot support the claim.
typedef RepSideSignalExtractor = SideDepths? Function(
  PoseFrame frame,
  double minLikelihood,
);

/// The default: this movement has no per-side reading defined.
SideDepths? _noSideReading(PoseFrame frame, double minLikelihood) => null;

/// Per-side squat depth, or null unless BOTH sides were genuinely seen.
///
/// The confidence bar here is deliberately HIGHER than the one the rep counter
/// runs on, and that is the whole point of the function. The coach asks the
/// lifter to stand side-on; from there the far hip and the far knee are behind
/// the body, and BlazePose does not report them as missing — it infers them,
/// and an inferred joint sits wherever the model's prior says a body of that
/// pose keeps it. Compare an observed leg against an inferred one and the
/// answer is not a measurement of the lifter, it is a measurement of the
/// model. Returning null is the honest outcome, and the panel renders it as
/// «—» rather than as a reassuring 50/50.
SideDepths? squatSideDepths(PoseFrame frame, double minLikelihood) {
  final lHip = frame.landmarks[LandmarkType.leftHip];
  final rHip = frame.landmarks[LandmarkType.rightHip];
  final lKnee = frame.landmarks[LandmarkType.leftKnee];
  final rKnee = frame.landmarks[LandmarkType.rightKnee];
  if (lHip == null || rHip == null || lKnee == null || rKnee == null) {
    return null;
  }
  for (final j in [lHip, rHip, lKnee, rKnee]) {
    if (j.likelihood < minLikelihood) return null;
  }
  return SideDepths(left: lHip.y - lKnee.y, right: rHip.y - rKnee.y);
}

/// Tuning for [RepCounter]. Defaults are for a squat read through
/// [squatDepthSignal].
class RepCounterConfig {
  const RepCounterConfig({
    this.topEnter = -0.15,
    this.topExit = -0.11,
    this.bottomExit = -0.08,
    this.bottomEnter = -0.04,
    this.minRepDurationMs = 600,
    this.maxRepDurationMs = 20000,
    this.minLikelihood = 0.5,
    this.minObservedRatio = 0.5,
    this.minSideLikelihood = 0.7,
  });

  /// Signal at or below this counts as standing at the top.
  ///
  /// -0.15 means the hip sits ~15% of frame height above the knee, which is
  /// an upright stance for a full-body framing.
  final double topEnter;

  /// Signal must rise above this to leave the top and start descending.
  ///
  /// The 0.04 gap to [topEnter] is the top hysteresis band — roughly 4% of
  /// frame height, several times ML Kit's jitter on a stationary subject, so
  /// a shaking landmark cannot rattle between top and descending.
  final double topExit;

  /// Signal must fall below this to leave the bottom and start ascending.
  /// Mirrors [topExit]: 0.04 below [bottomEnter].
  final double bottomExit;

  /// Signal must reach this to register as having hit depth.
  ///
  /// -0.04 is deliberately the same boundary [SquatDepthClassifier] uses
  /// between "almost there" and "half-rep", so the counter and the coach
  /// agree on what depth means rather than contradicting each other on
  /// screen.
  final double bottomEnter;

  /// Floor on a full lap. Under this, the lap is [RepRejectReason.tooFast]
  /// and discarded.
  ///
  /// 600ms sits below any real squat (competition speed is ~0.8-1.0s) so it
  /// never rejects a genuine rep, but above the duration of a landmark
  /// glitch, which is what it is there to catch.
  final int minRepDurationMs;

  /// Ceiling on a lap. Over this, the lap is [RepRejectReason.abandoned], the
  /// machine returns to the top and has to be re-armed.
  ///
  /// The floor above exists to reject something too fast to be a body. This
  /// exists to reject something too slow to be a repetition — a lifter who
  /// stopped, sat down, or walked out of the movement without walking out of
  /// the frame. Without it the machine holds the rep open indefinitely and
  /// eventually completes it, so the set summary gains a repetition nobody
  /// performed and the coach faults the lifter for it.
  ///
  /// 20 seconds is a `PRODUCT_HEURISTIC`, and deliberately far above any real
  /// repetition rather than close to one: the tempo readout on the S23 set
  /// this was measured from averaged 1.9s, and even a 5-3-5-3 tempo protocol
  /// with a long pause comes to about 16s. The abandoned rep it was written
  /// for ran to 33s. Sitting at ten times a normal repetition means a slow
  /// lifter is never the one this catches.
  final int maxRepDurationMs;

  /// Per-joint confidence floor. ML Kit's likelihood below ~0.5 usually
  /// means the joint is occluded and its position is being inferred.
  final double minLikelihood;

  /// Confidence floor for the per-side symmetry reading, higher than
  /// [minLikelihood] on purpose.
  ///
  /// 0.5 is the bar for "this joint is worth counting a rep on", where an
  /// averaged pair absorbs a soft reading on one side. Symmetry is the
  /// DIFFERENCE between the two sides, so a soft reading is the entire signal
  /// rather than half of it, and the coach's own «встаньте боком» instruction
  /// puts one whole leg behind the other. 0.7 is a `PRODUCT_HEURISTIC`: above
  /// the band where ML Kit is visibly inferring an occluded joint, below where
  /// it would refuse every real front-on rep. See [squatSideDepths].
  final double minSideLikelihood;

  /// How much of a repetition has to have been actually visible before its
  /// quality record is allowed to say anything.
  ///
  /// Frames whose joints fall under [minLikelihood] yield no signal, so no
  /// rule runs on them and nothing can be recorded against the rep. With the
  /// old two-way split that silence was indistinguishable from a rep nobody
  /// complained about, and a lifter who walked half out of frame was told
  /// their form was clean. 0.5 is a `PRODUCT_HEURISTIC`: below half the frames
  /// seen, the honest answer is that the app did not watch the rep.
  final double minObservedRatio;

  /// The thresholds must form a strictly increasing ladder, otherwise the
  /// hysteresis bands overlap and the machine can skip a phase.
  bool get isOrdered =>
      topEnter < topExit &&
      topExit < bottomExit &&
      bottomExit < bottomEnter &&
      // A window, not a point: with the ceiling at or below the floor every
      // lap is rejected by one bound or the other and no repetition can ever
      // be counted.
      minRepDurationMs < maxRepDurationMs;
}

/// Quality record for one completed rep.
class RepQuality {
  const RepQuality({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.peakSignal,
    required this.severityByRule,
    this.observedFrames = 0,
    this.missedFrames = 0,
    this.bottomHoldMs = 0,
    this.peakSides,
  });

  /// 1-based position in the set.
  final int index;

  final int startMs;
  final int endMs;

  /// Deepest point reached, in signal units.
  final double peakSignal;

  /// Worst severity each rule reached at any point during this rep.
  final Map<String, int> severityByRule;

  /// Frames during this rep that produced a usable signal.
  final int observedFrames;

  /// Frames during this rep that did not: a joint missing, or below
  /// [RepCounterConfig.minLikelihood]. No rule ran on these.
  final int missedFrames;

  /// How long the lifter spent at the bottom of this repetition.
  ///
  /// Wall time between reaching depth and starting back up, summed over every
  /// visit — a lifter who sinks back down mid-ascent is still in the same rep,
  /// and their hold is the total, not the last leg of it.
  final int bottomHoldMs;

  /// Depth down each leg at the deepest frame of this rep, or null when that
  /// frame could not support the claim (see [squatSideDepths]).
  ///
  /// Taken at the PEAK rather than averaged over the rep: the deepest point is
  /// where a side that is not pulling its weight shows the difference, and an
  /// average over the descent dilutes it with the frames where both sides are
  /// near-identical by definition.
  final SideDepths? peakSides;

  /// Share of this rep the app could actually see, or null when the rep
  /// predates frame accounting (a hand-built [RepQuality] with both counts at
  /// their defaults).
  double? get observedRatio {
    final total = observedFrames + missedFrames;
    if (total == 0) return null;
    return observedFrames / total;
  }

  /// Whether enough of the rep was visible for its silence to mean anything.
  ///
  /// True for a record with no frame accounting at all, because the alternative
  /// is retroactively marking every rep from an older session unobserved.
  bool isObservedAt(double minRatio) {
    final ratio = observedRatio;
    return ratio == null || ratio >= minRatio;
  }

  int get durationMs => endMs - startMs;

  /// Worst severity from any rule during the rep. 0 when nothing fired.
  int get maxSeverity {
    var worst = 0;
    for (final s in severityByRule.values) {
      if (s > worst) worst = s;
    }
    return worst;
  }

  /// A rep nothing complained about.
  ///
  /// Silence only. Whether the app was in a position to complain is
  /// [isObservedAt] — read [RepCounter.cleanReps], which asks both.
  bool get isClean => maxSeverity == 0;

  /// Rules that fired a nudge or a stop, for the post-set summary.
  List<String> get offendingRules => severityByRule.entries
      .where((e) => e.value > 0)
      .map((e) => e.key)
      .toList(growable: false);
}

/// What [RepCounter.update] returns when something happened. Null means the
/// frame moved nothing — which is most frames.
class RepEvent {
  const RepEvent({
    required this.kind,
    required this.phase,
    required this.repCount,
    this.rep,
    this.rejectReason,
  });

  final RepEventKind kind;

  /// Phase *after* applying this frame.
  final RepPhase phase;

  /// Running count of accepted reps.
  final int repCount;

  /// Non-null only when [kind] is [RepEventKind.repCompleted].
  final RepQuality? rep;

  /// Non-null only when [kind] is [RepEventKind.repRejected].
  final RepRejectReason? rejectReason;
}

/// Phase-tracking rep counter. Feed it every frame; it tells you when
/// something changed.
///
/// ```dart
/// final counter = RepCounter();
/// for (final frame in frames) {
///   final event = counter.update(frame, feedback: rules.map(...));
///   if (event?.kind == RepEventKind.repCompleted) { ... }
/// }
/// ```
class RepCounter {
  RepCounter({
    this.config = const RepCounterConfig(),
    RepSignalExtractor? signal,
    RepSideSignalExtractor? sideSignal,
  })  : _signal = signal ?? squatDepthSignal,
        // No reading unless a caller names an extractor for THIS movement.
        // Defaulting to the squat's would have every movement report a hip-vs-
        // knee split, including the ones where the legs are not what is moving.
        _sideSignal = sideSignal ?? _noSideReading {
    if (!config.isOrdered) {
      throw ArgumentError.value(
        config,
        'config',
        'thresholds must satisfy topEnter < topExit < bottomExit < '
            'bottomEnter; overlapping hysteresis bands let the machine skip '
            'a phase',
      );
    }
  }

  final RepCounterConfig config;
  final RepSignalExtractor _signal;
  final RepSideSignalExtractor _sideSignal;

  final List<RepQuality> _reps = <RepQuality>[];
  final Map<String, int> _severity = <String, int>{};

  RepPhase _phase = RepPhase.top;
  bool _armed = false;
  int _repStartMs = 0;
  double _peakSignal = double.negativeInfinity;
  double? _lastSignal;
  int _observedFrames = 0;
  int _missedFrames = 0;
  int _bottomHoldMs = 0;
  int? _bottomEnteredMs;
  SideDepths? _peakSides;

  /// Accepted reps so far.
  int get repCount => _reps.length;

  RepPhase get phase => _phase;

  /// Quality record per accepted rep, oldest first.
  List<RepQuality> get reps => List.unmodifiable(_reps);

  /// Reps that were watched and drew no complaint.
  ///
  /// Was `_reps.where((r) => r.isClean)`, which counted a rep the app never
  /// saw as a good one: unusable frames return early from [update], so no rule
  /// runs, no severity is recorded, and `maxSeverity == 0` — the same value a
  /// clean rep produces. [unobservedReps] is now its own outcome.
  int get cleanReps => _reps
      .where((r) => r.isObservedAt(config.minObservedRatio) && r.isClean)
      .length;

  /// Reps that were watched and did draw a complaint.
  int get sloppyReps => _reps
      .where((r) => r.isObservedAt(config.minObservedRatio) && !r.isClean)
      .length;

  /// Reps that finished with too little of them visible to judge.
  ///
  /// `cleanReps + sloppyReps + unobservedReps == repCount`, always.
  int get unobservedReps =>
      _reps.where((r) => !r.isObservedAt(config.minObservedRatio)).length;

  /// Last usable signal value, or null if no frame has been accepted yet.
  /// Exposed for debugging and threshold tuning.
  double? get lastSignal => _lastSignal;

  /// True once a frame has been seen with the lifter standing at the top.
  ///
  /// Until then the machine will not start a rep. Opening the camera
  /// mid-squat and standing up is not a rep, and counting it would be the
  /// first thing a user noticed.
  bool get isArmed => _armed;

  /// Discards the in-flight repetition if it has run past
  /// [RepCounterConfig.maxRepDurationMs], WITHOUT requiring a scorable frame.
  ///
  /// **Why this is not simply inline in [update].** Production drops an
  /// unscorable frame — the lifter stepped out of shot, or the detector lost
  /// them — before it ever reaches [update] at all
  /// (`RepSessionController._onFrame`'s own comment: "An unscorable frame is
  /// dropped entirely — it must not reach the rep counter"). A lifter who
  /// disappears mid-repetition produces exactly that kind of frame, so an
  /// expiry check reachable only through [update] would never see the one
  /// case it exists for: the counter would sit in `descending` or `bottom`
  /// until a scorable frame happened to arrive again, which might be never.
  /// GPT-PM, reviewing the first version of this gate: caught live, not
  /// theoretical.
  ///
  /// So the clock runs on the frame's OWN timestamp, independent of whether
  /// the frame carries a usable pose, and callers are expected to feed it
  /// every frame — [update] does, for the case a caller reads no other frames
  /// at all, and `RepSessionController._onFrame` calls it a second time,
  /// directly, on the frames [update] never sees.
  ///
  /// Idempotent: once the lap is discarded [_phase] is back at
  /// [RepPhase.top], so a second call with a later timestamp does nothing.
  RepEvent? checkExpiry(int timestampMs) {
    // Disarmed as well as discarded, deliberately. `_discard` returns the
    // machine to the top phase while the SIGNAL may still be deep, and at the
    // top a signal above `topExit` opens a new rep on the very next frame — so
    // without this the abandoned rep would simply restart and be abandoned
    // again every 20 seconds. Re-arming means standing up first, which is the
    // same bar `isArmed` already sets for opening the camera mid-squat.
    if (_phase != RepPhase.top &&
        timestampMs - _repStartMs > config.maxRepDurationMs) {
      _armed = false;
      return _discard(RepRejectReason.abandoned);
    }
    return null;
  }

  /// Pushes the abandonment deadline out by [pausedMs] — time the set spent
  /// paused, measured on the frame clock, must not count against a
  /// repetition that was left open across it. A no-op with no repetition in
  /// flight: [_repStartMs] gets overwritten the next time one opens, so
  /// extending it while at [RepPhase.top] has nothing left to affect.
  ///
  /// Gating [checkExpiry] on "counting is live" only stops the check from
  /// firing WHILE paused — the camera keeps delivering frames through a
  /// pause by design, so the timestamp on the first frame after resume has
  /// already advanced by the whole paused span, and comparing it straight
  /// against a `_repStartMs` stamped before the pause abandons the rep the
  /// instant the set resumes. This is the other half of that fix: the
  /// caller measures the paused span on the same frame clock and shifts the
  /// deadline to match, so paused time is excluded rather than merely
  /// deferred. GPT-PM, round 2: the gating alone still failed
  /// `rep_expiry_pause_test.dart`'s own positive control.
  void extendDeadline(int pausedMs) {
    _repStartMs += pausedMs;
  }

  /// Feed one frame. [feedback] is whatever the rule classifiers said about
  /// this frame; it is folded into the in-flight rep's quality record.
  ///
  /// Returns null when nothing changed.
  RepEvent? update(
    PoseFrame frame, {
    Iterable<FormFeedback> feedback = const <FormFeedback>[],
  }) {
    // Before signal extraction, which is one of the two places this age check
    // has to run — see [checkExpiry]'s own doc for the other.
    final expired = checkExpiry(frame.timestampMs);
    if (expired != null) return expired;

    final s = _signal(frame, config.minLikelihood);
    // Unusable frame: missing or low-confidence joints. Change nothing —
    // holding the previous phase is strictly better than guessing. It is
    // counted, though: a rep made mostly of these frames was not observed,
    // and used to be reported as clean because nothing had complained.
    if (s == null) {
      if (_phase != RepPhase.top) _missedFrames++;
      return null;
    }
    _lastSignal = s;

    if (!_armed) {
      if (s <= config.topEnter) _armed = true;
      return null;
    }

    // Accumulate quality for a rep already in flight. A rep that starts on
    // this very frame is accumulated by _beginRep instead, so nothing is
    // double-counted and nothing is missed.
    if (_phase != RepPhase.top) {
      _observedFrames++;
      _accumulate(feedback);
      if (s > _peakSignal) {
        _peakSignal = s;
        // Read on the peak frame, and allowed to come back null there: a rep
        // whose deepest moment was the one the far leg disappeared for has no
        // symmetry reading, and the previous frame's is a different moment of
        // a different depth.
        _peakSides = _sideSignal(frame, config.minSideLikelihood);
      }
    }

    switch (_phase) {
      case RepPhase.top:
        if (s > config.topExit) {
          _beginRep(frame.timestampMs, s, feedback);
          return _phaseEvent();
        }
        return null;

      case RepPhase.descending:
        if (s >= config.bottomEnter) {
          _phase = RepPhase.bottom;
          _bottomEnteredMs = frame.timestampMs;
          return _phaseEvent();
        }
        if (s <= config.topEnter) {
          // Came back up without hitting depth: a partial rep.
          return _discard(RepRejectReason.incomplete);
        }
        return null;

      case RepPhase.bottom:
        if (s <= config.bottomExit) {
          _phase = RepPhase.ascending;
          _closeBottomVisit(frame.timestampMs);
          return _phaseEvent();
        }
        return null;

      case RepPhase.ascending:
        if (s <= config.topEnter) {
          return _complete(frame.timestampMs);
        }
        if (s >= config.bottomEnter) {
          // Sank back down mid-ascent — still the same rep, not a new one, so
          // this opens a SECOND visit to the bottom whose time is added to the
          // first rather than replacing it.
          _phase = RepPhase.bottom;
          _bottomEnteredMs = frame.timestampMs;
          return _phaseEvent();
        }
        return null;
    }
  }

  /// Clear the count and the quality log — a new set.
  void reset() {
    _reps.clear();
    _clearRepState();
    _phase = RepPhase.top;
    _armed = false;
    _lastSignal = null;
  }

  void _beginRep(int timestampMs, double signal, Iterable<FormFeedback> fb) {
    _phase = RepPhase.descending;
    _repStartMs = timestampMs;
    _peakSignal = signal;
    _severity.clear();
    _observedFrames = 1;
    _missedFrames = 0;
    _bottomHoldMs = 0;
    _bottomEnteredMs = null;
    _peakSides = null;
    _accumulate(fb);
  }

  void _accumulate(Iterable<FormFeedback> feedback) {
    for (final f in feedback) {
      final prev = _severity[f.rule];
      if (prev == null || f.severity > prev) {
        _severity[f.rule] = f.severity;
      }
    }
  }

  /// Adds the visit that is ending to the running hold and forgets its start.
  ///
  /// Idempotent by way of the null: a rep that ends straight off the bottom
  /// closes the visit on the way out and must not then count it twice.
  void _closeBottomVisit(int timestampMs) {
    final entered = _bottomEnteredMs;
    if (entered == null) return;
    final held = timestampMs - entered;
    if (held > 0) _bottomHoldMs += held;
    _bottomEnteredMs = null;
  }

  RepEvent? _complete(int timestampMs) {
    _closeBottomVisit(timestampMs);
    final duration = timestampMs - _repStartMs;
    if (duration < config.minRepDurationMs) {
      return _discard(RepRejectReason.tooFast);
    }
    final quality = RepQuality(
      index: _reps.length + 1,
      startMs: _repStartMs,
      endMs: timestampMs,
      peakSignal: _peakSignal,
      severityByRule: Map<String, int>.unmodifiable(_severity),
      observedFrames: _observedFrames,
      missedFrames: _missedFrames,
      bottomHoldMs: _bottomHoldMs,
      peakSides: _peakSides,
    );
    _reps.add(quality);
    _phase = RepPhase.top;
    _clearRepState();
    return RepEvent(
      kind: RepEventKind.repCompleted,
      phase: RepPhase.top,
      repCount: _reps.length,
      rep: quality,
    );
  }

  RepEvent _discard(RepRejectReason reason) {
    _phase = RepPhase.top;
    _clearRepState();
    return RepEvent(
      kind: RepEventKind.repRejected,
      phase: RepPhase.top,
      repCount: _reps.length,
      rejectReason: reason,
    );
  }

  void _clearRepState() {
    _severity.clear();
    _repStartMs = 0;
    _peakSignal = double.negativeInfinity;
    _observedFrames = 0;
    _missedFrames = 0;
    _bottomHoldMs = 0;
    _bottomEnteredMs = null;
    _peakSides = null;
  }

  RepEvent _phaseEvent() => RepEvent(
        kind: RepEventKind.phaseChanged,
        phase: _phase,
        repCount: _reps.length,
      );
}
