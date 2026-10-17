import 'location_permission_status.dart';

/// The ONE place that reads or requests location and notification permission
/// (S04 design 2.2, S04-R-021).
///
/// Rules:
/// - The operating system owns the state; implementations never cache it
///   across calls (design 6.1).
/// - Nothing calls a request method at launch, in onboarding or on a tab
///   switch. A request happens only at a Start tap, after the pre-prompt, and
///   at most once per tap.
abstract class PermissionService {
  /// Reads the current location permission. Never prompts.
  Future<LocationPermissionStatus> locationStatus();

  /// Shows the system prompt for fine and coarse location together and returns
  /// the resulting status. When the status is already permanently denied or
  /// restricted this returns that status without prompting.
  Future<LocationPermissionStatus> requestLocation();

  /// Reads the current notification permission. Never prompts.
  Future<NotificationPermissionStatus> notificationStatus();

  /// Shows the system notification prompt and returns the resulting status.
  Future<NotificationPermissionStatus> requestNotification();

  /// Opens the app's system settings screen. Returns false when it could not
  /// be opened.
  Future<bool> openSettings();
}
