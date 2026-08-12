import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../data/coach_phases.dart';
import '../state/coach_phase_providers.dart';

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
/// ## Absent once the set is running
///
/// Deliberately: an instruction band over a live set competes with the cue
/// card, which is the thing the user is meant to be reading mid-rep.
class CoachReadinessBand extends ConsumerWidget {
  const CoachReadinessBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachSessionProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final text = switch (state.phase) {
      CoachPhase.qualityCheck => state.blocker == CoachBlocker.none
          ? l10n.coachCheckingView
          : _blockerText(l10n, state.blocker),
      CoachPhase.ready => l10n.coachReady,
      // Launch, preparation, calibration, active, paused and summary say
      // nothing here. Calibration is in the enum but never entered — see
      // `phaseAfterFrame`'s doc for why this app does not fake a settling bar.
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();

    final settled = state.phase == CoachPhase.ready;

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

  static String _blockerText(AppLocalizations l10n, CoachBlocker b) =>
      switch (b) {
        CoachBlocker.noBody => l10n.coachBlockerNoBody,
        CoachBlocker.cropped => l10n.coachBlockerCropped,
        CoachBlocker.tooFar => l10n.coachBlockerTooFar,
        CoachBlocker.sensorBug => l10n.coachBlockerSensor,
        CoachBlocker.none => l10n.coachCheckingView,
      };
}
