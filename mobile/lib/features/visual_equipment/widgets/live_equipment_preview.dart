import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live_equipment_providers.dart';

/// Camera preview for live recognition.
///
/// Rebuilds off the service's [LiveEquipmentService.cameraSurface] notifier
/// rather than reading a getter once. That difference is the whole fix for the
/// black square the operator reported: `liveEquipmentServiceProvider` is a plain
/// `Provider` whose value never changes, so watching it alone built this widget
/// exactly once — before `start()` had finished opening the camera — and nothing
/// ever rebuilt it. The placeholder was permanent, and because the widget was
/// also `const`, even a parent rebuild could not reach it (`Element.updateChild`
/// short-circuits on an identical const widget).
///
/// Two listenables, because there are two distinct transitions and neither one
/// implies the other:
///   * null -> a controller exists (a plain field assignment inside `start()`),
///   * controller -> `isInitialized` (the controller's own `CameraValue`).
class LiveEquipmentPreview extends ConsumerWidget {
  const LiveEquipmentPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(liveEquipmentServiceProvider);
    return ValueListenableBuilder<CameraController?>(
      valueListenable: svc.cameraSurface,
      builder: (context, cam, _) {
        if (cam == null) return const _Warming();
        return ValueListenableBuilder<CameraValue>(
          valueListenable: cam,
          builder: (context, value, __) {
            if (!value.isInitialized) return const _Warming();
            final size = value.previewSize;
            return FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // Swapped: the sensor reports landscape while the preview is
                // painted portrait.
                width: size?.height ?? 720,
                height: size?.width ?? 1280,
                child: CameraPreview(cam),
              ),
            );
          },
        );
      },
    );
  }
}

/// Shown only while the camera is genuinely still opening — a state that now
/// ends on its own.
class _Warming extends StatelessWidget {
  const _Warming();

  @override
  Widget build(BuildContext context) {
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
