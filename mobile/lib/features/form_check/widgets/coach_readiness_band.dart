import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../data/coach_phases.dart';
import '../data/cue_text.dart';
import '../data/pose_gate.dart';
import '../state/coach_phase_providers.dart';
import '../state/form_check_providers.dart';

/// The design's pre-set stages, drawn over the camera: what is wrong with the
/// view, how far the coach is from settled, and when it is ready
/// (`App.tsx:4188-4197`, phases `quality-check` / `calibration` / `ready`).
///
/// ## What it replaces
///
/// Nothing said any of this. The gate has always known precisely why a frame
/// was unusable — six distinct verdicts — and the screen used that only to
/// withhold a rep count. A user whose hips were outside the frame saw a
/// camera, a skeleton, and no reps, with nothing connecting the three.
///
/// ## The one instruction surface
///
/// This is now the ONLY place on the page that says whether the coach can see
/// you and what to do about it. Three other surfaces used to answer that same
/// question independently, and a screenshot from a real phone caught all three
/// disagreeing in one frame: this band said "Ready. Start when you are.", the
/// cue card at the bottom said "Ready - do a rep.", and the avatar's own centred
/// box said "Can't place your torso — step back so your shoulders and hips are
/// both in view". A fourth line, "stand tall to start counting", sat inside the
/// rep badge directly above.
///
/// They were not contradicting each other by accident. Each read a different
/// signal — `PoseGateVerdict.isScorable`, `blockerFor(verdict)`, and
/// `buildPoseAvatar`'s shoulder-and-hip requirement — and each was locally
/// correct about the signal it read. The gate can say `ok` on a frame the
/// avatar cannot draw, because `SquatDepthClassifier.requiredLandmarks` is hips
/// and knees while a spine needs a shoulder. Nothing was wrong except that all
/// three were rendered at once.
///
/// So the resolution is a priority order in one widget, not three widgets each
/// checking whether the others are talking:
///
/// 1. the gate is blocking — the coach cannot score anything, and the verdict
///    knows WHY in a way nothing below it does;
/// 2. the avatar has a pose and still cannot place a body — the scene the user
///    is looking at is empty;
/// 3. the counter has not armed — the view is fine and the number still cannot
///    move, which is the one state a `0` looks broken in;
/// 4. ready, or still judging the view.
///
/// Rungs 1 and 2 were the other way round until Codex pointed out what that
/// costs. `pose_avatar.dart` drops landmarks outside its coordinate contract,
/// so a frame whose coordinates arrive in the wrong UNITS yields no torso —
/// and the avatar rung answered a sensor fault with "step back so your
/// shoulders and hips are both in view", which no amount of stepping back
/// fixes. The gate has a verdict for that frame and the avatar only has an
/// absence, so the one that can name the cause goes first.
///
/// The cue card keeps only what this cannot say: the verdict on a repetition
/// that has already happened. The two are mutually exclusive by construction,
/// and `coach_single_status_test.dart` holds them to it.
///
/// ## Absent when there is nothing to instruct
///
/// Once the view is usable, the counter is armed and the set is running, this
/// renders nothing — an instruction band over a live set competes with the cue
/// card, which is the thing the user is meant to be reading mid-rep. Rungs 1
/// and 2 are exempt: losing the body mid-set is exactly when the user needs to
/// be told, and before this they were told by a different widget.
class CoachReadinessBand extends ConsumerWidget {
  const CoachReadinessBand({
    super.key,
    this.avatarCannotPlaceBody = false,
    this.waitingForTop = false,
    this.repVerdictShowing = false,
  });

  /// The avatar received a pose and could not build a body from it.
  ///
  /// Passed in rather than read here so this widget keeps working in a bare
  /// harness, and so the page — which already has to know, to decide whether to
  /// paint a figure — is not asked the question twice.
  final bool avatarCannotPlaceBody;

  /// The rep counter has not yet seen the lifter standing at the top, so the
  /// count physically cannot move however hard they work.
  ///
  /// This used to be a second line inside the rep badge. It says something
  /// about whether the coach is ready, which is this band's subject, and having
  /// it directly above "Ready. Start when you are." is how the screen ended up
  /// telling the user both that it was waiting for them and that it was not.
  final bool waitingForTop;

