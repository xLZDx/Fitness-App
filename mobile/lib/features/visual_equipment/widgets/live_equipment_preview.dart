import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/camera/camera_session.dart';

/// Live camera viewfinder.
///
/// Rebuilds off [CameraSession.surface] rather than reading a getter once. That
/// difference is the whole fix for the black square the operator reported: the
/// preview used to watch a plain `Provider` whose value never changes and read
/// the controller as a one-shot field, so it built exactly once — before the
/// camera had finished opening — and nothing ever rebuilt it. It was `const`
/// too, so even a parent rebuild could not reach it (`Element.updateChild`
/// short-circuits on an identical const widget).
///
/// Two listenables, because there are two distinct transitions and neither
/// implies the other:
///   * null -> a controller exists (a field assignment inside `start()`),
///   * controller -> `isInitialized` (the controller's own `CameraValue`).
class LiveEquipmentPreview extends StatelessWidget {
  const LiveEquipmentPreview({super.key, required this.session});

  final CameraSession session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraController?>(
      valueListenable: session.surface,
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
