import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// NEW-OFFLINE-LOG. The "Mark complete" action must (a) ignore a second tap
/// while the first write is in flight and (b) not let the streak write hold
/// the spinner or fail the completion.
///
/// The repository is a [MockWorkoutSessionRepository] whose `save` and
/// `recordStreak` are gated or made to hang, so the overlap is a real overlap
/// of two awaiting calls rather than a re-read of a flag.
class _GatedRepo extends MockWorkoutSessionRepository {
  _GatedRepo() : super(latency: Duration.zero);

  /// Completed by the test to let a pending `save` finish.
  Completer<void>? saveGate;

  /// When set, `save` throws this after the gate (if any).
  Object? saveError;

  /// `recordStreak` never completes (an offline Firestore transaction).
  bool streakHangs = false;

  /// `recordStreak` throws.
  bool streakThrows = false;

  int saveCalls = 0;
  int streakCalls = 0;

  @override
  Future<void> save(String uid, WorkoutSession session) async {
    saveCalls += 1;
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (saveError != null) throw saveError!;
    await super.save(uid, session);
  }

  @override
  Future<void> recordStreak(String uid, int days) {
    streakCalls += 1;
    if (streakHangs) return Completer<void>().future;
    if (streakThrows) return Future<void>.error(StateError('transaction'));
    return super.recordStreak(uid, days);
  }
}

WorkoutSession _session(String id) {
  final now = DateTime.now();
  return WorkoutSession(
    id: id,
    title: 'Leg day',
    exercises: const [],
    startedAt: now.subtract(const Duration(minutes: 40)),
    completedAt: now,
    status: WorkoutSessionStatus.completed,
  );
}

const _user = AuthUser(uid: 'alice', displayName: 'Alice');

ProviderContainer _container(_GatedRepo repo) {
  final c = ProviderContainer(overrides: [
    authUserProvider.overrideWith((ref) => Stream.value(_user)),
    workoutSessionRepositoryProvider.overrideWith((ref) {
      ref.onDispose(repo.dispose);
      return repo;
    }),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('LogSessionAction re-entrancy', () {
    test('two overlapping completions produce exactly one write', () async {
      final repo = _GatedRepo()..saveGate = Completer<void>();
      final c = _container(repo);
      await c.read(authUserProvider.future);
      c.listen(logSessionActionProvider, (_, __) {});
      final action = c.read(logSessionActionProvider.notifier);

      final first = action.log(_session('s1'));
      await pumpEventQueue();
      expect(c.read(logSessionActionProvider).isLoading, isTrue);
      expect(repo.saveCalls, 1);

      // The second tap lands while the first save is still awaiting.
      await action.log(_session('s1'));
      expect(repo.saveCalls, 1,
          reason: 'a second tap while one is in flight must be ignored');
      expect(c.read(logSessionActionProvider).isLoading, isTrue,
          reason: 'the ignored call must not resolve the spinner early');

      repo.saveGate!.complete();
      await first;

      expect(repo.saveCalls, 1);
      expect(c.read(logSessionActionProvider).hasError, isFalse);
      expect(repo.cached('alice').map((s) => s.id), ['s1']);
    });

    test('the guard is released after success, so the next completion writes',
        () async {
      final repo = _GatedRepo();
      final c = _container(repo);
      await c.read(authUserProvider.future);
      c.listen(logSessionActionProvider, (_, __) {});
      final action = c.read(logSessionActionProvider.notifier);

      await action.log(_session('s1'));
      await action.log(_session('s2'));

      expect(repo.saveCalls, 2);
      expect(repo.cached('alice').map((s) => s.id).toSet(), {'s1', 's2'});
    });

    test('the guard is released after a failed save, and the error is kept',
        () async {
      final repo = _GatedRepo()..saveError = StateError('rejected');
      final c = _container(repo);
      await c.read(authUserProvider.future);
      c.listen(logSessionActionProvider, (_, __) {});
      final action = c.read(logSessionActionProvider.notifier);

      await action.log(_session('s1'));
      expect(c.read(logSessionActionProvider).hasError, isTrue);

      repo.saveError = null;
      await action.log(_session('s1'));
      expect(repo.saveCalls, 2,
          reason: 'an error state is not "in flight"; retry must write');
      expect(c.read(logSessionActionProvider).hasError, isFalse);
    });
  });

  group('LogSessionAction streak write', () {
    test('a failing streak write is swallowed; the completion still succeeds',
        () async {
      final repo = _GatedRepo()..streakThrows = true;
      final c = _container(repo);
      await c.read(authUserProvider.future);
      c.listen(logSessionActionProvider, (_, __) {});

      await c.read(logSessionActionProvider.notifier).log(_session('s1'));

      expect(repo.streakCalls, 1, reason: 'the streak path must be reached');
      expect(c.read(logSessionActionProvider).hasError, isFalse);
      expect(repo.cached('alice').map((s) => s.id), ['s1']);
    });

    testWidgets(
        'a streak write that never completes is cut at 4 s and does not fail '
        'the completion', (tester) async {
      final repo = _GatedRepo()..streakHangs = true;
      final c = _container(repo);
      c.listen(authUserProvider, (_, __) {});
      c.listen(logSessionActionProvider, (_, __) {});
      await tester.pump();
      expect(c.read(authUserProvider).valueOrNull, _user);

      final done = c.read(logSessionActionProvider.notifier).log(_session('s1'));
      await tester.pump(const Duration(seconds: 3));
      expect(repo.streakCalls, 1);
      expect(c.read(logSessionActionProvider).isLoading, isTrue,
          reason: 'still within the 4 s bound');

      await tester.pump(const Duration(seconds: 2));
      await done;

      final state = c.read(logSessionActionProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse,
          reason: 'the timeout is swallowed like any streak failure');
      expect(repo.cached('alice').map((s) => s.id), ['s1']);
    });
  });
}
