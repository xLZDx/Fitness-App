import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/form_classifier.dart';
import '../data/pose_detector_service.dart';
import '../data/pose_landmark.dart';
import '../data/rep_counter.dart';
import '../data/voice_coach.dart';

/// Currently-active classifier set. Defaults to the three movements with
/// highest injury risk. The page swaps the set when the user picks an
/// exercise.
final activeClassifiersProvider =
    StateProvider<List<FormClassifier>>((_) => [
          SquatDepthClassifier(),
          DeadliftBackAngleClassifier(),
          PushupAlignmentClassifier(),
        ]);

final poseDetectorServiceProvider =
    Provider<PoseDetectorService>((_) {
  // Default mock yields nothing — production binds the MlKit-backed
  // service from main.dart.
  return MockPoseDetectorService(const []);
});

/// Drives the live overlay: every frame, run the active classifier set
/// and emit the worst feedback. Null when no frame yet / no rule fires.
class FormFeedbackController extends Notifier<FormFeedback?> {
  StreamSubscription<PoseFrame>? _sub;

  @override
  FormFeedback? build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    _sub?.cancel();
    _sub = svc.frames().listen(_onFrame);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onFrame(PoseFrame frame) {
    final classifiers = ref.read(activeClassifiersProvider);
    state = worstFeedback(classifiers, frame);
  }
}

final formFeedbackControllerProvider =
    NotifierProvider<FormFeedbackController, FormFeedback?>(
        FormFeedbackController.new);

/// Thresholds the rep counter runs on. A provider rather than a constant so
/// a future per-exercise profile (press, curl) can override it in one place.
final repCounterConfigProvider =
    Provider<RepCounterConfig>((_) => const RepCounterConfig());

/// Speech engine. Defaults to the mock so widget tests never open a
/// MethodChannel; `main.dart` binds [TtsVoiceCoach] on device.
final voiceCoachProvider = Provider<VoiceCoach>((ref) {
  final coach = MockVoiceCoach();
  ref.onDispose(() => unawaited(coach.dispose()));
  return coach;
});

/// User-facing mute switch for spoken cues. The coach is the enforcement
/// point; this provider is the single source of truth the UI writes to.
final voiceMutedProvider = StateProvider<bool>((_) => false);

/// Snapshot of the current set: how many reps, where in the movement, and
/// the quality record for each rep completed so far.
class RepSessionState {
  const RepSessionState({
    this.repCount = 0,
    this.phase = RepPhase.top,
    this.reps = const <RepQuality>[],
  });

  final int repCount;
  final RepPhase phase;
  final List<RepQuality> reps;

  int get cleanReps => reps.where((r) => r.isClean).length;

  int get sloppyReps => reps.length - cleanReps;
}

/// Drives rep counting off the same frame stream as [FormFeedbackController]:
/// per frame, run the active rules, fold them into the rep counter, and offer
/// the worst one to the voice coach (which decides whether to actually speak).
///
/// State is only republished when the counter reports an event, so a 30 FPS
/// camera does not trigger 30 widget rebuilds a second.
class RepSessionController extends Notifier<RepSessionState> {
  StreamSubscription<PoseFrame>? _sub;
  RepCounter? _counter;

  @override
  RepSessionState build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    final coach = ref.watch(voiceCoachProvider);
    _counter = RepCounter(config: ref.watch(repCounterConfigProvider));

    coach.setMuted(ref.read(voiceMutedProvider));
    ref.listen<bool>(voiceMutedProvider, (_, isMuted) {
      coach.setMuted(isMuted);
      if (isMuted) unawaited(coach.stop());
    });

    _sub?.cancel();
    _sub = svc.frames().listen(_onFrame);
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return const RepSessionState();
  }

  void _onFrame(PoseFrame frame) {
    final counter = _counter;
    if (counter == null) return;

    final feedback = <FormFeedback>[];
    FormFeedback? worst;
    for (final c in ref.read(activeClassifiersProvider)) {
      final f = c.evaluate(frame);
      if (f == null) continue;
      feedback.add(f);
      if (worst == null || f.severity > worst.severity) worst = f;
    }

    final event = counter.update(frame, feedback: feedback);
    if (event != null) {
      state = RepSessionState(
        repCount: counter.repCount,
        phase: counter.phase,
        reps: counter.reps,
      );
    }

    if (worst != null) {
      unawaited(ref.read(voiceCoachProvider).cue(worst));
    }
  }

  /// Start a new set: clear the count and the quality log.
  void resetSet() {
    _counter?.reset();
    unawaited(ref.read(voiceCoachProvider).stop());
    state = const RepSessionState();
  }
}

final repSessionControllerProvider =
    NotifierProvider<RepSessionController, RepSessionState>(
        RepSessionController.new);
