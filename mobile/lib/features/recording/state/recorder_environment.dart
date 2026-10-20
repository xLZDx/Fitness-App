/// Everything the recorder reads from the rest of the app, as one port (S04
/// design 5.4 checks 1, 3, 4, 5; lane R9 wires it). It keeps the state layer
/// free of S02/S03 imports and makes each precondition fakeable.
library;

/// How the engine-detach rule is applied (design 5.6, S04-37). Until device
/// test T2 passes the default applies.
enum EngineDetachPolicy {
  /// Default branch: on detach the collection stops at once and the notification
  /// stops claiming Recording; recovery (4.5) applies on the next start.
  stopImmediately,

  /// Option b: the service survives; the state reports `engineDetached`
  /// (notification shows the fixed "stopped" text) and collection stops after
  /// `kEngineDetachGraceMs`.
  graceThenStop,
}

abstract class RecorderEnvironment {
  /// Signed-in uid when the activity journal availability is `open` for it;
  /// null for `binding`, `gaveUp`, `failedToOpen`, `notEnabled`.
  String? get openJournalOwnerUid;

  /// Location consent granted and not withdrawn (design 6.2).
  bool get locationConsentGranted;

  /// A gym timer of the same account is running (S04-D SH-4).
  bool get gymTimerRunning;

  /// A session of a foreign account is running.
  bool get foreignSessionRunning;

  /// Current UTC time in milliseconds since the epoch.
  int nowUtcMs();

  /// Device UTC offset in minutes at start.
  int utcOffsetMinutes();

  /// A new recording uuid.
  String newRecordingId();

  /// Fixed foreground-notification strings (localised by lane R8; never built
  /// from a fix).
  String? get notificationTitle;
  String? get notificationText;

  /// Whether Start requires notification permission (D-5 option A = true).
  bool get requireNotificationPermission;
}
