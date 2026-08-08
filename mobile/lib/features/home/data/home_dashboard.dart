import '../../equipment/data/equipment_models.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/workout_log.dart';

/// The arithmetic behind the redesigned Home screen.
///
/// ## Why this file exists
///
/// R11a rebuilds Home against the real Figma Make prototype
/// (`App.tsx`, `HomeScreen`, lines 2441-2548), which shows five things the old
/// screen had no number for: a greeting keyed to the time of day, a plan
/// progress bar, a muscle-recovery strip, a seven-day week strip, and three
/// week totals (workouts / volume / records).
///
/// None of them needed a new entity. Every one is arithmetic over rows the app
/// already stores — which is why it lives here as pure functions rather than
/// inside the widget: the widget stays a renderer, and these stay testable
/// without a Flutter binding, same split as `progress_stats.dart` and
/// `session_digest.dart` already use.
///
/// **What is NOT here, deliberately:** the prototype's header also shows
/// "Силовая база · Неделя 2 из 8" — a multi-week *programme*. No such entity
/// exists in this app: `GeneratedPlan` (`ai_planner/data/workout_plan.dart:4`)
/// is one day's worth of training and carries no week index or horizon.
/// [derivePlanProgress] gives the bar the same shape from data that is real —
/// this week's scheduled sessions and how many are done — rather than printing
/// a week number the app would be inventing.

