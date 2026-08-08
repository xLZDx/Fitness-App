import '../../workouts/data/workout_session.dart';

/// The heaviest thing a person has lifted on one exercise, and when.
///
/// ## Why this is a measurement and not an estimate
///
/// The usual way to compare sets across different rep counts is a one-rep-max
/// formula — Epley, Brzycki, Lombardi. Every one of them is a model fitted to
/// somebody else's population, and a "record" produced by one is a number the
/// user has never actually lifted. This app already refuses to invent a body
/// weight for an unweighted set (`day_result.dart`); inventing a lift would be
/// the same mistake with a trophy on it.
///
/// So a record is the heaviest weight actually recorded for that exercise.
/// Reps are carried alongside because 85 kg for 8 and 85 kg for 1 are not the
/// same achievement, and ties at the same weight go to the higher rep count —
/// which is the direction a person actually improves in between weight jumps.
class PersonalRecord {
  const PersonalRecord({
    required this.exerciseId,
    required this.exerciseTitle,
    required this.weightKg,
    required this.reps,
    required this.achievedAt,
  });

  final String exerciseId;
  final String exerciseTitle;
  final double weightKg;
  final int reps;
  final DateTime achievedAt;

  /// True when this beats [other] — heavier, or the same weight for more reps.
  bool beats(PersonalRecord other) =>
      weightKg > other.weightKg ||
      (weightKg == other.weightKg && reps > other.reps);
}

/// One week's worth of work.
class WeeklyVolume {
  const WeeklyVolume({
    required this.weekStart,
    required this.volumeKg,
    required this.sessions,
  });

  /// Monday of the week, at midnight local.
  final DateTime weekStart;
  final double volumeKg;
  final int sessions;
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Monday of [t]'s week. ISO weeks, so the chart does not shift by locale.
DateTime weekStartOf(DateTime t) {
  final d = _dayOf(t);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

Iterable<WorkoutSession> _completed(List<WorkoutSession> sessions) =>
    sessions.where((s) => s.status == WorkoutSessionStatus.completed);

/// Weight actually moved in one session: `weight × reps` over every set that
/// recorded both. A set without a weight contributes nothing — same rule as
/// [DayResult], and for the same reason.
double sessionVolume(WorkoutSession s) {
  var total = 0.0;
  for (final e in s.exercises) {
    for (final set in e.sets) {
      final w = set.weightKg;
      final r = set.reps;
      if (w != null && r != null) total += w * r;
    }
  }
  return total;
}

/// The last [weeks] weeks ending with the week [now] falls in, oldest first.
///
/// Weeks with no training are present with zero rather than missing: a gap is
/// the most informative bar on the chart, and a chart that silently closes its
/// gaps shows a consistency nobody had.
List<WeeklyVolume> volumeByWeek(
  List<WorkoutSession> sessions,
  DateTime now, {
  int weeks = 8,
}) {
  final thisWeek = weekStartOf(now);
  final buckets = <DateTime, ({double volume, int count})>{
    for (var i = weeks - 1; i >= 0; i--)
      thisWeek.subtract(Duration(days: 7 * i)): (volume: 0.0, count: 0),
  };

  for (final s in _completed(sessions)) {
    final w = weekStartOf(s.startedAt);
    final b = buckets[w];
    if (b == null) continue; // older than the window
    buckets[w] =
        (volume: b.volume + sessionVolume(s), count: b.count + 1);
  }

  return [
    for (final e in buckets.entries)
      WeeklyVolume(
        weekStart: e.key,
        volumeKg: e.value.volume,
        sessions: e.value.count,
      ),
  ];
}

/// Change in volume between the last four weeks and the four before them, as a
/// fraction (`0.18` for the design's "+18% за месяц").
///
/// Null when the earlier period moved no weight at all: a percentage against
/// zero is either infinity or a lie, and "+∞% за месяц" is not a compliment.
double? volumeTrend(List<WorkoutSession> sessions, DateTime now) {
  final byWeek = volumeByWeek(sessions, now, weeks: 8);
  final earlier =
      byWeek.take(4).fold(0.0, (sum, w) => sum + w.volumeKg);
  final recent =
      byWeek.skip(4).fold(0.0, (sum, w) => sum + w.volumeKg);
  if (earlier <= 0) return null;
  return (recent - earlier) / earlier;
}

/// One entry per day of [month]'s calendar month: how many sessions were
/// completed that day.
///
/// Days in the future are included as zero rather than omitted, so the chart
/// keeps the shape of a month instead of growing a bar at a time.
List<int> monthActivity(List<WorkoutSession> sessions, DateTime month) {
  final days = DateTime(month.year, month.month + 1, 0).day;
  final out = List<int>.filled(days, 0);
  for (final s in _completed(sessions)) {
    final d = _dayOf(s.startedAt);
    if (d.year == month.year && d.month == month.month) out[d.day - 1]++;
  }
  return out;
}

/// The best set on record for every exercise that has one, keyed by exercise.
///
/// Only sets that recorded BOTH a weight and reps can hold a record: "heaviest
/// ever" over sets where the weight is unknown would be a ranking of what the
/// user bothered to type in.
Map<String, PersonalRecord> personalRecords(List<WorkoutSession> sessions) {
  final best = <String, PersonalRecord>{};
  for (final s in _completed(sessions)) {
    for (final e in s.exercises) {
      for (final set in e.sets) {
        final w = set.weightKg;
        final r = set.reps;
        if (w == null || r == null || w <= 0) continue;
        final candidate = PersonalRecord(
          exerciseId: e.exerciseId,
          exerciseTitle: e.exerciseTitle,
          weightKg: w,
          reps: r,
          achievedAt: s.startedAt,
        );
        final current = best[e.exerciseId];
        if (current == null || candidate.beats(current)) {
          best[e.exerciseId] = candidate;
        }
      }
    }
  }
  return best;
}

/// Records whose best-ever set was achieved on or after [since], newest first.
///
/// This is the honest reading of the design's "3 рекорда": three exercises
/// whose standing record was set this month. A count of "every set that beat
/// the previous one" would grow by one every time a beginner adds 2.5 kg, and
/// would say nothing about where they now stand.
List<PersonalRecord> recentRecords(
  List<WorkoutSession> sessions,
  DateTime since,
) {
  final records = personalRecords(sessions).values
      .where((r) => !r.achievedAt.isBefore(since))
      .toList()
    ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
  return records;
}
