import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/workout_log.dart';

/// Auto-deload signal. Pure function on the user's recent history +
/// scheduled sessions. The marketing line is *"Other apps push you
/// harder. We're the only one that knows when to pull you back."* —
/// no top-20 incumbent ships this combination today.
///
/// Inputs combine three orthogonal signals:
///   1. **Difficulty trend** — average of the last 7 ratings. > 0.4
///      means most sessions felt too hard (tooHard = +1, justRight = 0,
///      tooEasy = -1).
///   2. **Compliance trend** — fraction of scheduled sessions in the
///      last 14 days the user actually completed. < 0.7 = falling off.
///   3. **Optional HRV trend** — when wearable data is available, the
///      7-day rolling-average HRV vs the 30-day baseline. < 0.92 =
///      meaningful drop.
///
/// Two of three signals trigger a deload recommendation. HRV is
/// optional because most users won't have a wearable on day one.
class DeloadVerdict {
  const DeloadVerdict({
    required this.shouldDeload,
    required this.reasons,
    required this.suggestedVolumeFactor,
  });

  /// True when the detector recommends a deload week.
  final bool shouldDeload;

  /// Human-readable reasons that triggered the recommendation, in order
  /// of magnitude. Empty when [shouldDeload] is false.
  final List<String> reasons;

  /// Factor to multiply the next 7 days' volume by. 0.5 = half-volume
  /// recovery week; 1.0 = no change.
  final double suggestedVolumeFactor;
}

DeloadVerdict detectDeload({
  required List<WorkoutLogEntry> recentLogs,
  required List<ScheduledSession> scheduledLast14Days,
  double? hrvCurrent7DayAvg,
  double? hrvBaseline30DayAvg,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final reasons = <String>[];

  // Signal 1: average difficulty over last 7 rated logs.
  final ratedLogs = recentLogs
      .where((l) => l.difficulty != null)
      .toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  final last7 = ratedLogs.take(7).toList();
  final tooHardSignal = last7.length >= 3 &&
      _avg(last7.map((l) => l.difficulty!.score.toDouble())) > 0.4;
  if (tooHardSignal) {
    reasons.add(
      'Last ${last7.length} workouts averaged "too hard" — your body is asking for a break.',
    );
  }

  // Signal 2: compliance over last 14 scheduled days. Only counts past
  // due (scheduled before now) so future schedules don't bias the ratio.
  final pastDue = scheduledLast14Days
      .where((s) =>
          s.status == ScheduledSessionStatus.pending &&
          s.scheduledFor.isBefore(t))
      .toList();
  final completed = scheduledLast14Days
      .where((s) => s.status == ScheduledSessionStatus.completed)
      .toList();
  final totalScheduled = pastDue.length + completed.length;
  double complianceRatio = 1.0;
  if (totalScheduled >= 5) {
    complianceRatio = completed.length / totalScheduled;
    if (complianceRatio < 0.7) {
      reasons.add(
        'You missed ${pastDue.length} of $totalScheduled scheduled sessions in the last 2 weeks.',
      );
    }
  }
  final complianceSignal = totalScheduled >= 5 && complianceRatio < 0.7;

  // Signal 3 (optional): HRV trend.
  bool hrvSignal = false;
  if (hrvCurrent7DayAvg != null &&
      hrvBaseline30DayAvg != null &&
      hrvBaseline30DayAvg > 0) {
    final ratio = hrvCurrent7DayAvg / hrvBaseline30DayAvg;
    if (ratio < 0.92) {
      hrvSignal = true;
      reasons.add(
        'HRV is ${((1 - ratio) * 100).toStringAsFixed(0)}% below your 30-day baseline — recovery is lagging.',
      );
    }
  }

  // Two-of-three trigger.
  final triggeredCount = (tooHardSignal ? 1 : 0) +
      (complianceSignal ? 1 : 0) +
      (hrvSignal ? 1 : 0);

  if (triggeredCount >= 2) {
    return DeloadVerdict(
      shouldDeload: true,
      reasons: List.unmodifiable(reasons),
      suggestedVolumeFactor: 0.5,
    );
  }
  return const DeloadVerdict(
    shouldDeload: false,
    reasons: [],
    suggestedVolumeFactor: 1.0,
  );
}

double _avg(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}