/// Day-bucket for [t], keyed in UTC so day arithmetic is immune to DST while
/// preserving the user's local-day notion of "today". Same helper, same reason,
/// as `progress_stats.dart:35`.
DateTime _dayOf(DateTime t) {
  final local = t.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// Monday of the week containing [t], as UTC midnight.
DateTime _weekStart(DateTime t) {
  final d = _dayOf(t);
  return d.subtract(Duration(days: d.weekday - 1));
}

// ─────────────────────────────────────────────────────────────────────────────
// Greeting
// ─────────────────────────────────────────────────────────────────────────────

/// Which of the three greetings the header shows.
///
/// An enum rather than a string: the words are localised, and a function that
/// returned "Good evening" could not be shown in Russian.
enum DayGreeting { morning, afternoon, evening }

/// Morning until noon, afternoon until 18:00, evening after.
///
/// Boundaries are local-clock, not UTC — a greeting is about the user's day.
DayGreeting greetingFor(DateTime now) {
  final h = now.toLocal().hour;
  if (h < 12) return DayGreeting.morning;
  if (h < 18) return DayGreeting.afternoon;
  return DayGreeting.evening;
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan progress
// ─────────────────────────────────────────────────────────────────────────────

/// How much of the week's schedule is behind the user.
class PlanProgress {
  const PlanProgress({required this.done, required this.total});

  final int done;
  final int total;

  /// 0.0-1.0. Zero when nothing is scheduled, so a caller that renders the bar
  /// anyway draws an empty one rather than dividing by zero.
  double get fraction => total == 0 ? 0 : done / total;

  /// Whole percent, for the label beside the bar.
  int get percent => (fraction * 100).round();

  /// Nothing scheduled this week — the bar has nothing to say and the caller
  /// hides it. A "0%" bar over an empty schedule reads as failure, not as
  /// "you have not planned anything yet".
  bool get isEmpty => total == 0;

  static const empty = PlanProgress(done: 0, total: 0);
}

/// This week's plan progress, Monday-based.
///
/// Cancelled rows are excluded from BOTH sides: a session the user dismissed is
/// not work outstanding, and counting it would leave the bar permanently short
/// of 100% for anyone who ever cancels one.
PlanProgress derivePlanProgress(
  List<ScheduledSession> scheduled, {
  DateTime? now,
}) {
  final monday = _weekStart(now ?? DateTime.now());
  final sunday = monday.add(const Duration(days: 7));

  var done = 0;
  var total = 0;
  for (final s in scheduled) {
    if (s.status == ScheduledSessionStatus.cancelled) continue;
    final d = _dayOf(s.scheduledFor);
    if (d.isBefore(monday) || !d.isBefore(sunday)) continue;
    total++;
    if (s.status == ScheduledSessionStatus.completed) done++;
  }
  return PlanProgress(done: done, total: total);
}

// ─────────────────────────────────────────────────────────────────────────────
// Muscle recovery
// ─────────────────────────────────────────────────────────────────────────────

/// How rested a muscle group is, by time since it was last trained.
enum RecoveryStatus {
  /// Trained within [kRecoveringHours] — still under repair.
  recovering,

  /// Between [kRecoveringHours] and [kMediumHours].
  medium,

  /// Past [kMediumHours], or never trained inside the history window.
  ready,
}

/// Under a day since the last session that worked this muscle.
const kRecoveringHours = 24;

/// Under two days. The 24/48h split is the ordinary hypertrophy-recovery
/// rule of thumb; it is a display heuristic over training dates, not a
/// physiological measurement, and nothing in the app acts on it.
const kMediumHours = 48;

/// One muscle group's row in the recovery strip.
class MuscleRecovery {
  const MuscleRecovery({
    required this.muscle,
    required this.status,
    required this.hoursSince,
  });

  /// Catalogue muscle key, not a word — the UI localises it via
  /// `CatalogLabels.muscle`, the same way `SessionDigest.muscles` is rendered.
  final String muscle;
  final RecoveryStatus status;

  /// Hours since the most recent session working this muscle.
  final int hoursSince;
}

/// Recovery state per muscle group, most-recently-trained first.
///
/// [logs] is the recent history window, [catalogue] maps exercise id to its
/// muscles. A muscle appears only if the window contains a session that worked
/// it: the alternative is listing every muscle in the catalogue as "ready",
/// which would tell a user who has never trained that they are fully recovered
/// from work they never did.
///
/// Primary muscles where the catalogue names them, else the first listed —
/// the same selection `digestForDay` (`session_digest.dart:84`) makes, so the
/// hero and this strip cannot disagree about what an exercise works.
List<MuscleRecovery> deriveRecovery(
  List<WorkoutLogEntry> logs,
  Map<String, ExerciseItem> catalogue, {
  DateTime? now,
  int max = 6,
}) {
  final n = now ?? DateTime.now();
  final lastTrained = <String, DateTime>{};

  for (final l in logs) {
    final item = catalogue[l.exerciseId];
    if (item == null) continue;
    final primary = item.primaryMuscles.isEmpty
        ? item.muscles.take(1)
        : item.primaryMuscles;
    for (final m in primary) {
      final prev = lastTrained[m];
      if (prev == null || l.completedAt.isAfter(prev)) {
        lastTrained[m] = l.completedAt;
      }
    }
  }

  final rows = <MuscleRecovery>[];
  for (final entry in lastTrained.entries) {
    // Clamped at zero: a log dated slightly in the future (clock skew between
    // a device and Firestore) would otherwise render as negative hours.
    final hours = n.difference(entry.value).inHours;
    final h = hours < 0 ? 0 : hours;
    rows.add(MuscleRecovery(
      muscle: entry.key,
      status: h < kRecoveringHours
          ? RecoveryStatus.recovering
          : h < kMediumHours
              ? RecoveryStatus.medium
              : RecoveryStatus.ready,
      hoursSince: h,
    ));
  }

  rows.sort((a, b) {
    final byTime = a.hoursSince.compareTo(b.hoursSince);
    // Ties broken by name so the strip does not reshuffle between rebuilds
    // when two muscles were trained in the same session.
    return byTime != 0 ? byTime : a.muscle.compareTo(b.muscle);
  });
  return rows.take(max).toList(growable: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Week strip
// ─────────────────────────────────────────────────────────────────────────────

/// One square in the seven-day strip.
class WeekDayCell {
  const WeekDayCell({
    required this.day,
    required this.done,
    required this.scheduled,
    required this.isToday,
  });

  /// UTC-keyed local day, Monday first.
  final DateTime day;

  /// A workout was logged on this day.
  final bool done;

  /// Something is (or was) on the schedule for this day.
  final bool scheduled;

  final bool isToday;

  /// Neither trained nor planned. The prototype draws these dimmer than a
  /// planned-but-unfinished day, which is the distinction the flag carries.
  bool get isRest => !done && !scheduled;
}

/// Monday-to-Sunday view of the current week.
///
/// Cancelled rows do not mark a day as scheduled — see [derivePlanProgress]
/// for why cancellation is treated as removal rather than as a miss.
List<WeekDayCell> deriveWeekStrip(
  List<WorkoutLogEntry> logs,
  List<ScheduledSession> scheduled, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = _dayOf(n);
  final monday = _weekStart(n);

  final doneDays = <DateTime>{for (final l in logs) _dayOf(l.completedAt)};
  final plannedDays = <DateTime>{
    for (final s in scheduled)
      if (s.status != ScheduledSessionStatus.cancelled) _dayOf(s.scheduledFor),
  };

  return List<WeekDayCell>.generate(7, (i) {
    final day = monday.add(Duration(days: i));
    return WeekDayCell(
      day: day,
      done: doneDays.contains(day),
      scheduled: plannedDays.contains(day),
      isToday: day == today,
    );
  }, growable: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Week totals
// ─────────────────────────────────────────────────────────────────────────────

/// The three numbers under the week strip.
class WeekTotals {
  const WeekTotals({
    required this.workouts,
    required this.volumeKg,
    required this.personalRecords,
  });

  final int workouts;

  /// Σ(weight × reps) over the week's logs. Sessions that carry no load
  /// (mobility, body-weight work) contribute nothing, which is why this can be
  /// zero on a week with several workouts.
  final double volumeKg;

  /// Logs this week that beat every earlier load recorded for the same
  /// exercise.
  final int personalRecords;

  static const empty =
      WeekTotals(workouts: 0, volumeKg: 0, personalRecords: 0);
}

/// This week's totals from [logs].
///
/// [logs] is the recent window, not the whole history — the same bound
/// `deriveProgress` documents. It is exact for the first two numbers, because
/// neither reaches back further than the current week. [personalRecords] is
/// bounded by it in one direction only: a load that beats everything inside the
/// window but not a heavier lift from before it would be counted here and
/// should not be. That is a window artefact, not a rounding choice, and it is
/// the reason this number is labelled "records" on a week strip rather than
/// stored or acted on anywhere.
WeekTotals deriveWeekTotals(
  List<WorkoutLogEntry> logs, {
  DateTime? now,
}) {
  if (logs.isEmpty) return WeekTotals.empty;
  final monday = _weekStart(now ?? DateTime.now());

  // Oldest first, so "every earlier log" is simply "everything seen so far".
  final ordered = [...logs]
    ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

  final bestBefore = <String, double>{};
  var workouts = 0;
  var volume = 0.0;
  var records = 0;

  for (final l in ordered) {
    final inWeek = !_dayOf(l.completedAt).isBefore(monday);
    final w = l.weightKg;

    if (inWeek) {
      workouts++;
      if (w != null && l.repsCompleted != null) {
        volume += w * l.repsCompleted!;
      }
      final prevBest = bestBefore[l.exerciseId];
      // Strictly greater: repeating your best is holding a record, not
      // setting one, and counting it would make every repeated top set a PR.
      if (w != null && prevBest != null && w > prevBest) records++;
    }

    if (w != null) {
      final prevBest = bestBefore[l.exerciseId];
      if (prevBest == null || w > prevBest) bestBefore[l.exerciseId] = w;
    }
  }

  return WeekTotals(
    workouts: workouts,
    volumeKg: volume,
    personalRecords: records,
  );
}
