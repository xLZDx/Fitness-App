import 'package:fitness_app/core/camera/camera_zoom.dart';

/// A camera that reports any zoom range and records what it was asked to do.
/// Stands in for the plugin controller: the presets a phone shows depend on the
/// device's real min/max, which hardware-free tests can only supply this way.
class FakeZoomBackend implements ZoomBackend {
  FakeZoomBackend(this.min, this.max, {this.delay});

  final double min;
  final double max;
  final Duration? delay;
  final List<double> requested = <double>[];

  @override
  Future<double> minZoom() async => min;

  @override
  Future<double> maxZoom() async => max;

  @override
  Future<void> setZoom(double level) async {
    if (delay != null) await Future<void>.delayed(delay!);
    requested.add(level);
  }
}
