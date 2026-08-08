import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/workout_log.dart'
    show DifficultyRating;
import 'package:fitness_app/features/workouts/data/workout_session.dart';

void main() {
  group('WorkoutSessionExercise', () {
    const exercise = WorkoutSessionExercise(
      exerciseId: 'squat',
      exerciseTitle: 'Back Squat',
      groupId: 'g1',
      sets: [(weightKg: 60.0, reps: 5), (weightKg: 60.0, reps: 5)],
      difficulty: DifficultyRating.justRight,
    );

    test('toJson/fromJson round-trips every set, in order', () {
      final json = exercise.toJson();
      final restored = WorkoutSessionExercise.fromJson(json);
      expect(restored, exercise);
      expect(restored.sets, hasLength(2));
    });

    test('a set with a declined field round-trips as null, not zero', () {
      const e = WorkoutSessionExercise(
        exerciseId: 'plank',
        exerciseTitle: 'Plank',
        sets: [(weightKg: null, reps: null)],
      );
      final restored = WorkoutSessionExercise.fromJson(e.toJson());
      expect(restored.sets.single.weightKg, isNull);
      expect(restored.sets.single.reps, isNull);
    });

    test('groupId is omitted from JSON, not written as null', () {
      const e = WorkoutSessionExercise(exerciseId: 'x', exerciseTitle: 'X');
      expect(e.toJson().containsKey('groupId'), isFalse);
    });

    test('fromJson falls back to exerciseId when title missing', () {
      final out = WorkoutSessionExercise.fromJson({
        'exerciseId': 'deadlift',
        'sets': <dynamic>[],
      });
      expect(out.exerciseTitle, 'deadlift');
    });
  });

  group('WorkoutSession', () {
    final pending = WorkoutSession(
      id: 's1',
      title: 'Push day',
      exercises: const [
        WorkoutSessionExercise(exerciseId: 'bench', exerciseTitle: 'Bench'),
      ],
      startedAt: DateTime.utc(2026, 8, 6, 9),
    );

    test('a new session has no completedAt and is pending', () {
      expect(pending.completedAt, isNull);
      expect(pending.status, WorkoutSessionStatus.pending);
      // The state a required completedAt could not express -- the reason
      // it's nullable in the first place.
      expect(pending.toJson().containsKey('completedAt'), isFalse);
    });

    test('completing fills completedAt and flips status', () {
      final done = pending.copyWith(
        completedAt: DateTime.utc(2026, 8, 6, 9, 45),
        status: WorkoutSessionStatus.completed,
        durationMinutes: 45,
      );
      final restored = WorkoutSession.fromJson(done.toJson());
      expect(restored, done);
      expect(restored.status, WorkoutSessionStatus.completed);
    });

    test('an abandoned session keeps completedAt null with its own status', () {
      final abandoned =
          pending.copyWith(status: WorkoutSessionStatus.abandoned);
      final restored = WorkoutSession.fromJson(abandoned.toJson());
      expect(restored.status, WorkoutSessionStatus.abandoned);
      expect(restored.completedAt, isNull);
    });

    test('toJson/fromJson round-trips a multi-exercise session losslessly', () {
      final session = pending.copyWith(exercises: const [
        WorkoutSessionExercise(
            exerciseId: 'bench', exerciseTitle: 'Bench', groupId: 'a'),
        WorkoutSessionExercise(
            exerciseId: 'row', exerciseTitle: 'Row', groupId: 'a'),
      ]);
      final restored = WorkoutSession.fromJson(session.toJson());
      expect(restored, session);
      expect(restored.exercises.map((e) => e.groupId), ['a', 'a']);
    });

    test('an unknown status string falls back to pending, not a crash', () {
      final json = pending.toJson()..['status'] = 'not_a_real_status';
      expect(
          WorkoutSession.fromJson(json).status, WorkoutSessionStatus.pending);
    });

    test('equality matches on all fields, including exercises', () {
      final a = pending;
      final b = pending.copyWith();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final c = pending.copyWith(title: 'Different');
      expect(a, isNot(equals(c)));

      final d = pending.copyWith(exercises: const []);
      expect(a, isNot(equals(d)));
    });
  });

  // R11e: asLogEntries() replaced the F3.3-era asLogEntryView(), which
  // returned exactly one row (first exercise, last set) and was documented as
  // "silently lossy" the day multi-exercise sessions arrived. This is that
  // day.
  group('WorkoutSession.asLogEntries', () {
    final single = WorkoutSession(
      id: 's1',
      title: 'Push day',
      exercises: const [
        WorkoutSessionExercise(exerciseId: 'bench', exerciseTitle: 'Bench'),
      ],
      startedAt: DateTime.utc(2026, 8, 6, 9),
    );
    final multi = WorkoutSession(
      id: 's_multi',
      title: 'Push day',
      exercises: const [
        WorkoutSessionExercise(
          exerciseId: 'bench',
          exerciseTitle: 'Bench',
          sets: [(weightKg: 60.0, reps: 8), (weightKg: 65.0, reps: 6)],
          difficulty: DifficultyRating.justRight,
        ),
        WorkoutSessionExercise(
          exerciseId: 'ohp',
          exerciseTitle: 'Overhead Press',
          sets: [(weightKg: 30.0, reps: 8)],
          difficulty: DifficultyRating.tooEasy,
        ),
      ],
      startedAt: DateTime.utc(2026, 8, 6, 9),
      completedAt: DateTime.utc(2026, 8, 6, 9, 45),
      status: WorkoutSessionStatus.completed,
      durationMinutes: 45,
    );

    test('emits one row per exercise, not just the first', () {
      final rows = multi.asLogEntries();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.exerciseId), ['bench', 'ohp']);
    });

    test('every row shares sessionId but has its own id', () {
      final rows = multi.asLogEntries();
      expect(rows.every((r) => r.sessionId == 's_multi'), isTrue);
      expect(rows.map((r) => r.id).toSet(), hasLength(2),
          reason: 'two rows sharing an id would upsert onto each other');
    });

    test('each row carries its OWN exercise\'s last set and difficulty, not '
        "the first exercise's", () {
      final rows = multi.asLogEntries();
      final bench = rows.firstWhere((r) => r.exerciseId == 'bench');
      final ohp = rows.firstWhere((r) => r.exerciseId == 'ohp');
      expect(bench.weightKg, 65.0, reason: 'the LAST set, not the first');
      expect(bench.difficulty, DifficultyRating.justRight);
      expect(ohp.weightKg, 30.0);
      expect(ohp.difficulty, DifficultyRating.tooEasy);
    });

    test('a single-exercise session behaves exactly as asLogEntryView used '
        'to -- one row, sessionId equals id', () {
      final rows = single
          .copyWith(
            completedAt: DateTime.utc(2026, 8, 6, 9, 30),
            status: WorkoutSessionStatus.completed,
          )
          .asLogEntries();
      expect(rows, hasLength(1));
      expect(rows.single.id, 's1');
      expect(rows.single.sessionId, 's1');
      expect(rows.single.exerciseId, 'bench');
    });

    test('a session with zero exercises still yields one placeholder row',
        () {
      final empty = single.copyWith(
        exercises: const [],
        completedAt: DateTime.utc(2026, 8, 6, 9, 15),
        status: WorkoutSessionStatus.completed,
      );
      final rows = empty.asLogEntries();
      expect(rows, hasLength(1));
      expect(rows.single.sessionId, 's1');
    });
  });

  // R11e: this pins the bug the player caught once already -- re-editing the
  // entry exercise's own set must not erase exercises appended after it.
  group('replaceEntryExercise', () {
    const bench = WorkoutSessionExercise(exerciseId: 'bench', exerciseTitle: 'Bench');
    const row = WorkoutSessionExercise(exerciseId: 'row', exerciseTitle: 'Row');
    const ohp =
        WorkoutSessionExercise(exerciseId: 'ohp', exerciseTitle: 'Overhead Press');

    test('on an empty list, the update becomes the only entry', () {
      expect(replaceEntryExercise(const [], bench), [bench]);
    });

    test('replaces index 0 and keeps everything after it untouched', () {
      final updatedBench = bench.copyWith(
          sets: const [(weightKg: 60.0, reps: 5)]);
      final out = replaceEntryExercise([bench, row, ohp], updatedBench);
      expect(out, [updatedBench, row, ohp]);
    });

    test('a single-exercise session is unaffected -- output has one entry',
        () {
      final updated = bench.copyWith(difficulty: DifficultyRating.tooEasy);
      expect(replaceEntryExercise([bench], updated), [updated]);
    });
  });
}
