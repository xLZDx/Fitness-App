import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session_repository.dart'
    show kWorkoutSessionHistoryWindow;

WorkoutSession _s(String id, DateTime when,
    {WorkoutSessionStatus status = WorkoutSessionStatus.completed}) {
  return WorkoutSession(
    id: id,
    title: 'Session $id',
    exercises: const [
      WorkoutSessionExercise(exerciseId: 'pushup', exerciseTitle: 'Push-ups'),
    ],
    startedAt: when,
    completedAt: status == WorkoutSessionStatus.completed ? when : null,
    status: status,
  );
}

void main() {
  group('MockWorkoutSessionRepository', () {
    late MockWorkoutSessionRepository repo;

    setUp(() => repo = MockWorkoutSessionRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    test('save then watch emits the new session, newest first', () async {
      final older = _s('s1', DateTime.utc(2026, 5, 1));
      final newer = _s('s2', DateTime.utc(2026, 5, 5));

      await repo.save('user_a', older);
      await repo.save('user_a', newer);

      final list = await repo.watch('user_a').first;
      expect(list.map((s) => s.id), ['s2', 's1']);
    });

    test('save is idempotent on id', () async {
      final base = _s('s1', DateTime.utc(2026, 5, 1));
      await repo.save('u', base);
      await repo.save('u', base.copyWith(title: 'Renamed'));

      final list = await repo.watch('u').first;
      expect(list, hasLength(1));
      expect(list.first.title, 'Renamed');
    });

    test('a pending (uncompleted) session saves and streams like any other',
        () async {
      final pending = _s('s1', DateTime.utc(2026, 5, 1),
          status: WorkoutSessionStatus.pending);
      await repo.save('u', pending);
      final list = await repo.watch('u').first;
      expect(list.single.status, WorkoutSessionStatus.pending);
      expect(list.single.completedAt, isNull);
    });

    test('delete removes the session and emits', () async {
      await repo.save('u', _s('s1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _s('s2', DateTime.utc(2026, 5, 5)));

      await repo.delete('u', 's1');
      final list = await repo.watch('u').first;
      expect(list.map((s) => s.id), ['s2']);
    });

    test('clear empties the user history', () async {
      await repo.save('u', _s('s1', DateTime.utc(2026, 5, 1)));
      await repo.clear('u');
      expect(await repo.watch('u').first, isEmpty);
    });

    test('cached returns the current sorted snapshot', () async {
      await repo.save('u', _s('s1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _s('s2', DateTime.utc(2026, 5, 5)));
      expect(repo.cached('u').map((s) => s.id), ['s2', 's1']);
    });

    group('exportAll', () {
      // Same non-truncation guarantee as WorkoutLogRepository.exportAll --
      // an export that silently caps at the window looks complete when it
      // is not.
      test('returns more than the window when there is more than the window',
          () async {
        for (var i = 0; i < kWorkoutSessionHistoryWindow + 5; i++) {
          await repo.save('u', _s('s$i', DateTime.utc(2026, 1, 1 + i)));
        }
        final all = await repo.exportAll('u');
        expect(all, hasLength(kWorkoutSessionHistoryWindow + 5));
      });

      test('an unknown uid exports empty, not an error', () async {
        expect(await repo.exportAll('nobody'), isEmpty);
      });
    });

    group('streak', () {
      test('recordStreak only ever raises the record', () async {
        await repo.recordStreak('u', 5);
        await repo.recordStreak('u', 3);
        expect((await repo.totals('u')).longestStreakDays, 5);
      });
    });
  });
}
