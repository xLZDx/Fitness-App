import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_availability.dart';
import '../../../core/camera/camera_session.dart';
import '../data/live_equipment_service.dart';
import '../data/live_recognition.dart';

/// The camera-permission platform calls, behind a provider so a widget test
/// can drive "Open Settings" without reaching the real platform channel.
final cameraPermissionGateProvider =
    Provider<CameraPermissionGate>((ref) => const CameraPermissionGate());

/// The Scan tab's camera.
///
/// Constructed but NOT started: an unstarted session holds no camera and its
/// surface is null, so widget tests render the preview placeholder without
/// touching a device and without needing a mock. The page starts and stops it.
final scanCameraSessionProvider = Provider<CameraSession>((ref) {
  final session = CameraSession();
  ref.onDispose(() => unawaited(session.dispose()));
  return session;
});

/// Defaults to the mock so widget tests never touch a camera; `main.dart`
/// overrides it with [MlKitLiveEquipmentService] on device.
final liveEquipmentServiceProvider = Provider<LiveEquipmentService>((ref) {
  final svc = MockLiveEquipmentService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Whether the user has switched live recognition on. Off by default: the
/// equipment labeler is the most expensive thing this app can do, so it only
/// runs when asked for.
///
/// This gates the LABELER, not the camera. The camera runs whenever the Scan
/// tab is open, which is what makes the viewfinder always show what it is
/// pointed at.
final liveModeEnabledProvider = StateProvider<bool>((_) => false);

/// The latest settled reading, or null when nothing is confidently recognised.
///
/// **autoDispose is load-bearing, not a style choice.** A keep-alive provider
/// would hold the labeler attached after the user leaves the Scan tab, burning
/// battery on frames nobody is looking at.
final liveRecognitionProvider =
    StreamProvider.autoDispose<LiveRecognition?>((ref) {
  final enabled = ref.watch(liveModeEnabledProvider);
  final svc = ref.watch(liveEquipmentServiceProvider);
  if (!enabled) {
    unawaited(svc.stop());
    return Stream<LiveRecognition?>.value(null);
  }
  ref.onDispose(() => unawaited(svc.stop()));

  // start() can fail for reasons the user must be told about: camera permission
  // denied, camera already in use, the model missing. An unawaited future would
  // drop those on the floor and leave the UI spinning "Looking…" forever, so
  // funnel both readings and failures through one controller the page watches.
  final out = StreamController<LiveRecognition?>();
  final sub = svc.recognitions().listen(out.add, onError: out.addError);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(out.close());
  });
  svc.start().catchError((Object e, StackTrace st) {
    if (!out.isClosed) out.addError(e, st);
  });

  return out.stream;
});
