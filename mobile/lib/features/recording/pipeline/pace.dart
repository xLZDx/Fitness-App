/// Pace and speed (S04-R-033, design 3.7). Pure Dart, no Flutter imports, no
/// I/O. Undefined is `null`: never zero, never infinite.
library;

import 'recording_constants.dart';

/// Average speed in m/s: moving distance over moving time. Null when the
/// moving time is not positive or an input is not finite.
double? averageSpeedMps(double distanceM, double movingTimeS) {
  if (!distanceM.isFinite || !movingTimeS.isFinite) return null;
  if (movingTimeS <= 0) return null;
  return distanceM / movingTimeS;
}

/// Average pace in seconds per kilometre: moving time over moving distance.
/// Null when the moving time is not positive, or the moving distance is below
/// [minMovingDistanceM] (default [kPaceMinMovingDistanceM]) or zero.
double? averagePaceSecPerKm(double distanceM, double movingTimeS,
    {double minMovingDistanceM = kPaceMinMovingDistanceM}) {
  if (!distanceM.isFinite || !movingTimeS.isFinite) return null;
  if (movingTimeS <= 0 || distanceM <= 0) return null;
  if (distanceM < minMovingDistanceM) return null;
  return movingTimeS / (distanceM / 1000.0);
}

/// Current pace over a trailing window of MOVING time. Feed it points of
/// `(moving time, cumulative moving distance)`; paused spans do not advance
/// the moving time, so they never enter the window.
class PaceWindow {
  PaceWindow({
    this.windowMs = kPaceWindowMs,
    this.minMovingDistanceM = kPaceMinMovingDistanceM,
  });

  final int windowMs;
  final double minMovingDistanceM;

  // Oldest first. The first point is the newest one at or before
  // `latest - windowMs`, once such a point exists.
  final List<({int tMs, double distM})> _pts = [];

  /// Adds the state after a smoothed fix. [movingMs] must not decrease and
  /// [distanceM] is the cumulative moving distance.
  void add(int movingMs, double distanceM) {
    _pts.add((tMs: movingMs, distM: distanceM));
    // Drop points that are older than the newest point at or before the
    // window start.
    final windowStart = movingMs - windowMs;
    var firstUseful = 0;
    for (var i = 0; i < _pts.length; i++) {
      if (_pts[i].tMs <= windowStart) firstUseful = i;
    }
    if (firstUseful > 0) _pts.removeRange(0, firstUseful);
  }

  /// Metres covered in the trailing window, or null until the window is full.
  double? get _windowDistanceM {
    if (_pts.length < 2) return null;
    final last = _pts.last;
    final first = _pts.first;
    if (last.tMs - first.tMs < windowMs) return null;
    return last.distM - first.distM;
  }

  /// Current pace in s/km; null until the window is full, while the moving
  /// distance is under the minimum, or when nothing moved in the window.
  double? get currentPaceSecPerKm {
    final d = _windowDistanceM;
    if (d == null || _pts.last.distM < minMovingDistanceM || d <= 0) {
      return null;
    }
    final t = (_pts.last.tMs - _pts.first.tMs) / 1000.0;
    return t / (d / 1000.0);
  }

  /// Current speed in m/s over the same window, with the same undefined rules.
  double? get currentSpeedMps {
    final d = _windowDistanceM;
    if (d == null || _pts.last.distM < minMovingDistanceM || d <= 0) {
      return null;
    }
    return d / ((_pts.last.tMs - _pts.first.tMs) / 1000.0);
  }
}
