/// The accuracy gate (S04-R-008, design 3.3). Pure Dart, no Flutter imports,
/// no I/O, no clock.
library;

import 'geo.dart';
import 'pipeline_types.dart';
import 'recording_constants.dart';

/// The verdict of [AccuracyGate.evaluate].
sealed class GateResult {
  const GateResult();
}

/// The fix passed. [sample] is the kept sample. When [reanchored] is true the
/// gate dropped a bad anchor: [sample] is the best-accuracy fix among the
/// recent speed-only rejections (it can be an earlier fix than the one just
/// evaluated), and the caller must write a gap around the break.
final class GateKept extends GateResult {
  const GateKept(this.sample, {this.reanchored = false});

  final PipelineSample sample;
  final bool reanchored;
}

/// The fix was rejected; only the counter moves.
final class GateRejected extends GateResult {
  const GateRejected(this.reason);

  final RejectReason reason;
}

/// Keeps a fix only if its coordinates are valid, its offset is strictly
/// increasing, its accuracy is at most [PipelineConfig.maxAccuracyM] and the
/// speed implied by the previous kept fix is at most
/// [PipelineConfig.maxImpliedSpeedMps].
///
/// The first fix has no previous fix and passes the speed rule. Bad-anchor
/// recovery: if one wrong fix passed, every later good fix would fail the
/// speed rule against it, so after [PipelineConfig.reanchorMinRejects]
/// consecutive speed-only rejections, or [PipelineConfig.reanchorMinSpanMs]
/// spanned by them, the gate re-anchors on the best-accuracy rejected fix. The
/// run is reset by a kept fix; rejections for another reason neither extend
/// nor reset it.
class AccuracyGate {
  AccuracyGate({this.config = const PipelineConfig()});

  final PipelineConfig config;

  PipelineSample? _anchor;
  GateCounters _counters = GateCounters.zero;
  int _reanchors = 0;

  // The current run of speed-only rejections.
  int _runCount = 0;
  int _runFirstOffsetMs = 0;
  PipelineSample? _runBest;

  /// The last kept sample (the anchor), or null before the first kept fix.
  PipelineSample? get anchor => _anchor;

  GateCounters get counters => _counters;

  /// How many times a bad anchor was dropped.
  int get reanchors => _reanchors;

  GateResult evaluate(PipelineSample s) {
    if (!isValidCoordinate(s.lat, s.lon)) return _reject(RejectReason.invalid);
    final prev = _anchor;
    if (prev != null && s.offsetMs <= prev.offsetMs) {
      return _reject(RejectReason.nonMonotonic);
    }
    final acc = s.accuracyM;
    if (acc == null || !acc.isFinite || acc < 0 || acc > config.maxAccuracyM) {
      return _reject(RejectReason.accuracy);
    }
    if (prev == null) return _keep(s);

    final dtS = (s.offsetMs - prev.offsetMs) / 1000.0;
    final impliedMps = haversineM(prev.lat, prev.lon, s.lat, s.lon) / dtS;
    if (impliedMps <= config.maxImpliedSpeedMps) return _keep(s);

    // Rejected by the speed rule only.
    if (_runCount == 0) _runFirstOffsetMs = s.offsetMs;
    _runCount++;
    final best = _runBest;
    if (best == null || acc <= best.accuracyM!) _runBest = s;
    final spanMs = s.offsetMs - _runFirstOffsetMs;
    if (_runCount >= config.reanchorMinRejects ||
        spanMs >= config.reanchorMinSpanMs) {
      final anchor = _runBest!;
      _reanchors++;
      _counters = _counters.plus(RejectReason.speed);
      _anchor = anchor;
      _clearRun();
      return GateKept(anchor, reanchored: true);
    }
    return _reject(RejectReason.speed);
  }

  /// Forgets the anchor so the next fix passes the speed rule (used when the
  /// recorder starts a new, unrelated track).
  void dropAnchor() {
    _anchor = null;
    _clearRun();
  }

  GateResult _keep(PipelineSample s) {
    _anchor = s;
    _clearRun();
    return GateKept(s);
  }

  GateResult _reject(RejectReason r) {
    _counters = _counters.plus(r);
    return GateRejected(r);
  }

  void _clearRun() {
    _runCount = 0;
    _runFirstOffsetMs = 0;
    _runBest = null;
  }
}
