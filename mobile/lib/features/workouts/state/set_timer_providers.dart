import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../form_check/state/form_check_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/cue_player.dart';
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
SetPlan planFor(ExerciseItem? exercise, FitnessTier? tier) {
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
  const loaded = {
    'barbell', 'dumbbell', 'kettlebell', 'ez_curl_bar', 'smith_machine',
    'squat_rack', 'bench_press', 'leg_press', 'lat_pulldown', 'cable_machine',
    'weight_plates', 't_bar_row', 'seated_row_machine', 'hack_squat_machine',
  };
  if (exercise?.equipmentId != null &&
      loaded.contains(exercise!.equipmentId)) {
    plan = plan.copyWith(
      workSeconds: (plan.workSeconds * 1.4).round(),
      restSeconds: plan.restSeconds < 60 ? 90 : plan.restSeconds,
    );
  }
  return plan;
}

/// The plan the timer will use for the exercise on screen.
final setPlanProvider = Provider.family<SetPlan, ExerciseItem?>((ref, ex) {
  final tier =
      ref.watch(currentProfileProvider).valueOrNull?.level.tier;
  return planFor(ex, tier);
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
  });

  final SetPhase phase;
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

  @override
  SetTimerState build() {
    ref.onDispose(_stopClock);
    return SetTimerState.idle;
  }

  void _stopClock() {
    _timer?.cancel();
    _timer = null;
  }

  /// Begins a set of [plan] for [exercise], announcing it first if the voice
  /// is on.
  void start(SetPlan plan, {String? spokenIntro}) {
    final session = _session ??= SetSession(plan);
    if (session.plan != plan || session.isFinished) {
      _session = SetSession(plan);
    }
    final s = _session!;
    _play(s.start());

    if (spokenIntro != null && ref.read(setVoiceEnabledProvider)) {
      unawaited(ref.read(voiceCoachProvider).say(spokenIntro));
    }

    _stopClock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
    _publish();
  }

  void pause() {
    _session?.pause();
    _stopClock();
    _publish();
  }

  void skip() {
    final s = _session;
    if (s == null) return;
    _play(s.skip());
    _publish();
  }

  void reset() {
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
    );
  }
}

final setTimerProvider =
    NotifierProvider<SetTimerController, SetTimerState>(
        SetTimerController.new);
