import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/data/day_result.dart';
import 'package:fitness_app/features/workouts/data/set_capture.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

/// R5 — the numbers the summary screen puts in front of the user.
///
/// Every one of them is a claim about what they just did, so each is pinned
/// here rather than trusted to a widget: a summary that overstates a workout
/// is worse than no summary, and one that says "0 кг" after a bodyweight
/// session reads as a failure.

WorkoutSession _s(
  String id,
  DateTime when, {
  required String exerciseId,
  int? minutes,
  List<SetCapture> sets = const [],
  WorkoutSessionStatus status = WorkoutSessionStatus.completed,
}) =>
    WorkoutSession(
      id: id,
      title: exerciseId,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: exerciseId,
          exerciseTitle: exerciseId,
          sets: sets,
        ),
      ],
      startedAt: when,
      completedAt: when.add(const Duration(minutes: 10)),
      status: status,
      durationMinutes: minutes,
    );

ExerciseItem _e(String id, List<String> primary) => ExerciseItem.fromJson({
      'id': id,
      'title': id,
      'primaryMuscles': primary,
      'muscles': primary,
    });

void main() {
  final day = DateTime(2026, 8, 8);
  final morning = DateTime(2026, 8, 8, 8);
  final evening = DateTime(2026, 8, 8, 19);
  final yesterday = DateTime(2026, 8, 7, 8);

  final catalogue = {
    'row': _e('row', ['back']),
    'pulldown': _e('pulldown', ['back']),
    'curl': _e('curl', ['biceps']),
  };

  test('a day with nothing completed is empty, not a row of zeros', () {
    final r = resultForDay(const [], catalogue, day);
    expect(r.isEmpty, isTrue);
    expect(r.exerciseCount, 0);
  });

  test('it sums exercises, sets, minutes and volume across the day', () {
    final r = resultForDay([
      _s('a', morning,
          exerciseId: 'row',
          minutes: 12,
          sets: const [(weightKg: 60, reps: 10)]),
      _s('b', evening,
          exerciseId: 'curl',
          minutes: 8,
          sets: const [(weightKg: 20, reps: 12)]),
    ], catalogue, day);

    expect(r.exerciseCount, 2);
    expect(r.setCount, 2);
    expect(r.totalMinutes, 20);
    expect(r.volumeKg, 60 * 10 + 20 * 12);
  });

  test('a session that is not completed is not a result', () {
    // Counting `pending` or `abandoned` would inflate every number on the
    // screen with work that was started and dropped.
    final r = resultForDay([
      _s('a', morning,
          exerciseId: 'row',
          minutes: 12,
          sets: const [(weightKg: 60, reps: 10)]),
      _s('b', morning,
          exerciseId: 'curl',
          minutes: 30,
          status: WorkoutSessionStatus.abandoned,
          sets: const [(weightKg: 99, reps: 99)]),
      _s('c', morning,
          exerciseId: 'curl',
          minutes: 30,
          status: WorkoutSessionStatus.pending,
          sets: const [(weightKg: 99, reps: 99)]),
    ], catalogue, day);

    expect(r.exerciseCount, 1);
    expect(r.totalMinutes, 12);
    expect(r.volumeKg, 600);
  });

  test('yesterday is not part of today', () {
    final r = resultForDay([
      _s('a', morning, exerciseId: 'row', minutes: 12),
      _s('old', yesterday, exerciseId: 'curl', minutes: 45),
    ], catalogue, day);

    expect(r.exerciseCount, 1);
    expect(r.totalMinutes, 12);
  });

  test('a set with no weight adds no volume rather than a guess', () {
    // Bodyweight, or the user declined to say. Inventing a body weight would
    // make the one number this card is entirely made of fiction.
    final r = resultForDay([
      _s('a', morning, exerciseId: 'row', minutes: 10, sets: const [
        (weightKg: null, reps: 12),
        (weightKg: 40, reps: 10),
      ]),
    ], catalogue, day);

    expect(r.setCount, 2);
    expect(r.volumeKg, 400);
    expect(r.hasWeights, isTrue);
  });

  test('a purely bodyweight day says it has no weights at all', () {
    final r = resultForDay([
      _s('a', morning,
          exerciseId: 'row',
          minutes: 10,
          sets: const [(weightKg: null, reps: 12)]),
    ], catalogue, day);

    expect(r.setCount, 1);
    expect(r.hasWeights, isFalse,
        reason: 'the card must be able to hide "0 кг", which reads as a '
            'failed workout rather than an unweighted one');
  });

  test('muscles are ranked by how much of the day worked them', () {
    final r = resultForDay([
      _s('a', morning, exerciseId: 'curl', minutes: 8),
      _s('b', morning, exerciseId: 'row', minutes: 10),
      _s('c', morning, exerciseId: 'pulldown', minutes: 10),
    ], catalogue, day);

    expect(r.muscles.first, 'back');
    expect(r.muscles, contains('biceps'));
  });

  test('muscle share is a fraction of the exercises done, not of the tally',
      () {
    // Two of three exercises worked the back. An exercise that listed two
    // primary muscles must not push the shares past 1 by counting itself
    // twice in the denominator.
    final r = resultForDay([
      _s('a', morning, exerciseId: 'row', minutes: 10),
      _s('b', morning, exerciseId: 'pulldown', minutes: 10),
      _s('c', morning, exerciseId: 'curl', minutes: 8),
    ], catalogue, day);

    expect(r.muscleShare['back'], closeTo(2 / 3, 1e-9));
    expect(r.muscleShare['biceps'], closeTo(1 / 3, 1e-9));
  });

  test('an exercise missing from the catalogue still counts as work done', () {
    final r = resultForDay([
      _s('a', morning, exerciseId: 'row', minutes: 10),
      _s('b', morning, exerciseId: 'deleted', minutes: 15),
    ], catalogue, day);

    expect(r.exerciseCount, 2);
    expect(r.totalMinutes, 25);
    expect(r.muscles, ['back']);
  });

  test('sessions come back earliest first', () {
    final r = resultForDay([
      _s('late', evening, exerciseId: 'curl', minutes: 8),
      _s('early', morning, exerciseId: 'row', minutes: 12),
    ], catalogue, day);

    expect(r.sessions.map((s) => s.id), ['early', 'late']);
  });
}
