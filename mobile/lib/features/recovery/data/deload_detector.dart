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
/// Why the detector reached its verdict — one code per signal, with its
/// numbers.
///
/// F027. These used to be composed English sentences on a `List<String>`, in a
/// pure data layer with no `BuildContext`, and `deload_banner.dart` rendered
/// `reasons.first` straight into a `Text`. A Russian user was told *"Last 7
/// workouts averaged 'too hard' — your body is asking for a break"* in English.
///
/// The same shape as `PlanReason`, deliberately: a sealed hierarchy switched
/// over at the presentation boundary, so a new signal cannot be added without
/// the renderer failing to compile.
sealed class DeloadSignal {
  const DeloadSignal();
}

/// The last [count] rated workouts averaged "too hard".
final class HardSessionsSignal extends DeloadSignal {
  const HardSessionsSignal(this.count);
  final int count;
}

/// [missed] of [scheduled] sessions in the last two weeks were not done.
final class MissedSessionsSignal extends DeloadSignal {
  const MissedSessionsSignal(this.missed, this.scheduled);
  final int missed;
  final int scheduled;
}

/// HRV is [percentBelow]% under the 30-day baseline.
final class HrvBelowBaselineSignal extends DeloadSignal {
  const HrvBelowBaselineSignal(this.percentBelow);
  final int percentBelow;
}

class DeloadVerdict {
  const DeloadVerdict({
    required this.shouldDeload,
    required this.reasons,
    required this.suggestedVolumeFactor,
  });

  /// True when the detector recommends a deload week.
  final bool shouldDeload;

  /// The signals that triggered the recommendation, in order of magnitude.
  /// Empty when [shouldDeload] is false.
  ///
  /// Codes, not sentences — see [DeloadSignal]. Rendered by
  /// `deload_signal_text.dart`, which has the locale.
  final List<DeloadSignal> reasons;

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
  final reasons = <DeloadSignal>[];

  // Signal 1: average difficulty over last 7 rated logs.
  final ratedLogs = recentLogs
      .where((l) => l.difficulty != null)
      .toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  final last7 = ratedLogs.take(7).toList();
  final tooHardSignal = last7.length >= 3 &&
      _avg(last7.map((l) => l.difficulty!.score.toDouble())) > 0.4;
  if (tooHardSignal) {
    reasons.add(HardSessionsSignal(last7.length));
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
      reasons.add(MissedSessionsSignal(pastDue.length, totalScheduled));
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
      reasons.add(HrvBelowBaselineSignal(((1 - ratio) * 100).round()));
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
