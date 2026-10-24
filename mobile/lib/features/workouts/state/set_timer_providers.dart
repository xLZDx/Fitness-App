import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../form_check/state/form_check_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/cue_player.dart';
import '../../form_check/data/voice_coach.dart' show GatedVoiceCoach;
import '../data/set_capture.dart';
import '../data/set_prescription.dart';
import '../data/set_session.dart';

/// Where cues are played. Overridden in tests with [SilentCuePlayer].
final cuePlayerProvider = Provider<CuePlayer>((ref) {
  final player = AssetCuePlayer();
  // Fire and forget: the first tick is at least ten seconds away, and a timer
  // that will not start until the audio device answers is worse than one whose
  // first sound is late.
  unawaited(player.warmUp());
  ref.onDispose(player.dispose);
  return player;
});

/// Whether the timer makes any sound. Separate from the form coach's mute so
/// somebody can have gongs without a talking coach, or the reverse.
final setCuesMutedProvider = StateProvider<bool>((_) => false);

/// Whether the coach speaks the exercise before the set.
final setVoiceEnabledProvider = StateProvider<bool>((_) => true);

/// What the user said they are lifting for one exercise, keyed by exercise id.
///
/// B8. The weight used to be asked at the END of the exercise, in a sheet that
/// appeared on every "mark complete" whether or not the movement involved a
/// weight at all — followed immediately by a second sheet for the difficulty
/// rating. Two modals to finish a press-up.
///
/// Operator, 2026-08-13: ask when Start is pressed, and only when the exercise
/// takes a load. Holding the answer here rather than passing it down means the
/// question is asked once per exercise per session: the timer collects it, the
/// completion button spends it, and neither needs to know about the other.
///
/// Scoped to the signed-in uid: the answer belongs to one person's session, so
/// a sign-out / account switch in the same process must not hand A's weight
/// and reps to B. It is also spent when the set is logged (see
/// `workout_player_page.dart`), so Monday's 80 kg is not silently re-used on
/// Wednesday.
final setLoadProvider = StateProvider.family<SetCapture?, String>((ref, _) {
  ref.watch(authUserProvider.select((u) => u.valueOrNull?.uid));
  return null;
});

/// The plan for [exercise], from what the intake said about experience.
///
/// Operator: *"эти значения должны быть разными для разных групп (новички,
/// профи, середина)"*. The tier comes from the questionnaire; a user who never
/// answered gets the middle plan, which is his own example.
///
/// A rep-counted lift is not a timed set, so barbell work gets fewer, longer
/// sets than a bodyweight hold. That distinction is read off `equipmentId`
/// rather than a list of exercise names, so it cannot drift out of step with
/// the catalog.
///
/// Repetition based unless the exercise is inherently timed
/// ([exerciseIsTimed]); with no exercise the plan stays timed, as before.
/// [capturedReps] and [loadKg] are what the person already said through the
/// capture sheet; without them reps default by tier ([defaultTargetReps]) and
/// the load stays unset.
SetPlan planFor(
  ExerciseItem? exercise,
  FitnessTier? tier, {
  double? loadKg,
  int? capturedReps,
}) {
  var plan = switch (tier) {
    // `never` takes the beginner plan rather than something gentler still.
    // There are three plans, and inventing a fourth for a tier that has never
    // been exercised against real users would be guessing at numbers, which is
    // worse than reusing numbers the operator has already looked at.
    FitnessTier.never || FitnessTier.beginner => SetPlan.beginner,
    FitnessTier.advanced => SetPlan.advanced,
    FitnessTier.intermediate || null => SetPlan.intermediate,
  };

  // Loaded work is counted in repetitions, not seconds. Timing it at all is a
  // convenience — it wants a longer rest and one fewer set than a floor
  // exercise, or the timer is telling a lifter to start again before they have
  // put the bar down.
  //
  // The id list moved to `set_capture.dart` as [kLoadedEquipmentIds]: "does
  // this want a longer rest" and "should we ask what was lifted" are the same
  // question, and two copies would have drifted.
  if (exerciseUsesLoad(
    equipmentId: exercise?.equipmentId,
    isStretch: exercise?.isStretch ?? false,
  )) {
    plan = plan.copyWith(
      workSeconds: (plan.workSeconds * 1.4).round(),
      restSeconds: plan.restSeconds < 60 ? 90 : plan.restSeconds,
    );
  }
  if (exercise != null && !exerciseIsTimed(exercise)) {
    plan = plan.copyWith(
      prescription: SetPrescription(
        mode: SetMode.reps,
        targetReps: capturedReps ?? defaultTargetReps(tier),
        loadKg: loadKg,
      ),
    );
  }
  return plan;
}

