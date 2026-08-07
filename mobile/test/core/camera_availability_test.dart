import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:fitness_app/core/camera/camera_availability.dart';

/// R2.9. These pin the mapping from a raw platform failure to the reason the
/// user is shown, because that mapping is the whole feature: the codes are
/// platform-specific and inconsistent (`CameraAccessDeniedWithoutPrompt` is
/// iOS-only; Android emits `CameraAccessDenied` for both askable and
/// permanent refusals), and getting one wrong sends the user to the wrong fix.
void main() {
  group('classifyCameraFailure', () {
    test('iOS permanent-refusal codes ask for Settings, not another prompt',
        () {
      // Verified against camera_avfoundation: these are the two codes it
      // declares for a refusal the in-app dialog can no longer change.
      for (final code in ['CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted']) {
        final failure = classifyCameraFailure(CameraException(code, 'x'));
        expect(failure.reason,
            CameraUnavailableReason.permissionPermanentlyDenied,
            reason: '$code must not offer a prompt that cannot appear');
        expect(failure.needsSettings, isTrue);
        expect(failure.isRetryable, isFalse);
      }
    });

    test('an askable refusal stays askable', () {
      final failure =
          classifyCameraFailure(CameraException('CameraAccessDenied', 'x'));
      expect(failure.reason, CameraUnavailableReason.permissionDenied);
      expect(failure.isRetryable, isTrue);
      expect(failure.needsSettings, isFalse);
    });

    test('a stray StateError does NOT masquerade as absent hardware', () {
      // Deliberate: an earlier draft classified every StateError as noCamera,
      // reasoning that `cameras.first` throws one on a device with no camera.
      // But matching by TYPE catches any StateError raised anywhere during
      // open, and noCamera is the single reason that renders no recovery
      // action at all — the worst outcome to arrive at by accident. Absent
      // hardware is now detected explicitly, at the one call site that can
      // tell (`CameraSession._open` checks `cameras.isEmpty`).
      final failure = classifyCameraFailure(StateError('No element'));
      expect(failure.reason, CameraUnavailableReason.initializationFailed);
      expect(failure.isRetryable, isTrue,
          reason: 'an unrecognised failure must still leave a way forward');
    });

    test('an explicitly-thrown no-camera reason survives classification', () {
      const thrown = CameraUnavailable(CameraUnavailableReason.noCamera);
      final failure = classifyCameraFailure(thrown);
      expect(failure.reason, CameraUnavailableReason.noCamera);
      expect(failure.isRetryable, isFalse,
          reason: 'retrying absent hardware can never succeed');
      expect(failure.needsSettings, isFalse);
    });

    test('an unrecognised camera error is retryable, not fatal', () {
      // Camera-busy lands here: neither platform exposes an in-use code to
      // Dart, and retry happens to be the right action for it anyway.
      final failure =
          classifyCameraFailure(CameraException('cameraNotReadable', 'busy'));
      expect(failure.reason, CameraUnavailableReason.initializationFailed);
      expect(failure.isRetryable, isTrue);
    });

    test('a non-camera error still produces a usable reason', () {
      final failure = classifyCameraFailure(ArgumentError('nonsense'));
      expect(failure.reason, CameraUnavailableReason.initializationFailed);
    });

    test('an already-classified failure passes through unchanged', () {
      const original = CameraUnavailable(CameraUnavailableReason.noCamera);
      expect(identical(classifyCameraFailure(original), original), isTrue,
          reason: 'wrapping a reason in itself would lose it');
    });

    test('the cause is kept for logs but is not the message', () {
      final cause = CameraException('CameraAccessDenied', 'raw platform text');
      final failure = classifyCameraFailure(cause);
      expect(failure.cause, same(cause));
    });
  });

  group('reasonForPermission', () {
    test('granted opens the camera', () {
      expect(reasonForPermission(PermissionStatus.granted), isNull);
    });

    test('denied is askable', () {
      expect(reasonForPermission(PermissionStatus.denied),
          CameraUnavailableReason.permissionDenied);
    });

    test('permanently denied and restricted both need Settings', () {
      expect(reasonForPermission(PermissionStatus.permanentlyDenied),
          CameraUnavailableReason.permissionPermanentlyDenied);
      // Device policy / parental controls. The user cannot grant it from a
      // prompt either, so it takes the same route.
      expect(reasonForPermission(PermissionStatus.restricted),
          CameraUnavailableReason.permissionPermanentlyDenied);
    });

    test('limited and provisional are treated as usable', () {
      // Photo-library concepts `Permission.camera` never returns. Mapped to
      // "may open" rather than invented into a state with no user action.
      expect(reasonForPermission(PermissionStatus.limited), isNull);
      expect(reasonForPermission(PermissionStatus.provisional), isNull);
    });
  });
}
