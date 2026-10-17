/// The immutable recorder state exposed to the UI, the strip and the
/// notification (S04 design 5.1, S04-03, S04-22, S04-34, S04-36, S04-37).
library;

import '../../activity/data/sport_type.dart';
import '../pipeline/pipeline_types.dart';
import '../pipeline/recorder_pipeline.dart';
import 'recorder_phase.dart';
import 'recording_journal_port.dart';

/// Independent condition flags (design 5.1).
class RecorderFlags {
  const RecorderFlags({
    this.poorAccuracy = false,
    this.offline = false,
    this.background = false,
    this.batteryCritical = false,
    this.storageWriteFailing = false,
  });

  /// True only while the phase is `recording` (design 5.1).
  final bool poorAccuracy;

  /// Never set in S04 (option A: no grounded source, design 5.1).
  final bool offline;

  /// App not visible (from the lifecycle observer, set by the UI lane through
  /// `RecorderController.setBackground`).
  final bool background;
  final bool batteryCritical;

  /// A journal write is failing and fixes are held in memory (banner).
  final bool storageWriteFailing;

  RecorderFlags copyWith({
    bool? poorAccuracy,
    bool? offline,
    bool? background,
    bool? batteryCritical,
    bool? storageWriteFailing,
  }) =>
      RecorderFlags(
        poorAccuracy: poorAccuracy ?? this.poorAccuracy,
        offline: offline ?? this.offline,
        background: background ?? this.background,
        batteryCritical: batteryCritical ?? this.batteryCritical,
        storageWriteFailing: storageWriteFailing ?? this.storageWriteFailing,
      );

  @override
  bool operator ==(Object other) =>
      other is RecorderFlags &&
      other.poorAccuracy == poorAccuracy &&
      other.offline == offline &&
      other.background == background &&
      other.batteryCritical == batteryCritical &&
      other.storageWriteFailing == storageWriteFailing;

  @override
  int get hashCode => Object.hash(
      poorAccuracy, offline, background, batteryCritical, storageWriteFailing);
}

/// Data for the automatic-stop notification (S04-35): reason, saved moving
/// time and distance. Never holds a coordinate.
class AutoStopNotice {
  const AutoStopNotice({
    required this.reason,
    required this.movingTimeMs,
    required this.distanceM,
  });

  final StopReason reason;
  final int movingTimeMs;
  final double distanceM;
}

/// Outcome of the last Keep / Delete / discard action (review C8). The UI shows
/// it instead of a silent no-op.
enum RecorderActionResult {
  /// Nothing to report (no action yet, or the last one succeeded).
  none,

  /// The action threw or could not complete; the phase is unchanged and the
  /// user can choose again.
  failed,

  /// The opposite decision was already durable; the controller continued the
  /// winner (KEEP completed the hand-off, DELETE completed the delete).
  alreadyDecided,
}

class _Unset {
  const _Unset();
}

const Object _unset = _Unset();

class RecorderState {
  const RecorderState({
    this.phase = RecorderPhase.idle,
    this.flags = const RecorderFlags(),
    this.startPanel = StartPanel.none,
    this.refusal,
    this.stopReason,
    this.autoStopNotice,
    this.handOffFailed = false,
    this.recordingId,
    this.sport,
    this.startUtcMs,
    this.metrics,
    this.hasRecoveredData = false,
    this.recoveredDistanceM = 0,
    this.recoveredMovingTimeMs = 0,
    this.manualPauseSinceMs,
    this.pausePromptDue = false,
    this.engineDetached = false,
    this.unfinished = const [],
    this.lastActionResult = RecorderActionResult.none,
    this.recoveryCheckFailed = false,
  });

  static const RecorderState initial = RecorderState();

  final RecorderPhase phase;
  final RecorderFlags flags;

  /// Start panel (S04-34): `preparing`, `cannotStart` or `startFailed`.
  final StartPanel startPanel;

  /// Why the last Start did not proceed; null otherwise.
  final StartRefusal? refusal;

  /// Why the recording ended (set from `stopping` on, cleared at the next
  /// start). The visible reason, for example "stopped: battery" (S04-22).
  final StopReason? stopReason;

  /// Set when an automatic stop completed (notification data, S04-35).
  final AutoStopNotice? autoStopNotice;

  /// The last hand-off failed and the recording was kept (offered again).
  final bool handOffFailed;

  final String? recordingId;
  final SportType? sport;
  final int? startUtcMs;

