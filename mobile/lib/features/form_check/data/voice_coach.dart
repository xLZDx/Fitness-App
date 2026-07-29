// GF.2 — Form coach spoken cues.
//
// Rule classifiers fire on every frame. At 15-30 FPS that is a voice reading
// the same sentence twenty times a second, which is worse than silence — the
// user turns it off and never turns it back on. [CueGate] is the policy that
// makes speech usable, and it is deliberately pure and clock-injected so the
// policy can be tested without a speech engine or a real second passing.
//
// Flutter-free on purpose, exactly like `pose_detector_service.dart`: the
// interface, the policy and the test double live here, and the platform
// adapter lives next door in `tts_voice_coach.dart`. Importing `flutter_tts`
// here would drag a MethodChannel into every unit test that wants to assert
// on throttling.

import 'form_classifier.dart';

/// Milliseconds since epoch. Injected so tests advance time by assignment
/// instead of by waiting.
typedef ClockMs = int Function();

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

/// What [CueGate] decided to do with a cue.
enum CueDecision {
  /// Say it normally.
  speak,

  /// Say it now, cutting off whatever is already speaking or queued.
  preempt,

  /// Say nothing.
  suppress,
}

/// Decides whether a piece of [FormFeedback] should reach the speaker.
///
/// Policy, in order:
///   1. Below [minSeverity] — silent. "Good depth" every rep is noise.
///   2. Identical to the last cue spoken — silent. Never the same sentence
///      twice in a row.
///   3. At or above [interruptSeverity] — spoken immediately, bypassing the
///      throttle window and preempting anything queued. A "stop, your back is
///      rounding" that waits its turn behind "chest up" is a safety defect.
///   4. Inside [minGapMs] of the last cue — silent.
///   5. Otherwise — spoken.
class CueGate {
  CueGate({
    this.minGapMs = 3000,
    this.minSeverity = 1,
    this.interruptSeverity = 2,
    ClockMs? clock,
  })  : assert(minGapMs >= 0, 'minGapMs cannot be negative'),
        assert(
          minSeverity <= interruptSeverity,
          'a cue that is severe enough to interrupt must also be severe '
          'enough to speak',
        ),
        _clock = clock ?? _wallClockMs;

  /// Minimum spacing between ordinary cues. Three seconds is about one
  /// squat rep — fast enough to be corrective, slow enough to be a coach
  /// rather than a metronome.
  final int minGapMs;

  /// Severities below this are never spoken.
  final int minSeverity;

  /// Severities at or above this bypass the throttle and preempt.
  final int interruptSeverity;

  final ClockMs _clock;

  String? _lastCue;
  int? _lastSpokenAtMs;

  /// The last cue actually released to the speaker, or null.
  String? get lastCue => _lastCue;

  /// When [lastCue] was released, or null.
  int? get lastSpokenAtMs => _lastSpokenAtMs;

  CueDecision decide(FormFeedback feedback) {
    if (feedback.severity < minSeverity) return CueDecision.suppress;
    final cue = feedback.cue.trim();
    if (cue.isEmpty) return CueDecision.suppress;
    if (cue == _lastCue) return CueDecision.suppress;

    final now = _clock();
    if (feedback.severity >= interruptSeverity) {
      _commit(cue, now);
      return CueDecision.preempt;
    }

    final last = _lastSpokenAtMs;
    if (last != null && now - last < minGapMs) return CueDecision.suppress;

    _commit(cue, now);
    return CueDecision.speak;
  }

  void _commit(String cue, int now) {
    _lastCue = cue;
    _lastSpokenAtMs = now;
  }

  /// Forget what was said and when. Call between sets, or on unmute, so a
  /// cue from five minutes ago cannot suppress the same cue now.
  void reset() {
    _lastCue = null;
    _lastSpokenAtMs = null;
  }
}

/// Speaks form cues out loud.
abstract class VoiceCoach {
  /// Offer a cue. Whether it is actually spoken is up to the coach's
  /// [CueGate] and mute state — callers may call this every frame.
  Future<void> cue(FormFeedback feedback);

  /// Stop speaking immediately and clear the gate.
  Future<void> stop();

  bool get muted;

  void setMuted(bool value);

  Future<void> dispose();
}

/// [VoiceCoach] with the gating and mute logic applied, leaving subclasses
/// to implement only "say this string" and "shut up".
abstract class GatedVoiceCoach implements VoiceCoach {
  GatedVoiceCoach({CueGate? gate}) : gate = gate ?? CueGate();

  final CueGate gate;

  bool _muted = false;

  @override
  bool get muted => _muted;

  @override
  void setMuted(bool value) {
    if (_muted == value) return;
    _muted = value;
    // Reset either way: muting drops the queue's history, unmuting should
    // not inherit a stale "already said that" from before the silence.
    gate.reset();
  }

  @override
  Future<void> cue(FormFeedback feedback) async {
    if (_muted) return;
    final decision = gate.decide(feedback);
    if (decision == CueDecision.suppress) return;
    if (decision == CueDecision.preempt) {
      await stopSpeaking();
    }
    await utter(feedback.cue.trim());
  }

  @override
  Future<void> stop() async {
    gate.reset();
    await stopSpeaking();
  }

  /// Push text to the speech engine.
  Future<void> utter(String text);

  /// Cancel anything speaking or queued.
  Future<void> stopSpeaking();
}

/// Test double. Records what would have been said instead of saying it.
class MockVoiceCoach extends GatedVoiceCoach {
  MockVoiceCoach({super.gate});

  /// Every cue released to the "speaker", in order.
  final List<String> spoken = <String>[];

  /// How many times speech was cancelled — by a preempting severity-2 cue
  /// or by an explicit [stop].
  int stopCalls = 0;

  bool disposed = false;

  @override
  Future<void> utter(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async => stopCalls++;

  @override
  Future<void> dispose() async => disposed = true;

  void clear() {
    spoken.clear();
    stopCalls = 0;
    gate.reset();
  }
}