/// The plan the timer will use for the exercise on screen.
final setPlanProvider = Provider.family<SetPlan, ExerciseItem?>((ref, ex) {
  final tier =
      ref.watch(currentProfileProvider).valueOrNull?.level.tier;
  // The person's own answer for this exercise (this session) pre-fills the
  // load and reps; nothing is persisted across sessions here.
  final captured = ex == null ? null : ref.watch(setLoadProvider(ex.id));
  return planFor(ex, tier,
      loadKg: captured?.weightKg, capturedReps: captured?.reps);
});

/// Live state of a running set. Null until the user starts one.
class SetTimerState {
  const SetTimerState({
    required this.phase,
    required this.setNumber,
    required this.secondsLeft,
    required this.totalSets,
    required this.progress,
    required this.running,
    this.introSpeaking = false,
    this.exerciseId,
  });

  /// The exercise the running session belongs to; null when unknown (callers
  /// that start without an id) or idle. Lets a page show its own idle card
  /// instead of another exercise's session.
  final String? exerciseId;

  final SetPhase phase;

  /// True while the spoken intro is still playing in the briefing phase; the
  /// "I am ready" button appears once it is false.
  final bool introSpeaking;
  final int setNumber;
  final int secondsLeft;
  final int totalSets;

  /// Through the current phase, for a ring that resets each set.
  final double progress;
  final bool running;

  static const idle = SetTimerState(
    phase: SetPhase.idle,
    setNumber: 0,
    secondsLeft: 0,
    totalSets: 0,
    progress: 0,
    running: false,
  );

  bool get isBriefing => phase == SetPhase.briefing;
  bool get isIdle => phase == SetPhase.idle;
  bool get isDone => phase == SetPhase.done;
}

/// Drives a [SetSession] from a real clock and plays its cues.
///
/// The session itself owns no timer — see `set_session.dart`. This is the only
/// place that knows what a second is, which is why the awkward parts (a
/// backgrounded app, a page left mid-set) are fixable in one place.
class SetTimerController extends Notifier<SetTimerState> {
  SetSession? _session;
  Timer? _timer;

  /// True while the spoken intro of the briefing phase is playing.
  bool _introSpeaking = false;

  /// Bumped whenever an intro is cancelled or finished early, so a late
  /// completion of an abandoned intro cannot touch the current state.
  int _introToken = 0;
  bool _disposed = false;

  /// Exercise the current session was started for.
  String? _exerciseId;

  @override
  SetTimerState build() {
    ref.onDispose(() {
      _disposed = true;
      _introToken++;
      _stopClock();
    });

    // Both switches take effect NOW, not at the next set.
    //
    // Reading them only where sound is produced -- `start()` for the voice,
    // `_play()` for the cues -- gates what is ABOUT to be played and leaves
    // whatever is already sounding to run to its end. The spoken intro is a
    // whole sentence, so switching the voice off mid-sentence changed nothing
    // audible for several seconds, which is exactly what "the button does not
    // react" looks like from the outside. The form coach has always done this
    // correctly (`form_check_providers.dart`, the same `ref.listen` +
    // `stop()` pair); the set timer never did.
    ref.listen<bool>(setVoiceEnabledProvider, (_, enabled) {
      if (!enabled) {
        unawaited(ref.read(voiceCoachProvider).stop());
        // Voice off means no waiting: open the gate right away.
        if (_introSpeaking) {
          _introToken++;
          _introSpeaking = false;
          _publish();
        }
      }
    });
    ref.listen<bool>(setCuesMutedProvider, (_, muted) {
      if (muted) unawaited(ref.read(cuePlayerProvider).stop());
    });

    return SetTimerState.idle;
  }

  void _stopClock() {
    _timer?.cancel();
    _timer = null;
  }

