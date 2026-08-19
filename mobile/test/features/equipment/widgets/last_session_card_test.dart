import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/widgets/last_session_card.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// Gate D6/D7 — [LastSessionCard] proven against the real widget tree, not
/// just the pure matcher/formatter it wraps: real seeded sessions flow
/// through real providers into real rendered text, in both shipped locales,
/// including the D3 truncated-window honesty case — see
/// `core/product/GATE_D_EQUIPMENT_TYPE_HISTORY_D0_NOTE_2026-08-19.md`.
/// (Gate D5's screenshot is captured separately, in
/// `tool/capture_last_session_card.dart` — see its own doc comment for why.)
class _FakeEquipmentRepository implements EquipmentRepository {
  _FakeEquipmentRepository(this.exerciseIds);
  final List<String> exerciseIds;

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => [
        for (final id in exerciseIds)
          ExerciseItem.fromJson({
            'id': id,
            'title': id,
            'equipmentId': equipmentId,
            'durationMinutes': 10,
            'difficulty': 'beginner',
            'muscles': const <String>[],
            'steps': const ['Step'],
          }),
      ];

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => const [];

  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;

  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
}

WorkoutSession _completedSession({
  required String id,
  required String exerciseId,
  required DateTime completedAt,
  double? weightKg,
  int? reps,
}) =>
    WorkoutSession(
      id: id,
      title: exerciseId,
      status: WorkoutSessionStatus.completed,
      startedAt: completedAt.subtract(const Duration(minutes: 20)),
      completedAt: completedAt,
      durationMinutes: 20,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: exerciseId,
          exerciseTitle: exerciseId,
          sets: [(weightKg: weightKg, reps: reps)],
        ),
      ],
    );

Widget _harness({
  required List<String> exerciseIds,
  required List<WorkoutSession> sessions,
  required WorkoutLogTotals totals,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: [
        equipmentRepositoryProvider
            .overrideWithValue(_FakeEquipmentRepository(exerciseIds)),
        workoutSessionsProvider.overrideWith((_) => Stream.value(sessions)),
        workoutSessionTotalsProvider
            .overrideWith((_) async => totals),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('capture'),
              child: SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: const LastSessionCard(equipmentId: 'leg_press'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  final base = DateTime(2026, 8, 19, 9);

  testWidgets(
      'REGRESSION (Gate D7 review): does not flash "not found" while the '
      'session stream has not delivered its first snapshot yet', (tester) async {
    // totals resolves immediately (a real, nonzero all-time count); the
    // session stream deliberately never emits during this test. Before the
    // fix, workoutSessionHistoryProvider collapsed "still loading" into an
    // empty list indistinguishable from "no sessions", so this combination
    // used to render the truncated-miss text even though the real history
    // -- which might contain a match -- simply had not arrived.
    final sessionsCtrl = StreamController<List<WorkoutSession>>();
    addTearDown(sessionsCtrl.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentRepositoryProvider.overrideWithValue(
              _FakeEquipmentRepository(const ['leg_press_machine'])),
          workoutSessionsProvider.overrideWith((_) => sessionsCtrl.stream),
          workoutSessionTotalsProvider.overrideWith(
              (_) async => const WorkoutLogTotals(total: 250, longestStreakDays: 40)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 360,
              child: LastSessionCard(equipmentId: 'leg_press'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('equipment.lastSession')), findsNothing,
        reason: 'must stay silent, not claim "not found", before the '
            'session stream has ever emitted');
    expect(find.text('Not found in your recent workouts'), findsNothing);
  });

  testWidgets('renders the real weight/reps/date for a matching session',
      (tester) async {
    await tester.pumpWidget(_harness(
      exerciseIds: const ['leg_press_machine'],
      sessions: [
        _completedSession(
          id: 's1',
          exerciseId: 'leg_press_machine',
          completedAt: base,
          weightKg: 45,
          reps: 10,
        ),
      ],
      totals: const WorkoutLogTotals(total: 1, longestStreakDays: 1),
    ));
    await tester.pumpAndSettle();

    expect(find.text('45 kg × 10 reps'), findsOneWidget);
    expect(find.byKey(const Key('equipment.lastSession')), findsOneWidget);
  });

  testWidgets('renders nothing for confirmed no-history (complete window, no match)',
      (tester) async {
    await tester.pumpWidget(_harness(
      exerciseIds: const ['leg_press_machine'],
      sessions: [
        _completedSession(
          id: 's1',
          exerciseId: 'bench_press_barbell',
          completedAt: base,
          weightKg: 80,
          reps: 5,
        ),
      ],
      totals: const WorkoutLogTotals(total: 1, longestStreakDays: 1),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment.lastSession')), findsNothing);
  });

  testWidgets(
      'a truncated window with no match says so honestly, not "no history"',
      (tester) async {
    await tester.pumpWidget(_harness(
      exerciseIds: const ['leg_press_machine'],
      sessions: [
        _completedSession(
          id: 's1',
          exerciseId: 'bench_press_barbell',
          completedAt: base,
          weightKg: 80,
          reps: 5,
        ),
      ],
      // allTimeTotal (250) far exceeds the one session in the window --
      // the window is truncated, so a miss must not read as "no history".
      totals: const WorkoutLogTotals(total: 250, longestStreakDays: 40),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment.lastSession')), findsOneWidget);
    expect(find.text('Not found in your recent workouts'), findsOneWidget);
  });

  testWidgets('renders in Russian too', (tester) async {
    await tester.pumpWidget(_harness(
      exerciseIds: const ['leg_press_machine'],
      sessions: [
        _completedSession(
          id: 's1',
          exerciseId: 'leg_press_machine',
          completedAt: base,
          weightKg: 45,
          reps: 10,
        ),
      ],
      totals: const WorkoutLogTotals(total: 1, longestStreakDays: 1),
      locale: const Locale('ru'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('45 кг × 10 повт.'), findsOneWidget);
    expect(find.text('Ваша последняя тренировка на этом оборудовании'),
        findsOneWidget);
  });
}

// A fifth test here once attempted RenderRepaintBoundary.toImage() under the
// default VM test platform to produce a real Gate D5 screenshot. It hung for
// the full 10-minute suite timeout: `toImage()` needs a working rasterizer,
// and the headless VM runner has none. Screenshot capture was moved to
// `tool/capture_last_session_card.dart` (run under `flutter test
// --platform=chrome`, which does have one) rather than left in this suite,
// where a rasterizer regression would silently cost ten minutes of every run.
