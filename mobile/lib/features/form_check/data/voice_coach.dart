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
///   2. Identical to the last cue spoken, within [repeatGapMs] — silent.
///   3. At or above [interruptSeverity] — spoken immediately, bypassing the
///      throttle window and preempting anything queued. A "stop, your back is
///      rounding" that waits its turn behind "chest up" is a safety defect.
///   4. Inside [minGapMs] of the last cue — silent.
///   5. Otherwise — spoken.
class CueGate {
  CueGate({
    this.minGapMs = 3000,
    this.interruptGapMs = 1200,
    this.repeatGapMs = 20000,
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

  /// Minimum spacing for a REPEATED interrupt-severity cue. Well under
  /// [minGapMs]: while a dangerous position persists the warning must keep
  /// coming, but 1.2s is long enough not to stutter over itself.
  final int interruptGapMs;

  /// How long the same cue stays silenced before it may be said again.
  ///
  /// Rule 2 used to be absolute — the same sentence was never spoken twice in a
  /// row, ever. Paired with the per-rep pacing in `RepSessionController` that
  /// turns into permanent silence: a user repeating one mistake hears about it
  /// once and then nothing, for the rest of the set.
  ///
  /// Twenty seconds is a handful of reps. Long enough not to nag — the red
  /// banner is what carries a persisting fault — short enough that a fault the
  /// user never fixed gets said again while it still matters.
  final int repeatGapMs;

  /// Severities below this are never spoken.
  final int minSeverity;

  /// Severities at or above this bypass the throttle and preempt.
  final int interruptSeverity;

  final ClockMs _clock;

  FormCueKey? _lastCue;
  int? _lastSpokenAtMs;

  /// The last cue actually released to the speaker, or null.
  FormCueKey? get lastCue => _lastCue;

  /// When [lastCue] was released, or null.
  int? get lastSpokenAtMs => _lastSpokenAtMs;

  /// Decide AND record. Convenience for callers that always speak whatever
  /// they are given; [peek] + [commit] is the pair to use when speaking can
  /// still fail after the decision.
  CueDecision decide(FormFeedback feedback) {
    final decision = peek(feedback);
    if (decision != CueDecision.suppress) commit(feedback);
    return decision;
  }

  /// Decide WITHOUT recording. Pure — call it as often as you like.
  ///
  /// The split exists because recording before the cue is actually delivered
  /// reintroduces the defect this whole feature was written to remove: if the
  /// text failed to resolve, the cue was dropped while the gate believed it had
  /// fired — so the throttle then silenced the *next*, real attempt to say the
  /// same thing. For a "stop, you are about to hurt yourself" cue that is the
  /// worst possible place to lose a message.
  CueDecision peek(FormFeedback feedback) {
    if (feedback.severity < minSeverity) return CueDecision.suppress;
    // Identity is the cue KEY, not the rendered sentence: "is this the same
    // fault as last time" must not change answer when the app's language does.
    final cue = feedback.cueKey;

    final now = _clock();

    // Interrupt-severity cues are checked BEFORE the repeat filter.
    // A dangerous position persists across frames, so the classifier emits
    // the SAME cue text every frame — with the repeat filter first, "stop,
    // your back is rounding" was spoken once and then silenced for the rest
    // of the dangerous streak. It still gets a floor (interruptGapMs) so it
    // repeats at a usable cadence instead of stuttering every frame.
    if (feedback.severity >= interruptSeverity) {
      final last = _lastSpokenAtMs;
      final sameCue = cue == _lastCue;
      if (sameCue && last != null && now - last < interruptGapMs) {
        return CueDecision.suppress;
      }
      return CueDecision.preempt;
    }

    final last = _lastSpokenAtMs;
    if (cue == _lastCue && last != null && now - last < repeatGapMs) {
      return CueDecision.suppress;
    }
    if (last != null && now - last < minGapMs) return CueDecision.suppress;

    return CueDecision.speak;
  }

  /// Record that [feedback]'s cue was actually delivered. Call only after the
  /// speaker has been given something to say.
  void commit(FormFeedback feedback) {
    _lastCue = feedback.cueKey;
    _lastSpokenAtMs = _clock();
  }

  /// Forget what was said and when. Call between sets, or on unmute, so a
  /// cue from five minutes ago cannot suppress the same cue now.
  void reset() {
    _lastCue = null;
    _lastSpokenAtMs = null;
  }
}

/// Turns a cue key into the sentence a coach should say.
///
/// Injected rather than imported so this file stays Flutter-free: resolving a
/// key needs `AppLocalizations`, and dragging that in here would put a
/// generated localization class inside every unit test of the throttle policy.
typedef CueTextResolver = String Function(FormCueKey cueKey);

String _identityResolver(FormCueKey cueKey) => cueKey.name;

/// Speaks form cues out loud.
abstract class VoiceCoach {
  /// Offer a cue. Whether it is actually spoken is up to the coach's
  /// [CueGate] and mute state — callers may call this every frame.
  Future<void> cue(FormFeedback feedback);

  /// Speak [text] now, subject only to mute.
  ///
  /// Lower-level than [cue]: no gate, no cue key, no de-duplication. It exists
  /// because the set timer needs to say a sentence the form coach's cue
  /// vocabulary has no word for — "three sets of thirty seconds, keep your
  /// lower back flat" — and giving the timer its own speech engine would mean
  /// two of them competing for the same speaker.
  ///
  /// Callers that speak on a schedule should use this. Callers that speak in
  /// reaction to a stream of frames should use [cue], which is what stops the
  /// coach repeating itself forty times a second.
  Future<void> say(String text);

  /// Stop speaking immediately and clear the gate.
  Future<void> stop();

  bool get muted;

  void setMuted(bool value);

  /// Last engine failure, or null when the coach is healthy.
  ///
  /// On the interface, not just the TTS implementation: a coach that has gone
  /// silent because the device has no voice installed is indistinguishable
  /// from a coach with nothing to say, and the user doing squats cannot tell
  /// "my form is fine" from "the coach is broken". Mirrors
  /// [HealthService.lastErrorMessage], which is wired the same way.
  String? get lastErrorMessage;

  Future<void> dispose();
}

/// [VoiceCoach] with the gating and mute logic applied, leaving subclasses
/// to implement only "say this string" and "shut up".
abstract class GatedVoiceCoach implements VoiceCoach {
  GatedVoiceCoach({CueGate? gate, CueTextResolver? resolveText})
      : gate = gate ?? CueGate(),
        resolveText = resolveText ?? _identityResolver;

  final CueGate gate;

  /// Turns a cue key into the sentence to speak.
  ///
  /// Defaults to the identity, which means an unwired coach speaks the key
  /// itself — deliberately ugly rather than silently English, so a missing
  /// binding is obvious the first time anyone hears it. `main.dart` binds the
  /// real resolver against the app's active locale.
  final CueTextResolver resolveText;

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
    final decision = gate.peek(feedback);
    if (decision == CueDecision.suppress) return;

    // Resolve BEFORE committing. An unresolvable cue must leave the gate
    // untouched so the next frame can try again, rather than being counted as
    // spoken and silencing the retry.
    final text = resolveText(feedback.cueKey).trim();
    if (text.isEmpty) return;

    if (decision == CueDecision.preempt) {
      await stopSpeaking();
    }
    gate.commit(feedback);
    await utter(text);
  }

  @override
  Future<void> say(String text) async {
    if (_muted) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await utter(trimmed);
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
  MockVoiceCoach({super.gate, super.resolveText});

  /// Every cue released to the "speaker", in order.
  final List<String> spoken = <String>[];

  /// How many times speech was cancelled — by a preempting severity-2 cue
  /// or by an explicit [stop].
  int stopCalls = 0;

  bool disposed = false;

  /// Settable so a test can drive the "coach is broken" UI path.
  @override
  String? lastErrorMessage;

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
