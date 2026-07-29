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
/// recognised.
///
/// **autoDispose is load-bearing, not a style choice.** A keep-alive provider
/// would hold the camera stream after the user leaves the Scan tab: the
/// camera indicator would stay lit and the classifier would keep burning
/// battery on frames nobody is looking at. With autoDispose, losing the last
/// listener tears the stream down and [ref.onDispose] releases the camera.
final liveRecognitionProvider =
    StreamProvider.autoDispose<LiveRecognition?>((ref) {
  final enabled = ref.watch(liveModeEnabledProvider);
  final svc = ref.watch(liveEquipmentServiceProvider);
  if (!enabled) {
    unawaited(svc.stop());
    return Stream<LiveRecognition?>.value(null);
  }
  ref.onDispose(() => unawaited(svc.stop()));

  // start() can fail for reasons the user must be told about: camera
  // permission denied, camera already in use, the model missing. An
  // unawaited future would drop those on the floor and leave the UI
  // spinning "Looking…" forever, so funnel both readings and failures
  // through one controller the page is already watching.
  final out = StreamController<LiveRecognition?>();
  final sub = svc.recognitions().listen(
        out.add,
        onError: out.addError,
      );
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(out.close());
  });
  svc.start().catchError((Object e, StackTrace st) {
    if (!out.isClosed) out.addError(e, st);
  });

  return out.stream;
});
