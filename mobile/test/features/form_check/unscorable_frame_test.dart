import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// End of the chain: an unscorable frame must not reach the rep counter and
/// must not reach the voice coach.
///
/// Asserted through [RepSessionController], not through `gatePose`. The rep
/// counter re-derives its own signal from the raw frame rather than consuming
/// the gate's verdict, so it is protected by exactly one early return in the
/// controller — one refactor away from being lost, and nothing else would
/// notice.
///
/// The positive control is not optional. A first draft of this file forgot to
/// call `start()`, so no frames flowed at all and "0 reps" passed for the wrong
/// reason. Any test that asserts an absence needs a sibling that proves the
/// pipeline was actually running.
PoseLandmark p(LandmarkType t, double x, double y, [double likelihood = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

/// A face at arm's length: shoulders real, everything below invented and
/// collapsed just under the chin.
PoseFrame faceSelfie(int ts) => PoseFrame(timestampMs: ts, landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.48, 0.15),
      LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.52, 0.15),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.48, 0.18),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.52, 0.18),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.48, 0.21),
      LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.52, 0.21),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.48, 0.24),
    });

/// A whole body, upright, with the hips at [hipY] and the knees fixed — the
/// only thing that varies through a squat.
PoseFrame squatFrame(int ts, double hipY) =>
    PoseFrame(timestampMs: ts, landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, hipY - 0.28),
      LandmarkType.rightShoulder:
          p(LandmarkType.rightShoulder, 0.55, hipY - 0.28),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, hipY),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, hipY),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.72),
      LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.72),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.45, 0.90),
    });

/// One rep: stand, sink until the hips reach the knees, stand again.
List<PoseFrame> oneSquat(int startTs) {
  final out = <PoseFrame>[];
  var ts = startTs;
  void hold(double hipY, int frames) {
    for (var i = 0; i < frames; i++) {
      out.add(squatFrame(ts, hipY));
      ts += 100;
    }
  }

  hold(0.42, 4); // standing: hip well above knee
  for (var hipY = 0.46; hipY < 0.71; hipY += 0.04) {
    out.add(squatFrame(ts, hipY));
    ts += 100;
  }
  hold(0.71, 4); // bottom: hip level with the knee
  for (var hipY = 0.68; hipY > 0.42; hipY -= 0.04) {
    out.add(squatFrame(ts, hipY));
    ts += 100;
  }
  hold(0.42, 4);
  return out;
}

Future<(RepSessionState, MockVoiceCoach, PoseGateReading)> run(
    List<PoseFrame> frames) async {
  final coach = MockVoiceCoach();
  final svc = MockPoseDetectorService(frames);
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWith((_) => svc),
    voiceCoachProvider.overrideWith((_) => coach),
  ]);
  addTearDown(container.dispose);

  container.read(repSessionControllerProvider);
  container.read(formFeedbackControllerProvider);
  await svc.start();
  await Future<void>.delayed(const Duration(milliseconds: 20));

  return (
    container.read(repSessionControllerProvider),
    coach,
    PoseGateReading(container.read(poseGateVerdictProvider).isScorable),
  );
}

/// Tiny wrapper so the record above reads at the call site.
class PoseGateReading {
  const PoseGateReading(this.scorable);
  final bool scorable;
}

void main() {
  test('POSITIVE CONTROL: a real squat stream does count reps', () async {
    final (session, _, gate) = await run(oneSquat(0));
    expect(gate.scorable, isTrue, reason: 'a whole upright body is scorable');
    expect(session.repCount, greaterThan(0),
        reason: 'without this the negative test below proves nothing');
  });

  test('a face-only stream produces no reps and no spoken cue', () async {
    final frames = [for (var i = 0; i < 30; i++) faceSelfie(i * 100)];
    final (session, coach, gate) = await run(frames);

    expect(session.repCount, 0, reason: 'a face is not a set of squats');
    expect(session.reps, isEmpty);
    expect(coach.spoken, isEmpty, reason: 'nothing real to warn about');
    expect(gate.scorable, isFalse,
        reason: 'the user must be told why, not left with a blank card');
  });
}
