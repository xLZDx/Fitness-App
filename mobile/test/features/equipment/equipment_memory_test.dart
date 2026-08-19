import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_memory.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

/// M3 — Level-1 equipment-type memory: "what did I last do on THIS TYPE of
/// machine", resolved from real logged sets via the exercise catalogue.
/// Never a claim about the physical unit in front of the user (see
/// [EquipmentMemory]'s doc comment) and never a number the user did not log.

ExerciseItem _e(String id, {String? equipmentId}) => ExerciseItem.fromJson({
      'id': id,
      'title': id,
      'equipmentId': equipmentId,
    });

WorkoutLogEntry _log(
  String id,
  DateTime when, {
  required String exerciseId,
  double? weightKg,
  int? repsCompleted,
}) =>
    WorkoutLogEntry(
      id: id,
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      completedAt: when,
      durationMinutes: 10,
      weightKg: weightKg,
      repsCompleted: repsCompleted,
    );

void main() {
  final catalogue = {
    'leg_press_a': _e('leg_press_a', equipmentId: 'leg_press'),
    'leg_press_b': _e('leg_press_b', equipmentId: 'leg_press'),
    'lat_pulldown': _e('lat_pulldown', equipmentId: 'cable_pulldown'),
    'plank': _e('plank'),
  };

  final older = DateTime(2026, 8, 1, 9);
  final newer = DateTime(2026, 8, 10, 9);

  test('returns the latest log entry mapped to the requested equipment', () {
    final history = [
      _log('1', older, exerciseId: 'leg_press_a', weightKg: 60, repsCompleted: 10),
      _log('2', newer, exerciseId: 'leg_press_a', weightKg: 70, repsCompleted: 8),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNotNull);
    expect(memory!.completedAt, newer);
    expect(memory.weightKg, 70);
    expect(memory.repsCompleted, 8);
  });

  test('unrelated equipment is excluded', () {
    final history = [
      _log('1', newer, exerciseId: 'lat_pulldown', weightKg: 40, repsCompleted: 10),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNull);
  });

  test('two different exercises on the same equipment type both count', () {
    final history = [
      _log('1', older, exerciseId: 'leg_press_a', weightKg: 60, repsCompleted: 10),
      _log('2', newer, exerciseId: 'leg_press_b', weightKg: 65, repsCompleted: 9),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNotNull);
    expect(memory!.exerciseId, 'leg_press_b');
    expect(memory.weightKg, 65);
  });

  test('a logged exercise missing from the catalogue is skipped, not guessed', () {
    final history = [
      _log('1', newer, exerciseId: 'deleted_exercise', weightKg: 999, repsCompleted: 1),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNull);
  });

  test('no history at all returns null, not zero', () {
    final memory = equipmentMemoryFor('leg_press', const [], catalogue);

    expect(memory, isNull);
  });

  test('a bodyweight or unweighted set keeps weight and reps null', () {
    final history = [
      _log('1', newer, exerciseId: 'leg_press_a'),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNotNull);
    expect(memory!.weightKg, isNull);
    expect(memory.repsCompleted, isNull);
    expect(memory.hasWeight, isFalse);
  });

  test('ordering does not depend on list order, only on completedAt', () {
    final history = [
      _log('1', newer, exerciseId: 'leg_press_a', weightKg: 70, repsCompleted: 8),
      _log('2', older, exerciseId: 'leg_press_a', weightKg: 60, repsCompleted: 10),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNotNull);
    expect(memory!.completedAt, newer);
    expect(memory.weightKg, 70);
  });

  test('equipment with no equipmentId (bodyweight exercises) never matches', () {
    final history = [
      _log('1', newer, exerciseId: 'plank'),
    ];

    final memory = equipmentMemoryFor('leg_press', history, catalogue);

    expect(memory, isNull);
  });
}
