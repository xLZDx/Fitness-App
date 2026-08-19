import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/equipment_setup_note.dart';
import '../data/equipment_setup_note_repository.dart';

/// Where setup notes live. In-memory by default, Firestore in `main.dart` --
/// same split as every other repository in this feature.
final equipmentSetupNoteRepositoryProvider =
    Provider<EquipmentSetupNoteRepository>((_) {
  return MockEquipmentSetupNoteRepository();
});

/// Identifies one (equipment type, gym) pair for [equipmentSetupNoteProvider].
/// A record, not two positional family params: Riverpod families key on
/// `==`, and a record's structural equality is exactly what two lookups for
/// the same pair need to share a cache entry.
typedef EquipmentSetupNoteKey = ({String equipmentId, String gymId});

/// The user's saved reminder for this equipment type at this gym, or null
/// when they have never saved one. MRD-05: this is the "context retrieval"
/// half of Gate G -- reading it is just watching this provider with the
/// page's own `equipmentId` and the profile's current `gymId`, nothing else
/// has to trigger a lookup.
final equipmentSetupNoteProvider = FutureProvider.family<EquipmentSetupNote?,
    EquipmentSetupNoteKey>((ref, key) {
  return ref
      .watch(equipmentSetupNoteRepositoryProvider)
      .get(equipmentId: key.equipmentId, gymId: key.gymId);
});
