import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_log_providers.dart';

import 'package:fitness_app/features/progress/data/progress_stats.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_log_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/data/workout_log_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';

/// The history listeners are windowed, and the numbers that are genuinely
/// all-time survive it.
///
/// Both listeners used to be unbounded and both attach on the landing screen,
/// so every cold start re-read the user's whole history — a cost that grows
/// with how long someone has been a customer rather than with how many people
/// are online, which is the one thing here that gets worse as the product
/// succeeds.
///
/// The risk windowing introduces is the reason this file exists: two of the
/// figures on screen are all-time, and letting them keep deriving from the
/// visible rows would have quietly redefined them. A three-year user would
/// have watched their workout count drop to the window size with nothing
/// erroring.
WorkoutLogEntry _log(String id, DateTime at) => WorkoutLogEntry(
      id: id,
      exerciseId: 'ex',
      exerciseTitle: 'Squat',
      completedAt: at,
      durationMinutes: 30,
    );

ScheduledSession _session(String id, DateTime at) => ScheduledSession(
      id: id,
      exerciseId: 'ex',
      exerciseTitle: 'Squat',
      scheduledFor: at,
      durationMinutes: 30,
    );

void main() {
  const uid = 'u1';
  final base = DateTime(2026, 8, 4, 12);

  group('the workout history listener', () {
    test('hands back at most a window, newest first', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      for (var i = 0; i < kWorkoutHistoryWindow + 50; i++) {
        await repo.save(uid, _log('e$i', base.subtract(Duration(days: i))));
      }
      final seen = await repo.watch(uid).first;
      expect(seen, hasLength(kWorkoutHistoryWindow));
      expect(seen.first.id, 'e0', reason: 'newest first');
    });

    test('a history smaller than the window is untouched', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      for (var i = 0; i < 5; i++) {
        await repo.save(uid, _log('e$i', base.subtract(Duration(days: i))));
      }
      expect(await repo.watch(uid).first, hasLength(5));
    });

    test('totals count the whole history, not the window', () async {
      // The assertion the gate turns on. `total` is rendered as "workouts" on
      // Home and Progress, and the window would have made it read 200 for
      // anyone with more than 200.
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      for (var i = 0; i < kWorkoutHistoryWindow + 50; i++) {
        await repo.save(uid, _log('e$i', base.subtract(Duration(days: i))));
      }
      final totals = await repo.totals(uid);
      expect(totals.total, kWorkoutHistoryWindow + 50);
      expect((await repo.watch(uid).first).length, lessThan(totals.total));
    });
  });

  group('the streak record', () {
    test('starts at zero and rises', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      expect((await repo.totals(uid)).longestStreakDays, 0);
      await repo.recordStreak(uid, 7);
      expect((await repo.totals(uid)).longestStreakDays, 7);
    });

    test('never falls', () async {
      // A record is a high-water mark. Once the days that made it scroll out
      // of the window the app can no longer see them, so anything that
      // recomputed from what is visible would erase it.
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      await repo.recordStreak(uid, 21);
      await repo.recordStreak(uid, 3);
      expect((await repo.totals(uid)).longestStreakDays, 21);
    });

    test('clearing the history clears the record with it', () async {
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      await repo.save(uid, _log('e1', base));
      await repo.recordStreak(uid, 9);
      await repo.clear(uid);
      final totals = await repo.totals(uid);
      expect(totals.total, 0);
      expect(totals.longestStreakDays, 0,
          reason: 'a record kept past a wipe is a number with no history '
              'behind it');
    });
  });

  group('deriveProgress against a window', () {
    final window = [
      for (var i = 0; i < 3; i++) _log('e$i', base.subtract(Duration(days: i))),
    ];

    test('uses the all-time total rather than the rows it can see', () {
      final stats = deriveProgress(
        window,
        now: base,
        totals: const WorkoutLogTotals(total: 812, longestStreakDays: 0),
      );
      expect(stats.total, 812);
      expect(stats.total, isNot(window.length));
    });

    test('keeps a record set outside the window', () {
      final stats = deriveProgress(
        window,
        now: base,
        totals: const WorkoutLogTotals(total: 812, longestStreakDays: 40),
      );
      expect(stats.longestStreakDays, 40,
          reason: 'the visible rows are a 3-day run; the record is older');
    });

    test('a longer run inside the window beats the stored record', () {
      // The other direction: the record is only a floor. Whichever is larger
      // wins, which is what lets a new record be noticed at all.
      final stats = deriveProgress(
        window,
        now: base,
        totals: const WorkoutLogTotals(total: 812, longestStreakDays: 2),
      );
      expect(stats.longestStreakDays, 3);
    });

    test('without totals it still derives from the logs', () {
      // Callers that genuinely hold the whole history — tests, and users whose
      // history fits inside the window — are unaffected.
      final stats = deriveProgress(window, now: base);
      expect(stats.total, 3);
      expect(stats.longestStreakDays, 3);
    });

    test('an empty window still shows the real total', () {
      // A signed-in user whose listener has not delivered yet has a total.
      // Rendering 0 there and the real number a moment later is a flicker on
      // the number people check most.
      final stats = deriveProgress(
        const [],
        now: base,
        totals: const WorkoutLogTotals(total: 812, longestStreakDays: 40),
      );
      expect(stats.total, 812);
      expect(stats.longestStreakDays, 40);
      expect(stats.currentStreakDays, 0);
    });
  });

  group('the scheduled session listener', () {
    test('keeps the latest dates, not the earliest', () async {
      // Ascending was the worst possible order here: completed sessions are
      // never deleted, so the oldest rows are the most numerous and the least
      // wanted, while every consumer looks forward.
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      for (var i = 0; i < kScheduledSessionWindow + 20; i++) {
        await repo.save(uid, _session('s$i', base.add(Duration(days: i))));
      }
      final seen = await repo.watch(uid).first;
      expect(seen, hasLength(kScheduledSessionWindow));
      expect(seen.last.id, 's${kScheduledSessionWindow + 19}',
          reason: 'the furthest-future session must survive the window');
      expect(seen.first.id, isNot('s0'),
          reason: 'the oldest are what gets dropped');
    });

    test('still arrives in ascending order', () async {
      // The window changed which rows arrive, not the contract. Every consumer
      // reads this stream as ascending.
      final repo = MockScheduledSessionRepository(latency: Duration.zero);
      for (var i = 0; i < 10; i++) {
        await repo.save(uid, _session('s$i', base.add(Duration(days: i))));
      }
      final seen = await repo.watch(uid).first;
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].scheduledFor.isAfter(seen[i - 1].scheduledFor), isTrue);
      }
    });
  });

  group('finishing a workout writes the streak down', () {
    ProviderContainer containerFor(MockWorkoutLogRepository repo) =>
        ProviderContainer(overrides: [
          workoutLogRepositoryProvider.overrideWithValue(repo),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AuthUser(uid: uid, email: 'u@example.com', displayName: 'U'),
            ),
          ),
        ]);

    test('a three-day run is recorded as the record', () async {
      // Without this the stored record would stay 0 forever and the whole
      // mechanism would be a number nobody writes.
      final repo = MockWorkoutLogRepository(latency: Duration.zero);
      final container = containerFor(repo);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      for (var i = 2; i >= 0; i--) {
        await container
            .read(logWorkoutActionProvider.notifier)
            .log(_log('e$i', DateTime.now().subtract(Duration(days: i))));
      }

      expect((await repo.totals(uid)).longestStreakDays, 3);
    });

    test('a save that succeeds is not failed by a record that does not',
        () async {
      // The log is the thing the user pressed a button for. A record write
      // failing after it saved must not surface as a failed workout.
      final repo = _RecordRefusingRepository();
      final container = containerFor(repo);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(logWorkoutActionProvider.notifier)
          .log(_log('e1', DateTime.now()));

      expect(container.read(logWorkoutActionProvider), isA<AsyncData<void>>());
      expect(repo.cached(uid), hasLength(1));
    });
  });
}

/// Saves fine, refuses to remember a record.
class _RecordRefusingRepository extends MockWorkoutLogRepository {
  _RecordRefusingRepository() : super(latency: Duration.zero);

  @override
  Future<void> recordStreak(String uid, int days) async {
    throw StateError('offline');
  }
}