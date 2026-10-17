/// System location permission state as the recorder needs it (S04 design 2.2).
enum LocationPermissionStatus {
  /// Fine (precise) location granted. The only state that allows recording.
  grantedPrecise,

  /// Only coarse location granted. Recording is refused: accuracy would fail
  /// the gate (S04-R-023).
  grantedApproximate,

  /// Denied, but the system prompt can still be shown.
  denied,

  /// Denied for good. Only the system settings screen can change it, so the
  /// app never re-requests (S04-R-023).
  permanentlyDenied,

  /// Blocked by device policy. Treated like [permanentlyDenied] for the UI.
  restricted;

  /// True only when recording may start or continue.
  bool get allowsRecording => this == LocationPermissionStatus.grantedPrecise;

  /// True when the only way forward is the system settings screen.
  bool get needsSettings =>
      this == LocationPermissionStatus.permanentlyDenied ||
      this == LocationPermissionStatus.restricted;
}

/// Notification permission state (S04 design 6.1, decision D-5).
enum NotificationPermissionStatus {
  granted,
  denied,
  permanentlyDenied;

  bool get isGranted => this == NotificationPermissionStatus.granted;
}
