/// The interface the recorder state needs from the recording journal (S04
/// design 2.2, 4.2 to 4.5). Lane R5 implements it in `journal/`; the state
/// layer depends only on this port and never touches files (S04-R-014).
///
/// Ownership split: the journal owns encoding, segments, the flush policy
/// (10 samples or the flush interval), the in-memory retry window for failed
/// writes (design 4.8), the owner-scope pinning of every step and the
/// seal/hand-off ordering. The recorder owns when things happen.
///
/// Errors: every method may throw; the recorder treats a throw as a content-free
/// failure and never reads the message (S04-R-052).
library;

import '../../activity/data/sport_type.dart';
import '../pipeline/pipeline_types.dart';
import 'recorder_phase.dart';

/// What `begin()` writes into `meta.json` (design 4.2). `ownerScopeId` is
/// captured by the journal itself.
class RecordingMeta {
  const RecordingMeta({
    required this.recordingId,
    required this.startUtcMs,
    required this.utcOffsetMinutes,
    required this.sport,
    required this.autoPauseEnabled,
    required this.ownerUid,
  });

  final String recordingId;
  final int startUtcMs;
  final int utcOffsetMinutes;
  final SportType sport;
  final bool autoPauseEnabled;
  final String ownerUid;
}

/// Journal `event` kinds (design 4.2). The pipeline events map onto the first
/// five; the recorder adds the rest.
enum JournalEventKind {
  pause,
  resume,
  autoPause,
  autoResume,
  gapStart,
  gapEnd,
  permissionRevoked,
  batteryCritical,
  stoppedBattery,
  stoppedStorage,
  stoppedAccount,
  stoppedConsent,
  stoppedCap,
  restart,
  segmentBreak,
}

/// Maps a [StopReason] to its journal stop event; null for reasons without one
/// (`user`, `permissionRevoked`, which has its own event).
JournalEventKind? journalStopEventFor(StopReason reason) => switch (reason) {
      StopReason.battery => JournalEventKind.stoppedBattery,
      StopReason.storage => JournalEventKind.stoppedStorage,
      StopReason.account => JournalEventKind.stoppedAccount,
      StopReason.consentWithdrawn => JournalEventKind.stoppedConsent,
      StopReason.sampleCap => JournalEventKind.stoppedCap,
      StopReason.permissionRevoked => JournalEventKind.permissionRevoked,
      StopReason.user => null,
    };

/// One event frame: the kind and the recording offset in milliseconds.
class JournalEvent {
  const JournalEvent(this.kind, this.offsetMs);

  final JournalEventKind kind;
  final int offsetMs;
}

/// Faults the journal reports asynchronously (a write is not awaited per fix).
enum JournalFault {
  /// A write failed; fixes are held in memory and retried (design 4.8). The
  /// recorder shows the storage banner.
  storageFailing,

  /// A retry succeeded; the banner clears.
  storageRecovered,

  /// The retry window (60 s) passed. The recorder stops with
  /// `StopReason.storage`.
  storageGaveUp,

  /// The owner scope is no longer bound (wipe, different uid, buffer bound
  /// passed). The recorder stops with `StopReason.account`.
  ownerScopeLost,
}

/// Readability of an unfinished recording found at start-up (design 4.5).
enum UnfinishedStatus {
  /// Readable and non-empty: offer Resume, Save as finished, Discard.
  readable,

  /// Unreadable: state `recoveryFailed`, Keep (quarantine) or Delete only.
  unreadable,

  /// Quarantined by an earlier Keep: never blocks Start, never offered.
  quarantined,
}

/// Summary of one unfinished recording.
class UnfinishedRecording {
  const UnfinishedRecording({
    required this.recordingId,
    required this.status,
    this.startUtcMs,
    this.sport,
    this.lastOffsetMs,
    this.sampleCount,
  });

  final String recordingId;
  final UnfinishedStatus status;
  final int? startUtcMs;
  final SportType? sport;
  final int? lastOffsetMs;
  final int? sampleCount;

  /// Start refuses while such a recording exists (design 5.4 check 2).
  bool get blocksStart => status != UnfinishedStatus.quarantined;
}

/// What `openForResume` returns once the journal has opened a new segment and
/// written the `restart` event and the gap pair (design 4.5).
class RecoveredRecording {
  const RecoveredRecording({
    required this.meta,
    required this.lastOffsetMs,
    required this.distanceM,
    required this.movingTimeMs,
    required this.keptCount,
  });

  final RecordingMeta meta;

  /// Last journaled offset; the interval to the restart is a pause interval.
  final int lastOffsetMs;

  /// Values recomputed from the journal before the interruption.
  final double distanceM;
  final int movingTimeMs;
  final int keptCount;
}

/// Arguments of `seal` (design 4.3).
class SealRequest {
  const SealRequest({required this.reason, this.lastOffsetMs});

  final StopReason reason;

  /// Offset at which the recording ends; null lets the journal use the last
  /// journaled offset (Save as finished after a kill).
  final int? lastOffsetMs;
}

/// Result of the hand-off into the S02 store.
enum HandOffResult {
  /// The activity exists (idempotent: also when it already existed).
  done,

  /// The hand-off could not complete; the recording stays on the device and is
  /// offered again (design 5.2 `stopping -> idle`).
  failedKept,
}

/// Result of the durable KEEP/DELETE decision (design 4.3, Z5, Z7).
enum DecisionOutcome {
  /// This call won the exclusive create.
  committed,

  /// The opposite decision was already durable; nothing was done.
  alreadyDecided,
}

abstract class RecordingJournalPort {
  /// Recordings without `SEALED` for the bound scope, completed. Applies the
  /// recovery table of design 4.3 (silent delete of empty ones, completion of
  /// `DELETE`). Never lists another account's recordings.
  Future<List<UnfinishedRecording>> listUnfinished();

  /// Writes `meta.json` (before the first sample) and opens segment 1.
  Future<void> begin(RecordingMeta meta);

  /// Queues one kept sample (raw, unsmoothed) with the current reject
  /// counters. Synchronous and cheap; the journal batches and flushes by its
  /// policy. Never throws; failures arrive on [faults].
  void enqueueSample(PipelineSample sample, GateCounters counters);

  /// Appends one event frame and forces an immediate flush (design 4.4).
  Future<void> appendEvent(JournalEvent event);

  /// Flushes everything queued. Called by `releaseAll()`.
  Future<void> flush();

  /// Changes the flush interval (5000 normally, 1000 at battery critical).
  void setFlushIntervalMs(int ms);

  /// Asynchronous write faults of the active recording.
  Stream<JournalFault> get faults;

  /// Opens a new segment of an unfinished recording and journals `restart`
  /// plus the pause-interval gap pair (design 4.5).
  Future<RecoveredRecording> openForResume(String recordingId);

  /// Flushes and seals the recording (SEALED, authenticated). Idempotent.
  Future<void> seal(String recordingId, SealRequest request);

  /// Hands the sealed recording off into the S02 store, then removes the
  /// journal files. Idempotent on the deterministic activity id.
  Future<HandOffResult> handOff(String recordingId);

  /// Records the durable KEEP decision (permission-revoked flow).
  Future<DecisionOutcome> decideKeep(String recordingId);

  /// Records the durable DELETE decision and runs the ordered delete.
  Future<DecisionOutcome> decideDelete(String recordingId);

  /// Quarantines an unreadable recording (Keep in `recoveryFailed`).
  Future<void> quarantine(String recordingId);
}
