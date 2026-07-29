import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Stands in for the ML Kit service when the native detector dies: the stream
/// stays open but carries an error instead of frames.
class _ErroringPoseService implements PoseDetectorService {
  final StreamController<PoseFrame> _ctrl =
      StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> frames() => _ctrl.stream;

  @override
  Future<void> start() async {
    _ctrl.addError(StateError('Pose detection failed: bad frame format'));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _ctrl.close();
}

void main() {
  // Regression, 2026-07-30. The detector's per-frame handler swallowed every
  // exception, including the permanent PlatformException that ML Kit raises
  // for a frame format it cannot read. On device that looked like a working
  // camera that never counted a rep, with nothing on screen and nothing in
  // the suite to catch it. Native failures must reach the UI.
  test('a fatal detector error reaches poseErrorProvider', () async {
    final svc = _ErroringPoseService();
    final container = ProviderContainer(
      overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    // Building the controller is what subscribes to the stream.
    container.read(formFeedbackControllerProvider);
    expect(container.read(poseErrorProvider), isNull);

    await svc.start();
    await pumpEventQueue();

    expect(container.read(poseErrorProvider),
        'Pose detection failed: bad frame format',
        reason: 'the page reads this to explain why nothing is counting');
    await svc.dispose();
  });

  test('the rep session controller also reports a fatal error', () async {
    final svc = _ErroringPoseService();
    final container = ProviderContainer(
      overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    container.read(repSessionControllerProvider);
    await svc.start();
    await pumpEventQueue();

    expect(container.read(poseErrorProvider), isNotNull,
        reason: 'either subscriber may be the only live one');
    await svc.dispose();
  });

  test('a healthy stream leaves the error slot empty', () async {
    final svc = MockPoseDetectorService([
      PoseFrame(timestampMs: 1, landmarks: const {}),
    ]);
    final container = ProviderContainer(
      overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    container.read(formFeedbackControllerProvider);
    await svc.start();
    await pumpEventQueue();

    expect(container.read(poseErrorProvider), isNull);
    await svc.dispose();
  });
}
