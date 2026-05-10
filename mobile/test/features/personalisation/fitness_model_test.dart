import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/personalisation/data/fitness_model.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

WorkoutLogEntry _log(
  String exId,
  DifficultyRating? d, {
  DateTime? at,
}) =>
    WorkoutLogEntry(
      id: 'l_${exId}_${(at ?? DateTime.now()).millisecondsSinceEpoch}',
      exerciseId: exId,
      exerciseTitle: exId,
      completedAt: at ?? DateTime.now(),
      durationMinutes: 30,
      difficulty: d,
    );

void main() {
  group('FitnessProfile', () {
    test('cold-start scoreFor returns ~0.5 (Beta(2,2) prior)', () {
      final p = FitnessProfile.empty;
      expect(p.scoreFor('quads').score, closeTo(0.5, 0.0001));
    });

    test('averageFor unknown muscles is 0.5', () {
      final p = FitnessProfile.empty;
      expect(p.averageFor(['quads', 'glutes']),
          closeTo(0.5, 0.0001));
    });
  });

  group('buildProfile', () {
    test('skips logs without difficulty rating', () {
      final logs = [_log('squat', null)];
      final p = buildProfile(
        logs,
        musclesByExerciseId: const {'squat': ['quads']},
      );
      expect(p.byMuscle, isEmpty);
    });

    test('three "tooEasy" raises quads score above neutral', () {
      final now = DateTime(2026, 5, 10);
      final logs = [
        _log('squat', DifficultyRating.tooEasy,
            at: now.subtract(const Duration(days: 1))),
        _log('squat', DifficultyRating.tooEasy,
            at: now.subtract(const Duration(days: 3))),
        _log('squat', DifficultyRating.tooEasy,
            at: now.subtract(const Duration(days: 5))),
      ];
      final p = buildProfile(
        logs,
        musclesByExerciseId: const {'squat': ['quads']},
        now: now,
      );
      expect(p.scoreFor('quads').score, greaterThan(0.5));
    });

    test('three "tooHard" lowers quads score below neutral', () {
      final now = DateTime(2026, 5, 10);
      final logs = [
        for (var i = 0; i < 3; i++)
          _log('squat', DifficultyRating.tooHard,
              at: now.subtract(Duration(days: i + 1))),
      ];
      final p = buildProfile(
        logs,
        musclesByExerciseId: const {'squat': ['quads']},
        now: now,
      );
      expect(p.scoreFor('quads').score, lessThan(0.5));
    });

    test('older logs decay to lower weight', () {
      final now = DateTime(2026, 5, 10);
      final ancient = _log('squat', DifficultyRating.tooHard,
          at: now.subtract(const Duration(days: 200)));
      final fresh = _log('squat', DifficultyRating.tooEasy,
          at: now.subtract(const Duration(days: 1)));
      final p = buildProfile(
        [ancient, fresh],
        musclesByExerciseId: const {'squat': ['quads']},
        now: now,
      );
      // Fresh "tooEasy" should dominate; score > 0.5.
      expect(p.scoreFor('quads').score, greaterThan(0.5));
    });
  });
}
