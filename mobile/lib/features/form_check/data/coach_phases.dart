import 'pose_gate.dart';

/// The stages the design walks a user through before and after a coached set
/// (`App.tsx:4188-4197`).
///
/// ## Why the app needs this at all
///
/// Form Check is one persistent camera panel: it opens the camera on arrival
/// and everything — placement, whether the view is usable, whether the
/// detector has settled, the set itself, the summary — happens in the same
/// undifferentiated screen. The design separates them, and the separation is
/// the point: a user who is told "step back" while a rep counter is already
/// running cannot tell whether the reps behind them counted.
///
/// ## Driven by real signals, not the prototype's timers
///
/// The prototype fakes every stage with `setTimeout` — quality-check walks
/// `['loading','too-dark','wrong-angle','ok']` on a clock, calibration
/// increments a percentage every 60ms. Neither is a measurement. This app
/// already has the real thing: [PoseGateVerdict] says exactly why a frame is
/// unusable, and it says so per frame. So [blockerFor] maps that verdict onto
/// the instruction the design shows, and [advanceCalibration] counts real
/// consecutive usable frames rather than milliseconds.
enum CoachPhase {
  /// What this is and what it will do, how to stand, and what it costs.
  /// Nothing is running.
  ///
  /// Was two stages -- `launch` then `preparation` -- until 2026-09-01, when
  /// the operator asked for one screen. There is nothing left for a second
  /// pre-camera phase to mean, so it is gone rather than kept as a stage the
  /// session passes through without stopping.
  launch,

  /// Which movement, and a looped demonstration of it. The camera is still
  /// off.
  ///
  /// Added 2026-09-01 on the operator's own description of the screen: choose
  /// the exercise, watch the demonstration, and press when ready -- «пока не
  /// нажата кнопка начать камера не включается». It is a phase rather than a
  /// flag on the page because the camera's whole lifecycle keys off the phase
  /// already, and because "back" from the live screen has to land somewhere
  /// nameable.
  selection,

  /// Is the view usable? Blocks until the gate says yes.
  qualityCheck,

  /// The detector has a usable view; hold still while it settles.
  calibration,

  /// Everything is ready; start when you want to.
  ready,

  /// Counting reps and giving cues.
  active,

  /// Stopped mid-set, resumable.
  paused,

  /// What the set was.
  summary,
}

/// What is standing between the user and a usable view, in the user's terms.
///
/// Deliberately coarser than [PoseGateVerdict]: the gate distinguishes six
/// conditions because the RULES need that precision, and a user needs to be
/// told one thing to do. Two verdicts collapse into [noBody] because the
/// action is identical, and one is kept apart from everything else because
/// the action is the opposite — see [sensorBug].
enum CoachBlocker {
  /// Nothing blocking; the frame is scorable.
  none,

  /// No body found, or the detector is guessing at one.
  noBody,

  /// A body, but cut off by the frame edge.
  cropped,

  /// A body, but too small to measure — a close-up, or far too far away.
  tooFar,

  /// The coordinates are not in the contract's space at all. Not the user's
  /// fault and not fixable by moving: "step back" would have them stepping
  /// back until they gave up, having done nothing wrong. See
  /// [PoseGateVerdict.unitMismatch]'s own doc.
  sensorBug,
}

/// Whether repetitions may be counted while the session is in [phase].
///
/// Stated as the two phases that STOP it rather than as `phase == active`, and
/// the difference is load-bearing. `active` is only ever entered by pressing
/// Start, and the count has never required that: the page counts from the
/// moment the view is usable, which is what every existing rep test drives and
/// what a user who just points the phone at themselves expects. Gating on
/// `== active` would have made counting depend on a button that did not exist
/// until this gate — a silent behaviour change dressed as a refactor.
///
/// [CoachPhase.paused] and [CoachPhase.summary] are the two states where the
/// user has SAID the set is not running. Summary is here because a finished
/// set whose numbers keep climbing while it is being read is not a summary of
/// anything — the defect the P2 test caught, one guard short.
bool countingIsLiveIn(CoachPhase phase) =>
    phase != CoachPhase.paused &&
    phase != CoachPhase.summary &&
    // And not on either pre-camera screen. [CoachPhase.selection] is the one
    // that matters: it is reached from the LIVE screen by pressing back, and
    // stopping the camera is asynchronous, so frames already in flight arrive
    // after the phase has moved -- without this they would land on the counter
    // of a set the user has just walked away from.
    //
    // [CoachPhase.launch] is deliberately NOT here, and the attempt to add it
    // "for consistency" is what proved why. Eighteen existing cases across
    // five files drive a real rep stream through a container left at the
    // default phase and assert the count moves -- `paused_set_test`'s own
    // POSITIVE CONTROL among them. `launch` is that default, so excluding it
    // does not tighten a guard, it silently redefines what every one of those
    // tests is exercising. The reachable-bug argument does not apply either:
    // nothing subscribes to the frame stream while the intro card is up,
    // because `form_check_page.dart` returns before
    // `formFeedbackControllerProvider` is ever watched.
    phase != CoachPhase.selection;

/// The instruction that belongs to a gate verdict.
CoachBlocker blockerFor(PoseGateVerdict verdict) {
  return switch (verdict) {
    PoseGateVerdict.ok => CoachBlocker.none,
    PoseGateVerdict.unitMismatch => CoachBlocker.sensorBug,
    PoseGateVerdict.missingJoints || PoseGateVerdict.lowConfidence =>
      CoachBlocker.noBody,
    PoseGateVerdict.outOfFrame => CoachBlocker.cropped,
    PoseGateVerdict.implausibleGeometry => CoachBlocker.tooFar,
  };
}

/// Which phase a verdict moves the session to, from where it is now.
///
/// Only the stages that advance on a MEASUREMENT are here. Everything driven
/// by a tap — launch → qualityCheck, ready → active, active ↔ paused, active →
/// summary — belongs to the controller, because a pure function over a
/// verdict cannot know that a button was pressed.
///
/// ## Why [CoachPhase.calibration] is in the enum and not in this function
///
/// The design has a calibration stage with a percentage that fills. In the
/// prototype that percentage is `setInterval(() => p + 4, 60)` — a clock, not
/// a measurement of anything.
///
/// This app has no settling signal to put behind it. `poseGateVerdictProvider`
/// is a `StateProvider`, so it notifies only when the verdict CHANGES: a
/// steadily-usable view emits nothing, and a bar counting "frames since ok"
/// would have to count timer ticks instead. That is the same theatre, moved
/// into our code — and this project's own rule is that a number the app cannot
/// measure does not get displayed as though it could.
///
/// So a usable view goes straight to [CoachPhase.ready]. The phase stays in
/// the enum because the design has it and because a real settling signal
/// (variance of the detector's own confidence over a window, say) would slot
/// in here without moving anything else.
CoachPhase phaseAfterFrame(CoachPhase phase, PoseGateVerdict verdict) {
  switch (phase) {
    case CoachPhase.qualityCheck:
      return verdict == PoseGateVerdict.ok
          ? CoachPhase.ready
          : CoachPhase.qualityCheck;
    case CoachPhase.ready:
      // Losing the view un-readies: "start when you are" over a frame that
      // cannot be scored is an invitation to a set nothing will count.
      return verdict == PoseGateVerdict.ok
          ? CoachPhase.ready
          : CoachPhase.qualityCheck;
    case CoachPhase.calibration:
    case CoachPhase.launch:
    case CoachPhase.selection:
    case CoachPhase.active:
    case CoachPhase.paused:
    case CoachPhase.summary:
      return phase;
  }
}
