import 'package:permission_handler/permission_handler.dart';

import 'location_permission_status.dart';
import 'permission_service.dart';

/// [PermissionService] over `permission_handler` (S04 design 2.2).
///
/// Reads the platform on every call and caches nothing.
///
/// Precise vs approximate: `permission_handler` reports one `granted` for
/// `Permission.location` and does not say which of fine/coarse was granted
/// (design 2.3 first step 3 lists this as UNKNOWN). [isPreciseGranted] is the
/// hook for a platform read that can tell; when it is null a granted location
/// is reported as [LocationPermissionStatus.grantedPrecise] and the accuracy
/// gate (S04-R-006) remains the backstop against coarse fixes.
class PermissionHandlerPermissionService implements PermissionService {
  const PermissionHandlerPermissionService({this.isPreciseGranted});

  final Future<bool> Function()? isPreciseGranted;

  @override
  Future<LocationPermissionStatus> locationStatus() async =>
      _mapLocation(await Permission.location.status);

  @override
  Future<LocationPermissionStatus> requestLocation() async {
    final current = await Permission.location.status;
    // Never re-prompt a permission that only the settings screen can change.
    if (current.isPermanentlyDenied || current.isRestricted) {
      return _mapLocation(current);
    }
    return _mapLocation(await Permission.location.request());
  }

  @override
  Future<NotificationPermissionStatus> notificationStatus() async =>
      _mapNotification(await Permission.notification.status);

  @override
  Future<NotificationPermissionStatus> requestNotification() async {
    final current = await Permission.notification.status;
    if (current.isPermanentlyDenied) return _mapNotification(current);
    return _mapNotification(await Permission.notification.request());
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  Future<LocationPermissionStatus> _mapLocation(PermissionStatus status) async {
    if (status.isGranted) {
      final probe = isPreciseGranted;
      if (probe == null || await probe()) {
        return LocationPermissionStatus.grantedPrecise;
      }
      return LocationPermissionStatus.grantedApproximate;
    }
    // `limited` is an iOS photo-library concept; as approximate it is refused,
    // which is the safe reading for a recorder.
    if (status.isLimited) return LocationPermissionStatus.grantedApproximate;
    if (status.isRestricted) return LocationPermissionStatus.restricted;
    if (status.isPermanentlyDenied) {
      return LocationPermissionStatus.permanentlyDenied;
    }
    return LocationPermissionStatus.denied;
  }

  NotificationPermissionStatus _mapNotification(PermissionStatus status) {
    if (status.isGranted || status.isProvisional) {
      return NotificationPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return NotificationPermissionStatus.permanentlyDenied;
    }
    return NotificationPermissionStatus.denied;
  }
}
