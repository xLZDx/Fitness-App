import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_log_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/state/workout_log_providers.dart';

WorkoutLogEntry _entry(String id, DateTime when) => WorkoutLogEntry(
      id: id,
      exerciseId: 'pushup',
      exerciseTitle: 'Push-ups',
      completedAt: when,
      durationMinutes: 10,
    );

ProviderContainer _container({
  required MockWorkoutLogRepository repo,
  AuthUser? user,
}) {
  return ProviderContainer(overrides: [
    workoutLogRepositoryProvider.overrideWithValue(repo),
    authUserProvider.overrideWith((_) => Stream.value(user)),
  ]);
}

void main() {
  group('workoutLogsProvider', () {
    test('returns empty list when signed out', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      final list = await container.read(workoutLogsProvider.future);
      expect(list, isEmpty);
    });

    test('streams logs scoped to the signed-in user', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save('alice', _entry('log_1', DateTime.utc(2026, 5, 1)));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      final list = await container.read(workoutLogsProvider.future);
      expect(list.map((e) => e.id), ['log_1']);
    });
  });

  group('logWorkoutActionProvider', () {
    test('writes to the repo for the current user', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(logWorkoutActionProvider.notifier)
          .log(_entry('log_x', DateTime.utc(2026, 5, 5)));

      expect(container.read(logWorkoutActionProvider).hasValue, isTrue);
      expect(repo.cached('alice').map((e) => e.id), ['log_x']);
    });

    test('reports an error when no user is signed in', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(logWorkoutActionProvider.notifier)
          .log(_entry('log_y', DateTime.utc(2026, 5, 5)));

      final state = container.read(logWorkoutActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
      expect(repo.cached('alice'), isEmpty);
    });
  });
}
