/// The live sample pipeline: gate, gaps, auto-pause and incremental metrics in
/// one object that the recorder and the replay tests both drive (S04 design 3,
/// S04-R-035). Pure Dart, no Flutter imports, no I/O, no clock, no randomness:
/// every instant is a recording offset passed in by the caller.
library;

import 'accuracy_gate.dart';
import 'auto_pause.dart';
import 'distance_accumulator.dart';
import 'elevation.dart';
import 'gap_detector.dart';
import 'pace.dart';
import 'pipeline_types.dart';
import 'recording_constants.dart';
import 'smoothing.dart';

/// A snapshot of the live numbers. The live distance uses the same smoothing
/// as the final value with a lag of two fixes and counts a few stationary
/// seconds before an auto-pause was confirmed, so it can differ slightly from
/// the final stored value (which is recomputed over the whole session).
class LiveMetrics {
  const LiveMetrics({
    required this.distanceM,
    required this.movingTimeMs,
    required this.elapsedMs,
    required this.currentPaceSecPerKm,
    required this.currentSpeedMps,
    required this.averagePaceSecPerKm,
    required this.averageSpeedMps,
    required this.ascentM,
    required this.descentM,
    required this.acquiring,
    required this.poorAccuracy,
    required this.autoPaused,
    required this.manualPaused,
    required this.counters,
    required this.keptCount,
  });

  final double distanceM;
  final int movingTimeMs;
  final int elapsedMs;
  final double? currentPaceSecPerKm;
  final double? currentSpeedMps;
  final double? averagePaceSecPerKm;
  final double? averageSpeedMps;
  final double? ascentM;
  final double? descentM;
  final bool acquiring;
  final bool poorAccuracy;
  final bool autoPaused;
  final bool manualPaused;
  final GateCounters counters;
  final int keptCount;
}

class RecorderPipeline {
  RecorderPipeline({
    this.config = const PipelineConfig(),
    bool autoPauseEnabled = true,
    this.smoothing = const WeightedMovingAverageSmoothing(),
  })  : _gate = AccuracyGate(config: config),
        _gaps = GapDetector(config: config),
        _auto = AutoPause(config: config, enabled: autoPauseEnabled),
        _pace = PaceWindow(
            windowMs: config.paceWindowMs,
            minMovingDistanceM: config.paceMinMovingDistanceM) {
    _smoother = smoothing.createIncremental();
  }

  final PipelineConfig config;
  final SmoothingStrategy smoothing;

  final AccuracyGate _gate;
  final GapDetector _gaps;
  final AutoPause _auto;
  final PaceWindow _pace;
  final ElevationAccumulator _elevation = ElevationAccumulator();
  late IncrementalSmoother _smoother;

  bool _manualPaused = false;
  int? _manualSinceMs;
  int _closedPausedMs = 0;
  int _nowMs = 0;
  int _kept = 0;
  // Distance of the closed segments plus the open segment's accumulator.
  double _closedDistanceM = 0;
  DistanceAccumulator _segDistance = DistanceAccumulator();
  double get _distanceM => _closedDistanceM + _segDistance.totalM;

  /// Advances time without a fix (a tick from the recorder). Opens a gap when
  /// no fix was kept for the poor-accuracy time.
  List<PipelineEvent> advanceTo(int offsetMs) {
    _touch(offsetMs);
    if (_manualPaused) return const [];
    return _onGapEvents(_gaps.advanceTo(offsetMs));
  }

  /// Feeds one raw fix. Returns the events to journal, in order. While a
  /// manual pause is on, fixes are ignored (not journaled, not counted).
  List<PipelineEvent> addSample(PipelineSample s) {
    _touch(s.offsetMs);
    if (_manualPaused) return const [];
    final out = <PipelineEvent>[..._onGapEvents(_gaps.advanceTo(s.offsetMs))];

    final r = _gate.evaluate(s);
    switch (r) {
      case GateRejected():
        out.add(FixRejected(s.offsetMs, r.reason));
      case GateKept():
        if (r.reanchored) {
          out.addAll(_onGapEvents(_gaps.openForReanchor()));
        }
        out.addAll(_keep(r.sample));
    }
    return out;
  }

