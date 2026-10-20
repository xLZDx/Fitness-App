/// Auto-pause (S04-R-012, design 3.6). Pure Dart, no Flutter imports, no I/O,
/// no clock: time arrives as the offsets of kept fixes.
library;

import 'geo.dart';
import 'pipeline_types.dart';
import 'recording_constants.dart';

/// Enters `pausedAuto` when speed stays below
/// [PipelineConfig.autoPauseBelowSpeedMps] for
/// [PipelineConfig.autoPauseEnterAfterMs], and leaves it when speed stays at
/// least [PipelineConfig.autoResumeSpeedMps] for
/// [PipelineConfig.autoResumeAfterMs]. The two thresholds are the hysteresis:
/// speeds in between change nothing, so 0.6 to 0.9 m/s jitter cannot flap.
///
/// It is fed with KEPT fixes only. The speed is the provider speed when
/// present, else the speed implied by the two last kept fixes. A fix with no
/// usable speed leaves the timers as they are.
///
/// The event offset is where the speed first crossed the threshold (the span
/// start and end), the sample that confirmed it is `detectedAtMs`. The span
/// `[AutoPaused.offsetMs, AutoResumed.offsetMs]` is what moving time and
/// distance exclude.
class AutoPause {
  AutoPause({this.config = const PipelineConfig(), this.enabled = true});

  final PipelineConfig config;

  /// When false the machine never pauses (the user switched it off, or the
  /// sport has the default off).
  final bool enabled;

  bool _paused = false;
  int? _belowSinceMs;
  int? _aboveSinceMs;
  int? _pausedSinceMs;
  PipelineSample? _prev;
  bool _suspended = false;

  /// True while in `pausedAuto`.
  bool get paused => _paused;

  /// Offset the open auto-pause started at, or null when not paused.
  int? get pausedSinceMs => _pausedSinceMs;

  /// Feeds one kept fix; returns `AutoPaused` or `AutoResumed` when the state
  /// changes.
  List<PipelineEvent> onKept(PipelineSample s) {
    final prev = _prev;
    _prev = s;
    if (!enabled || _suspended) return const [];
    final v = _speedOf(s, prev);
    if (v == null) return const [];

    if (!_paused) {
      if (v < config.autoPauseBelowSpeedMps) {
        final since = _belowSinceMs ??= s.offsetMs;
        if (s.offsetMs - since >= config.autoPauseEnterAfterMs) {
          _paused = true;
          _pausedSinceMs = since;
          _belowSinceMs = null;
          _aboveSinceMs = null;
          return [AutoPaused(since, s.offsetMs)];
        }
      } else {
        _belowSinceMs = null;
      }
      return const [];
    }

    if (v >= config.autoResumeSpeedMps) {
      final since = _aboveSinceMs ??= s.offsetMs;
      if (s.offsetMs - since >= config.autoResumeAfterMs) {
        _paused = false;
        _pausedSinceMs = null;
        _belowSinceMs = null;
        _aboveSinceMs = null;
        return [AutoResumed(since, s.offsetMs)];
      }
    } else {
      _aboveSinceMs = null;
    }
    return const [];
  }

  /// A discontinuity (gap, re-anchor): the next fix has no previous fix to
  /// derive a speed from.
  void breakChain() {
    _prev = null;
  }

  /// A manual pause starts at [offsetMs]. A manual pause suppresses the auto
  /// rules; an open auto-pause span is closed at [offsetMs] so spans never
  /// overlap. Returns `AutoResumed(closedByManualPause)` in that case.
  List<PipelineEvent> suspend(int offsetMs) {
    _suspended = true;
    _belowSinceMs = null;
    _aboveSinceMs = null;
    _prev = null;
    if (!_paused) return const [];
    _paused = false;
    _pausedSinceMs = null;
    return [AutoResumed(offsetMs, offsetMs, closedByManualPause: true)];
  }

  /// Manual resume: the auto rules start again from the prior moving state.
  void resume() {
    _suspended = false;
    _prev = null;
    _belowSinceMs = null;
    _aboveSinceMs = null;
  }

  static double? _speedOf(PipelineSample s, PipelineSample? prev) {
    final p = s.speedMps;
    if (p != null && p.isFinite && p >= 0) return p;
    if (prev == null) return null;
    final dtS = (s.offsetMs - prev.offsetMs) / 1000.0;
    if (dtS <= 0) return null;
    return haversineM(prev.lat, prev.lon, s.lat, s.lon) / dtS;
  }
}
