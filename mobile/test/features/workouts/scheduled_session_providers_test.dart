import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

ScheduledSession _s(String id, DateTime when,
        {ScheduledSessionStatus status = ScheduledSessionStatus.pending}) =>
    ScheduledSession(
      id: id,
      exerciseId: 'pushup',
      exerciseTitle: 'Push-ups',
      scheduledFor: when,
      durationMinutes: 10,
      status: status,
    );

ProviderContainer _container({
  required MockScheduledSessionRepository repo,
  AuthUser? user,
}) {
  return ProviderContainer(overrides: [
    scheduledSessionRepositoryProvider.overrideWithValue(repo),
    authUserProvider.overrideWith((_) => Stream.value(user)),
  ]);
}

void main() {
  group('filterUpcoming', () {
    test('keeps only pending sessions in the next 14 days', () {
      final now = DateTime(2026, 5, 8, 12);
      final list = [
        _s('past', now.subtract(const Duration(days: 1))),
        _s('today', now.add(const Duration(hours: 5))),
        _s('week', now.add(const Duration(days: 7))),
        _s('outside', now.add(const Duration(days: 30))),
        _s('cancelled', now.add(const Duration(days: 1)),
            status: ScheduledSessionStatus.cancelled),
        _s('completed', now.add(const Duration(days: 1)),
            status: ScheduledSessionStatus.completed),
      ];
      final out = filterUpcoming(list, now: now);
      expect(out.map((s) => s.id), ['today', 'week']);
    });

    test('returns sessions sorted ascending', () {
      final now = DateTime(2026, 5, 8);
      final list = [
        _s('a', now.add(const Duration(days: 5))),
        _s('b', now.add(const Duration(days: 1))),
        _s('c', now.add(const Duration(days: 3))),
      ];
      final out = filterUpcoming(list, now: now);
      expect(out.map((s) => s.id), ['b', 'c', 'a']);
    });
  });

  group('scheduledSessionsProvider', () {
    test('returns empty list when signed out', () async {
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);

      await container.read(authUserProvider.future);
      final list = await container.read(scheduledSessionsProvider.future);
      expect(list, isEmpty);
    });

    test('streams sessions for the signed-in user', () async {
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save('alice', _s('s_1', DateTime(2026, 6, 1)));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final list = await container.read(scheduledSessionsProvider.future);
      expect(list.map((s) => s.id), ['s_1']);
    });
  });

  group('scheduleSessionActionProvider', () {
    test('writes to the repo for the current user', () async {
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(scheduleSessionActionProvider.notifier)
          .schedule(_s('s_x', DateTime(2026, 6, 5)));

      expect(container.read(scheduleSessionActionProvider).hasValue, isTrue);
      expect(repo.cached('alice').map((s) => s.id), ['s_x']);
    });

    test('errors when no user is signed in', () async {
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final container = _container(repo: repo, user: null);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(scheduleSessionActionProvider.notifier)
          .schedule(_s('s_y', DateTime(2026, 6, 5)));

      final state = container.read(scheduleSessionActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    });

    test('cancel deletes the session', () async {
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await repo.save('alice', _s('s_1', DateTime(2026, 6, 1)));

      final container = _container(
        repo: repo,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(scheduleSessionActionProvider.notifier)
          .cancel('s_1');

      expect(container.read(scheduleSessionActionProvider).hasValue, isTrue);
      expect(repo.cached('alice'), isEmpty);
    });
  });
}
