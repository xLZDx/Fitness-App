import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
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

/// A coach whose engine is broken — the shape of a phone with no voice pack
/// installed for the app's language.
class _FailingVoiceCoach implements VoiceCoach {
  @override
  String? lastErrorMessage;

  @override
  Future<void> cue(FormFeedback feedback) async {
    lastErrorMessage = 'MissingPluginException: no voice installed';
  }

  @override
  bool muted = false;

  @override
  void setMuted(bool value) => muted = value;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// A frame a rule can actually score, so the coach is genuinely asked to speak.
/// A frame the gate rejects would exercise nothing.
PoseFrame _squatFrame() {
  PoseLandmark p(LandmarkType t, double x, double y) =>
      PoseLandmark(type: t, x: x, y: y, likelihood: 0.95);
  return PoseFrame(timestampMs: 1, landmarks: {
    LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.20),
    LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.20),
    LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.55),
    LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.55),
    LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.70),
    LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.70),
  });
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

  group('a speech failure reaches something the UI can watch', () {
    // The page used to read `ref.watch(voiceCoachProvider).lastErrorMessage`.
    // That provider yields one long-lived object and the message is a getter
    // over a mutable field, so a failure notified NOTHING -- the banner painted
    // only if some unrelated provider happened to change afterwards. On a phone
    // with no voice installed the coach could sit permanently mute with the card
    // explaining why never shown, which is the exact confusion it was added to
    // remove.

    test('a failing coach populates voiceErrorProvider', () async {
      final coach = _FailingVoiceCoach();
      final svc = MockPoseDetectorService([_squatFrame()]);
      final container = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        voiceCoachProvider.overrideWithValue(coach),
      ]);
      addTearDown(container.dispose);

      container.read(repSessionControllerProvider);
      expect(container.read(voiceErrorProvider), isNull);

      await svc.start();
      await pumpEventQueue();

      expect(container.read(voiceErrorProvider), contains('no voice installed'),
          reason: 'silence must be distinguishable from "your form is fine"');
      await svc.dispose();
    });

    test('a healthy coach leaves it null', () async {
      // The positive control: the banner must not appear on a working device.
      final coach = MockVoiceCoach();
      final svc = MockPoseDetectorService([_squatFrame()]);
      final container = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        voiceCoachProvider.overrideWithValue(coach),
      ]);
      addTearDown(container.dispose);

      container.read(repSessionControllerProvider);
      await svc.start();
      await pumpEventQueue();

      expect(container.read(voiceErrorProvider), isNull);
      await svc.dispose();
    });
  });

  group('a stale error does not outlive the failure', () {
    // The provider is app-scoped and nothing ever cleared it. One transient
    // native failure pinned "camera unavailable" onto the screen for good:
    // leaving the page, returning, backgrounding, resuming -- the page reads
    // `_startError ?? poseErrorProvider`, so even a fully successful restart
    // could not get past it. The only exit was reinstalling the app.

    test('a delivered frame retires it', () async {
      final svc = MockPoseDetectorService([
        PoseFrame(timestampMs: 1, landmarks: const {}),
      ]);
      final container = ProviderContainer(
        overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      container.read(formFeedbackControllerProvider);
      // A failure from an earlier visit to the page, still on display.
      container.read(poseErrorProvider.notifier).state = 'stale failure';

      await svc.start();
      await pumpEventQueue();

      expect(container.read(poseErrorProvider), isNull,
          reason: 'frames are flowing, so the reason nothing works is gone');
      await svc.dispose();
    });

    test('the rep session controller retires it too', () async {
      // Either subscriber may be the only live one, so neither may be the only
      // one that can recover.
      final svc = MockPoseDetectorService([
        PoseFrame(timestampMs: 1, landmarks: const {}),
      ]);
      final container = ProviderContainer(
        overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      container.read(repSessionControllerProvider);
      container.read(poseErrorProvider.notifier).state = 'stale failure';

      await svc.start();
      await pumpEventQueue();

      expect(container.read(poseErrorProvider), isNull);
      await svc.dispose();
    });

    test('a start that delivers NO frame does not retire it', () async {
      // The positive control, and the design decision it guards. Clearing when
      // start() returns would look equivalent and is not: in an earlier bug in
      // this same feature the camera started, the preview painted, and no frame
      // ever arrived. Only a delivered frame proves the pipeline works, so the
      // error must survive a start that produces nothing.
      //
      // This test has to actually START the service. Asserting on a value the
      // test itself just wrote, without running anything, would pass no matter
      // what the production code did.
      final svc = MockPoseDetectorService(const []);
      final container = ProviderContainer(
        overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      container.read(formFeedbackControllerProvider);
      container.read(poseErrorProvider.notifier).state = 'still broken';

      await svc.start();
      await pumpEventQueue();

      expect(container.read(poseErrorProvider), 'still broken',
          reason: 'a camera that starts and then delivers nothing is the exact '
              'failure this error exists to report');
      await svc.dispose();
    });
  });
}
