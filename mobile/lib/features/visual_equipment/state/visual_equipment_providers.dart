import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/visual_equipment_match.dart';
import '../data/visual_equipment_service.dart';

final visualEquipmentServiceProvider =
    Provider<VisualEquipmentService>((_) {
  return MockVisualEquipmentService();
});

class VisualEquipmentController
    extends Notifier<AsyncValue<List<VisualMatch>>> {
  @override
  AsyncValue<List<VisualMatch>> build() => const AsyncValue.data([]);

  Future<void> classifyBytes(List<int> bytes) async {
    state = const AsyncValue.loading();
    try {
      final r = await ref
          .read(visualEquipmentServiceProvider)
          .classify(imageBytes: bytes);
      state = AsyncValue.data(r);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final visualEquipmentControllerProvider = NotifierProvider<
    VisualEquipmentController, AsyncValue<List<VisualMatch>>>(
  VisualEquipmentController.new,
);
