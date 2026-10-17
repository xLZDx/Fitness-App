/// Elevation gain and loss (S04-R-034, design 3.7). Pure Dart, no Flutter
/// imports, no I/O.
library;

import 'recording_constants.dart';

/// Ascent and descent from GPS altitude, fed fix by fix (O(1) per fix, so the
/// same class serves the live number and the final computation).
///
/// Rules, in order: (1) a running median over the last
/// [kAltitudeMedianWindow] kept altitudes; (2) a step between consecutive
/// accepted medians above [kAltitudeMaxStepMps] metres per second (at least
/// one second) is an outlier and ignored; after [kAltitudeOutlierAcceptAfter]
/// consecutive outliers the new level is accepted without counting; (3)
/// hysteresis: a change counts only after the median moves
/// [kAltitudeHysteresisM] from the last counted level. No barometer in S04.
/// With no altitude at all ascent and descent are undefined (null), never 0.
class ElevationAccumulator {
  ElevationAccumulator({
    this.hysteresisM = kAltitudeHysteresisM,
    this.medianWindow = kAltitudeMedianWindow,
    this.maxStepMps = kAltitudeMaxStepMps,
    this.acceptAfter = kAltitudeOutlierAcceptAfter,
  });

  final double hysteresisM;
  final int medianWindow;
  final double maxStepMps;
  final int acceptAfter;

  final List<double> _window = [];
  double? _refMedian;
  int _refMs = 0;
  double? _level;
  int _outliers = 0;
  double _ascent = 0;
  double _descent = 0;
  bool _any = false;

  /// Metres climbed, or null when no altitude was ever seen.
  double? get ascentM => _any ? _ascent : null;

  /// Metres descended, or null when no altitude was ever seen.
  double? get descentM => _any ? _descent : null;

  /// Number of outliers ignored so far (diagnostic).
  int get outlierCount => _ignored;
  int _ignored = 0;

  /// Feeds the altitude of a kept fix at [offsetMs]; null or non-finite values
  /// are skipped.
  void add(int offsetMs, double? altitudeM) {
    if (altitudeM == null || !altitudeM.isFinite) return;
    _any = true;
    _window.add(altitudeM);
    if (_window.length > medianWindow) _window.removeAt(0);
    final m = _median(_window);

    final ref = _refMedian;
    if (ref == null) {
      _refMedian = m;
      _refMs = offsetMs;
      _level = m;
      return;
    }
    final dtS = (offsetMs - _refMs) / 1000.0;
    final allowed = maxStepMps * (dtS < 1.0 ? 1.0 : dtS);
    if ((m - ref).abs() > allowed) {
      _outliers++;
      _ignored++;
      if (_outliers < acceptAfter) return;
      // A sustained new level: accept it without counting the jump.
      _outliers = 0;
      _refMedian = m;
      _refMs = offsetMs;
      _level = m;
      return;
    }
    _outliers = 0;
    _refMedian = m;
    _refMs = offsetMs;

    final level = _level!;
    if (m - level >= hysteresisM) {
      _ascent += m - level;
      _level = m;
    } else if (level - m >= hysteresisM) {
      _descent += level - m;
      _level = m;
    }
  }

  static double _median(List<double> values) {
    final s = List<double>.of(values)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
  }
}
