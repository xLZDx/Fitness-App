import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workouts/state/workout_session_providers.dart';
import '../data/equipment_memory.dart';
import '../data/equipment_models.dart';
import 'equipment_providers.dart';

/// Same construction as `todayResultProvider`: the catalogue map is built
/// here so Riverpod rebuilds it only when the catalogue changes, not once per
/// `.family` read.
final _equipmentMemoryCatalogueProvider =
    Provider<Map<String, ExerciseItem>>((ref) {
  final catalog =
      ref.watch(safeCatalogProvider).valueOrNull ?? const <ExerciseItem>[];
  return {for (final e in catalog) e.id: e};
});

/// Level-1 equipment-type memory: what the user last logged on this
/// [equipmentId], if anything. See [EquipmentMemory] for what "type" means
/// here and why nothing beyond the last logged set is surfaced.
final equipmentMemoryProvider =
    Provider.family<EquipmentMemory?, String>((ref, equipmentId) {
  final history = ref.watch(workoutSessionHistoryProvider);
  final catalogue = ref.watch(_equipmentMemoryCatalogueProvider);
  return equipmentMemoryFor(equipmentId, history, catalogue);
});
