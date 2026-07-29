import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mlkit_live_equipment_service.dart';
import '../state/live_equipment_providers.dart';

/// Camera preview for live recognition.
///
/// The type check keeps `CameraController` out of the service interface: the
/// mock used by widget tests has no camera at all and renders the placeholder
/// instead, so tests never need a camera binding.
class LiveEquipmentPreview extends ConsumerWidget {
  const LiveEquipmentPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(liveEquipmentServiceProvider);
    if (svc is MlKitLiveEquipmentService) {
      final cam = svc.cameraController;
      if (cam != null && cam.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: cam.value.previewSize?.height ?? 720,
            height: cam.value.previewSize?.width ?? 1280,
            child: CameraPreview(cam),
          ),
        );
      }
    }
    return const ColoredBox(
      color: Colors.black54,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
