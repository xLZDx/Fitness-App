import '../../workouts/data/workout_log.dart';
import 'equipment_models.dart';

/// What the user last did on a piece of equipment, by TYPE.
///
/// "Type" is the whole contract: [equipmentId] identifies a machine model
/// (e.g. "leg press"), never the physical unit the scanner just photographed.
/// Two gyms' leg presses -- or the same gym's, six months apart -- collapse
/// into one id, so this is "last time you used a leg press", not "last time
/// you used *this* leg press". Nothing here claims otherwise.
///
/// Every field is copied verbatim from a real [WorkoutLogEntry] the user
/// logged. There is no derived trend, no projected next weight, no "up 5kg
/// since last time" -- Level-1 memory is recall, not coaching.
class EquipmentMemory {
  const EquipmentMemory({
    required this.equipmentId,
    required this.exerciseId,
    required this.exerciseTitle,
    required this.completedAt,
    this.weightKg,
    this.repsCompleted,
  });

  final String equipmentId;
  final String exerciseId;
  final String exerciseTitle;
  final DateTime completedAt;

  /// Null for a bodyweight set, or one the user logged without a weight.
  /// Absence is shown as absence, never as "0 kg".
  final double? weightKg;
  final int? repsCompleted;

  bool get hasWeight => weightKg != null;
}

/// The most recent logged set on [equipmentId], or `null` if the user has
/// never logged one.
///
/// [history] need not be sorted or pre-filtered -- every entry is resolved
/// to its equipment type via [catalogue] and the latest match by
/// [WorkoutLogEntry.completedAt] wins, so callers can pass
/// `workoutSessionHistoryProvider` straight through.
///
/// A log entry whose `exerciseId` is missing from [catalogue] (deleted or
/// renamed since it was logged) is skipped rather than guessed at -- a stale
/// id is not evidence about the equipment asked for.
EquipmentMemory? equipmentMemoryFor(
  String equipmentId,
  List<WorkoutLogEntry> history,
  Map<String, ExerciseItem> catalogue,
) {
  WorkoutLogEntry? latest;
  for (final entry in history) {
    final exercise = catalogue[entry.exerciseId];
    if (exercise == null || exercise.equipmentId != equipmentId) continue;
    if (latest == null || entry.completedAt.isAfter(latest.completedAt)) {
      latest = entry;
    }
  }
  if (latest == null) return null;

  return EquipmentMemory(
    equipmentId: equipmentId,
    exerciseId: latest.exerciseId,
    exerciseTitle: latest.exerciseTitle,
    completedAt: latest.completedAt,
    weightKg: latest.weightKg,
    repsCompleted: latest.repsCompleted,
  );
}
