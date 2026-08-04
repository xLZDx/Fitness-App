import '../../workouts/data/workout_log.dart';
import '../../workouts/data/workout_log_totals.dart';

/// Aggregated progress numbers derived from a [WorkoutLogEntry] history.
/// All math lives here so the page widget stays a thin renderer and the
/// derivations are unit-testable without spinning up Flutter.
class ProgressStats {
  const ProgressStats({
    required this.total,
    required this.thisWeek,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.last8Weeks,
  });

  final int total;
  final int thisWeek;
  final int currentStreakDays;
  final int longestStreakDays;

  /// Workouts per week, oldest → newest, length 8. Index 7 is "this week".
  final List<int> last8Weeks;

  static const empty = ProgressStats(
    total: 0,
    thisWeek: 0,
    currentStreakDays: 0,
    longestStreakDays: 0,
    last8Weeks: [0, 0, 0, 0, 0, 0, 0, 0],
  );
}

/// Day-bucket for [t] — keyed in UTC so [Duration.inDays] math is immune to
/// DST transitions while preserving the user's local-day notion of "today".
DateTime _dayOf(DateTime t) {
  final local = t.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// Monday of the week that contains [t], expressed in UTC midnight so the
/// difference in days between two week starts is always exactly 7.
DateTime _weekStart(DateTime t) {
  final d = _dayOf(t);
  // weekday: Monday = 1, Sunday = 7. The local→UTC conversion above already
  // happened, so .weekday on the UTC result is the user-local weekday.
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Progress numbers for a history [logs], newest first.
///
/// [logs] is the recent window the listener carries, not the full history —
/// see `kWorkoutHistoryWindow`. Everything derived from recent activity
/// (this week, the 8-week chart, the current streak) is answered from it
/// correctly, because none of those reach further back than the window does.
///
/// [totals] supplies the two that are genuinely all-time. Passing null keeps
/// the old behaviour of deriving them from [logs], which is right for a caller
/// that really does hold everything — a test, or a user whose history fits
/// inside the window — and wrong for anyone else, which is why the production
/// call sites pass it.
ProgressStats deriveProgress(
  List<WorkoutLogEntry> logs, {
  DateTime? now,
  WorkoutLogTotals? totals,
}) {
  if (logs.isEmpty) {
    // Not necessarily an empty history: a signed-in user whose window has not
    // arrived yet still has a total, and showing 0 where their real count
    // belongs is the flicker this branch exists to avoid.
    return totals == null
        ? ProgressStats.empty
        : ProgressStats(
            total: totals.total,
            thisWeek: 0,
            currentStreakDays: 0,
            longestStreakDays: totals.longestStreakDays,
            last8Weeks: const [0, 0, 0, 0, 0, 0, 0, 0],
          );
  }
  final today = _dayOf(now ?? DateTime.now());

  // Unique workout days (any number of workouts on the same day → one day).
  final daySet = <DateTime>{};
  for (final l in logs) {
    daySet.add(_dayOf(l.completedAt));
  }
  final days = daySet.toList()..sort();

  // Current streak: walk back day-by-day from today (or yesterday if user
  // hasn't worked out yet today) and count consecutive day matches.
  int current = 0;
  DateTime cursor = today;
  if (!daySet.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while (daySet.contains(cursor)) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  // Longest streak: scan the sorted days array.
  int longest = 0;
  int run = 0;
  DateTime? prev;
  for (final d in days) {
    if (prev != null && d.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > longest) longest = run;
    prev = d;
  }

  // This-week count: logs since the local Monday of [today].
  final monday = _weekStart(today);
  final thisWeek = logs.where((l) {
    final d = _dayOf(l.completedAt);
    return !d.isBefore(monday);
  }).length;

  // Last 8 weeks of counts (oldest → newest, index 7 = this week).
  final buckets = List<int>.filled(8, 0);
  for (final l in logs) {
    final w = _weekStart(l.completedAt);
    final weeksAgo = monday.difference(w).inDays ~/ 7;
    if (weeksAgo < 0 || weeksAgo > 7) continue;
    buckets[7 - weeksAgo]++;
  }

  final record = totals?.longestStreakDays ?? 0;

  return ProgressStats(
    // All-time when we have it. `logs.length` is the window size for anyone
    // whose history outgrew it, and rendering that as "workouts" would tell a
    // three-year customer they had done 200.
    total: totals?.total ?? logs.length,
    thisWeek: thisWeek,
    currentStreakDays: current,
    // The record beats the window: a streak set before the window begins is
    // still the record, and `longest` here can only see what is visible now.
    longestStreakDays: longest > record ? longest : record,
    last8Weeks: List.unmodifiable(buckets),
  );
}
