import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

void main() {
  group('auth-restore window (MVP-1)', () {
    // MockAuthRepository (used by most other tests) replays its current
    // user synchronously on listen, which never reproduces a real cold
    // start: FirebaseAuth.userChanges() has no first emission at all until
    // the native SDK finishes restoring a persisted session. A directly
    // overridden StreamController that has not emitted yet is the only way
    // to model that genuinely-unresolved window in a test.
    late StreamController<AuthUser?> auth;
    late MockWorkoutSessionRepository repo;
    late ProviderContainer container;

    setUp(() {
      auth = StreamController<AuthUser?>.broadcast();
      repo = MockWorkoutSessionRepository(latency: Duration.zero);
      container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
        workoutSessionRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);
      addTearDown(auth.close);
    });

    test(
        'workoutSessionTotalsProvider stays loading during the restore '
        'window, never a false zero', () async {
      final sub =
          container.listen(workoutSessionTotalsProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      // Auth genuinely has not resolved yet -- must not have collapsed to
      // AsyncData(WorkoutLogTotals.zero).
      final duringRestore = container.read(workoutSessionTotalsProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out zero totals');
      expect(duringRestore.hasValue, isFalse);

      const uid = 'alice';
      final startedAt = DateTime(2026, 8, 19, 9);
      await repo.save(
        uid,
        WorkoutSession(
          id: 's1',
          title: 'Leg day',
          exercises: const [],
          startedAt: startedAt,
          completedAt: startedAt.add(const Duration(minutes: 40)),
          status: WorkoutSessionStatus.completed,
        ),
      );
      await repo.recordStreak(uid, 5);

      auth.add(const AuthUser(uid: uid, displayName: 'Alice'));
      await pumpEventQueue();

      final resolved = container.read(workoutSessionTotalsProvider);
      expect(resolved.valueOrNull, WorkoutLogTotals(total: 1, longestStreakDays: 5));
    });

    test(
        'workoutSessionsProvider stays loading during the restore window, '
        'never a false empty history', () async {
      final sub = container.listen(workoutSessionsProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final duringRestore = container.read(workoutSessionsProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out empty history');

      const uid = 'bob';
      final startedAt = DateTime(2026, 8, 19, 9);
      await repo.save(
        uid,
        WorkoutSession(
          id: 's1',
          title: 'Push day',
          exercises: const [],
          startedAt: startedAt,
          completedAt: startedAt.add(const Duration(minutes: 40)),
          status: WorkoutSessionStatus.completed,
        ),
      );

      auth.add(const AuthUser(uid: uid, displayName: 'Bob'));
      await pumpEventQueue();

      final resolved = container.read(workoutSessionsProvider);
      expect(resolved.valueOrNull?.length, 1);
    });

    test('both providers correctly resolve to empty/zero for a genuinely '
        'signed-out user (not the restore window)', () async {
      final totalsSub =
          container.listen(workoutSessionTotalsProvider, (_, __) {});
      final sessionsSub =
          container.listen(workoutSessionsProvider, (_, __) {});
      addTearDown(totalsSub.close);
      addTearDown(sessionsSub.close);

      auth.add(null);
      await pumpEventQueue();

      expect(container.read(workoutSessionTotalsProvider).valueOrNull,
          WorkoutLogTotals.zero);
      expect(container.read(workoutSessionsProvider).valueOrNull, isEmpty);
    });
  });
}
