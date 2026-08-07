import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// Why the camera could not be opened, in terms the user can act on.
///
/// R2.9. This exists because every failure used to reach the scanner as a bare
/// `Object` and render as one sentence — "camera unavailable" — whether the
/// user had denied the permission, denied it permanently, or was holding a
/// device with no camera at all. Three different problems with three different
/// fixes, and the screen told the user none of them.
///
/// Deliberately NOT a mirror of the plugin's own error codes. Those are
/// platform-specific (`CameraAccessDeniedWithoutPrompt` exists only on iOS),
/// inconsistent, and are exactly the raw exception text this app must never
/// put in front of a user.
enum CameraUnavailableReason {
  /// Denied, but askable again — the in-app request is the fix.
  permissionDenied,

  /// Denied for good, or restricted by device policy. Only the system
  /// settings screen can change it, so that is the only honest action.
  permissionPermanentlyDenied,

  /// No camera hardware at all. Nothing to retry; the gallery path is the
  /// only remaining way to use recognition.
  noCamera,

  /// Everything else: the camera exists and is permitted, but this attempt
  /// failed. Retry is worth offering.
  ///
  /// Camera-busy ("another app is using it") is deliberately NOT a separate
  /// reason. Verified against both platform packages: `camera_avfoundation`
  /// declares exactly `CameraAccessDenied` / `CameraAccessDeniedWithoutPrompt`
  /// / `CameraAccessRestricted`, and the Android side of
  /// `camera_android_camerax` emits only `CameraAccessDenied` and
  /// `AudioAccessDenied`. Neither exposes an in-use code to the Dart layer, so
  /// a separate "camera busy" state could only be produced by pattern-matching
  /// free-text descriptions — a guess dressed as a diagnosis. It lands here,
  /// where the offered action (retry) happens to be the right one for a
  /// transient conflict anyway.
  initializationFailed,
}

/// A camera failure the UI can render without inspecting a plugin exception.
///
/// [cause] is kept for logs only. It must never reach the screen — see the
/// prohibition on showing internal exceptions to users.
class CameraUnavailable implements Exception {
  const CameraUnavailable(this.reason, [this.cause]);

  final CameraUnavailableReason reason;
  final Object? cause;

  /// True when the system settings screen is the only way forward.
  bool get needsSettings =>
      reason == CameraUnavailableReason.permissionPermanentlyDenied;

  /// True when trying again could plausibly work.
  bool get isRetryable =>
      reason == CameraUnavailableReason.initializationFailed ||
      reason == CameraUnavailableReason.permissionDenied;

  @override
  String toString() => 'CameraUnavailable($reason, cause: $cause)';
}

/// iOS-only codes, verified in `camera_avfoundation`. Android's plugin emits
/// only `CameraAccessDenied` of this family.
const _deniedForeverCodes = {
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
};

/// Classifies a raw failure from the camera plugin.
///
/// Only reached when the permission gate already passed, so a denial arriving
/// here means the platform disagrees with `permission_handler` — rare, and
/// still a permission problem from the user's point of view.
CameraUnavailable classifyCameraFailure(Object error) {
  if (error is CameraUnavailable) return error;
  if (error is CameraException) {
    if (_deniedForeverCodes.contains(error.code)) {
      return CameraUnavailable(
          CameraUnavailableReason.permissionPermanentlyDenied, error);
    }
    if (error.code == 'CameraAccessDenied') {
      return CameraUnavailable(
          CameraUnavailableReason.permissionDenied, error);
    }
  }
  // No `StateError -> noCamera` rule. An empty camera list is detected at the
  // one call site that can tell (`CameraSession._open`), which throws the
  // reason directly and is passed through above. Matching StateError by TYPE
  // here would classify any unrelated StateError raised anywhere during open
  // as "no camera" — and `noCamera` is the single reason that renders no
  // recovery action at all, so a stray match strands the user on purpose-built
  // dead end. Unrecognised failures are better off retryable.
  return CameraUnavailable(CameraUnavailableReason.initializationFailed, error);
}

/// Maps a [PermissionStatus] to a reason, or null when the camera may open.
///
/// `limited` and `provisional` are iOS photo-library concepts that
/// `Permission.camera` never returns; they are treated as granted rather than
/// invented into a state the user could not act on.
CameraUnavailableReason? reasonForPermission(PermissionStatus status) {
  if (status.isGranted || status.isLimited || status.isProvisional) return null;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return CameraUnavailableReason.permissionPermanentlyDenied;
  }
  return CameraUnavailableReason.permissionDenied;
}

/// The camera permission gate, injectable so widget tests never touch the
/// platform channel.
///
/// A class rather than two loose functions because the scanner needs all three
/// operations (read, request, open settings) and a test needs to swap all three
/// at once.
class CameraPermissionGate {
  const CameraPermissionGate();

  /// Current status without prompting. Used to decide whether an explanation
  /// should be shown BEFORE the system dialog appears.
  Future<PermissionStatus> status() => Permission.camera.status;

  /// Shows the system prompt. On a permanently-denied permission the platform
  /// returns immediately without a dialog, which is why the caller must handle
  /// the result rather than assume a prompt was seen.
  Future<PermissionStatus> request() => Permission.camera.request();

  /// Opens the app's settings page. Returns false when the platform refused.
  Future<bool> openSettings() => openAppSettings();
}
