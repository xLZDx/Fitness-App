import '../../equipment/data/equipment_models.dart';
import 'scheduled_session.dart';

/// One line about a whole training day, from the several single-exercise rows
/// that make it up.
///
/// ## Why this exists
///
/// The audit's §7.2: the design's Home hero reads "Спина и бицепс, 7
/// упражнений · 48 минут", and nothing in the app could produce that sentence.
/// `ScheduledSession` carries ONE exercise, so Home showed the next single
/// row — "Push-ups, 10 min" — where the design promised the shape of the
/// session.
///
/// The fix is not a new entity. Seven scheduled rows for the same day already
/// ARE the session; what was missing is the arithmetic that says so. Keeping
/// it a pure function over rows the app already stores means Home stops lying
/// about the day without a Firestore migration behind it.
class SessionDigest {
  const SessionDigest({
    required this.sessions,
    required this.exerciseCount,
    required this.totalMinutes,
    required this.muscles,
  });

  /// The rows this digest speaks for, in their original order. The first is
  /// what "start" opens — the day is described as a whole, but it is still
  /// entered one exercise at a time.
  final List<ScheduledSession> sessions;

  final int exerciseCount;
  final int totalMinutes;

  /// Catalogue muscle keys, most-worked first. Keys, not words: the UI
  /// localises them, and a digest that returned Russian could not be shown in
  /// English.
  final List<String> muscles;

  bool get isEmpty => sessions.isEmpty;
}

/// How many muscle groups a one-line hero can carry before it stops being a
/// glance. The design's own example names two.
const _maxMuscles = 3;

/// Digest of everything scheduled for the same calendar day as [sessions.first].
///
/// Same DAY, not a fixed window: someone who trains at 07:00 and again at
/// 19:00 has one training day, and a two-hour window would call it two. The
/// day is taken from the first row rather than from the clock, so the answer
/// does not change while the screen is open.
///
/// [catalogue] supplies the muscles; a row whose exercise is not in it still
/// counts towards the exercise total and the minutes, because it IS scheduled.
/// Dropping it would make the hero disagree with the list underneath it.
SessionDigest digestForDay(
  List<ScheduledSession> sessions,
  Map<String, ExerciseItem> catalogue,
) {
  if (sessions.isEmpty) {
    return const SessionDigest(
      sessions: [],
      exerciseCount: 0,
      totalMinutes: 0,
      muscles: [],
    );
  }
  final day = sessions.first.scheduledFor;
  final sameDay = sessions
      .where((s) =>
          s.scheduledFor.year == day.year &&
          s.scheduledFor.month == day.month &&
          s.scheduledFor.day == day.day)
      .toList();

  // Counted by how many of the day's exercises work each muscle, so "Спина и
  // бицепс" names what the day is mostly about rather than whatever the first
  // exercise happened to list.
  final tally = <String, int>{};
  for (final s in sameDay) {
    // Every exercise of each row, not one per row. Until B5b "several
    // exercises in a day" meant several ROWS, so counting rows was the same
    // thing; `buildProgrammeSchedule` now writes one row per day and folds the
    // rest into it, and a tally over `s.exerciseId` alone would describe a
    // four-exercise day by its first exercise's muscles.
    for (final exercise in s.exercises) {
      final item = catalogue[exercise.exerciseId];
      if (item == null) continue;
      final primary = item.primaryMuscles.isEmpty
          ? item.muscles.take(1)
          : item.primaryMuscles;
      for (final m in primary) {
        tally[m] = (tally[m] ?? 0) + 1;
      }
    }
  }
  final ranked = tally.keys.toList()
    // Ties broken by name so the hero does not reshuffle between rebuilds on
    // a day that works two muscles equally.
    ..sort((a, b) {
      final byCount = tally[b]!.compareTo(tally[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  return SessionDigest(
    sessions: sameDay,
    // Exercises, not rows. `sameDay.length` was the same number until B5b and
    // is not any more: a programme day is one row holding several exercises,
    // and the hero would have said "1 exercise · 40 min" over a workout of
    // four.
    exerciseCount: sameDay.fold(0, (sum, s) => sum + s.exerciseCount),
    totalMinutes: sameDay.fold(0, (sum, s) => sum + s.durationMinutes),
    muscles: ranked.take(_maxMuscles).toList(),
  );
}
