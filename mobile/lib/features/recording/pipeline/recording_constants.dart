/// Every tunable number of the recording sample pipeline (S04 design 3). Pure
/// Dart, no Flutter imports, no I/O.
///
/// All values are PROPOSED (Req S04-R-006 .. S04-R-034): none is measured on a
/// device yet. The replay fixtures decide, not opinion. The constants are
/// overridable only through [PipelineConfig], which tests construct directly.
library;

import '../../activity/data/sport_type.dart';

/// Requested fix interval while recording or auto-paused (S04-R-006). The
/// location adapter applies it; the pipeline never reads a clock.
const int kSamplingIntervalMs = 1000;

/// Interval at battery critical (S04-R-030), applied by the adapter.
const int kBatteryCriticalIntervalMs = 5000;

/// Reduced interval during a manual pause (S04-R-057), applied by the adapter.
const int kManualPauseIntervalMs = 10000;

/// After this long in manual pause the recorder raises a prompt (S04-R-057).
/// Used by the recorder state, not by the pipeline.
const int kManualPausePromptAfterMs = 30 * 60 * 1000;

/// Accuracy gate (S04-R-008): kept when accuracy is at most this (30.0 kept,
/// 30.1 rejected).
const double kGateMaxAccuracyM = 30.0;

/// Accuracy gate: kept when the speed implied by the previous kept fix is at
/// most this.
const double kGateMaxImpliedSpeedMps = 30.0;

/// Bad-anchor recovery (design 3.3): after this many consecutive speed-only
/// rejections ...
const int kReanchorMinRejects = 5;

/// ... or after this much time spanned by speed-only rejections, the gate
/// drops its anchor and re-anchors.
const int kReanchorMinSpanMs = 30000;

/// Poor accuracy (S04-R-009): no kept fix for this long opens a gap.
const int kPoorAccuracyAfterMs = 10000;

/// Smoothing `smooth-wma5-1` (design 3.5): the window covers this many fixes on
/// each side of the centre (so 5 in total).
const int kSmoothingWindowRadius = 2;

/// Smoothing never moves a point further than this from its raw position
/// (S04-R-011).
const double kSmoothingMaxDisplacementM = 15.0;

/// Lower bound for an accuracy used as a weight divisor (metres), so a reported
/// accuracy of 0 cannot produce an infinite weight.
const double kSmoothingMinAccuracyM = 1.0;

/// Algorithm id of the smoothing step; part of `formulaVersion`.
const String kSmoothingAlgorithmId = 'smooth-wma5-1';

/// Prefix of the calculator version in `formulaVersion` (distance, pace,
/// elevation rules). The full string is `<prefix>.<smoothing id>` and must stay
/// within `kMaxVersionStringLength` (32).
const String kCalculatorVersionPrefix = 'rec1';

/// Auto-pause (S04-R-012): enter when speed stays below this ...
const double kAutoPauseBelowSpeedMps = 0.5;

/// ... for this long ...
const int kAutoPauseEnterAfterMs = 8000;

/// ... and leave when speed is at least this ...
const double kAutoResumeSpeedMps = 1.0;

/// ... for this long.
const int kAutoResumeAfterMs = 3000;

/// Mean Earth radius for great-circle distance (design 3.7).
const double kMeanEarthRadiusM = 6371008.8;

/// Trailing window of moving time for the current pace (S04-R-033).
const int kPaceWindowMs = 10000;

/// Pace is undefined while moving distance is below this (S04-R-033).
const double kPaceMinMovingDistanceM = 10.0;

/// Elevation (S04-R-034, design 3.7): running median over this many kept
/// altitudes ...
const int kAltitudeMedianWindow = 5;

/// ... a step above this many metres per second between consecutive medians is
/// an outlier and ignored ...
const double kAltitudeMaxStepMps = 10.0;

/// ... after this many consecutive outliers the new level is accepted (a real
/// level change, for example after a gap, must not freeze the calculator) ...
const int kAltitudeOutlierAcceptAfter = 5;

/// ... and a change counts only after the altitude moves this far from the last
/// counted level.
const double kAltitudeHysteresisM = 3.0;

/// Auto-pause default per sport (S04-R-012): on for exactly walk, run and ride,
/// off for every other sport value. The user can switch it off.
bool autoPauseDefaultOn(SportType sport) =>
    sport == SportType.walking ||
    sport == SportType.running ||
    sport == SportType.cycling;

/// The pipeline thresholds as one value, so replay tests can override a number
/// without touching the constants. The defaults are the constants above.
class PipelineConfig {
  const PipelineConfig({
    this.maxAccuracyM = kGateMaxAccuracyM,
    this.maxImpliedSpeedMps = kGateMaxImpliedSpeedMps,
    this.reanchorMinRejects = kReanchorMinRejects,
    this.reanchorMinSpanMs = kReanchorMinSpanMs,
    this.poorAccuracyAfterMs = kPoorAccuracyAfterMs,
    this.autoPauseBelowSpeedMps = kAutoPauseBelowSpeedMps,
    this.autoPauseEnterAfterMs = kAutoPauseEnterAfterMs,
    this.autoResumeSpeedMps = kAutoResumeSpeedMps,
    this.autoResumeAfterMs = kAutoResumeAfterMs,
    this.paceWindowMs = kPaceWindowMs,
    this.paceMinMovingDistanceM = kPaceMinMovingDistanceM,
  });

  final double maxAccuracyM;
  final double maxImpliedSpeedMps;
  final int reanchorMinRejects;
  final int reanchorMinSpanMs;
  final int poorAccuracyAfterMs;
  final double autoPauseBelowSpeedMps;
  final int autoPauseEnterAfterMs;
  final double autoResumeSpeedMps;
  final int autoResumeAfterMs;
  final int paceWindowMs;
  final double paceMinMovingDistanceM;
}
