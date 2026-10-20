/// Small interfaces between the scan screens and everything that needs a real
/// device: camera + pose stream, speech and haptics. The screens only see
/// these, so widget tests replace them with fakes and never open a platform
/// channel.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/camera/camera_session.dart';
import '../../../form_check/data/mlkit_pose_detector_service.dart';
import '../../../form_check/data/pose_landmark.dart';
import '../../../form_check/state/form_check_providers.dart'
    show voiceCoachProvider;
import '../../../visual_equipment/widgets/live_equipment_preview.dart';
import '../../state/progress_photos_providers.dart';

/// Camera preview, pose frames and still capture for the scan.
abstract class ScanCamera {
  /// Pose frames in the isotropic coordinate contract of `PoseFrame`.
  Stream<PoseFrame> frames();

  /// True while the scene is sustained dark.
  ValueListenable<bool> get lowLight;

  /// The lens that is actually open.
  ValueListenable<SessionFacing> get facing;

  /// Opens the camera (asking for permission) and starts pose detection.
  /// Throws when the camera cannot be used.
  Future<void> start();

  Future<void> stop();

  Future<void> flip();

  /// Takes one still and returns its pixels, or null when the camera declined.
  Future<Uint8List?> captureStill();

  Widget buildPreview(BuildContext context);

  Future<void> dispose();
}

/// Speaks a short phrase. Best effort; honours the user's mute switch.
abstract class ScanSpeaker {
  Future<void> say(String text);
  Future<void> stop();
}

/// Tactile feedback for the countdown and the shutter.
abstract class ScanHaptics {
  void tick();
  void shutter();
  void warn();
}

/// Millisecond clock the shutter machine is fed from. Overridden in tests.
typedef ScanClock = int Function();

final scanClockProvider = Provider<ScanClock>(
  (_) => () => DateTime.now().millisecondsSinceEpoch,
);

class _PlatformHaptics implements ScanHaptics {
  const _PlatformHaptics();

  @override
  void tick() => unawaited(HapticFeedback.selectionClick());

  @override
  void shutter() => unawaited(HapticFeedback.heavyImpact());

  @override
  void warn() => unawaited(HapticFeedback.lightImpact());
}

final scanHapticsProvider =
    Provider<ScanHaptics>((_) => const _PlatformHaptics());

/// Routes speech through the app's single voice coach, so the scan never owns a
/// second speech engine and the existing mute switch applies.
class _VoiceCoachSpeaker implements ScanSpeaker {
  _VoiceCoachSpeaker(this._ref);
  final Ref _ref;

  @override
  Future<void> say(String text) async {
    try {
      await _ref.read(voiceCoachProvider).say(text);
    } catch (_) {
      // Speech is a nicety: a missing TTS voice must never break the scan.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _ref.read(voiceCoachProvider).stop();
    } catch (_) {}
  }
}

final scanSpeakerProvider =
    Provider<ScanSpeaker>((ref) => _VoiceCoachSpeaker(ref));

/// Real camera: the progress-photo [CameraSession] (rear lens by default) with
/// ML Kit pose detection attached to the same session, so there is one camera
/// and one stream.
class MlKitScanCamera implements ScanCamera {
  MlKitScanCamera({
    required CameraSession session,
    required Future<Uint8List?> Function() takeStill,
    MlKitPoseDetectorService? detector,
  })  : _session = session,
        _takeStill = takeStill,
        _detector = detector ?? MlKitPoseDetectorService(session: session);

  final CameraSession _session;
  final Future<Uint8List?> Function() _takeStill;
  final MlKitPoseDetectorService _detector;

  @override
  Stream<PoseFrame> frames() => _detector.frames();

  @override
  ValueListenable<bool> get lowLight => _session.isLowLight;

  @override
  ValueListenable<SessionFacing> get facing => _session.activeFacing;

  @override
  Future<void> start() async {
    await _detector.ensurePermission();
    await _detector.start();
  }

  @override
  Future<void> stop() => _detector.stop();

  @override
  Future<void> flip() => _detector.flipCamera();

  @override
  Future<Uint8List?> captureStill() => _takeStill();

  @override
  Widget buildPreview(BuildContext context) =>
      LiveEquipmentPreview(session: _session);

  @override
  Future<void> dispose() => _detector.dispose();
}

final scanCameraProvider = Provider.autoDispose<ScanCamera>((ref) {
  final session = ref.read(progressPhotoCameraProvider);
  final camera = MlKitScanCamera(
    session: session,
    takeStill: () => ref.read(progressPhotosRepositoryProvider).takeShot(),
  );
  ref.onDispose(() => unawaited(camera.dispose()));
  return camera;
});
