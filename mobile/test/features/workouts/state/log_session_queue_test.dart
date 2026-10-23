import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/workout_queue_flag.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/offline/app_wiring.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// LogSessionAction.log with the V0 queue: flag off equals the legacy path;
/// flag on commits to the queue BEFORE repo.save and a queue failure means
/// no save.
class _Repo extends MockWorkoutSessionRepository {
  _Repo(this.events) : super(latency: Duration.zero);
  final List<String> events;
  Completer<void>? gate;
  int saves = 0;
  Object? err;

  @override
  Future<void> save(String uid, WorkoutSession session) async {
    saves++;
    events.add('save');
    if (gate != null) await gate!.future;
    if (err != null) throw err!;
    await super.save(uid, session);
  }
}

class _Gateway extends Fake implements WorkoutQueueGateway {
  _Gateway(this.events);
  final List<String> events;
  final List<QueuedSet> calls = [];
  Completer<void>? gate;
  Object? error;

  @override
  Future<void> acceptSet(QueuedSet set) async {
    calls.add(set);
    events.add('accept');
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    events.add('accepted');
  }
}

WorkoutSession _session() => WorkoutSession(
      id: 'day_d1',
      title: 'Leg day',
      exercises: const [],
      startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      completedAt: DateTime.now(),
      status: WorkoutSessionStatus.completed,
    );

const _q = QueuedSet(
  sessionId: 'day_d1',
  exerciseId: 'e1',
  dayId: 'd1',
  startedAtMs: 1,
  performedAtMs: 2,
  weightKg: 50,
  reps: 5,
);

void main() {
  late List<String> events;
  late _Repo repo;
  late _Gateway gw;

  ProviderContainer make({bool flag = true, AuthUser? user}) {
    final u = user ?? const AuthUser(uid: 'alice', displayName: 'A');
    final c = ProviderContainer(overrides: [
      workoutCommandQueueEnabledProvider.overrideWithValue(flag),
      workoutQueueGatewayProvider.overrideWithValue(gw),
      authUserProvider.overrideWith((ref) => Stream.value(u)),
      workoutSessionRepositoryProvider.overrideWith((ref) {
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ]);
    addTearDown(c.dispose);
    // Prime the stream provider so authUser has a value.
    c.listen(authUserProvider, (_, __) {});
    return c;
  }

  setUp(() {
    events = [];
    repo = _Repo(events);
    gw = _Gateway(events);
  });

  Future<void> primed(ProviderContainer c) =>
      c.read(authUserProvider.future).then((_) {});

  test('flag OFF + queued given: queue never touched, save runs once',
      () async {
    final c = make(flag: false);
    await primed(c);
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(gw.calls, isEmpty);
    expect(events.where((e) => e == 'save'), hasLength(1));
    expect(c.read(logSessionActionProvider).hasError, isFalse);
  });

  test('flag OFF + queued null: legacy path', () async {
    final c = make(flag: false);
    await primed(c);
    await c.read(logSessionActionProvider.notifier).log(_session());
    expect(gw.calls, isEmpty);
    expect(repo.saves, 1);
  });

  test('flag ON: accept completes BEFORE save starts', () async {
    final c = make();
    await primed(c);
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(events, ['accept', 'accepted', 'save']);
    expect(gw.calls.single, same(_q));
    expect(c.read(logSessionActionProvider).hasError, isFalse);
  });

  test('flag ON: save is not started while accept is still pending', () async {
    final c = make();
    await primed(c);
    gw.gate = Completer<void>();
    final f = c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repo.saves, 0);
    expect(c.read(logSessionActionProvider).isLoading, isTrue);
    // A second tap while the first is in flight is ignored (one accept).
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(gw.calls, hasLength(1));
    gw.gate!.complete();
    await f;
    expect(repo.saves, 1);
  });

  test('flag ON + queued null (the rating re-log): no accept, save runs',
      () async {
    final c = make();
    await primed(c);
    await c.read(logSessionActionProvider.notifier).log(_session());
    expect(gw.calls, isEmpty);
    expect(repo.saves, 1);
  });

  test('flag ON: accept throws => error state, repo.save NEVER called',
      () async {
    final c = make();
    await primed(c);
    gw.error = StateError('Workout queue is not available');
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    final s = c.read(logSessionActionProvider);
    expect(s.hasError, isTrue);
    expect(s.error, isA<StateError>());
    expect(repo.saves, 0);
    // After a failure the action is usable again.
    gw.error = null;
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(c.read(logSessionActionProvider).hasError, isFalse);
    expect(repo.saves, 1);
  });

  test('flag ON: accept ok but save fails => error state, accept happened once',
      () async {
    final c = make();
    await primed(c);
    repo.err = StateError('disk');
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(c.read(logSessionActionProvider).hasError, isTrue);
    expect(gw.calls, hasLength(1));
  });

  test('signed out: error, neither accept nor save', () async {
    final c = ProviderContainer(overrides: [
      workoutCommandQueueEnabledProvider.overrideWithValue(true),
      workoutQueueGatewayProvider.overrideWithValue(gw),
      authUserProvider.overrideWith((ref) => Stream<AuthUser?>.value(null)),
      workoutSessionRepositoryProvider.overrideWith((ref) {
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(authUserProvider, (_, __) {});
    await c.read(authUserProvider.future);
    await c.read(logSessionActionProvider.notifier).log(_session(), queued: _q);
    expect(c.read(logSessionActionProvider).hasError, isTrue);
    expect(gw.calls, isEmpty);
    expect(repo.saves, 0);
  });
}
