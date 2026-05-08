import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/mock_workout_log_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

WorkoutLogEntry _e(String id, DateTime when, {String exId = 'pushup'}) {
  return WorkoutLogEntry(
    id: id,
    exerciseId: exId,
    exerciseTitle: exId,
    completedAt: when,
    durationMinutes: 10,
  );
}

void main() {
  group('MockWorkoutLogRepository', () {
    late MockWorkoutLogRepository repo;

    setUp(() => repo = MockWorkoutLogRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    test('save then watch emits the new entry, newest first', () async {
      final older = _e('log_1', DateTime.utc(2026, 5, 1));
      final newer = _e('log_2', DateTime.utc(2026, 5, 5));

      await repo.save('user_a', older);
      await repo.save('user_a', newer);

      final list = await repo.watch('user_a').first;
      expect(list.map((e) => e.id), ['log_2', 'log_1']);
    });

    test('save is idempotent on id', () async {
      final base = _e('log_1', DateTime.utc(2026, 5, 1));
      await repo.save('u', base);
      await repo.save('u', base.copyWith(durationMinutes: 99));

      final list = await repo.watch('u').first;
      expect(list, hasLength(1));
      expect(list.first.durationMinutes, 99);
    });

    test('watch is per-user', () async {
      await repo.save('alice', _e('log_a', DateTime.utc(2026, 1, 1)));
      await repo.save('bob', _e('log_b', DateTime.utc(2026, 2, 1)));

      final aList = await repo.watch('alice').first;
      final bList = await repo.watch('bob').first;
      expect(aList.map((e) => e.id), ['log_a']);
      expect(bList.map((e) => e.id), ['log_b']);
    });

    test('delete removes the entry and emits', () async {
      await repo.save('u', _e('log_1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _e('log_2', DateTime.utc(2026, 5, 5)));

      await repo.delete('u', 'log_1');
      final list = await repo.watch('u').first;
      expect(list.map((e) => e.id), ['log_2']);
    });

    test('clear empties the user history', () async {
      await repo.save('u', _e('log_1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _e('log_2', DateTime.utc(2026, 5, 5)));

      await repo.clear('u');
      final list = await repo.watch('u').first;
      expect(list, isEmpty);
    });

    test('cached returns the current sorted snapshot', () async {
      await repo.save('u', _e('log_1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _e('log_2', DateTime.utc(2026, 5, 5)));
      expect(repo.cached('u').map((e) => e.id), ['log_2', 'log_1']);
    });

    test('watch streams subsequent saves', () async {
      final stream = repo.watch('u');
      final received = <List<WorkoutLogEntry>>[];
      final sub = stream.listen(received.add);

      await repo.save('u', _e('log_1', DateTime.utc(2026, 5, 1)));
      await Future<void>.delayed(Duration.zero);
      await repo.save('u', _e('log_2', DateTime.utc(2026, 5, 5)));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // Initial empty + after save 1 + after save 2.
      expect(received, hasLength(greaterThanOrEqualTo(3)));
      expect(received.last.map((e) => e.id), ['log_2', 'log_1']);
    });
  });
}
