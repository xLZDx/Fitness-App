import 'equipment_setup_note.dart';

/// Where a user's per-(equipment type, gym) setup reminders live.
abstract class EquipmentSetupNoteRepository {
  /// The note for this pair, or null when the user has never saved one.
  Future<EquipmentSetupNote?> get({
    required String equipmentId,
    required String gymId,
  });

  /// Overwrites the note for `(note.equipmentId, note.gymId)`. An empty
  /// [EquipmentSetupNote.note] is a valid save (the user cleared the box) and
  /// is stored as such, not silently turned into a delete -- deleting is
  /// [delete]'s job, explicitly.
  Future<void> save(EquipmentSetupNote note);

  Future<void> delete({required String equipmentId, required String gymId});
}

/// In-memory [EquipmentSetupNoteRepository] -- the default binding and what
/// tests run against.
class MockEquipmentSetupNoteRepository implements EquipmentSetupNoteRepository {
  final Map<String, EquipmentSetupNote> _store = {};

  @override
  Future<EquipmentSetupNote?> get({
    required String equipmentId,
    required String gymId,
  }) async =>
      _store[equipmentSetupNoteId(equipmentId: equipmentId, gymId: gymId)];

  @override
  Future<void> save(EquipmentSetupNote note) async {
    _store[note.id] = note;
  }

  @override
  Future<void> delete({
    required String equipmentId,
    required String gymId,
  }) async {
    _store.remove(equipmentSetupNoteId(equipmentId: equipmentId, gymId: gymId));
  }
}
