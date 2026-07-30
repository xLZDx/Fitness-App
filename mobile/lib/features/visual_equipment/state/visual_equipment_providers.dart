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

  /// The file route decodes JPEG + EXIF rotation correctly
  /// (see VisualEquipmentService — the raw-bytes route is gone).
  Future<void> classifyFilePath(String path) async {
    state = const AsyncValue.loading();
    try {
      final r = await ref
          .read(visualEquipmentServiceProvider)
          .classifyFile(path: path);
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
