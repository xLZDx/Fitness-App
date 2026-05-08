import 'equipment_models.dart';

/// Equipment catalog + exercise lookup. Implementations:
///   * [AssetEquipmentRepository] — loads `assets/data/equipment.json` and
///     `assets/data/exercises.json` shipped with the app. Used today.
///   * (Future Phase 2C) FirestoreEquipmentRepository — server-curated.
abstract class EquipmentRepository {
  /// Returns every known piece of equipment in the catalog.
  Future<List<EquipmentItem>> listEquipment();

  /// Looks up a single piece of equipment by id (the same id encoded in
  /// the QR code, e.g. `treadmill_precor_trm211`).
  Future<EquipmentItem?> findEquipment(String id);

  /// Every exercise that targets [equipmentId]. Use [ExerciseItem.equipmentId]
  /// `null` to fetch body-weight exercises.
  Future<List<ExerciseItem>> exercisesFor(String equipmentId);

  /// Body-weight / no-equipment "Workout at Home" exercises.
  Future<List<ExerciseItem>> bodyweightExercises();
}