  /// Live numbers of THIS run (the pipeline restarts after a recovery); null
  /// outside a recording. Add [recoveredDistanceM] / [recoveredMovingTimeMs]
  /// through [totalDistanceM] / [totalMovingTimeMs].
  final LiveMetrics? metrics;

  /// A recovery resume: recovered data already exists, so a Stop in
  /// `acquiring` goes to `stopping`, never to "nothing recorded" (UX1).
  final bool hasRecoveredData;
  final double recoveredDistanceM;
  final int recoveredMovingTimeMs;

  /// Offset at which the open manual pause began (S04-36); null otherwise.
  final int? manualPauseSinceMs;

  /// The manual pause lasted `kManualPausePromptAfterMs`: ask Resume or Finish
  /// (S04-36 AC-2). Cleared by resume or stop.
  final bool pausePromptDue;

  /// The engine detached while a service lives (S04-37, policy
  /// `graceThenStop`): the notification must not say Recording.
  final bool engineDetached;

  /// Result of the last unfinished-recording check (restoring / recovery).
  final List<UnfinishedRecording> unfinished;

  /// Result of the last Keep / Delete / discard action (review C8).
  final RecorderActionResult lastActionResult;

  /// The unfinished-recording check failed (or found a recording that is only
  /// temporarily unreadable) and is retried (review C16).
  final bool recoveryCheckFailed;

  double get totalDistanceM => recoveredDistanceM + (metrics?.distanceM ?? 0);

  int get totalMovingTimeMs =>
      recoveredMovingTimeMs + (metrics?.movingTimeMs ?? 0);

  /// The notification may say Recording (design 5.6): collecting, and the
  /// engine has not detached.
  bool get claimsRecording => phase.isCollecting && !engineDetached;

  bool get isBusy =>
      phase == RecorderPhase.preparing || phase == RecorderPhase.stopping;

  RecorderState copyWith({
    RecorderPhase? phase,
    RecorderFlags? flags,
    StartPanel? startPanel,
    Object? refusal = _unset,
    Object? stopReason = _unset,
    Object? autoStopNotice = _unset,
    bool? handOffFailed,
    Object? recordingId = _unset,
    Object? sport = _unset,
    Object? startUtcMs = _unset,
    Object? metrics = _unset,
    bool? hasRecoveredData,
    double? recoveredDistanceM,
    int? recoveredMovingTimeMs,
    Object? manualPauseSinceMs = _unset,
    bool? pausePromptDue,
    bool? engineDetached,
    List<UnfinishedRecording>? unfinished,
    RecorderActionResult? lastActionResult,
    bool? recoveryCheckFailed,
  }) =>
      RecorderState(
        phase: phase ?? this.phase,
        flags: flags ?? this.flags,
        startPanel: startPanel ?? this.startPanel,
        refusal: identical(refusal, _unset)
            ? this.refusal
            : refusal as StartRefusal?,
        stopReason: identical(stopReason, _unset)
            ? this.stopReason
            : stopReason as StopReason?,
        autoStopNotice: identical(autoStopNotice, _unset)
            ? this.autoStopNotice
            : autoStopNotice as AutoStopNotice?,
        handOffFailed: handOffFailed ?? this.handOffFailed,
        recordingId: identical(recordingId, _unset)
            ? this.recordingId
            : recordingId as String?,
        sport: identical(sport, _unset) ? this.sport : sport as SportType?,
        startUtcMs:
            identical(startUtcMs, _unset) ? this.startUtcMs : startUtcMs as int?,
        metrics: identical(metrics, _unset)
            ? this.metrics
            : metrics as LiveMetrics?,
        hasRecoveredData: hasRecoveredData ?? this.hasRecoveredData,
        recoveredDistanceM: recoveredDistanceM ?? this.recoveredDistanceM,
        recoveredMovingTimeMs:
            recoveredMovingTimeMs ?? this.recoveredMovingTimeMs,
        manualPauseSinceMs: identical(manualPauseSinceMs, _unset)
            ? this.manualPauseSinceMs
            : manualPauseSinceMs as int?,
        pausePromptDue: pausePromptDue ?? this.pausePromptDue,
        engineDetached: engineDetached ?? this.engineDetached,
        unfinished: unfinished ?? this.unfinished,
        lastActionResult: lastActionResult ?? this.lastActionResult,
        recoveryCheckFailed: recoveryCheckFailed ?? this.recoveryCheckFailed,
      );

  /// Counters of the gate for the batch frame and logs (integers only).
  GateCounters get counters => metrics?.counters ?? GateCounters.zero;
}
