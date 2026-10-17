/// Projection of phase and flags onto the 13 S04-D display states (design 5.1,
/// S04-03 AC-2). One pure function in one file, so a change of the S04-D order
/// changes only this file and the table test.
library;

import 'recorder_phase.dart';
import 'recorder_state.dart';

/// The 13 names of S04-D 5.1, in that order.
enum RecorderDisplayState {
  idle,
  acquiring,
  recording,
  poorAccuracy,
  offline,
  pausedManual,
  pausedAuto,
  background,
  restoring,
  recoveryFailed,
  batteryCritical,
  permissionRevoked,
  finished,
}

/// Banner channel, at most one (highest first).
enum RecorderBanner { storageWriteFailing, batteryCritical }

/// Chip channel, at most two.
enum RecorderChip { offline, background }

class RecorderDisplay {
  const RecorderDisplay({
    required this.headline,
    required this.banner,
    required this.chips,
    required this.busy,
  });

  final RecorderDisplayState headline;
  final RecorderBanner? banner;
  final List<RecorderChip> chips;

  /// `preparing` and `stopping` show a busy label on the headline.
  final bool busy;
}

/// The three channels of S04-D 5.3. Headline order, highest first:
/// permissionRevoked, recoveryFailed, restoring, pausedManual, pausedAuto,
/// acquiring, poorAccuracy, recording. `preparing` projects to `idle` with a
/// busy label; `stopping` projects to the headline of the phase it came from,
/// which the state does not keep, so it shows `recording` with a busy label
/// (the UI lane may refine it with its own memory of the previous headline).
RecorderDisplay displayOf(RecorderState s) {
  final headline = switch (s.phase) {
    RecorderPhase.permissionRevoked => RecorderDisplayState.permissionRevoked,
    RecorderPhase.recoveryFailed => RecorderDisplayState.recoveryFailed,
    RecorderPhase.restoring => RecorderDisplayState.restoring,
    RecorderPhase.pausedManual => RecorderDisplayState.pausedManual,
    RecorderPhase.pausedAuto => RecorderDisplayState.pausedAuto,
    RecorderPhase.acquiring => RecorderDisplayState.acquiring,
    RecorderPhase.recording => s.flags.poorAccuracy
        ? RecorderDisplayState.poorAccuracy
        : RecorderDisplayState.recording,
    RecorderPhase.stopping => RecorderDisplayState.recording,
    RecorderPhase.finished => RecorderDisplayState.finished,
    RecorderPhase.idle ||
    RecorderPhase.preparing =>
      RecorderDisplayState.idle,
  };
  final banner = s.flags.storageWriteFailing
      ? RecorderBanner.storageWriteFailing
      : (s.flags.batteryCritical && s.phase.isCollecting
          ? RecorderBanner.batteryCritical
          : null);
  return RecorderDisplay(
    headline: headline,
    banner: banner,
    chips: [
      if (s.flags.offline) RecorderChip.offline,
      if (s.flags.background) RecorderChip.background,
    ],
    busy: s.isBusy,
  );
}