  /// The cue card is currently showing a verdict on a finished repetition.
  ///
  /// Only silences the two rungs that are merely informational — "ready" and
  /// "checking the view". A blocking rung still speaks over a verdict, and the
  /// page stops rendering the cue card in that case, which is what keeps
  /// "exactly one message" true in both directions.
  ///
  /// Without this the screen was quietly wrong in a way that is easy to miss:
  /// once a rep had been counted but the set had not been started, the band
  /// said "Ready. Start when you are." while the card underneath said "Clean
  /// rep". Neither is false; together they are two answers to a question the
  /// user did not ask twice.
  final bool repVerdictShowing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachSessionProvider);
    final verdict = ref.watch(poseGateVerdictProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final (text, key, settled) = _status(l10n, state, verdict);
    if (text == null) return const SizedBox.shrink();

    // Carries no outer margin on purpose. It used to wrap itself in
    // `Padding(all: 12)`, which placed its top-left corner at exactly (12, 12)
    // of whatever it was dropped into -- the same point the rep badge claims
    // with `Positioned(left: 12, top: 12)`. Both were true statements about
    // where each belonged, and together they drew one on top of the other.
    // Where this band sits is the composing screen's business; see
    // `CoachTopStrip`.
    return Container(
      key: const Key('coach.readinessBand'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colors.cameraOverlay,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                settled
                    ? Icons.check_circle_outline_rounded
                    : Icons.center_focus_weak_rounded,
                size: 18,
                color: settled ? theme.colors.success : Colors.white,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  key: key,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The one thing worth saying, its key, and whether it reads as settled.
  ///
  /// Returns a null text when the band should not render at all. The keys are
  /// the ones the surfaces this absorbed already used, so a test that looked
  /// for `form_check.avatar_no_torso` still finds it — in its new home.
  (String?, Key?, bool) _status(
    AppLocalizations l10n,
    CoachSessionState state,
    PoseGateVerdict verdict,
  ) {
    // The gate FIRST, and the avatar only when the gate is happy.
    //
    // The order was the other way round for one round of review, and Codex was
    // right to kill it. `buildPoseAvatar` drops any landmark more than half a
    // unit outside the coordinate contract (`pose_avatar.dart`'s `_drawSlack`),
    // so a `unitMismatch` frame — coordinates in the wrong space entirely —
    // also produces "no torso". With the avatar on top, the screen answered a
    // sensor bug with "step back so your shoulders and hips are both in view":
    // the user steps back forever, having done nothing wrong. That is the exact
    // failure `PoseGateVerdict.unitMismatch` was separated out to prevent, and
    // this rung order is what keeps it prevented.
    if (state.blocker != CoachBlocker.none) {
      // `poseGateHint`, not `blockerFor`. `CoachBlocker` is deliberately coarse
      // — five verdicts collapsed into four instructions — and while the cue
      // card also spoke, the precise sentence still reached the user from
      // there. Now that this band is the only voice, collapsing here would
      // silently downgrade "Too dark or too blurry to read your position" into
      // "Step into frame so your whole body is visible", which is different
      // advice for a different problem.
      final hint = poseGateHint(l10n, verdict);
      return (
        hint.isEmpty ? _blockerText(l10n, state.blocker) : hint,
        const Key('form_check.gate_hint'),
        false,
      );
    }
    if (avatarCannotPlaceBody) {
      return (
        l10n.formcheckAvatarNoTorso,
        const Key('form_check.avatar_no_torso'),
        false,
      );
    }
    // Still spoken mid-set. The view is fine and the number cannot move, which
    // is the one state a frozen `0` looks broken in — `RepSessionState.isArmed`
    // exists for exactly that reason. Dropping it once the set is running
    // would trade one defect for a quieter one.
    //
    // Not while the set is paused or finished, though: `countingIsLiveIn`
    // stops frames reaching the counter in both, so "stand tall to start
    // counting" would be an instruction that cannot work however exactly the
    // user follows it. Standing tall does not arm a counter nothing is
    // feeding.
    if (waitingForTop && countingIsLiveIn(state.phase)) {
      return (
        l10n.formcheckWaitingForTop,
        const Key('form_check.waiting_for_top'),
        false,
      );
    }
    // Below this line nothing is wrong and nothing is being waited for, so
    // nothing here is worth interrupting a running set — or talking over a
    // verdict — for.
    if (!_preSet(state.phase)) return (null, null, false);
    if (repVerdictShowing) return (null, null, false);
    return switch (state.phase) {
      CoachPhase.ready => (l10n.coachReady, const Key('coach.ready'), true),
      CoachPhase.qualityCheck => (
          l10n.coachCheckingView,
          const Key('coach.checking'),
          false,
        ),
      // Launch, calibration, active, paused and summary say
      // nothing here. Calibration is in the enum but never entered — see
      // `phaseAfterFrame`'s doc for why this app does not fake a settling bar.
      _ => (null, null, false),
    };
  }

  /// Whether the user has not yet started the set.
  static bool _preSet(CoachPhase phase) =>
      phase != CoachPhase.active &&
      phase != CoachPhase.paused &&
      phase != CoachPhase.summary;

  static String _blockerText(AppLocalizations l10n, CoachBlocker b) =>
      switch (b) {
        CoachBlocker.noBody => l10n.coachBlockerNoBody,
        CoachBlocker.cropped => l10n.coachBlockerCropped,
        CoachBlocker.tooFar => l10n.coachBlockerTooFar,
        CoachBlocker.sensorBug => l10n.coachBlockerSensor,
        CoachBlocker.none => l10n.coachCheckingView,
      };
}
