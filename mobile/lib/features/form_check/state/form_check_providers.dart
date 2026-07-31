import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/form_classifier.dart';
import '../data/pose_detector_service.dart';
import '../data/pose_gate.dart';
import '../data/pose_landmark.dart';
import '../data/pose_unit_probe.dart';
import '../data/rep_counter.dart';
import '../data/voice_coach.dart';

/// Currently-active classifier set.
///
/// **All three run on every frame, always.** There is no exercise picker in the
/// UI, so a squatting user is also evaluated by the hip-hinge rule and the
/// push-up rule. That is why the operator's post-set summary listed three rule
/// ids at once, and it is why fixing an individual rule's thresholds is
/// cosmetic until the set is chosen per exercise (gate V0c).
final activeClassifiersProvider =
    StateProvider<List<FormClassifier>>((_) => [
          SquatDepthClassifier(),
          DeadliftHipHingeClassifier(),
          PushupAlignmentClassifier(),
        ]);

final poseDetectorServiceProvider =
    Provider<PoseDetectorService>((_) {
  // Default mock yields nothing — production binds the MlKit-backed
  // service from main.dart.
  return MockPoseDetectorService(const []);
});

/// Last fatal detector failure, or null while healthy.
///
/// The pose stream reports native failures as stream errors. Without a sink
/// for them they land on the Zone's uncaught-error handler and the user just
/// sees a live camera that never counts a rep — which is precisely how the
/// NV21 format bug stayed invisible until a device test.
final poseErrorProvider = StateProvider<String?>((_) => null);

/// Records a fatal detector error so the page can say what went wrong.
void _recordPoseError(Ref ref, Object e) {
  ref.read(poseErrorProvider.notifier).state =
      e is StateError ? e.message : e.toString();
}

/// Thresholds for "is this frame worth scoring". A provider so a future
/// per-exercise profile can loosen or tighten them in one place.
final poseGateConfigProvider =
    Provider<PoseGateConfig>((_) => const PoseGateConfig());

/// Why the last frame could not be scored, or [PoseGateVerdict.ok].
///
/// The page reads this to show a specific instruction ("step back", "too
/// dark") instead of an empty cue card. Before the gate existed there was
/// nothing to show, because a frame with invented joints always produced
/// feedback — the user could not distinguish "your form is fine" from "the
/// coach cannot see you".
///
/// A `StateProvider` only notifies on a changed value, so writing this on every
/// frame does not rebuild anything while the verdict holds steady.
final poseGateVerdictProvider =
    StateProvider<PoseGateVerdict>((_) => PoseGateVerdict.ok);

/// What the coordinates actually measured this session.
///
/// Read-only: nothing in the scoring path consults it. It exists because every
/// threshold in the gate, the rep counter and the classifiers was picked against
/// an assumed range, and this is the first thing in the app that reports the
/// real one. See `pose_unit_probe.dart`.
final poseUnitReportProvider =
    StateProvider<PoseUnitReport>((_) => PoseUnitReport.empty);

/// Drives the live overlay: every frame, run the active classifier set
/// and emit the worst feedback. Null when no frame yet / no rule fires.
class FormFeedbackController extends Notifier<FormFeedback?> {
  StreamSubscription<PoseFrame>? _sub;
  final PoseUnitProbe _probe = PoseUnitProbe();

  @override
  FormFeedback? build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    _sub?.cancel();
    _sub = svc.frames().listen(
          _onFrame,
          onError: (Object e) => _recordPoseError(ref, e),
        );
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onFrame(PoseFrame frame) {
    // Before the gate, on purpose: a frame the gate rejects is exactly the
    // frame whose coordinates are most worth knowing about.
    _probe.observe(frame);
    ref.read(poseUnitReportProvider.notifier).state = _probe.report;

    final classifiers = ref.read(activeClassifiersProvider);
    final result = evaluateGated(
      classifiers,
      frame,
      config: ref.read(poseGateConfigProvider),
    );
    ref.read(poseGateVerdictProvider.notifier).state = result.verdict;
    state = result.worst;
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
    _sub = svc.frames().listen(
          _onFrame,
          onError: (Object e) => _recordPoseError(ref, e),
        );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return const RepSessionState();
  }

  void _onFrame(PoseFrame frame) {
    final counter = _counter;
    if (counter == null) return;

    final result = evaluateGated(
      ref.read(activeClassifiersProvider),
      frame,
      config: ref.read(poseGateConfigProvider),
    );
    // An unscorable frame is dropped entirely — it must not reach the rep
    // counter and it must not reach the voice coach. This single early return
    // is what stops a selfie of a face from producing six reps and an endless
    // repeated safety warning.
    if (!result.scorable) return;

    final feedback = result.feedback;
    final worst = result.worst;

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
