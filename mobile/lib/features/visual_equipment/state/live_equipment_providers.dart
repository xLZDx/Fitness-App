import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/live_equipment_service.dart';
import '../data/live_recognition.dart';

/// Defaults to the mock so widget tests never touch a camera; `main.dart`
/// overrides it with [MlKitLiveEquipmentService] on device.
final liveEquipmentServiceProvider = Provider<LiveEquipmentService>((ref) {
  final svc = MockLiveEquipmentService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Whether the user has switched live recognition on. Off by default: the
/// camera stream is the most expensive thing this app can do, so it only
/// runs when asked for.
final liveModeEnabledProvider = StateProvider<bool>((_) => false);

/// The latest settled reading, or null when nothing is confidently
/// recognised. Starts/stops the camera with the provider's own lifecycle so
/// leaving the tab always releases it.
final liveRecognitionProvider = StreamProvider<LiveRecognition?>((ref) {
  final enabled = ref.watch(liveModeEnabledProvider);
  final svc = ref.watch(liveEquipmentServiceProvider);
  if (!enabled) {
    unawaited(svc.stop());
    return Stream<LiveRecognition?>.value(null);
  }
  unawaited(svc.start());
  ref.onDispose(() => unawaited(svc.stop()));
  return svc.recognitions().map<LiveRecognition?>((r) => r);
});
