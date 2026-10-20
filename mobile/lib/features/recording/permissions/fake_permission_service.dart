import 'location_permission_status.dart';
import 'permission_service.dart';

/// Scripted [PermissionService] for tests. Counts every call so tests can
/// assert "launch, onboarding and tab switches request nothing" (S04-17 AC-1)
/// and "at most one request per tap" (S04-17 AC-3).
class FakePermissionService implements PermissionService {
  FakePermissionService({
    this.location = LocationPermissionStatus.denied,
    this.notification = NotificationPermissionStatus.granted,
    this.locationRequestResult,
    this.notificationRequestResult,
  });

  /// Current location status, returned by [locationStatus]. Tests flip it to
  /// script a mid-recording revocation.
  LocationPermissionStatus location;

  /// Current notification status.
  NotificationPermissionStatus notification;

  /// Status the next [requestLocation] moves [location] to. Null = unchanged.
  LocationPermissionStatus? locationRequestResult;

  /// Status the next [requestNotification] moves [notification] to. Null =
  /// unchanged.
  NotificationPermissionStatus? notificationRequestResult;

  /// When set, [locationStatus] throws this (scripts a failed platform read).
  Object? locationStatusError;

  int locationStatusCount = 0;
  int locationRequestCount = 0;
  int notificationStatusCount = 0;
  int notificationRequestCount = 0;
  int openSettingsCount = 0;

  /// Result of [openSettings].
  bool openSettingsResult = true;

  /// Sum of all request calls (location plus notification).
  int get requestCount => locationRequestCount + notificationRequestCount;

  /// Sum of every call of every kind; 0 means the service was never touched.
  int get totalCalls =>
      locationStatusCount +
      locationRequestCount +
      notificationStatusCount +
      notificationRequestCount +
      openSettingsCount;

  @override
  Future<LocationPermissionStatus> locationStatus() async {
    locationStatusCount++;
    final error = locationStatusError;
    if (error != null) throw error;
    return location;
  }

  @override
  Future<LocationPermissionStatus> requestLocation() async {
    locationRequestCount++;
    // Mirror the real contract: a permanently denied permission never prompts.
    if (!location.needsSettings) {
      location = locationRequestResult ?? location;
    }
    return location;
  }

  @override
  Future<NotificationPermissionStatus> notificationStatus() async {
    notificationStatusCount++;
    return notification;
  }

  @override
  Future<NotificationPermissionStatus> requestNotification() async {
    notificationRequestCount++;
    if (notification != NotificationPermissionStatus.permanentlyDenied) {
      notification = notificationRequestResult ?? notification;
    }
    return notification;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    return openSettingsResult;
  }
}
