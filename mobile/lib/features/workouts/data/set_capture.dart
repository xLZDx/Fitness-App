/// What the user actually lifted in one set. Null fields mean "declined to
/// say".
///
/// Lives in `data/`, not `widgets/`, because [WorkoutSessionExercise]
/// (`workout_session.dart`) needs it and a data model must not depend on a
/// widget file. `set_capture_sheet.dart` re-exports this so its own public
/// surface is unchanged for existing importers.
typedef SetCapture = ({double? weightKg, int? reps});

/// Equipment whose sets carry an external load, and are therefore worth asking
/// a weight for.
///
/// One list, not two. `planFor` (`set_timer_providers.dart`) already had these
/// ids inline to decide that loaded work wants longer rests; asking "does this
/// exercise take a weight" is the same question, and a second copy would have
/// drifted the first time a machine was added to one of them.
const kLoadedEquipmentIds = {
  'barbell', 'dumbbell', 'kettlebell', 'ez_curl_bar', 'smith_machine',
  'squat_rack', 'bench_press', 'leg_press', 'lat_pulldown', 'cable_machine',
  'weight_plates', 't_bar_row', 'seated_row_machine', 'hack_squat_machine',
};

/// Whether it makes sense to ask what was lifted.
///
/// Operator, 2026-08-13: *"не спрашивать вес вообще если для упражнения вес не
/// нужен, например для йоги, присида, отжимания, скручивания"*. A weight field
/// on a press-up is not a harmless extra box — it is a question with no true
/// answer, so the only way past it is to dismiss it, on every single set.
///
/// Deliberately a WHITELIST of loaded equipment rather than a blacklist of
/// bodyweight movements. The catalogue is 1,887 rows and grows; an unknown or
/// missing `equipmentId` therefore means "no weight asked", which is the
/// harmless direction to be wrong in. A stretch never asks, whatever it is
/// tagged with.
bool exerciseUsesLoad({String? equipmentId, bool isStretch = false}) {
  if (isStretch) return false;
  final id = equipmentId;
  return id != null && kLoadedEquipmentIds.contains(id);
}
