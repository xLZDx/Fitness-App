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

    test('a back-off scheme reports the top set, not the last one', () {
      // The anchor used to be `sets.last`. For a ramp that is the working set
      // and for a top-set-and-back-off it is the lightest thing the user did —
      // and `progression.dart` reads these rows to decide the next load, so it
      // would have walked the weight down a set scheme nobody showed it.
      final backOff = WorkoutSession(
        id: 's_backoff',
        title: 'Squat day',
        exercises: const [
          WorkoutSessionExercise(
            exerciseId: 'squat',
            exerciseTitle: 'Squat',
            sets: [
              (weightKg: 100.0, reps: 3),
              (weightKg: 85.0, reps: 8),
              (weightKg: 85.0, reps: 8),
            ],
          ),
        ],
        startedAt: DateTime.utc(2026, 8, 6, 9),
      );
      final row = backOff.asLogEntries().single;
      expect(row.weightKg, 100.0);
      expect(row.repsCompleted, 3);
    });

    test('a bodyweight exercise reports its best set rather than nothing', () {
      // No set carries a weight, so the comparison falls through to reps
      // instead of discarding every candidate.
      final bw = WorkoutSession(
        id: 's_bw',
        title: 'Calisthenics',
        exercises: const [
          WorkoutSessionExercise(
            exerciseId: 'pushup',
            exerciseTitle: 'Push Up',
            sets: [(weightKg: null, reps: 12), (weightKg: null, reps: 20)],
          ),
        ],
        startedAt: DateTime.utc(2026, 8, 6, 9),
      );
      final row = bw.asLogEntries().single;
      expect(row.weightKg, isNull);
      expect(row.repsCompleted, 20);
    });

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

    test('each row carries its OWN exercise\'s working set and difficulty, not '
        "the first exercise's", () {
      final rows = multi.asLogEntries();
      final bench = rows.firstWhere((r) => r.exerciseId == 'bench');
      final ohp = rows.firstWhere((r) => r.exerciseId == 'ohp');
      expect(bench.weightKg, 65.0, reason: 'the heaviest set, not the first');
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

  // The day player's counterpart. Position identifies "the exercise being
  // logged" only when there is exactly one; inside a scheduled day the tap can
  // belong to exercise three, and `replaceEntryExercise` would have written it
  // over exercise one.
  group('upsertExerciseById', () {
    const bench = WorkoutSessionExercise(exerciseId: 'bench', exerciseTitle: 'Bench');
    const row = WorkoutSessionExercise(exerciseId: 'row', exerciseTitle: 'Row');
    const ohp =
        WorkoutSessionExercise(exerciseId: 'ohp', exerciseTitle: 'Overhead Press');

    test('on an empty list, the update becomes the only entry', () {
      expect(upsertExerciseById(const [], bench), [bench]);
    });

    test('an exercise the session has never seen is appended', () {
      expect(upsertExerciseById([bench, row], ohp), [bench, row, ohp]);
    });

    test('updates in place by id, without moving it or touching its neighbours',
        () {
      final updatedRow = row.copyWith(sets: const [(weightKg: 60.0, reps: 5)]);
      final out = upsertExerciseById([bench, row, ohp], updatedRow);
      expect(out, [bench, updatedRow, ohp]);
    });

    test('the last exercise of a day updates without duplicating', () {
      final rated = ohp.copyWith(difficulty: DifficultyRating.tooHard);
      final out = upsertExerciseById([bench, row, ohp], rated);
      expect(out, [bench, row, rated]);
      expect(out.where((e) => e.exerciseId == 'ohp'), hasLength(1));
    });

    test('position is irrelevant -- index 0 is never assumed to be the target',
        () {
      final updatedBench = bench.copyWith(sets: const [(weightKg: 80.0, reps: 3)]);
      // The distinguishing case against replaceEntryExercise: same input, but
      // the exercise being written is not the one at index 0.
      final byId = upsertExerciseById([bench, row], row.copyWith(
          sets: const [(weightKg: 40.0, reps: 8)]));
      expect(byId.first, bench, reason: 'exercise one must be left alone');
      expect(upsertExerciseById([bench, row], updatedBench),
          [updatedBench, row]);
    });
  });
}
