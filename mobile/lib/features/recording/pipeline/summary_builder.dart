/// Builds the session summary at finish (S04-R-036, design 3.8). Pure Dart, no
/// Flutter imports, no I/O.
library;

import '../../activity/data/activity_summary.dart';
import '../../activity/data/activity_versions.dart';
import '../../activity/data/summary_fields.dart';
import 'recorded_track.dart';
import 'recording_constants.dart';

/// The result of [buildSessionSummary]. When any value is outside the S02
/// bounds the session is flagged: [summary] is null and nothing is written
/// clamped.
class SessionSummaryResult {
  const SessionSummaryResult({
    required this.metrics,
    required this.startUtc,
    required this.endUtc,
    required this.movingTimeS,
    required this.elapsedS,
    required this.formulaVersion,
    required this.metricDefinitionVersion,
    required this.summary,
    required this.flaggedFields,
  });

  final SessionMetrics metrics;
  final DateTime startUtc;
  final DateTime endUtc;
  final double movingTimeS;
  final double elapsedS;

  /// `<calculator prefix>.<smoothing id>`, at most 32 characters.
  final String formulaVersion;

  /// The S02 constant, kept as is.
  final String metricDefinitionVersion;

  /// Distance, ascent, descent and average speed; null when [flagged].
  final ActivitySummary? summary;

  /// Names of the values that failed the S02 bounds or version shape.
  final List<String> flaggedFields;

  bool get flagged => flaggedFields.isNotEmpty;
}

/// Calculates [track] and checks every value against the S02 bounds
/// (`kSummaryNumericBounds`, `kVersionStringPattern`). Elapsed time is
/// `endUtc - startUtc`.
SessionSummaryResult buildSessionSummary({
  required RecordedTrack track,
  required DateTime startUtc,
  SessionCalculator calculator = const SessionCalculator(),
}) {
  final m = calculator.compute(track);
  final start = startUtc.toUtc();
  final end = start.add(Duration(milliseconds: track.elapsedMs));
  final formula = '$kCalculatorVersionPrefix.${m.smoothingId}';

  final flagged = <String>[];
  void check(String name, double? v) {
    if (v == null) return;
    final b = kSummaryNumericBounds[name];
    if (b == null || !b.accepts(v)) flagged.add(name);
  }

  check('distanceM', m.distanceM);
  check('ascentM', m.ascentM);
  check('descentM', m.descentM);
  check('avgSpeedMps', m.avgSpeedMps);
  check('movingTimeS', m.movingTimeS);
  if (formula.length > kMaxVersionStringLength ||
      !kVersionStringPattern.hasMatch(formula)) {
    flagged.add('formulaVersion');
  }

  return SessionSummaryResult(
    metrics: m,
    startUtc: start,
    endUtc: end,
    movingTimeS: m.movingTimeS,
    elapsedS: m.elapsedS,
    formulaVersion: formula,
    metricDefinitionVersion: kMetricDefinitionVersion,
    summary: flagged.isEmpty
        ? ActivitySummary(
            distanceM: m.distanceM,
            ascentM: m.ascentM,
            descentM: m.descentM,
            avgSpeedMps: m.avgSpeedMps,
          )
        : null,
    flaggedFields: List.unmodifiable(flagged),
  );
}
