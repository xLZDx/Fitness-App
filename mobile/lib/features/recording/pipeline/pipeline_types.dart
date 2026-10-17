/// The public input and event types of the recording sample pipeline (S04
/// design 3). Pure Dart, no Flutter imports, no I/O.
///
/// Time never comes from a clock: every instant is an integer offset in
/// milliseconds from the recording start, supplied by the caller (the fix
/// timestamp minus the start time, or the recorder's own offset for a tick).
library;

/// One location fix after the adapter dropped bearing, provider name,
/// satellite count and device ids (S04-R-007). It is both the pipeline input
/// and the kept sample that goes into the journal.
class PipelineSample {
  const PipelineSample({
    required this.offsetMs,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    this.altitudeM,
    this.speedMps,
  });

  /// Milliseconds from the recording start. A kept sample is strictly greater
  /// than the previous kept one.
  final int offsetMs;
  final double lat;
  final double lon;

  /// Horizontal accuracy in metres; null when the provider gave none (the gate
  /// then rejects the fix).
  final double? accuracyM;

  /// Altitude in metres, when present.
  final double? altitudeM;

  /// Provider speed in m/s, when present.
  final double? speedMps;

  PipelineSample copyWith({double? lat, double? lon}) => PipelineSample(
        offsetMs: offsetMs,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        accuracyM: accuracyM,
        altitudeM: altitudeM,
        speedMps: speedMps,
      );

  @override
  bool operator ==(Object other) =>
      other is PipelineSample &&
      other.offsetMs == offsetMs &&
      other.lat == lat &&
      other.lon == lon &&
      other.accuracyM == accuracyM &&
      other.altitudeM == altitudeM &&
      other.speedMps == speedMps;

  @override
  int get hashCode =>
      Object.hash(offsetMs, lat, lon, accuracyM, altitudeM, speedMps);

  @override
  String toString() =>
      'PipelineSample(t=$offsetMs, lat=$lat, lon=$lon, acc=$accuracyM)';
}

/// Why the gate rejected a fix (S04-R-008). Rejected fixes are not journaled;
/// only the counts are kept.
enum RejectReason {
  /// Latitude or longitude is not finite or out of range.
  invalid,

  /// Accuracy is missing, not finite, or above the limit.
  accuracy,

  /// The speed implied by the previous kept fix is above the limit.
  speed,

  /// The offset is not strictly greater than the last kept offset.
  nonMonotonic,
}

/// The four integer reject counters (design 3.3). They are the only trace of a
/// rejected fix and appear only as integers in a batch frame and in logs.
class GateCounters {
  const GateCounters({
    this.accuracy = 0,
    this.speed = 0,
    this.invalid = 0,
    this.nonMonotonic = 0,
  });

  static const GateCounters zero = GateCounters();

  final int accuracy;
  final int speed;
  final int invalid;
  final int nonMonotonic;

  int get total => accuracy + speed + invalid + nonMonotonic;

  GateCounters plus(RejectReason r) => GateCounters(
        accuracy: accuracy + (r == RejectReason.accuracy ? 1 : 0),
        speed: speed + (r == RejectReason.speed ? 1 : 0),
        invalid: invalid + (r == RejectReason.invalid ? 1 : 0),
        nonMonotonic: nonMonotonic + (r == RejectReason.nonMonotonic ? 1 : 0),
      );

  @override
  bool operator ==(Object other) =>
      other is GateCounters &&
      other.accuracy == accuracy &&
      other.speed == speed &&
      other.invalid == invalid &&
      other.nonMonotonic == nonMonotonic;

  @override
  int get hashCode => Object.hash(accuracy, speed, invalid, nonMonotonic);

  @override
  String toString() =>
      'GateCounters(accuracy=$accuracy, speed=$speed, invalid=$invalid, '
      'nonMonotonic=$nonMonotonic)';
}

/// Why a gap was opened.
enum GapCause {
  /// No fix was kept for the poor-accuracy time (S04-R-009).
  noFix,

  /// The gate dropped a bad anchor and re-anchored (design 3.3).
  reanchor,
}

/// A closed or open time span `[startMs, endMs]` in recording offsets. An open
/// span has a null [endMs] and runs to the end of the recording.
class TrackInterval {
  const TrackInterval(this.startMs, [this.endMs]);

  final int startMs;
  final int? endMs;

  @override
  bool operator ==(Object other) =>
      other is TrackInterval && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'TrackInterval($startMs, $endMs)';
}

/// What the pipeline reports to the recorder. The recorder journals the
/// events and maps them to journal frames; the pipeline never writes.
sealed class PipelineEvent {
  const PipelineEvent(this.offsetMs);

  /// The offset the event is about, in recording milliseconds. For
  /// [AutoPaused] and [AutoResumed] this can lie before the sample that caused
  /// the event (the span starts where the speed first crossed the threshold).
  final int offsetMs;
}

/// The first fix passed the gate: acquiring ends (S04-R-009).
final class FirstFixAcquired extends PipelineEvent {
  const FirstFixAcquired(super.offsetMs);
}

/// A fix passed the gate: journal [sample] (raw, unsmoothed).
final class FixKept extends PipelineEvent {
  FixKept(this.sample) : super(sample.offsetMs);

  final PipelineSample sample;
}

/// A fix was rejected: count only, never journaled.
final class FixRejected extends PipelineEvent {
  const FixRejected(super.offsetMs, this.reason);

  final RejectReason reason;
}

/// A gap starts (journal event `gapStart`). [offsetMs] is the offset of the
/// last kept fix. Poor accuracy is on from here until [GapEnded].
final class GapStarted extends PipelineEvent {
  const GapStarted(super.offsetMs, this.cause);

  final GapCause cause;
}

/// The gap ends on the next kept fix (journal event `gapEnd`).
final class GapEnded extends PipelineEvent {
  const GapEnded(super.offsetMs);
}

/// Auto-pause entered (journal event `autoPause`). [offsetMs] is where the
/// speed first fell below the threshold; [detectedAtMs] is the offset of the
/// sample that confirmed it.
final class AutoPaused extends PipelineEvent {
  const AutoPaused(super.offsetMs, this.detectedAtMs);

  final int detectedAtMs;
}

/// Auto-pause left (journal event `autoResume`). [offsetMs] is where the speed
/// first reached the resume threshold; [detectedAtMs] is the offset of the
/// confirming sample. [closedByManualPause] is true when a manual pause ended
/// the span instead of movement (then both offsets are the manual pause
/// offset).
final class AutoResumed extends PipelineEvent {
  const AutoResumed(super.offsetMs, this.detectedAtMs,
      {this.closedByManualPause = false});

  final int detectedAtMs;
  final bool closedByManualPause;
}
