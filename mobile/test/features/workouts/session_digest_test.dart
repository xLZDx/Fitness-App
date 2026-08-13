import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/session_digest.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

/// R4 — the arithmetic Home was missing.
///
/// Audit §7.2: the design's hero reads "Спина и бицепс, 7 упражнений · 48
/// минут" and nothing could produce it, because `ScheduledSession` carries one
/// exercise. Seven rows for the same day already are the session; these tests
/// pin the sum that says so.
ScheduledSession _s(String id, DateTime when, int minutes) => ScheduledSession(
      id: 'sched_$id',
      exerciseId: id,
      exerciseTitle: id,
      scheduledFor: when,
      durationMinutes: minutes,
      status: ScheduledSessionStatus.pending,
    );

ExerciseItem _e(String id, List<String> primary, List<String> all) =>
    ExerciseItem.fromJson({
      'id': id,
      'title': id,
      'primaryMuscles': primary,
      'muscles': all,
    });

void main() {
  final morning = DateTime(2026, 8, 8, 7, 30);
  final evening = DateTime(2026, 8, 8, 19, 0);
  final tomorrow = DateTime(2026, 8, 9, 7, 30);

  final catalogue = {
    'row': _e('row', ['back'], ['back', 'biceps']),
    'pulldown': _e('pulldown', ['back'], ['back', 'biceps']),
    'curl': _e('curl', ['biceps'], ['biceps']),
    'squat': _e('squat', ['quadriceps'], ['quadriceps', 'glutes']),
  };

  test('a single row holding several exercises counts all of them (B5b)', () {
    // Until B5b "several exercises in a day" meant several ROWS, and counting
    // rows was the same number. `buildProgrammeSchedule` now writes ONE row per
    // day with the rest folded into it, so counting rows would put "1 exercise
    // · 45 min" over a workout of three.
    final day = ScheduledSession(
      id: 'sched_day',
      exerciseId: 'row',
      exerciseTitle: 'row',
      extraExercises: const [
        WorkoutSessionExercise(exerciseId: 'curl', exerciseTitle: 'curl'),
        WorkoutSessionExercise(exerciseId: 'squat', exerciseTitle: 'squat'),
      ],
      scheduledFor: morning,
      durationMinutes: 45,
    );
    final d = digestForDay([day], catalogue);
    expect(d.exerciseCount, 3);
    expect(d.totalMinutes, 45);
  });

  test('the muscles of a day describe all its exercises, not just the first',
      () {
    final day = ScheduledSession(
      id: 'sched_day',
      exerciseId: 'row',
      exerciseTitle: 'row',
      extraExercises: const [
        WorkoutSessionExercise(exerciseId: 'squat', exerciseTitle: 'squat'),
      ],
      scheduledFor: morning,
      durationMinutes: 20,
    );
    final d = digestForDay([day], catalogue);
    expect(d.muscles, containsAll(['back', 'quadriceps']));
  });

  test('an empty day is empty rather than a zeroed sentence', () {
    final d = digestForDay(const [], catalogue);
    expect(d.isEmpty, isTrue);
    expect(d.exerciseCount, 0);
    expect(d.muscles, isEmpty);
  });

  test('it sums the exercises and the minutes of one day', () {
    final d = digestForDay([
      _s('row', morning, 12),
      _s('pulldown', morning, 10),
      _s('curl', morning, 8),
    ], catalogue);

    expect(d.exerciseCount, 3);
    expect(d.totalMinutes, 30);
  });

  test('morning and evening are ONE training day, not two', () {
    // A fixed-length window would have called these separate sessions. Someone
    // who trains twice has one training day, and the hero has to agree with
    // the list underneath it.
    final d = digestForDay([
      _s('row', morning, 12),
      _s('curl', evening, 8),
    ], catalogue);

    expect(d.exerciseCount, 2);
    expect(d.totalMinutes, 20);
  });

  test('tomorrow is not counted into today', () {
    final d = digestForDay([
      _s('row', morning, 12),
      _s('squat', tomorrow, 30),
    ], catalogue);

    expect(d.exerciseCount, 1);
    expect(d.totalMinutes, 12);
    expect(d.sessions.single.exerciseId, 'row');
  });

  test('muscles are ranked by how much of the day works them', () {
    // Two back exercises and one biceps: the day is a back day that also does
    // some biceps, which is what the design sentence says. Taking the first
    // exercise's muscles would have called this whatever came first.
    final d = digestForDay([
      _s('curl', morning, 8),
      _s('row', morning, 12),
      _s('pulldown', morning, 10),
    ], catalogue);

    expect(d.muscles.first, 'back');
    expect(d.muscles, contains('biceps'));
  });

  test('a tie is broken by name, so the hero does not reshuffle', () {
    final a = digestForDay(
        [_s('row', morning, 10), _s('curl', morning, 10)], catalogue);
    final b = digestForDay(
        [_s('curl', morning, 10), _s('row', morning, 10)], catalogue);
    expect(a.muscles, b.muscles);
  });

  test('at most three muscles reach the hero', () {
    final many = {
      for (final m in ['back', 'biceps', 'chest', 'glutes', 'quadriceps'])
        m: _e(m, [m], [m]),
    };
    final d = digestForDay(
      [for (final m in many.keys) _s(m, morning, 5)],
      many,
    );
    expect(d.muscles.length, 3);
    expect(d.exerciseCount, 5, reason: 'the cap is on words, not on exercises');
  });

  test('an exercise missing from the catalogue still counts', () {
    // It IS scheduled. Dropping it would make the hero disagree with the list
    // right below it, which is worse than a hero that names fewer muscles.
    final d = digestForDay([
      _s('row', morning, 12),
      _s('deleted_exercise', morning, 15),
    ], catalogue);

    expect(d.exerciseCount, 2);
    expect(d.totalMinutes, 27);
    expect(d.muscles, ['back']);
  });
}
