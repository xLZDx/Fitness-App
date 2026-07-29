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

/// Tuning for [RepCounter]. Defaults are for a squat read through
/// [squatDepthSignal].
class RepCounterConfig {
  const RepCounterConfig({
    this.topEnter = -0.15,
    this.topExit = -0.11,
    this.bottomExit = -0.08,
    this.bottomEnter = -0.04,
    this.minRepDurationMs = 600,
    this.minLikelihood = 0.5,
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

  /// Per-joint confidence floor. ML Kit's likelihood below ~0.5 usually
  /// means the joint is occluded and its position is being inferred.
  final double minLikelihood;

  /// The thresholds must form a strictly increasing ladder, otherwise the
  /// hysteresis bands overlap and the machine can skip a phase.
  bool get isOrdered =>
      topEnter < topExit && topExit < bottomExit && bottomExit < bottomEnter;
}

/// Quality record for one completed rep.
class RepQuality {
  const RepQuality({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.peakSignal,
    required this.severityByRule,
  });

  /// 1-based position in the set.
  final int index;

  final int startMs;
  final int endMs;

  /// Deepest point reached, in signal units.
  final double peakSignal;

  /// Worst severity each rule reached at any point during this rep.
  final Map<String, int> severityByRule;

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
  }) : _signal = signal ?? squatDepthSignal {
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

  final List<RepQuality> _reps = <RepQuality>[];
  final Map<String, int> _severity = <String, int>{};

  RepPhase _phase = RepPhase.top;
  bool _armed = false;
  int _repStartMs = 0;
  double _peakSignal = double.negativeInfinity;
  double? _lastSignal;

  /// Accepted reps so far.
  int get repCount => _reps.length;

  RepPhase get phase => _phase;

  /// Quality record per accepted rep, oldest first.
  List<RepQuality> get reps => List.unmodifiable(_reps);

  int get cleanReps => _reps.where((r) => r.isClean).length;

  int get sloppyReps => _reps.length - cleanReps;

  /// Last usable signal value, or null if no frame has been accepted yet.
  /// Exposed for debugging and threshold tuning.
  double? get lastSignal => _lastSignal;

  /// True once a frame has been seen with the lifter standing at the top.
  ///
  /// Until then the machine will not start a rep. Opening the camera
  /// mid-squat and standing up is not a rep, and counting it would be the
  /// first thing a user noticed.
  bool get isArmed => _armed;

  /// Feed one frame. [feedback] is whatever the rule classifiers said about
  /// this frame; it is folded into the in-flight rep's quality record.
  ///
  /// Returns null when nothing changed.
  RepEvent? update(
    PoseFrame frame, {
    Iterable<FormFeedback> feedback = const <FormFeedback>[],
  }) {
    final s = _signal(frame, config.minLikelihood);
    // Unusable frame: missing or low-confidence joints. Change nothing —
    // holding the previous phase is strictly better than guessing.
    if (s == null) return null;
    _lastSignal = s;

    if (!_armed) {
      if (s <= config.topEnter) _armed = true;
      return null;
    }

    // Accumulate quality for a rep already in flight. A rep that starts on
    // this very frame is accumulated by _beginRep instead, so nothing is
    // double-counted and nothing is missed.
    if (_phase != RepPhase.top) {
      _accumulate(feedback);
      if (s > _peakSignal) _peakSignal = s;
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
          return _phaseEvent();
        }
        return null;

      case RepPhase.ascending:
        if (s <= config.topEnter) {
          return _complete(frame.timestampMs);
        }
        if (s >= config.bottomEnter) {
          // Sank back down mid-ascent — still the same rep, not a new one.
          _phase = RepPhase.bottom;
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

  RepEvent? _complete(int timestampMs) {
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
  }

  RepEvent _phaseEvent() => RepEvent(
        kind: RepEventKind.phaseChanged,
        phase: _phase,
        repCount: _reps.length,
      );
}
