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
/// intro card ends on a button reading "включить камеру" and its own body text
/// promises the camera is not yet in use (`App.tsx:4558-4562`) — so drawing
/// that screen over a live preview would have been a lie in the interface, not
/// a compromise. And the change moves the permission prompt
/// LATER, to the moment the user explicitly asks for it, which is the safer
/// direction to be wrong in.
class CoachPhaseController extends Notifier<CoachSessionState> {
  @override
  CoachSessionState build() =>
      CoachSessionState(phase: ref.watch(coachInitialPhaseProvider));

  /// The user has read the intro card and is going on to choose a movement.
  ///
  /// Does NOT open the camera — that is the whole point of the phase it moves
  /// to. The page still asks for the camera PERMISSION here, because the intro
  /// card is where the reason for it is written down; the hardware itself
  /// waits for [openCamera].
  void continueToSelection() =>
      state = state.copyWith(phase: CoachPhase.selection);

  /// The user has chosen a movement and pressed the start button.
  ///
  /// Only moves the phase. Actually opening the camera belongs to the page,
  /// which owns the service handle and the lifecycle token — a Notifier that
  /// reached for hardware would also have to own tearing it down.
  void openCamera() => state = state.copyWith(phase: CoachPhase.qualityCheck);

  /// Back out of the live screen without leaving the coach.
  ///
  /// Operator, point 3: «если нажать назад то попадёшь на страницу выбора
  /// упражнений с роликами». The blocker is reset with the phase — it
  /// describes a camera that is about to be stopped, and carrying it onto a
  /// screen with no camera would have the selection screen explaining why a
  /// view it is not showing is unusable.
  void backToSelection() =>
      state = const CoachSessionState(phase: CoachPhase.selection);

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
