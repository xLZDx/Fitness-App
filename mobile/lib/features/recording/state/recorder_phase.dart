/// The recorder phase model (S04 design 5.1, 5.2, S04-03). Pure Dart.
///
/// ONE phase plus independent flags keeps the transition table finite. The 13
/// display states of S04-D are a projection (`recorder_display.dart`).
library;

/// Exactly one phase at any time.
enum RecorderPhase {
  idle,
  preparing,
  acquiring,
  recording,
  pausedManual,
  pausedAuto,
  stopping,
  restoring,
  recoveryFailed,
  finished,
  permissionRevoked,
}

/// Legal phase transitions (design 5.2). Every other pair is undefined; the
/// transition-table test enumerates all pairs against this map.
const Map<RecorderPhase, Set<RecorderPhase>> kLegalTransitions = {
  RecorderPhase.idle: {RecorderPhase.preparing, RecorderPhase.restoring},
  RecorderPhase.preparing: {RecorderPhase.acquiring, RecorderPhase.idle},
  RecorderPhase.acquiring: {
    RecorderPhase.recording,
    RecorderPhase.stopping,
    RecorderPhase.idle,
    RecorderPhase.permissionRevoked,
  },
  RecorderPhase.recording: {
    RecorderPhase.pausedManual,
    RecorderPhase.pausedAuto,
    RecorderPhase.stopping,
    RecorderPhase.idle,
    RecorderPhase.permissionRevoked,
  },
  RecorderPhase.pausedManual: {
    RecorderPhase.recording,
    RecorderPhase.stopping,
    RecorderPhase.idle,
    RecorderPhase.permissionRevoked,
  },
  RecorderPhase.pausedAuto: {
    RecorderPhase.recording,
    RecorderPhase.pausedManual,
    RecorderPhase.stopping,
    RecorderPhase.idle,
    RecorderPhase.permissionRevoked,
  },
  RecorderPhase.stopping: {RecorderPhase.finished, RecorderPhase.idle},
  RecorderPhase.restoring: {
    RecorderPhase.acquiring,
    RecorderPhase.stopping,
    RecorderPhase.idle,
    RecorderPhase.recoveryFailed,
  },
  RecorderPhase.recoveryFailed: {RecorderPhase.idle},
  RecorderPhase.permissionRevoked: {RecorderPhase.stopping, RecorderPhase.idle},
  RecorderPhase.finished: {RecorderPhase.idle},
};

/// True when [from] to [to] is in the table. A transition to the same phase is
/// not a transition and is not legal.
bool isLegalTransition(RecorderPhase from, RecorderPhase to) =>
    kLegalTransitions[from]?.contains(to) ?? false;

extension RecorderPhaseX on RecorderPhase {
  /// A subscription is open and the pipeline runs (the phases in which fixes
  /// are consumed, including both pauses).
  bool get isCollecting =>
      this == RecorderPhase.acquiring ||
      this == RecorderPhase.recording ||
      this == RecorderPhase.pausedManual ||
      this == RecorderPhase.pausedAuto;

  /// A recording is in progress (collecting, or being stopped).
  bool get isActive => isCollecting || this == RecorderPhase.stopping;

  bool get isPaused =>
      this == RecorderPhase.pausedManual || this == RecorderPhase.pausedAuto;
}

/// Why a recording ended (journal `stopped*` events and the SEALED payload).
enum StopReason {
  /// The user finished.
  user,

  /// Battery at or below 3 percent, not charging (S04-22).
  battery,

  /// Journal writes kept failing for the retry window (design 4.8).
  storage,

  /// The sample cap was reached (design 5.5).
  sampleCap,

  /// The location consent was withdrawn during the recording (S04-R-054).
  consentWithdrawn,

  /// The owner account changed or signed out (design 4.7); visible on screen.
  account,

  /// Location permission was lost (S04-R-024). Not an automatic-stop
  /// notification reason: it has its own notification.
  permissionRevoked;

  /// The set that posts the separate automatic-stop notification (S04-35 AC-1,
  /// Y10). `permissionRevoked` and `account` are deliberately not in it.
  bool get postsAutoStopNotification =>
      this == StopReason.battery ||
      this == StopReason.storage ||
      this == StopReason.sampleCap ||
      this == StopReason.consentWithdrawn;

  /// True for every reason except a user stop.
  bool get isAutomatic => this != StopReason.user;
}

/// Visible reason code when Start did not proceed (design 5.4: no silent
/// no-op).
enum StartRefusal {
  /// Journal availability is not `open` for the signed-in user.
  journalNotOpen,

  /// The unfinished-recording check did not complete in time.
  checkIncomplete,

  /// An unfinished (not quarantined) recording exists: show the recovery offer.
  unfinishedRecording,

  /// Location consent is missing or withdrawn.
  consentMissing,

  /// System location permission is not granted precise.
  permissionNotGranted,

  /// Notification permission is not granted (default D-5 option A).
  notificationDenied,

  /// A gym timer of the same account runs (S04-D SH-4).
  gymTimerRunning,

  /// A session of another account is running.
  foreignSession,

  /// Writing `meta.json` or `begin()` failed.
  beginFailed,

  /// The location service could not be started.
  serviceStartFailed,
}

/// The panel that Start shows (S04-34).
enum StartPanel {
  none,

  /// Checks are running ("preparing").
  preparing,

  /// A precondition failed or the checks timed out; Try again / Add manually.
  cannotStart,

  /// The service start hung or failed; Try again.
  startFailed,
}
