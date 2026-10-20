import 'fix.dart';

/// Parameters for one [LocationSource.start] call.
///
/// Notification texts are supplied by the caller (localised strings belong to
/// the l10n lane); the seam never holds user-facing copy.
class LocationRequest {
  const LocationRequest({
    this.intervalSeconds = 1,
    this.distanceFilterMeters = 0,
    this.notificationTitle,
    this.notificationText,
  });

  /// Requested time between fixes, seconds.
  final int intervalSeconds;

  /// Minimum movement between fixes, metres. 0 = no distance filter.
  final int distanceFilterMeters;

  /// Foreground-service notification title, when the adapter owns the service.
  final String? notificationTitle;

  /// Foreground-service notification body, when the adapter owns the service.
  final String? notificationText;
}

/// The ONE seam through which the app reads device location (S04-R-003).
///
/// Rules:
/// - No location package or plugin type is imported outside the
///   `recording/location/` folder.
/// - No subscription exists while idle, finished, after sign-out or after boot.
///   The caller creates it only inside `startRecording` and releases it in one
///   `finally` path, so [activeSubscriptions] is 0 outside a recording.
/// - Implementations make no network call (S04-R-005).
abstract class LocationSource {
  /// Starts one subscription and returns its fixes.
  ///
  /// Errors from the platform (permission lost, provider disabled) arrive as
  /// stream error events. Calling [start] while a subscription is active is a
  /// programming error and throws [StateError].
  Stream<Fix> start(LocationRequest request);

  /// Ends the subscription. Idempotent: a second call, or a call with no
  /// subscription, completes normally.
  Future<void> stop();

  /// Changes the request rate of the active subscription without creating a
  /// second one (manual pause 10 s, battery critical 5 s; S04-R-057). A no-op
  /// when no subscription is active.
  Future<void> setInterval(int seconds);

  /// Fires when the adapter can observe that the UI engine detached while the
  /// subscription was active (S04 design 5.6). Adapters that cannot observe it
  /// return an empty stream.
  Stream<void> get engineDetached;

  /// Number of live subscriptions. 0 or 1; exposed so tests can assert the
  /// "no passive collection" rule.
  int get activeSubscriptions;
}
