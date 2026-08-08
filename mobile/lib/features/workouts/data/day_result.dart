import '../../equipment/data/equipment_models.dart';
import 'workout_session.dart';

/// What the user actually did today, from the sessions they completed.
///
/// ## Why this counts a DAY and not a session
///
/// The design's summary screen reads "48 мин · 7 упр. · 18 подх. · 4 820 кг"
/// (`App.tsx:4634`), which describes one multi-exercise workout. The app does
/// not write one. `workout_player_page.dart:265` is explicit about it — "one
/// exercise, at most one set per session" — so a real day of seven exercises
/// is seven `WorkoutSession` rows, each with a single exercise and a single
/// set.
///
/// Reading the design literally would therefore produce a screen that says
/// "1 упражнение" after every exercise, seven times. Counting the day gives
/// the number the design is actually about: what the person did before they
/// stopped. The entity change that would make a session multi-exercise is a
/// migration on live Firestore data (audit §7.2) and is not this gate.
///
/// [SessionDigest] does the same arithmetic for SCHEDULED sessions; this is
/// deliberately a separate type rather than a shared one, because the two
/// answer different questions from different fields — a plan has
/// `durationMinutes` and no sets, a result has sets, weights and a real
/// elapsed time.
class DayResult {
  const DayResult({
    required this.sessions,
    required this.exerciseCount,
    required this.setCount,
    required this.totalMinutes,
    required this.volumeKg,
    required this.muscles,
    required this.muscleShare,
  });

  /// The completed sessions this speaks for, earliest first.
  final List<WorkoutSession> sessions;

  final int exerciseCount;
  final int setCount;
  final int totalMinutes;

  /// Total weight moved: `weight × reps`, summed over every set that recorded
  /// both.
  ///
  /// A set with no weight (bodyweight, or the user declined to say) adds
  /// nothing rather than guessing a body weight — inventing the number that
  /// this figure is entirely made of would make the whole card fiction.
  final double volumeKg;

  /// Catalogue muscle keys, most-worked first. Keys, not words: the UI
  /// localises them.
  final List<String> muscles;

  /// Fraction of the day's exercises that worked each muscle, 0..1, for every
  /// muscle touched — not just the [muscles] shown.
  ///
  /// This is a share of the work done, and nothing more. The design draws
  /// these bars under a heading about recovery and adds "48-72 ч
  /// восстановления" (`App.tsx:4706`); that number is a physiological claim
  /// this app has no basis for, so the bar ships and the claim does not.
  final Map<String, double> muscleShare;

  bool get isEmpty => sessions.isEmpty;

  /// Whether any set recorded a weight. When false the volume card has nothing
  /// to say and should not claim "0 кг", which reads as a failed workout
  /// rather than an unweighted one.
  bool get hasWeights => volumeKg > 0;
}

/// How many muscle groups the summary names. Same limit as the Home hero, for
/// the same reason: past three it stops being a glance.
const _maxMuscles = 3;

/// Everything completed on the same calendar day as [day].
///
/// [day] is passed in rather than read from the clock so the screen does not
/// change under the user at midnight, and so tests do not depend on when they
/// run.
///
/// Only `completed` sessions count. An abandoned one is not a result, and
/// including it would inflate every number on the screen.
DayResult resultForDay(
  List<WorkoutSession> sessions,
  Map<String, ExerciseItem> catalogue,
  DateTime day,
) {
  final done = sessions
      .where((s) =>
          s.status == WorkoutSessionStatus.completed &&
          s.startedAt.year == day.year &&
          s.startedAt.month == day.month &&
          s.startedAt.day == day.day)
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  if (done.isEmpty) {
    return const DayResult(
      sessions: [],
      exerciseCount: 0,
      setCount: 0,
      totalMinutes: 0,
      volumeKg: 0,
      muscles: [],
      muscleShare: {},
    );
  }

  var exercises = 0;
  var sets = 0;
  var minutes = 0;
  var volume = 0.0;
  final tally = <String, int>{};

  for (final s in done) {
    minutes += s.durationMinutes ?? 0;
    for (final e in s.exercises) {
      exercises++;
      sets += e.sets.length;
      for (final set in e.sets) {
        final w = set.weightKg;
        final r = set.reps;
        if (w != null && r != null) volume += w * r;
      }
      final item = catalogue[e.exerciseId];
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
    // Ties broken by name so the list does not reshuffle between rebuilds.
    ..sort((a, b) {
      final byCount = tally[b]!.compareTo(tally[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  return DayResult(
    sessions: done,
    exerciseCount: exercises,
    setCount: sets,
    totalMinutes: minutes,
    volumeKg: volume,
    muscles: ranked.take(_maxMuscles).toList(),
    // Denominated in exercises, not in tally entries: an exercise listing two
    // primary muscles must not make the shares sum past 1 for the wrong
    // reason. "Half the day worked your back" is the sentence a bar can
    // honestly draw.
    muscleShare: {
      for (final e in tally.entries) e.key: e.value / exercises,
    },
  );
}
