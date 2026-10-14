import 'package:flutter/material.dart';

import '../../../core/camera/camera_zoom.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// Smallest touch target on the Scan screen, in logical pixels (the zoom chips
/// and the OK / NOT OK marks).
const double kScanTouchTarget = 44;

/// Phone-camera style zoom for the Scan preview (operator order 2026-10-14, B):
/// a small current-zoom label and one chip per preset the DEVICE really has
/// (0.6, 1, 2, 3, 5, 10x -- see [CameraZoom.presetsFor]), the active one
/// highlighted. Draws nothing while no camera is open.
///
/// Keys: `scan-zoom-label`, and `scan-zoom-<preset>` per chip (`scan-zoom-0.6`,
/// `scan-zoom-1`, ...).
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.zoom});

  final CameraZoom zoom;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ZoomState?>(
      valueListenable: zoom.state,
      builder: (context, state, _) {
        if (state == null) return const SizedBox.shrink();
        final List<double> presets = CameraZoom.presetsFor(state);
        if (presets.length < 2) {
          // A fixed-zoom camera: nothing to choose between.
          return const SizedBox.shrink();
        }
        final double? active = CameraZoom.activePreset(state);
        // Dark ink on the camera whatever the app theme: this sits on the
        // preview, which is dark.
        final AppSemanticColors dark = AppSemanticColors.dark;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: dark.cameraOverlay,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            // Six 44 px targets plus the label need ~330 px: scale down on a
            // narrower window instead of overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    CameraZoom.label(state.current),
                    key: const Key('scan-zoom-label'),
                    style: TextStyle(
                      color: dark.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final double p in presets)
                  _PresetChip(
                    preset: p,
                    selected: active == p,
                    onTap: () => zoom.requestLevel(p),
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final double preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppSemanticColors dark = AppSemanticColors.dark;
    final String text = CameraZoom.label(preset);
    return Semantics(
      button: true,
      selected: selected,
      label: text,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('scan-zoom-${text.substring(0, text.length - 1)}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // A 44 x 44 touch target (the accessibility minimum), with no outer
          // margin so neighbouring targets do not overlap or leave dead gaps.
          constraints: const BoxConstraints(
              minWidth: kScanTouchTarget, minHeight: kScanTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: selected ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: selected ? null : BorderRadius.circular(18),
            color: selected ? dark.textPrimary : Colors.transparent,
          ),
          child: Text(
            text,
            key: Key('scan-zoom-text-${text.substring(0, text.length - 1)}'),
            style: TextStyle(
              color: selected ? dark.cameraOverlay.withValues(alpha: 1) : dark.textPrimary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinch-to-zoom over the preview. Wraps [child] without taking taps: a tap
/// still reaches whatever is underneath; only a two-finger scale zooms.
class ZoomPinchLayer extends StatefulWidget {
  const ZoomPinchLayer({super.key, required this.zoom, required this.child});

  final CameraZoom zoom;
  final Widget child;

  @override
  State<ZoomPinchLayer> createState() => _ZoomPinchLayerState();
}

class _ZoomPinchLayerState extends State<ZoomPinchLayer> {
  double _base = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (_) => _base = widget.zoom.state.value?.current ?? 1,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2 || widget.zoom.state.value == null) return;
        widget.zoom.requestLevel(_base * d.scale);
      },
      child: widget.child,
    );
  }
}
