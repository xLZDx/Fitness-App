/// Position smoothing (S04-R-010, S04-R-011, design 3.5). Pure Dart, no
/// Flutter imports, no I/O.
///
/// Smoothing is derived data: the raw gate-passed fixes are journaled
/// unchanged and the smoothed track is recomputed from them, so changing the
/// algorithm needs no re-recording.
library;

import 'geo.dart';
import 'pipeline_types.dart';
import 'recording_constants.dart';

/// A smoothing algorithm. The [id] goes into the session `formulaVersion`.
abstract class SmoothingStrategy {
  const SmoothingStrategy();

  /// The algorithm id, for example `smooth-wma5-1`.
  String get id;

  /// Smooths ONE continuous segment (no gap or pause inside it) in one call.
  /// The result has the same length and the same offsets; only positions can
  /// differ from the input.
  List<PipelineSample> smooth(List<PipelineSample> segment);

  /// A live smoother for the same algorithm; [IncrementalSmoother.add] and
  /// [IncrementalSmoother.flush] together give exactly the result of
  /// [smooth] on the same fixes.
  IncrementalSmoother createIncremental();
}

/// Feeds one continuous segment fix by fix. The output lags the input.
abstract class IncrementalSmoother {
  /// Adds a raw fix; returns the smoothed fixes that became final (possibly
  /// none), in order.
  List<PipelineSample> add(PipelineSample raw);

  /// Ends the segment; returns the remaining smoothed fixes, in order.
  List<PipelineSample> flush();
}

/// `smooth-wma5-1`: a centred weighted moving average over up to 5 kept fixes
/// (weight 1 / accuracy squared), each smoothed point clamped to at most
/// [maxDisplacementM] from its raw position. Segment ends use a shorter
/// symmetric window. Live use has a lag of [kSmoothingWindowRadius] fixes.
class WeightedMovingAverageSmoothing extends SmoothingStrategy {
  const WeightedMovingAverageSmoothing({
    this.radius = kSmoothingWindowRadius,
    this.maxDisplacementM = kSmoothingMaxDisplacementM,
  });

  final int radius;
  final double maxDisplacementM;

  @override
  String get id => kSmoothingAlgorithmId;

  @override
  List<PipelineSample> smooth(List<PipelineSample> segment) {
    final inc = createIncremental();
    final out = <PipelineSample>[];
    for (final s in segment) {
      out.addAll(inc.add(s));
    }
    out.addAll(inc.flush());
    return out;
  }

  @override
  IncrementalSmoother createIncremental() => _WmaIncremental(this);

  /// The smoothed copy of `window[centre]`, using all of `window`.
  PipelineSample smoothCentre(List<PipelineSample> window, int centre) {
    final c = window[centre];
    var wSum = 0.0;
    var dLat = 0.0;
    var dLon = 0.0;
    for (final s in window) {
      final acc = s.accuracyM ?? kGateMaxAccuracyM;
      final a = acc < kSmoothingMinAccuracyM ? kSmoothingMinAccuracyM : acc;
      final w = 1.0 / (a * a);
      wSum += w;
      dLat += w * (s.lat - c.lat);
      dLon += w * (s.lon - c.lon);
    }
    dLat /= wSum;
    dLon /= wSum;
    // Clamp the move to maxDisplacementM in a local plane around the raw point.
    final northM = dLat * kMetresPerDegree;
    final eastM = dLon * kMetresPerDegree * cosLatDeg(c.lat);
    final moveM = hypotM(northM, eastM);
    if (moveM > maxDisplacementM) {
      final k = maxDisplacementM / moveM;
      dLat *= k;
      dLon *= k;
    }
    return c.copyWith(lat: c.lat + dLat, lon: c.lon + dLon);
  }
}

class _WmaIncremental implements IncrementalSmoother {
  _WmaIncremental(this._algo);

  final WeightedMovingAverageSmoothing _algo;

  // The last up to (2 * radius + 1) raw fixes; the absolute index of _buf[0]
  // is _count - _buf.length.
  final List<PipelineSample> _buf = [];
  int _count = 0;
  int _emitted = 0;

  PipelineSample _at(int absolute) => _buf[absolute - (_count - _buf.length)];

  PipelineSample _emit(int index) {
    // The window is symmetric and shrinks towards the segment ends (radius 0 at
    // the first and the last fix, which stay raw). A one-sided window would
    // pull an end point inwards and lose about two steps of distance at every
    // segment end.
    var r = _algo.radius;
    if (r > index) r = index;
    if (r > _count - 1 - index) r = _count - 1 - index;
    final lo = index - r;
    final hi = index + r;
    final window = <PipelineSample>[
      for (var i = lo; i <= hi; i++) _at(i),
    ];
    return _algo.smoothCentre(window, index - lo);
  }

  @override
  List<PipelineSample> add(PipelineSample raw) {
    _buf.add(raw);
    _count++;
    final keep = 2 * _algo.radius + 1;
    if (_buf.length > keep) _buf.removeAt(0);
    final out = <PipelineSample>[];
    while (_emitted + _algo.radius <= _count - 1) {
      out.add(_emit(_emitted));
      _emitted++;
    }
    return out;
  }

  @override
  List<PipelineSample> flush() {
    final out = <PipelineSample>[];
    while (_emitted < _count) {
      out.add(_emit(_emitted));
      _emitted++;
    }
    return out;
  }
}
