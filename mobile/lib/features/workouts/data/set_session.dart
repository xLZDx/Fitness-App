/// A timed set: get ready, work, rest, repeat, done.
///
/// Operator's specification, verbatim: *"нужно кнопка начать упражнение, если
/// это несколько подходов то должен быть звуковой сигнал старта, за 5 сек до
/// конца подхода тикание и финальный гонг, потом перерыв и снова тикание за 5
/// сек до начала подхода и гонг начала... пример с пресом например один подход
/// это 30 секунд подход и 10 сек отдых и так 3 раза - эти значения должны быть
/// разными для разных групп (новички, профи, середина)"*.
///
/// ## Why this is a plain class
///
/// It owns no timer, plays no sound and imports nothing from Flutter. It is
/// advanced by [tick] and it reports what just happened. Everything that makes
/// a timer hard to trust — does it fire the gong twice if the widget rebuilds,
/// does it keep counting after you leave the page, does the last tick of the
/// rest also start the next set — is decidable here, in a test, in
/// milliseconds rather than by sitting through three real minutes.
library;

import 'set_prescription.dart';

/// Where in the set we are.
enum SetPhase {
  /// Nothing running. The starting state and the state after [reset].
  idle,

  /// The spoken briefing and the "I am ready" gate. No clock runs and no
  /// cue plays here: the instruction is heard in full, the person gets into
  /// position at their own pace, and only [SetSession.confirmReady] moves on.
  briefing,

  /// The short countdown after the person said they are ready; ticks, then
  /// the start gong, then work.
  gettingReady,

  /// Working.
  work,

  /// Resting between sets.
  rest,

  /// All sets finished.
  done,
}

/// Something the UI should react to at this instant — a sound to play, a
/// sentence to speak. Returned by [tick] rather than pushed, so a rebuild can
/// never replay one.
enum SetCue {
  /// Three, two, one. Emitted once per second over the last [SetPlan.cueLead]
  /// seconds of getting-ready, work and rest.
  tick,

  /// A set begins.
  startGong,

  /// A set ends.
  endGong,

  /// Every set is finished.
  finished,
}

/// How long the phases run. Different for different people, which is the whole
/// point of asking about experience during onboarding.
class SetPlan {
  const SetPlan({
    required this.sets,
    required this.workSeconds,
    required this.restSeconds,
    this.readySeconds = 3,
    this.cueLead = 5,
    this.prescription = const SetPrescription(),
  });

  final int sets;
  final int workSeconds;
  final int restSeconds;

  /// The short countdown after "I am ready", before the first set. The
  /// time to get into position is the open-ended briefing gate, not this.
  final int readySeconds;

  /// Timed (default) or repetition based. For a rep based set [workSeconds]
  /// is not used as a clock: the work phase ends when the person taps Done.
  final SetPrescription prescription;

  bool get isRepBased => prescription.isReps;

  /// How many seconds of ticking precede the end of a phase. The operator
  /// asked for five.
  final int cueLead;

  /// Beginner / intermediate / advanced, for a timed bodyweight exercise.
  ///
  /// The numbers are the operator's example scaled by experience: his "30
  /// seconds on, 10 off, three times" is the middle row. A beginner gets less
  /// work and more rest; someone advanced gets the reverse. They are a
  /// starting point a user can override, not a prescription — which is why
  /// they live in one const table instead of being computed from something
  /// that would imply more precision than there is.
  static const beginner =
      SetPlan(sets: 3, workSeconds: 20, restSeconds: 20);
  static const intermediate =
      SetPlan(sets: 3, workSeconds: 30, restSeconds: 10);
  static const advanced =
      SetPlan(sets: 4, workSeconds: 45, restSeconds: 10);

  SetPlan copyWith({
    int? sets,
    int? workSeconds,
    int? restSeconds,
    int? readySeconds,
    int? cueLead,
    SetPrescription? prescription,
  }) =>
      SetPlan(
        sets: sets ?? this.sets,
        workSeconds: workSeconds ?? this.workSeconds,
        restSeconds: restSeconds ?? this.restSeconds,
        readySeconds: readySeconds ?? this.readySeconds,
        cueLead: cueLead ?? this.cueLead,
        prescription: prescription ?? this.prescription,
      );

  /// Total wall-clock, ready included. The last set is not followed by a rest.
  int get totalSeconds =>
      readySeconds + sets * workSeconds + (sets - 1) * restSeconds;

  @override
  bool operator ==(Object other) =>
      other is SetPlan &&
      other.sets == sets &&
      other.workSeconds == workSeconds &&
      other.restSeconds == restSeconds &&
      other.readySeconds == readySeconds &&
      other.cueLead == cueLead &&
      other.prescription == prescription;

  @override
  int get hashCode => Object.hash(
      sets, workSeconds, restSeconds, readySeconds, cueLead, prescription);
}

/// One second of the session, and everything the UI needs to draw it.
class SetTick {
  const SetTick({
    required this.phase,
    required this.setNumber,
    required this.secondsLeft,
    required this.cues,
  });

  final SetPhase phase;

  /// 1-based. Zero while getting ready.
  final int setNumber;

  /// In the current phase.
  final int secondsLeft;

  /// What to play or say at this instant. Usually empty.
  final List<SetCue> cues;
}

/// The session itself.
///
/// Advance it with [tick] once a second. It does not know what a second is —
/// the caller owns the clock, which is what makes a three-minute session
/// testable in a millisecond.
class SetSession {
  SetSession(this.plan);

  final SetPlan plan;

  SetPhase _phase = SetPhase.idle;
  int _setNumber = 0;
  int _left = 0;
  bool _running = false;

