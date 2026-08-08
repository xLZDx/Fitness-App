import 'dart:async' show unawaited;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart'
    show poseDetectorServiceProvider;
import 'package:fitness_app/features/posture/data/measured_posture_config.dart';
import 'package:fitness_app/features/posture/state/posture_providers.dart';

PoseLandmark _lm(LandmarkType type, double x, double y) =>
    PoseLandmark(type: type, x: x, y: y, likelihood: 0.95);

/// One frame with a shoulder-height difference that lands inside
/// `shoulderAsymmetryRange`'s interquartile band (a "typical" verdict) and
/// ears offset far enough forward to clear `forwardHeadRange`'s p95 (a
/// "notable" verdict) -- distinct verdicts per metric on the same frame
/// prove the three signals are not being cross-wired.
PoseFrame _frame(int t) => PoseFrame(timestampMs: t, landmarks: {
      LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.4, 0.314),
      LandmarkType.rightShoulder: _lm(LandmarkType.rightShoulder, 0.6, 0.3),
      LandmarkType.leftHip: _lm(LandmarkType.leftHip, 0.42, 0.5),
      LandmarkType.rightHip: _lm(LandmarkType.rightHip, 0.58, 0.5),
      LandmarkType.leftEar: _lm(LandmarkType.leftEar, 0.78, 0.15),
      LandmarkType.rightEar: _lm(LandmarkType.rightEar, 0.82, 0.15),
    });

void main() {
  group('summarizePostureCapture (pure)', () {
    test('averages samples and assigns a verdict per metric', () {
      final result = summarizePostureCapture(
        shoulderAsymmetrySamples: [shoulderAsymmetryRange.median],
        pelvisTiltSamples: [pelvisTiltRange.p95 + 1],
        forwardHeadSamples: [],
      );
      expect(result.shoulderAsymmetry!.verdict, PostureVerdict.typical);
      expect(result.pelvisTilt!.verdict, PostureVerdict.notable);
      expect(result.forwardHead, isNull);
      expect(result.isEmpty, isFalse);
    });

    test('every metric missing reads as an empty result', () {
      final result = summarizePostureCapture(
        shoulderAsymmetrySamples: [],
        pelvisTiltSamples: [],
        forwardHeadSamples: [],
      );
      expect(result.isEmpty, isTrue);
    });

    test('averages multiple samples rather than taking the last one', () {
      final result = summarizePostureCapture(
        shoulderAsymmetrySamples: [0.0, 0.2],
        pelvisTiltSamples: [],
        forwardHeadSamples: [],
      );
      expect(result.shoulderAsymmetry!.value, closeTo(0.1, 1e-9));
    });
  });

  group('PostureSessionController', () {
    test('captures frames for the configured window, then averages them',
        () async {
      final svc = MockPoseDetectorService(List.generate(6, _frame));
      final container = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        // Real time in a unit test would mean waiting out 2.5s for nothing;
        // the window's LENGTH is not what this test is about.
        postureCaptureDurationProvider
            .overrideWithValue(const Duration(milliseconds: 150)),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(postureSessionControllerProvider.notifier);
      expect(container.read(postureSessionControllerProvider).phase,
          PostureCapturePhase.idle);

      notifier.start();
      expect(container.read(postureSessionControllerProvider).phase,
          PostureCapturePhase.capturing);

      unawaited(svc.start());
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final state = container.read(postureSessionControllerProvider);
      expect(state.phase, PostureCapturePhase.done);
      expect(state.result, isNotNull);
      expect(state.result!.isEmpty, isFalse);
      expect(state.result!.shoulderAsymmetry!.verdict, PostureVerdict.typical);
      expect(state.result!.forwardHead!.verdict, PostureVerdict.notable);
    });

    test('reset() returns to idle with no result', () async {
      final svc = MockPoseDetectorService(List.generate(6, _frame));
      final container = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        postureCaptureDurationProvider
            .overrideWithValue(const Duration(milliseconds: 100)),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(postureSessionControllerProvider.notifier);
      notifier.start();
      unawaited(svc.start());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(container.read(postureSessionControllerProvider).phase,
          PostureCapturePhase.done);

      notifier.reset();
      final state = container.read(postureSessionControllerProvider);
      expect(state.phase, PostureCapturePhase.idle);
      expect(state.result, isNull);
    });
  });
}
