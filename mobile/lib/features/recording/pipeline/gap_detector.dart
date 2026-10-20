/// Acquiring, poor accuracy and gaps (S04-R-009, design 3.4). Pure Dart, no
/// Flutter imports, no I/O, no clock: time arrives as recording offsets.
library;

import 'pipeline_types.dart';
import 'recording_constants.dart';

/// Tracks the time since the last kept fix.
///
/// `acquiring` lasts from the start to the first kept fix. If no fix is kept
/// for [PipelineConfig.poorAccuracyAfterMs], poor accuracy is on and a gap
/// opens at the offset of the last kept fix (`gapStart`); the next kept fix
/// closes it (`gapEnd`). Before the first kept fix the flag is on after the
/// same time but no gap event is produced, because there is no track to
/// break. Distance is never interpolated across a gap.
class GapDetector {
  GapDetector({this.config = const PipelineConfig(), int startMs = 0})
      : _referenceMs = startMs;

  final PipelineConfig config;

  int _referenceMs;
  int? _lastKeptMs;
  bool _gapOpen = false;
  bool _poorAccuracy = false;
  bool _suspended = false;

  /// True from the start until the first fix is kept.
  bool get acquiring => _lastKeptMs == null;

  /// True while no fix was kept for the poor-accuracy time.
  bool get poorAccuracy => _poorAccuracy;

  /// True between `gapStart` and `gapEnd`.
  bool get gapOpen => _gapOpen;

  /// Offset of the last kept fix, or null before the first one.
  int? get lastKeptOffsetMs => _lastKeptMs;

  /// Advances time to [nowMs] and returns `GapStarted` when the limit has just
  /// been crossed. Does nothing while suspended (manual pause).
  List<PipelineEvent> advanceTo(int nowMs) {
    if (_suspended || _poorAccuracy) return const [];
    if (nowMs - _referenceMs < config.poorAccuracyAfterMs) return const [];
    _poorAccuracy = true;
    final last = _lastKeptMs;
    if (last == null) return const [];
    _gapOpen = true;
    return [GapStarted(last, GapCause.noFix)];
  }

  /// Opens a gap at the last kept fix for a re-anchor (design 3.3), unless one
  /// is already open (then the open gap is reused).
  List<PipelineEvent> openForReanchor() {
    final last = _lastKeptMs;
    if (_gapOpen || last == null) return const [];
    _gapOpen = true;
    _poorAccuracy = true;
    return [GapStarted(last, GapCause.reanchor)];
  }

  /// Registers a kept fix. Returns `FirstFixAcquired` for the first one and
  /// `GapEnded` when a gap was open; the caller emits the `FixKept` itself.
  /// The returned events are `(before, after)`: [before] precedes `FixKept`,
  /// [after] follows it.
  ({List<PipelineEvent> before, List<PipelineEvent> after}) onKept(
      int offsetMs) {
    final before = <PipelineEvent>[];
    final after = <PipelineEvent>[];
    if (_lastKeptMs == null) before.add(FirstFixAcquired(offsetMs));
    if (_gapOpen) after.add(GapEnded(offsetMs));
    _gapOpen = false;
    _poorAccuracy = false;
    _lastKeptMs = offsetMs;
    _referenceMs = offsetMs;
    return (before: before, after: after);
  }

  /// Manual pause: no gap logic while the user has paused.
  void suspend() {
    _suspended = true;
  }

  /// Manual resume at [nowMs]: the poor-accuracy timer restarts here.
  void resume(int nowMs) {
    _suspended = false;
    if (!_gapOpen) _poorAccuracy = false;
    _referenceMs = nowMs;
  }
}
