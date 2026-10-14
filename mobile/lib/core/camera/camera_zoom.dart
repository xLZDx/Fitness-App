import 'package:flutter/foundation.dart';

/// What a camera can do about zoom. The real implementation is a
/// `CameraController` ([CameraControllerZoom] in `camera_session.dart`); tests
/// give it a fake that reports any min/max, which is the only way to prove the
/// presets for an ultra-wide phone and for a 1..4x phone without hardware.
abstract class ZoomBackend {
  Future<double> minZoom();
  Future<double> maxZoom();
  Future<void> setZoom(double level);
}

/// The zoom range of the open camera and where it is now.
@immutable
class ZoomState {
  const ZoomState({required this.min, required this.max, required this.current});

  final double min;
  final double max;
  final double current;

  ZoomState withCurrent(double value) =>
      ZoomState(min: min, max: max, current: value);

  @override
  bool operator ==(Object other) =>
      other is ZoomState &&
      other.min == min &&
      other.max == max &&
      other.current == current;

  @override
  int get hashCode => Object.hash(min, max, current);
}

/// Zoom presets and clamping for one camera session.
///
/// Operator order 2026-10-14 (B): phone-camera style presets 0.6, 1, 2, 3, 5,
/// 10x, shown only when the DEVICE's real range contains them -- 0.6x only on
/// a phone that reports a minimum zoom of 0.6 or less (an ultra-wide lens) --
/// plus pinch to zoom, always clamped to the device limits.
class CameraZoom {
  CameraZoom();

  /// The presets a phone camera app offers, ascending.
  static const List<double> kPresets = <double>[0.6, 1, 2, 3, 5, 10];

  /// Tolerance for "the device reports 0.6" (it may report 0.5999 or 0.61).
  static const double kEdgeTolerance = 0.02;

  final ValueNotifier<ZoomState?> _state = ValueNotifier<ZoomState?>(null);
  ZoomBackend? _backend;

  /// Null while no camera is open.
  ValueListenable<ZoomState?> get state => _state;

  /// Reads the camera's range and publishes it. [initial] is clamped.
  Future<void> attach(ZoomBackend backend, {double initial = 1.0}) async {
    _backend = backend;
    double min = 1.0;
    double max = 1.0;
    try {
      min = await backend.minZoom();
      max = await backend.maxZoom();
    } catch (e) {
      debugPrint('zoom range unavailable, zoom disabled: $e');
      _backend = null;
      _state.value = null;
      return;
    }
    if (max < min) max = min;
    _state.value =
        ZoomState(min: min, max: max, current: initial.clamp(min, max));
  }

  /// Forgets the camera (it was released).
  void detach() {
    _backend = null;
    _state.value = null;
  }

  /// Sets [level], clamped to the device range. Returns the applied level, or
  /// null when there is no camera or the camera refused.
  Future<double?> setLevel(double level) async {
    final backend = _backend;
    final current = _state.value;
    if (backend == null || current == null) return null;
    final double clamped = level.clamp(current.min, current.max).toDouble();
    try {
      await backend.setZoom(clamped);
    } catch (e) {
      debugPrint('set zoom failed: $e');
      return null;
    }
    // The camera may have been released while the call was in flight.
    if (!identical(_backend, backend)) return null;
    _state.value = current.withCurrent(clamped);
    return clamped;
  }

  bool _applying = false;
  double? _pending;

  /// Fire-and-forget zoom for a pinch: a gesture produces a level per frame, so
  /// calls are coalesced -- one in flight, and only the LATEST waiting level
  /// is applied after it. Clamped like [setLevel].
  Future<void> requestLevel(double level) async {
    if (_applying) {
      _pending = level;
      return;
    }
    _applying = true;
    try {
      double? next = level;
      while (next != null) {
        _pending = null;
        await setLevel(next);
        next = _pending;
      }
    } finally {
      _applying = false;
    }
  }

  /// Back to 1x (or the nearest the device allows). Used when leaving the
  /// screen so the next visit does not start zoomed in.
  Future<void> reset() async {
    await setLevel(1.0);
  }

  /// Presets inside [state]'s range; 0.6x only when the device goes that wide.
  static List<double> presetsFor(ZoomState state) => <double>[
        for (final p in kPresets)
          if (p >= state.min - kEdgeTolerance &&
              p <= state.max + kEdgeTolerance)
            p,
      ];

  /// The preset the current level is at (within 4%), or null between presets.
  static double? activePreset(ZoomState state) {
    for (final p in presetsFor(state)) {
      if ((state.current - p).abs() <= p * 0.04) return p;
    }
    return null;
  }

  /// "0.6x", "1x", "2.5x".
  static String label(double level) {
    final String s = level.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}x';
  }
}
