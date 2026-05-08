import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/asset_equipment_repository.dart';
import '../data/equipment_models.dart';
import '../data/equipment_repository.dart';

final equipmentRepositoryProvider = Provider<EquipmentRepository>((ref) {
  return AssetEquipmentRepository();
});

/// All exercises that target a specific piece of equipment, looked up by id.
final exercisesForEquipmentProvider =
    FutureProvider.family<List<ExerciseItem>, String>((ref, equipmentId) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.exercisesFor(equipmentId);
});

final equipmentByIdProvider =
    FutureProvider.family<EquipmentItem?, String>((ref, id) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.findEquipment(id);
});