  /// Begins a set of [plan] for [exercise].
  ///
  /// A fresh start enters the briefing phase: [spokenIntro] (if the voice is
  /// on) is spoken IN FULL with no clock running and no cue playing, then the
  /// person confirms with [confirmReady]. Only that starts the short
  /// countdown. Resuming after a pause does not repeat the intro.
  ///
  /// Starting for a different [exerciseId] than the running session's replaces
  /// that session (it is reset first), even if the plans happen to be equal.
  void start(SetPlan plan, {String? spokenIntro, String? exerciseId}) {
    if (exerciseId != null && _session != null && _exerciseId != exerciseId) {
      reset();
    }
    _exerciseId = exerciseId;
    final session = _session ??= SetSession(plan);
    if (session.plan != plan || session.isFinished) {
      _session = SetSession(plan);
    }
    final s = _session!;
    final entering = s.phase == SetPhase.idle;
    _play(s.start());

    _stopClock();
    if (s.phase == SetPhase.briefing) {
      if (entering &&
          spokenIntro != null &&
          ref.read(setVoiceEnabledProvider)) {
        _introSpeaking = true;
        unawaited(_speakIntro(spokenIntro, ++_introToken));
      }
    } else {
      _startClock();
    }
    _publish();
  }

  void _startClock() {
    _stopClock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
  }

  /// Speaks the intro and opens the "I am ready" gate when it ends.
  ///
  /// The wait is bounded: a TTS engine that never reports completion must not
  /// block the session, so after the timeout the speech is cut and the gate
  /// opens anyway. A broken or muted voice completes at once.
  Future<void> _speakIntro(String text, int token) async {
    final coach = ref.read(voiceCoachProvider);
    final limit = Duration(seconds: 15 + text.length ~/ 8);
    try {
      final spoken =
          coach is GatedVoiceCoach ? coach.sayAndWait(text) : coach.say(text);
      await spoken.timeout(limit);
    } on TimeoutException {
      unawaited(coach.stop());
    } catch (_) {
      // A failing engine is the same as a silent one: open the gate.
    }
    if (_disposed || token != _introToken) return;
    _introSpeaking = false;
    _publish();
  }

  /// Drops a running intro (pause, stop, "I am ready" while it still talks).
  void _cancelIntro() {
    if (!_introSpeaking) return;
    _introToken++;
    _introSpeaking = false;
    unawaited(ref.read(voiceCoachProvider).stop());
  }

  /// "I am ready": ends the briefing and starts the short countdown.
  void confirmReady() {
    final s = _session;
    if (s == null || s.phase != SetPhase.briefing) return;
    _cancelIntro();
    _play(s.confirmReady());
    _startClock();
    _publish();
  }

  void pause() {
    _cancelIntro();
    _session?.pause();
    _stopClock();
    _publish();
  }

  void skip() {
    final s = _session;
    if (s == null) return;
    // In the gate, skip means "ready".
    if (s.phase == SetPhase.briefing) {
      confirmReady();
      return;
    }
    _play(s.skip());
    if (s.isFinished) _stopClock();
    _publish();
  }

  /// "Done" on a rep based set; works while paused too.
  void finishRepSet() {
    final s = _session;
    if (s == null) return;
    _play(s.finishRepSet());
    if (s.isFinished) {
      _stopClock();
    } else if (s.isRunning) {
      _startClock();
    }
    _publish();
  }

  void reset() {
    _cancelIntro();
    _stopClock();
    _session?.reset();
    _session = null;
    state = SetTimerState.idle;
  }

  void _onSecond() {
    final s = _session;
    if (s == null) return;
    _play(s.tick().cues);
    if (s.isFinished) _stopClock();
    _publish();
  }

  void _play(List<SetCue> cues) {
    if (cues.isEmpty) return;
    if (!ref.read(setCuesMutedProvider)) {
      final player = ref.read(cuePlayerProvider);
      for (final c in cues) {
        unawaited(player.play(c));
      }
    }
  }

  void _publish() {
    final s = _session;
    if (s == null) {
      state = SetTimerState.idle;
      return;
    }
    state = SetTimerState(
      phase: s.phase,
      setNumber: s.setNumber,
      secondsLeft: s.secondsLeft,
      totalSets: s.plan.sets,
      progress: s.phaseProgress,
      running: s.isRunning,
      introSpeaking: _introSpeaking,
      exerciseId: _exerciseId,
    );
  }
}

final setTimerProvider =
    NotifierProvider<SetTimerController, SetTimerState>(
        SetTimerController.new);
