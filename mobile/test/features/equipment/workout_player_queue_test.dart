import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/workout_queue_flag.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/offline/app_wiring.dart';
import 'package:fitness_app/features/workouts/offline/status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// The player's Mark complete button with the V0 queue wired: what the user
/// sees (chip, error snackbar) and what is written (queue before legacy save).
ExerciseItem _ex(String id, String title) => ExerciseItem.fromJson({
      'id': id,
      'title': title,
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': const ['quadriceps'],
      'steps': const ['Stand tall', 'Sit back', 'Drive up'],
    });

final _squat = _ex('ea_air_squat', 'Air Squat');
final _row = _ex('ea_row', 'Bent-over Row');

class _Gateway extends Fake implements WorkoutQueueGateway {
  final List<QueuedSet> calls = [];
  Object? error;
  int savesAtAccept = -1;
  MockWorkoutSessionRepository? repoToProbe;

  @override
  Future<void> acceptSet(QueuedSet set) async {
    calls.add(set);
    if (error != null) throw error!;
  }
}

Widget _app({
  required bool flag,
  required _Gateway gw,
  required MockWorkoutSessionRepository repo,
  SessionSyncStatus? status,
  List<String>? statusIds,
  String? exerciseId,
  String? dayId,
}) {
  final day = ScheduledSession(
    id: 'day_1',
    exerciseId: _squat.id,
    exerciseTitle: _squat.title,
    scheduledFor: DateTime.utc(2026, 8, 14, 9),
    durationMinutes: 30,
    extraExercises: [
      WorkoutSessionExercise(exerciseId: _row.id, exerciseTitle: _row.title),
    ],
  );
  return ProviderScope(
    overrides: [
      workoutCommandQueueEnabledProvider.overrideWithValue(flag),
      workoutQueueGatewayProvider.overrideWithValue(gw),
      workoutQueueSessionStatusProvider.overrideWith((ref, id) {
        statusIds?.add(id);
        return Stream.value(status);
      }),
      exerciseResolutionProvider.overrideWith((ref, id) async =>
          ExerciseResolution.found([_squat, _row].firstWhere((e) => e.id == id))),
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      workoutSessionRepositoryProvider.overrideWithValue(repo),
      scheduledSessionsProvider.overrideWith((_) => Stream.value([day])),
      workoutSessionsProvider.overrideWith((_) => repo.watch('u1')),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkoutPlayerPage(exerciseId: exerciseId ?? 'ea_row', dayId: dayId),
    ),
  );
}

void main() {
  Future<void> tall(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t) async {
    await t.tap(find.byKey(const Key('player.markComplete')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<List<WorkoutSession>> stored(
          WidgetTester t, MockWorkoutSessionRepository r) async =>
      (await t.runAsync(() => r.watch('u1').first))!;

  testWidgets('flag OFF: no chip, gateway untouched, set saved as before',
      (t) async {
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    final gw = _Gateway();
    await t.pumpWidget(_app(flag: false, gw: gw, repo: repo, dayId: 'day_1'));
    await t.pumpAndSettle();
    await tap(t);
    expect(gw.calls, isEmpty);
    expect(find.byKey(const Key('player.queueChip')), findsNothing);
    expect(await stored(t, repo), hasLength(1));
  });

  testWidgets('flag ON, day: queue gets the set, then legacy save happens, '
      'rest timer starts', (t) async {
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    final gw = _Gateway();
    await t.pumpWidget(_app(flag: true, gw: gw, repo: repo, dayId: 'day_1'));
    await t.pumpAndSettle();
    await tap(t);
    expect(gw.calls, hasLength(1));
    final q = gw.calls.single;
    expect(q.exerciseId, 'ea_row');
    expect(q.dayId, 'day_1');
    expect(q.sessionId, 'day_day_1');
    expect(q.startedAtMs, greaterThan(0));
    expect(q.performedAtMs, greaterThanOrEqualTo(q.startedAtMs));
    final s = await stored(t, repo);
    expect(s, hasLength(1));
    expect(s.single.id, 'day_day_1');
    final c = ProviderScope.containerOf(t.element(find.byType(WorkoutPlayerPage)));
    expect(c.read(restTimerProvider).endsAt, isNotNull);
  });

  testWidgets('flag ON, no day: dayId null in the queued set', (t) async {
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    final gw = _Gateway();
    await t.pumpWidget(_app(flag: true, gw: gw, repo: repo));
    await t.pumpAndSettle();
    await tap(t);
    expect(gw.calls.single.dayId, isNull);
    expect(gw.calls.single.exerciseId, 'ea_row');
  });

  testWidgets('accept failure: error snackbar, NO repo.save, NO rest timer',
      (t) async {
    await tall(t);
    final repo = MockWorkoutSessionRepository(latency: Duration.zero);
    addTearDown(repo.dispose);
    final gw = _Gateway()..error = StateError('Workout queue is not available');
    await t.pumpWidget(_app(flag: true, gw: gw, repo: repo, dayId: 'day_1'));
    await t.pumpAndSettle();
    await tap(t);
    expect(gw.calls, hasLength(1));
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(find.textContaining('Workout queue is not available'), findsOneWidget);
    expect(await stored(t, repo), isEmpty);
    final c = ProviderScope.containerOf(t.element(find.byType(WorkoutPlayerPage)));
    expect(c.read(restTimerProvider).endsAt, isNull);
    expect(find.textContaining('Nice work'), findsNothing);
  });

  group('chip', () {
    Future<void> run(WidgetTester t, SessionSyncStatus? st,
        {List<String>? ids}) async {
      await tall(t);
      final repo = MockWorkoutSessionRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      await t.pumpWidget(_app(
          flag: true,
          gw: _Gateway(),
          repo: repo,
          status: st,
          statusIds: ids,
          dayId: 'day_1'));
      await t.pumpAndSettle();
    }

    testWidgets('pending', (t) async {
      final ids = <String>[];
      await run(t, const SessionSyncStatus(sessionId: 'x', pending: 2), ids: ids);
      expect(find.byKey(const Key('player.queueChip')), findsOneWidget);
      expect(find.text('Saved on this device, waiting to sync'), findsOneWidget);
      expect(ids, contains('day_day_1'),
          reason: 'the chip reads the queue session of the day');
    });
    testWidgets('synced', (t) async {
      await run(t, const SessionSyncStatus(sessionId: 'x', synced: 1));
      expect(find.text('Synced'), findsOneWidget);
    });
    testWidgets('could not sync wins over pending and synced', (t) async {
      await run(t,
          const SessionSyncStatus(sessionId: 'x', synced: 1, pending: 1, couldNotSync: 1));
      expect(find.textContaining('Could not sync'), findsOneWidget);
      expect(find.text('Synced'), findsNothing);
    });
    testWidgets('pending wins over synced', (t) async {
      await run(t, const SessionSyncStatus(sessionId: 'x', synced: 3, pending: 1));
      expect(find.text('Saved on this device, waiting to sync'), findsOneWidget);
      expect(find.text('Synced'), findsNothing);
    });
    testWidgets('all zero or unknown status: no chip', (t) async {
      await run(t, const SessionSyncStatus(sessionId: 'x'));
      expect(find.byKey(const Key('player.queueChip')), findsNothing);
    });
    testWidgets('null status (queue not open): no chip', (t) async {
      await run(t, null);
      expect(find.byKey(const Key('player.queueChip')), findsNothing);
    });
    testWidgets('superseded only: no misleading "Synced" chip', (t) async {
      await run(t, const SessionSyncStatus(sessionId: 'x', superseded: 1));
      expect(find.text('Synced'), findsNothing);
    });
  });
}