  /// The user pauses at [offsetMs]. Suppresses the auto rules and the gap
  /// timer; an open auto-pause span is closed (`AutoResumed.closedByManualPause`).
  /// The recorder journals the manual `pause` event itself.
  List<PipelineEvent> pauseManual(int offsetMs) {
    _touch(offsetMs);
    if (_manualPaused) return const [];
    _breakSegment();
    final wasAutoSince = _auto.pausedSinceMs;
    final ev = _auto.suspend(offsetMs);
    if (wasAutoSince != null) _closedPausedMs += offsetMs - wasAutoSince;
    _gaps.suspend();
    _manualPaused = true;
    _manualSinceMs = offsetMs;
    return ev;
  }

  /// The user resumes at [offsetMs]; the prior moving state returns.
  List<PipelineEvent> resumeManual(int offsetMs) {
    _touch(offsetMs);
    if (!_manualPaused) return const [];
    _closedPausedMs += offsetMs - _manualSinceMs!;
    _manualPaused = false;
    _manualSinceMs = null;
    _auto.resume();
    _gaps.resume(offsetMs);
    _gate.dropAnchor();
    return const [];
  }

  /// Ends the recording at [offsetMs]: finalises the live smoother. Emits no
  /// events; open gap and pause spans stay open and end at the stop offset.
  void finish(int offsetMs) {
    _touch(offsetMs);
    _breakSegment();
  }

  GateCounters get counters => _gate.counters;

  /// How many times the gate dropped a bad anchor.
  int get reanchors => _gate.reanchors;

  LiveMetrics get metrics {
    final openPause = _manualSinceMs ?? _auto.pausedSinceMs;
    final movingMs = _nowMs -
        _closedPausedMs -
        (openPause == null ? 0 : _nowMs - openPause);
    final moving = movingMs < 0 ? 0 : movingMs;
    final movingS = moving / 1000.0;
    return LiveMetrics(
      distanceM: _distanceM,
      movingTimeMs: moving,
      elapsedMs: _nowMs,
      currentPaceSecPerKm: _pace.currentPaceSecPerKm,
      currentSpeedMps: _pace.currentSpeedMps,
      averagePaceSecPerKm: averagePaceSecPerKm(_distanceM, movingS,
          minMovingDistanceM: config.paceMinMovingDistanceM),
      averageSpeedMps: averageSpeedMps(_distanceM, movingS),
      ascentM: _elevation.ascentM,
      descentM: _elevation.descentM,
      acquiring: _gaps.acquiring,
      poorAccuracy: _gaps.poorAccuracy,
      autoPaused: _auto.paused,
      manualPaused: _manualPaused,
      counters: _gate.counters,
      keptCount: _kept,
    );
  }

  void _touch(int offsetMs) {
    if (offsetMs > _nowMs) _nowMs = offsetMs;
  }

  List<PipelineEvent> _keep(PipelineSample s) {
    final marks = _gaps.onKept(s.offsetMs);
    _kept++;
    final out = <PipelineEvent>[...marks.before, FixKept(s), ...marks.after];
    _elevation.add(s.offsetMs, s.altitudeM);
    final pausedSince = _auto.pausedSinceMs;
    final autoEvents = _auto.onKept(s);
    for (final e in autoEvents) {
      if (e is AutoPaused) {
        _breakSegment();
      } else if (e is AutoResumed && pausedSince != null) {
        _closedPausedMs += e.offsetMs - pausedSince;
      }
    }
    out.addAll(autoEvents);
    // Fixes inside an auto-pause span do not add live distance.
    if (!_auto.paused) _feed(s);
    return out;
  }

  List<PipelineEvent> _onGapEvents(List<PipelineEvent> events) {
    for (final e in events) {
      if (e is GapStarted) {
        _breakSegment();
        _auto.breakChain();
      }
    }
    return events;
  }

  void _feed(PipelineSample raw) {
    for (final p in _smoother.add(raw)) {
      _accept(p);
    }
  }

  void _accept(PipelineSample p) {
    _segDistance.add(p.lat, p.lon);
    final moving = p.offsetMs - _closedPausedMs;
    _pace.add(moving < 0 ? 0 : moving, _distanceM);
  }

  void _breakSegment() {
    for (final p in _smoother.flush()) {
      _accept(p);
    }
    _smoother = smoothing.createIncremental();
    _closedDistanceM += _segDistance.totalM;
    _segDistance = DistanceAccumulator();
  }
}