  SetPhase get phase => _phase;
  int get setNumber => _setNumber;
  int get secondsLeft => _left;
  bool get isRunning => _running;
  bool get isFinished => _phase == SetPhase.done;

  /// 0..1 through the whole session, for a progress ring.
  double get progress {
    if (_phase == SetPhase.idle) return 0;
    if (_phase == SetPhase.done) return 1;
    if (_phase == SetPhase.briefing) return 0;
    var elapsed = 0;
    if (_phase == SetPhase.gettingReady) {
      elapsed = plan.readySeconds - _left;
    } else {
      elapsed = plan.readySeconds;
      elapsed += (_setNumber - 1) * (plan.workSeconds + plan.restSeconds);
      elapsed += _phase == SetPhase.work
          ? plan.workSeconds - _left
          : plan.workSeconds + (plan.restSeconds - _left);
    }
    return (elapsed / plan.totalSeconds).clamp(0.0, 1.0);
  }

  /// Fraction through the CURRENT phase, for a ring that resets each set.
  double get phaseProgress {
    final total = switch (_phase) {
      SetPhase.gettingReady => plan.readySeconds,
      // A rep based set has no clock, so no arc to sweep.
      SetPhase.work => plan.isRepBased ? 0 : plan.workSeconds,
      SetPhase.rest => plan.restSeconds,
      SetPhase.idle || SetPhase.briefing || SetPhase.done => 0,
    };
    if (total <= 0) return _phase == SetPhase.done ? 1 : 0;
    return ((total - _left) / total).clamp(0.0, 1.0);
  }

  /// Begins, or resumes after [pause]. Starting an already-running session is
  /// a no-op rather than a restart: a double tap must not send the user back
  /// to set one.
  List<SetCue> start() {
    if (_running) return const [];
    if (_phase == SetPhase.idle || _phase == SetPhase.done) {
      // Starts in the briefing gate, not in a countdown: nothing counts down
      // until the person confirms with [confirmReady].
      _phase = SetPhase.briefing;
      _setNumber = 0;
      _left = 0;
    }
    _running = true;
    return const [];
  }

  /// "I am ready": leaves the briefing gate and starts the short countdown.
  /// Also resumes a paused session, so the button works in either state. A
  /// no-op outside the briefing, so a double tap cannot skip anything.
  List<SetCue> confirmReady() {
    if (_phase != SetPhase.briefing) return const [];
    _running = true;
    return _advance();
  }

  void pause() => _running = false;

  void reset() {
    _running = false;
    _phase = SetPhase.idle;
    _setNumber = 0;
    _left = 0;
  }

  /// Ends the current set early and moves on — "I am done with this one".
  List<SetCue> skip() {
    if (!_running || _phase == SetPhase.idle || _phase == SetPhase.done) {
      return const [];
    }
    _left = 0;
    return _advance();
  }

  /// "Done" on a repetition based set: ends the work phase and moves to rest
  /// (or finishes). Unlike [skip] it also works while paused, because the
  /// person finishing their reps does not depend on the clock; the session
  /// resumes so the rest countdown runs. A no-op outside a rep based work
  /// phase.
  List<SetCue> finishRepSet() {
    if (_phase != SetPhase.work || !plan.isRepBased) return const [];
    _running = true;
    _left = 0;
    return _advance();
  }

  /// One second of clock. Returns the cues for this instant.
  ///
  /// Ticking a paused or finished session does nothing, so a Timer that
  /// outlives the page cannot quietly drive it to completion.
  SetTick tick() {
    if (!_running ||
        _phase == SetPhase.idle ||
        _phase == SetPhase.done ||
        // The gate waits for the person, and a rep based set waits for Done:
        // neither has a clock to run down.
        _phase == SetPhase.briefing ||
        (_phase == SetPhase.work && plan.isRepBased)) {
      return SetTick(
        phase: _phase,
        setNumber: _setNumber,
        secondsLeft: _left,
        cues: const [],
      );
    }

    _left -= 1;
    final cues = <SetCue>[];

    if (_left <= 0) {
      cues.addAll(_advance());
    } else if (_left <= plan.cueLead) {
      // Ticking runs over the last `cueLead` seconds of every phase — before
      // a set starts and before it ends. The operator asked for both.
      cues.add(SetCue.tick);
    }

    return SetTick(
      phase: _phase,
      setNumber: _setNumber,
      secondsLeft: _left < 0 ? 0 : _left,
      cues: cues,
    );
  }

  List<SetCue> _beginSet() {
    _setNumber += 1;
    _phase = SetPhase.work;
    _left = plan.isRepBased ? 0 : plan.workSeconds;
    return [SetCue.startGong];
  }

  /// Moves out of whatever phase just ran out.
  List<SetCue> _advance() {
    switch (_phase) {
      case SetPhase.briefing:
        _phase = SetPhase.gettingReady;
        _left = plan.readySeconds;
        // A zero-length countdown would otherwise sit at 0 for a whole second
        // before the first work tick.
        return _left <= 0 ? _beginSet() : const [];

      case SetPhase.gettingReady:
        return _beginSet();

      case SetPhase.work:
        if (_setNumber >= plan.sets) {
          _phase = SetPhase.done;
          _left = 0;
          _running = false;
          // Both, and in this order: the set ended AND the session ended. A
          // single "finished" would leave the last set without the sound
          // every other set got.
          return [SetCue.endGong, SetCue.finished];
        }
        _phase = SetPhase.rest;
        _left = plan.restSeconds;
        return [SetCue.endGong];

      case SetPhase.rest:
        return _beginSet();

      case SetPhase.idle:
      case SetPhase.done:
        return const [];
    }
  }
}
