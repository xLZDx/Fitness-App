import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_memory_providers.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// M3 wiring — `equipmentMemoryProvider` has to actually reach the real
/// completed-session history and the real safe catalogue, not just get the
/// arithmetic right in isolation (`equipment_memory_test.dart` covers that).

ExerciseItem _e(String id, {String? equipmentId}) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      muscles: const [],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: const ['a'],
    );

WorkoutSession _session(
  String id,
  String exerciseId,
  DateTime completedAt, {
  double? weightKg,
  int? reps,
}) =>
    WorkoutSession(
      id: id,
      title: exerciseId,
      startedAt: completedAt,
      completedAt: completedAt,
      status: WorkoutSessionStatus.completed,
      durationMinutes: 10,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: exerciseId,
          exerciseTitle: exerciseId,
          sets: weightKg == null && reps == null
              ? const []
              : [(weightKg: weightKg, reps: reps)],
        ),
      ],
    );

ProviderContainer _container(List<WorkoutSession> sessions) {
  final c = ProviderContainer(overrides: [
    workoutSessionsProvider.overrideWith((_) => Stream.value(sessions)),
    safeCatalogProvider.overrideWith((_) async => [
          _e('leg_press_a', equipmentId: 'leg_press'),
          _e('lat_pulldown', equipmentId: 'cable_pulldown'),
        ]),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('resolves the real completed session through the real catalogue',
      () async {
    final when = DateTime(2026, 8, 10, 9);
    final c = _container([
      _session('s1', 'leg_press_a', when, weightKg: 70, reps: 8),
    ]);
    await c.read(safeCatalogProvider.future);
    await c.read(workoutSessionsProvider.future);

    final memory = c.read(equipmentMemoryProvider('leg_press'));

    expect(memory, isNotNull);
    expect(memory!.weightKg, 70);
    expect(memory.repsCompleted, 8);
  });

  test('a pending (uncompleted) session is not memory', () async {
    final when = DateTime(2026, 8, 10, 9);
    final pending = WorkoutSession(
      id: 's1',
      title: 'leg_press_a',
      startedAt: when,
      status: WorkoutSessionStatus.pending,
      durationMinutes: 10,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: 'leg_press_a',
          exerciseTitle: 'leg_press_a',
          sets: const [(weightKg: 70.0, reps: 8)],
        ),
      ],
    );
    final c = _container([pending]);
    await c.read(safeCatalogProvider.future);
    await c.read(workoutSessionsProvider.future);

    final memory = c.read(equipmentMemoryProvider('leg_press'));

    expect(memory, isNull);
  });

  test('a different equipment id in the same catalogue returns null',
      () async {
    final when = DateTime(2026, 8, 10, 9);
    final c = _container([
      _session('s1', 'lat_pulldown', when, weightKg: 40, reps: 10),
    ]);
    await c.read(safeCatalogProvider.future);
    await c.read(workoutSessionsProvider.future);

    final memory = c.read(equipmentMemoryProvider('leg_press'));

    expect(memory, isNull);
  });
}
