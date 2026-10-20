/// Distance of one continuous segment along a minimum-step chord (S04-R-032,
/// design 3.7). Pure Dart, no Flutter imports, no I/O.
library;

import 'geo.dart';
import 'recording_constants.dart';

/// Sums great-circle distance over the smoothed points of ONE segment, but
/// only between "anchor" points that are at least [minStepM] apart. Residual
/// jitter after smoothing is shorter than the step and so adds no length; the
/// part of the path after the last anchor is counted as the straight line to
/// the newest point, so a segment shorter than the step still has its length
/// and a straight clean track is measured exactly. The live pipeline and the
/// final calculator use this one class, so after the last point both agree.
class DistanceAccumulator {
  DistanceAccumulator({this.minStepM = kDistanceMinStepM});

  final double minStepM;

  double _committedM = 0;
  double? _anchorLat;
  double? _anchorLon;
  double _lastLat = 0;
  double _lastLon = 0;

  /// Adds the next smoothed point of the segment.
  void add(double lat, double lon) {
    final aLat = _anchorLat;
    final aLon = _anchorLon;
    if (aLat == null || aLon == null) {
      _anchorLat = lat;
      _anchorLon = lon;
    } else {
      final d = haversineM(aLat, aLon, lat, lon);
      if (d >= minStepM) {
        _committedM += d;
        _anchorLat = lat;
        _anchorLon = lon;
      }
    }
    _lastLat = lat;
    _lastLon = lon;
  }

  /// Distance so far, including the straight part after the last anchor.
  double get totalM {
    final aLat = _anchorLat;
    final aLon = _anchorLon;
    if (aLat == null || aLon == null) return 0;
    return _committedM + haversineM(aLat, aLon, _lastLat, _lastLon);
  }
}
