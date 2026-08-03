import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../data/visual_equipment_match.dart';
import '../data/visual_equipment_service.dart';
import 'machine_card_providers.dart';

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
    ref.read(lastMachineCardProvider.notifier).clear();
    try {
      final r = await ref
          .read(visualEquipmentServiceProvider)
          .classifyFile(path: path);
      state = AsyncValue.data(r);
      // In the catalog → the catalog answers, and it answers immediately.
      // Operator: *"если есть в каталоге то показывать из каталога сразу"*.
      if (r.isEmpty) await _describeInstead(path);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Not in the catalog. Ask the model what the thing actually is, show the
  /// user that, and keep the card so the missing clip has a name and a photo
  /// attached to it.
  ///
  /// Deliberately after `state` is already set: recognition has finished and
  /// the screen has stopped spinning. This second question is additive, and if
  /// it fails the user still has the honest "not in the catalog" answer rather
  /// than an error where a result used to be.
  Future<void> _describeInstead(String path) async {
    final card = await ref.read(machineDescriberProvider).describe(
          path: path,
          languageCode: ref.read(effectiveLanguageCodeProvider),
        );
    if (card == null) return;
    ref.read(lastMachineCardProvider.notifier).set(card);
    try {
      await ref.read(machineCardRepositoryProvider).save(card);
    } catch (e) {
      // The user is looking at the card either way; only the record failed.
      // Losing one row of "what people photograph" is not worth taking the
      // answer off their screen.
      debugPrint('could not save the machine card: $e');
    }
  }
}

final visualEquipmentControllerProvider = NotifierProvider<
    VisualEquipmentController, AsyncValue<List<VisualMatch>>>(
  VisualEquipmentController.new,
);
