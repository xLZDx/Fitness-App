import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_phases.dart';
import '../data/pose_gate.dart';
import 'form_check_providers.dart';

/// Where the coached session is, and why the view is unusable when it is.
class CoachSessionState {
  const CoachSessionState({
    this.phase = CoachPhase.launch,
    this.blocker = CoachBlocker.none,
  });

  final CoachPhase phase;
  final CoachBlocker blocker;

  CoachSessionState copyWith({CoachPhase? phase, CoachBlocker? blocker}) =>
      CoachSessionState(
        phase: phase ?? this.phase,
        blocker: blocker ?? this.blocker,
      );
}

/// Drives the coached session through the design's stages.
///
/// Starts at [CoachPhase.launch]: nothing is running, and in particular the
/// camera is not open.
///
/// It used to start at [CoachPhase.qualityCheck] because the page opened the
/// camera on arrival, and this doc used to argue that moving it wanted device
/// verification first. That argument is now the wrong way round. The design's
/// preparation card ends on a button reading "включить камеру" and its own body
/// text promises the camera is not yet in use (`App.tsx:4558-4562`) — so
/// drawing those screens over a live preview would have been a lie in the
/// interface, not a compromise. And the change moves the permission prompt
/// LATER, to the moment the user explicitly asks for it, which is the safer
/// direction to be wrong in.
class CoachPhaseController extends Notifier<CoachSessionState> {
  @override
  CoachSessionState build() =>
      CoachSessionState(phase: ref.watch(coachInitialPhaseProvider));

  /// The user asked to begin. Show them how to stand before anything opens.
  void toPreparation() =>
      state = state.copyWith(phase: CoachPhase.preparation);

  /// Back out of the preparation card to the intro.
  void toLaunch() => state = state.copyWith(phase: CoachPhase.launch);

  /// The user has read the preparation card and asked for the camera.
  ///
  /// Only moves the phase. Actually opening the camera belongs to the page,
  /// which owns the service handle and the lifecycle token — a Notifier that
  /// reached for hardware would also have to own tearing it down.
  void openCamera() => state = state.copyWith(phase: CoachPhase.qualityCheck);

  /// Fold the current gate verdict in.
  void onVerdict(PoseGateVerdict verdict) {
    state = state.copyWith(
      phase: phaseAfterFrame(state.phase, verdict),
      blocker: blockerFor(verdict),
    );
  }

  /// The user started the set.
  void start() => state = state.copyWith(phase: CoachPhase.active);

  void pause() {
    if (state.phase != CoachPhase.active) return;
    state = state.copyWith(phase: CoachPhase.paused);
  }

  void resume() {
    if (state.phase != CoachPhase.paused) return;
    state = state.copyWith(phase: CoachPhase.active);
  }

  void finish() => state = state.copyWith(phase: CoachPhase.summary);

  /// Back to judging the view.
  void restart() => state = const CoachSessionState();
}

/// Where a fresh coached session begins.
///
/// A provider rather than a constant purely so a test can start at the screen
/// it is actually about. Fifteen existing cases — the skeleton toggle, the cue
/// gate, rep counting — pump this page to exercise the camera UI and have
/// nothing to say about the intro cards; making each of them tap through two
/// screens would be fifteen copies of a walk-through that tests nothing, and
/// the first one to be written slightly differently would be the one that
/// stops catching its own bug.
///
/// Production never overrides it.
final coachInitialPhaseProvider = Provider<CoachPhase>((_) => CoachPhase.launch);

final coachPhaseControllerProvider =
    NotifierProvider<CoachPhaseController, CoachSessionState>(
        CoachPhaseController.new);

/// The session state, kept in step with the live gate verdict.
///
/// ## The split, and why it is not one object
///
/// [CoachPhaseController] owns the phases a TAP moves — start, pause, resume,
/// finish. This provider overlays the phase a VERDICT moves, by reading the
/// controller's phase and folding the current verdict onto it. So while the
/// user has not started, the controller sits at [CoachPhase.qualityCheck] and
/// what the screen shows is whatever the live verdict makes of it; the moment
/// `start()` is called the controller's own phase wins and the verdict stops
/// moving anything.
///
/// The fold happens here rather than by writing back into the controller
/// because a provider that mutates another provider during its build is what
/// Riverpod's "cannot modify a provider while building" error exists to catch.
///
/// Derived, not polled. `poseGateVerdictProvider` notifies on every CHANGE of
/// verdict, and a change is exactly when this needs to move — so there is no
/// timer to leave pending behind a test and no wakeup burned on a screen that
/// is showing a steady answer.
final coachSessionProvider = Provider<CoachSessionState>((ref) {
  final verdict = ref.watch(poseGateVerdictProvider);
  final current = ref.watch(coachPhaseControllerProvider);

  if (current.phase == CoachPhase.qualityCheck ||
      current.phase == CoachPhase.ready) {
    return CoachSessionState(
      phase: phaseAfterFrame(current.phase, verdict),
      blocker: blockerFor(verdict),
    );
  }
  // Mid-set, paused or finished: the verdict no longer moves the phase, but
  // the blocker is still worth carrying for anything that wants to explain a
  // gap in the rep count.
  return current.copyWith(blocker: blockerFor(verdict));
});
