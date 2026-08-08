import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_phases.dart';
import '../data/pose_gate.dart';
import 'form_check_providers.dart';

/// Where the coached session is, and why the view is unusable when it is.
class CoachSessionState {
  const CoachSessionState({
    this.phase = CoachPhase.qualityCheck,
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
/// Starts at [CoachPhase.qualityCheck] rather than [CoachPhase.launch]: this
/// app opens the camera on arrival (`form_check_page.dart`'s start lifecycle,
/// which nine tests pin deliberately), so by the time this controller exists
/// there is already a frame stream to judge. Gating the camera behind an intro
/// screen changes WHEN the camera opens, and that wants verification on a real
/// device before it ships — see R11h in
/// `core/plans/PLAN_R11_FIGMA_PARITY_REBUILD_2026-08-08.md`.
class CoachPhaseController extends Notifier<CoachSessionState> {
  @override
  CoachSessionState build() => const CoachSessionState();

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
