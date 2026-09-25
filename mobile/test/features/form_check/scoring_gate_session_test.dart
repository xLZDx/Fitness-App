import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show faceSelfie, oneSquat, squatFrame;

/// Gate T3 wiring: `RepSessionController._onFrame` must not judge a rep on
/// joints that are cropped or guessed, must publish ONE effective verdict, and
/// must leave a completed rep's record alone while the live overlay goes
/// neutral.

class _ManualService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _frames.close();

  Future<void> push(PoseFrame f) async {
    _frames.add(f);
    await Future<void>.delayed(Duration.zero);
  }
}

/// The frame with the ankle where the camera cuts it off. Confident, so only the
/// EDGE says it cannot be trusted; hips and knees — all the squat classifier
/// reads — are untouched.
PoseFrame _ankleCropped(PoseFrame f) => PoseFrame(
      timestampMs: f.timestampMs,
      landmarks: {
        ...f.landmarks,
        LandmarkType.leftAnkle: const PoseLandmark(
            type: LandmarkType.leftAnkle, x: 0.45, y: 0.99, likelihood: 0.95),
      },
    );

ProviderContainer _container(_ManualService svc) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWith((_) => svc),
    voiceCoachProvider.overrideWith((_) => MockVoiceCoach()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void _createControllers(ProviderContainer c, {required bool feedbackFirst}) {
  if (feedbackFirst) {
    c.read(formFeedbackControllerProvider);
    c.read(repSessionControllerProvider);
  } else {
    c.read(repSessionControllerProvider);
    c.read(formFeedbackControllerProvider);
  }
}

void main() {
  for (final feedbackFirst in [true, false]) {
    group(
        'effective verdict, feedback controller created '
        '${feedbackFirst ? "first" : "second"}', () {
      test('classifier ok + scoring outOfFrame -> outOfFrame, then ok again',
          () async {
        final svc = _ManualService();
        final c = _container(svc);
        _createControllers(c, feedbackFirst: feedbackFirst);

        await svc.push(squatFrame(0, 0.42));
        expect(c.read(poseEffectiveGateVerdictProvider), PoseGateVerdict.ok,
            reason: 'positive control: a whole body is ok');

        await svc.push(_ankleCropped(squatFrame(100, 0.42)));
        expect(c.read(poseGateVerdictProvider), PoseGateVerdict.ok,
            reason: 'the raw classifier gate only reads hips and knees');
        expect(c.read(poseEffectiveGateVerdictProvider),
            PoseGateVerdict.outOfFrame,
            reason: 'the scored ankle is cropped, whatever the listener order');

        await svc.push(squatFrame(200, 0.42));
        expect(c.read(poseEffectiveGateVerdictProvider), PoseGateVerdict.ok,
            reason: 'the next reliable frame clears it');
      });

      test('a classifier verdict that is not ok wins over the scoring one',
          () async {
        final svc = _ManualService();
        final c = _container(svc);
        _createControllers(c, feedbackFirst: feedbackFirst);

        await svc.push(faceSelfie(0));
        final raw = c.read(poseGateVerdictProvider);
        expect(raw, isNot(PoseGateVerdict.ok),
            reason: 'positive control: the classifier itself rejected it');
        expect(c.read(poseEffectiveGateVerdictProvider), raw);
      });
    });
  }

  group('what a rep is judged on', () {
    Future<RepSessionState> run(List<PoseFrame> frames) async {
      final svc = _ManualService();
      final c = _container(svc);
      c.read(repSessionControllerProvider);
      c.read(formFeedbackControllerProvider);
      c.read(coachPhaseControllerProvider.notifier).start();
      for (final f in frames) {
        await svc.push(f);
      }
      return c.read(repSessionControllerProvider);
    }

    test('POSITIVE CONTROL: a fully visible rep is counted AND judged',
        () async {
      final s = await run(oneSquat(0));
      expect(s.repCount, 1);
      expect(s.lastRepPeakMatch, isNotNull);
      expect(s.lastRepMissedTarget, isNotNull);
    });

    test(
        'a rep whose scored ankle is cropped throughout is counted but '
        'neither judged nor called missed', () async {
      final s = await run([for (final f in oneSquat(0)) _ankleCropped(f)]);
      expect(s.repCount, 1, reason: 'counting does not depend on the ankle');
      expect(s.lastRepPeakMatch, isNull);
      expect(s.lastRepMissedTarget, isNull,
          reason: 'cannot tell is not a miss');
      expect(s.lastRepEvaluated, isFalse,
          reason: 'squat depth cannot fault, so nothing judged this rep');
    });

    test(
        'a completed missed rep stays missed while the live overlay goes '
        'neutral on an unreliable frame', () async {
      final svc = _ManualService();
      final c = _container(svc);
      c.read(repSessionControllerProvider);
      c.read(formFeedbackControllerProvider);
      c.read(coachPhaseControllerProvider.notifier).start();
      for (final f in oneSquat(0)) {
        await svc.push(f);
      }
      final before = c.read(repSessionControllerProvider);
      expect(before.lastRepMissedTarget, isTrue,
          reason: 'positive control: the rep was judged and missed');

      await svc.push(_ankleCropped(squatFrame(5000, 0.42)));
      final after = c.read(repSessionControllerProvider);
      expect(after.lastRepMissedTarget, isTrue, reason: 'record untouched');
      expect(after.lastRepPeakMatch, before.lastRepPeakMatch);
      expect(after.lastRepEvaluated, before.lastRepEvaluated);

      final classifiers = [SquatDepthClassifier()];
      expect(
          avatarVerdictSeverity(classifiers, null,
              lastRepMissedTarget: true, currentFrameReliable: true),
          2,
          reason: 'positive control: reliable, the missed rep paints red');
      expect(
          avatarVerdictSeverity(classifiers, null,
              lastRepMissedTarget: true,
              currentFrameReliable:
                  c.read(poseEffectiveGateVerdictProvider).isScorable),
          isNull,
          reason: 'the live body cannot be judged, so no verdict colour');
    });

    test('a can-fault rule keeps its colour whatever the target scoring says',
        () {
      expect(
          avatarVerdictSeverity(
              [PushupAlignmentClassifier()],
              const FormFeedback(
                  rule: 'pushup.alignment',
                  severity: 2,
                  cueKey: FormCueKey.pushupAlignSagging),
              currentFrameReliable: false),
          2,
          reason: 'the rule reads its own joints; only the silhouette '
              'fallback depends on the target-scored joints');
    });

    test('a right-side-on rep is scored on the visible side, end to end',
        () async {
      final baseline = await run(oneSquat(0));
      final s = await run([for (final f in oneSquat(0)) _rightSideOn(f)]);
      expect(s.repCount, 1);
      expect(s.lastRepPeakMatch, isNotNull,
          reason: 'scored on the mapped right joints; on the raw frame the '
              'hidden left shoulder and ankle would leave under four joints');
      expect(s.lastRepPeakMatch, baseline.lastRepPeakMatch,
          reason: 'the mapped frame IS the fully visible body');
      expect(s.lastRepMissedTarget, baseline.lastRepMissedTarget);
    });

    test('a rep only cropped at the bottom is judged on its reliable frames',
        () async {
      final baseline = await run(oneSquat(0));
      final frames = oneSquat(0);
      final cropBottom = [
        for (final f in frames)
          f.landmarks[LandmarkType.leftHip]!.y >= 0.70 ? _ankleCropped(f) : f,
      ];
      expect(
          cropBottom.any((f) => f.landmarks[LandmarkType.leftAnkle]!.y > 0.98),
          isTrue,
          reason: 'positive control: some frames really were cropped');
      final s = await run(cropBottom);
      expect(s.repCount, 1);
      expect(s.lastRepPeakMatch, isNotNull,
          reason: 'the descent frames were reliable and scored');
      expect(s.lastRepPeakMatch, lessThanOrEqualTo(baseline.lastRepPeakMatch!),
          reason: 'the cropped bottom frames add nothing to the peak');
    });

    test('with no target nothing is scored and nothing crashes', () async {
      final svc = _ManualService();
      final c = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWith((_) => svc),
        voiceCoachProvider.overrideWith((_) => MockVoiceCoach()),
        poseTargetProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      c.read(repSessionControllerProvider);
      c.read(coachPhaseControllerProvider.notifier).start();
      for (final f in oneSquat(0)) {
        await svc.push(f);
      }
      final s = c.read(repSessionControllerProvider);
      expect(s.repCount, 1);
      expect(s.lastRepPeakMatch, isNull);
      expect(s.lastRepMissedTarget, isNull);
      expect(c.read(poseEffectiveGateVerdictProvider), PoseGateVerdict.ok);

      await svc.push(faceSelfie(9000));
      expect(
          c.read(poseEffectiveGateVerdictProvider), isNot(PoseGateVerdict.ok),
          reason: 'the classifier verdict still applies without a target');
    });

    test(
        'the effective verdict keeps moving while the set is paused, and '
        'works without the feedback controller', () async {
      final svc = _ManualService();
      final c = _container(svc);
      c.read(repSessionControllerProvider); // feedback controller NOT created
      c.read(coachPhaseControllerProvider.notifier)
        ..start()
        ..pause();
      await svc.push(_ankleCropped(squatFrame(0, 0.42)));
      expect(
          c.read(poseEffectiveGateVerdictProvider), PoseGateVerdict.outOfFrame);
      expect(c.read(repSessionControllerProvider).repCount, 0);
      await svc.push(squatFrame(100, 0.42));
      expect(c.read(poseEffectiveGateVerdictProvider), PoseGateVerdict.ok);
    });
  });
}

/// The same body seen from its right side: the far (left) shoulder and ankle are
/// hidden — low confidence, off to one side — and the right ones carry the real
/// positions. Hips and knees stay confident on both sides, as they are in a real
/// side-on view, so the classifier itself still accepts the frame.
PoseFrame _rightSideOn(PoseFrame f) {
  PoseLandmark hidden(LandmarkType t, PoseLandmark o) =>
      PoseLandmark(type: t, x: 0.20, y: o.y, likelihood: 0.10);
  PoseLandmark asRight(LandmarkType t, PoseLandmark o) =>
      PoseLandmark(type: t, x: o.x, y: o.y, likelihood: 0.95);
  final l = f.landmarks;
  return PoseFrame(timestampMs: f.timestampMs, landmarks: {
    ...l,
    LandmarkType.leftShoulder:
        hidden(LandmarkType.leftShoulder, l[LandmarkType.leftShoulder]!),
    LandmarkType.leftAnkle:
        hidden(LandmarkType.leftAnkle, l[LandmarkType.leftAnkle]!),
    LandmarkType.rightShoulder:
        asRight(LandmarkType.rightShoulder, l[LandmarkType.leftShoulder]!),
    LandmarkType.rightHip:
        asRight(LandmarkType.rightHip, l[LandmarkType.leftHip]!),
    LandmarkType.rightKnee:
        asRight(LandmarkType.rightKnee, l[LandmarkType.leftKnee]!),
    LandmarkType.rightAnkle:
        asRight(LandmarkType.rightAnkle, l[LandmarkType.leftAnkle]!),
  });
}
