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

  /// Mean brightness (0..1) of the latest analysed frame, or null when the
  /// camera cannot measure it. NON-abstract on purpose: an implementer that
  /// does not measure stays valid, and the screen then falls back to the
  /// `lowLight` verdict (over-exposure is simply not detected).
  double? get luminance => null;

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
  /// Resolves to true when the phrase was handed to the speech engine and
  /// false when speech failed or is unavailable. The failure stays swallowed
  /// (a missing TTS voice must never break the scan) but is observable, so the
  /// live-region fallback can be tested (D-80).
  Future<bool> say(String text);
  Future<void> stop();
}

/// The named, distinguishable haptic patterns of the capture screen (D-80):
/// the documented non-visual alternative to the skeleton overlay.
enum ScanHapticPattern {
  /// All four checks pass.
  ready,

  /// Readiness was lost.
  lost,

  /// One pattern per failing check class.
  distance,
  lighting,
  position,
  pose,
}

/// Tactile feedback for the countdown and the shutter.
abstract class ScanHaptics {
  void tick();
  void shutter();
  void warn();

  /// A named pattern. Distinct patterns are distinct call sequences.
  void pattern(ScanHapticPattern p);
}

/// The manual-shutter timer lengths the user can choose (D-80).
const List<int> kScanManualTimerChoices = [3, 5, 10];

/// Default manual-shutter timer in seconds.
const int kScanManualTimerDefault = 5;

/// The chosen manual-shutter timer; a value outside [kScanManualTimerChoices]
/// is treated as the default by the screen.
final scanManualTimerSecondsProvider =
    StateProvider<int>((_) => kScanManualTimerDefault);

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

  @override
  void pattern(ScanHapticPattern p) {
    switch (p) {
      case ScanHapticPattern.ready:
        unawaited(HapticFeedback.mediumImpact());
      case ScanHapticPattern.lost:
        unawaited(HapticFeedback.heavyImpact());
      case ScanHapticPattern.distance:
        unawaited(_burst([HapticFeedback.lightImpact]));
      case ScanHapticPattern.lighting:
        unawaited(_burst(
            [HapticFeedback.lightImpact, HapticFeedback.lightImpact]));
      case ScanHapticPattern.position:
        unawaited(_burst([
          HapticFeedback.lightImpact,
          HapticFeedback.lightImpact,
          HapticFeedback.lightImpact,
        ]));
      case ScanHapticPattern.pose:
        unawaited(_burst(
            [HapticFeedback.selectionClick, HapticFeedback.heavyImpact]));
    }
  }

  Future<void> _burst(List<Future<void> Function()> steps) async {
    for (var i = 0; i < steps.length; i++) {
      await steps[i]();
      if (i + 1 < steps.length) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }
}

final scanHapticsProvider =
    Provider<ScanHaptics>((_) => const _PlatformHaptics());

/// Routes speech through the app's single voice coach, so the scan never owns a
/// second speech engine and the existing mute switch applies.
class _VoiceCoachSpeaker implements ScanSpeaker {
  _VoiceCoachSpeaker(this._ref);
  final Ref _ref;

  @override
  Future<bool> say(String text) async {
    try {
      await _ref.read(voiceCoachProvider).say(text);
      return true;
    } catch (_) {
      // Speech is a nicety: a missing TTS voice must never break the scan.
      return false;
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
  double? get luminance => _session.lastBrightness;

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
