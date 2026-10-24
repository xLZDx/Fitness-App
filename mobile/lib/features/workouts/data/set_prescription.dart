/// What one set asks of the person: a number of repetitions, or a time.
///
/// Local to the workouts feature on purpose. A programme-level prescription
/// ("2 reps at 90 kg") is a later step; until then the mode is derived from the
/// exercise itself and the numbers from the person's tier and last captured
/// load. Nothing here is persisted.
library;

import '../../equipment/data/equipment_models.dart';
import '../../profile/data/profile_models.dart';

enum SetMode {
  /// Counted in repetitions; the person taps "Done" when the set is finished.
  reps,

  /// Counted in seconds (isometric holds, cardio, stretching): the clock ends
  /// the set.
  timed,
}

/// The prescription for one set. Defaulted to timed so every caller that
/// predates it keeps today's behaviour.
class SetPrescription {
  const SetPrescription({
    this.mode = SetMode.timed,
    this.targetReps,
    this.loadKg,
  });

  final SetMode mode;

  /// Only meaningful for [SetMode.reps].
  final int? targetReps;

  /// Null when no load is known (bodyweight, or the person has not said).
  final double? loadKg;

  bool get isReps => mode == SetMode.reps;

  @override
  bool operator ==(Object other) =>
      other is SetPrescription &&
      other.mode == mode &&
      other.targetReps == targetReps &&
      other.loadKg == loadKg;

  @override
  int get hashCode => Object.hash(mode, targetReps, loadKg);
}

/// Default repetitions per set for a tier.
///
/// Beginner (and `never`) 12, intermediate 10, advanced 8: a lighter load for
/// more reps while technique is being learned, heavier and lower for the
/// experienced. A starting point the person can change through the capture
/// sheet, not a prescription.
int defaultTargetReps(FitnessTier? tier) => switch (tier) {
      FitnessTier.never || FitnessTier.beginner => 12,
      FitnessTier.advanced => 8,
      FitnessTier.intermediate || null => 10,
    };

/// Equipment that is inherently timed: cardio machines.
const _timedEquipmentIds = {
  'treadmill',
  'rowing_machine',
  'exercise_bike',
  'elliptical',
  'stair_climber',
};

/// Catalogue groups that are timed work: mobility and yoga.
const _timedVendorGroups = {'stretching - mobility', 'yoga'};

/// Title words of isometric holds and cardio drills that the catalogue does not
/// tag any other way. Whole-word matches only, so "pushup" or "runner's
/// lunge" style titles are not caught by accident.
final _timedTitle = RegExp(
  r'\b(plank|planks|wall sit|hollow hold|dead hang|l-sit|isometric|'
  r'hold|holds|jumping jacks?|mountain climbers?|high knees|jog|jogging|'
  r'run|running|sprint|sprints|jump rope|skipping|stretch|stretches|'
  r'yoga|pilates|mobility|cardio)\b',
  caseSensitive: false,
);

/// Whether the exercise is inherently timed. Everything else, loaded or
/// bodyweight strength work, is counted in repetitions.
bool exerciseIsTimed(ExerciseItem exercise) {
  if (exercise.isStretch) return true;
  if (_timedEquipmentIds.contains(exercise.equipmentId)) return true;
  if (_timedVendorGroups.contains(exercise.vendorGroup?.toLowerCase().trim())) {
    return true;
  }
  return _timedTitle.hasMatch(exercise.title);
}
