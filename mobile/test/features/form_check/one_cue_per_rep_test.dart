import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat;

/// The pacing of spoken cues.
///
/// Operator, 2026-07-31, watching a recording of his own set: *"то что она
/// постоянно повторяет одно и то же это бесит, просто красный и зелёный банер
/// должно хватить и одно замечание голосом на один присид"*.
///
/// He was right about the mechanism as well as the feeling. A severity-2 cue
/// took the interrupt path, which repeats every `interruptGapMs` (1.2 s) for as
/// long as the position holds — and a fault that persists through a squat holds
/// for most of it. The coach was pacing itself with a stopwatch while the user
/// was pacing himself with repetitions.
///
/// The rep is now the unit. A real coach watches the whole movement and then
/// says one thing.

/// Always faults, so the cue path is exercised without depending on any
/// particular rule's thresholds — which is the point: this pins the PACING,
/// and must keep passing when the rules change underneath it.
class _AlwaysFaults implements FormClassifier {
  @override
  String get rule => 'test.always';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftHip,
        LandmarkType.rightHip,
        LandmarkType.leftKnee,
        LandmarkType.rightKnee,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) => const FormFeedback(
        rule: 'test.always',
        severity: 2,
        cueKey: FormCueKey.pushupAlignSagging,
      );
}

Future<(MockVoiceCoach, RepSessionState, int)> runReps(int reps) async {
  final frames = <PoseFrame>[];
  for (var i = 0; i < reps; i++) {
    frames.addAll(oneSquat(i * 10000));
  }
  final svc = MockPoseDetectorService(frames);
  final coach = MockVoiceCoach();
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWithValue(svc),
    voiceCoachProvider.overrideWithValue(coach),
    activeClassifiersProvider.overrideWithValue([_AlwaysFaults()]),
    poseTargetProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);

  container.read(repSessionControllerProvider);
  await svc.start();
  await pumpEventQueue();
  final state = container.read(repSessionControllerProvider);
  await svc.dispose();
  return (coach, state, frames.length);
}

void main() {
  silhouetteTests();
  test('a set of three reps produces at most three utterances', () async {
    final (coach, state, frameCount) = await runReps(3);

    expect(state.repCount, 3, reason: 'the fixture must actually do three reps');
    expect(frameCount, greaterThan(40),
        reason: 'the point of this test is that MANY frames produced FEW cues; '
            'with only a handful of frames it would prove nothing');
    expect(coach.spoken.length, lessThanOrEqualTo(3),
        reason: 'one remark per repetition, not one per frame: '
            'said ${coach.spoken.length} times across $frameCount frames');
  });

  test('it is not silent either — a faulted rep does get said once', () async {
    // The positive control. "At most three" is also satisfied by zero, and a
    // coach that never speaks is a different bug with the same test result.
    final (coach, _, _) = await runReps(1);
    expect(coach.spoken.length, 1);
  });

  test('the cue lands at the END of the rep, not during it', () async {
    // Pacing, stated as a property rather than a count: after a whole set the
    // number of utterances tracks reps, and the last one carries the rep's
    // verdict. If cues were emitted mid-movement the count would climb with
    // frames instead.
    final (coach, state, _) = await runReps(2);
    expect(coach.spoken.length, lessThanOrEqualTo(2));
    expect(state.lastRepCue, isNotNull,
        reason: 'the banner reads this, so it must survive the rep boundary');
    expect(state.lastRepClean, isFalse);
  });

  test('a clean set says nothing and shows green', () async {
    // With no faulting rule the coach has nothing to say, and the card must
    // report a clean rep rather than staying blank.
    final svc = MockPoseDetectorService(oneSquat(0));
    final coach = MockVoiceCoach();
    final container = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWithValue(svc),
      voiceCoachProvider.overrideWithValue(coach),
      activeClassifiersProvider.overrideWithValue([SquatDepthClassifier()]),
      // No target: this test is about the RULES having nothing to say, and a
      // stick-figure fixture would fail a silhouette it was never drawn for.
      poseTargetProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    container.read(repSessionControllerProvider);
    await svc.start();
    await pumpEventQueue();

    final state = container.read(repSessionControllerProvider);
    expect(state.repCount, greaterThan(0));
    expect(coach.spoken, isEmpty,
        reason: 'the squat-depth rule reports and never warns');
    expect(state.lastRepClean, isTrue);
    expect(state.lastRepCue, isNull);
    await svc.dispose();
  });

  group('the rule set follows the chosen exercise', () {
    // The operator's set summary read "Ошибки: Глубина приседа, Линия корпуса"
    // for eight consecutive squats. "Линия корпуса" is the PUSH-UP rule, which
    // measures the shoulder-hip-ankle angle -- a quantity that sweeps through
    // its whole range as someone stands up out of a squat. Every rule used to
    // run on every frame because there was no picker.

    test('a squat is judged only by squat rules', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedExerciseProvider.notifier).state =
          FormExercise.squat;
      final rules = container.read(activeClassifiersProvider);
      expect(rules.map((c) => c.rule), ['squat.depth']);
      expect(rules.map((c) => c.rule), isNot(contains('pushup.alignment')));
    });

    test('switching the exercise switches the rules', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedExerciseProvider.notifier).state =
          FormExercise.pushup;
      expect(container.read(activeClassifiersProvider).map((c) => c.rule),
          ['pushup.alignment']);
    });
  });
}

/// The silhouette gate: a repetition that never reached the target shape is not
/// a correct repetition, whatever the per-frame rules said.
///
/// Operator, on the build where both absolute rules had been withdrawn and
/// nothing had replaced them: *"новый билд вообще больше не говорит ничего и
/// все повторения правильные даже если я неправильно делаю"*. Silence was the
/// honest answer to a coach with no reliable measure — and a useless one. These
/// tests are the difference between the two.
/// The silhouette gate: a repetition that never reached the target shape is not
/// a correct repetition, whatever the per-frame rules said.
///
/// Operator, on the build where both absolute rules had been withdrawn and
/// nothing had replaced them: *"новый билд вообще больше не говорит ничего и
/// все повторения правильные даже если я неправильно делаю"*. Silence was the
/// honest answer for a coach with no reliable measure, and a useless one. This
/// is the difference between the two.
///
/// Both fixtures are built by interpolating the SHIPPED targets rather than by
/// hand. A hand-drawn "good squat" would only ever prove that my drawing
/// matches my own target.
PoseFrame _blend(int ts, double t, {bool upright = false}) {
  PoseLandmark lm(LandmarkType k, (double, double) a, (double, double) b) {
    var x = a.$1 + (b.$1 - a.$1) * t;
    final y = a.$2 + (b.$2 - a.$2) * t;
    // The shallow variant keeps everything stacked vertically: hips drop, but
    // the torso never inclines and the knees never travel forward. It reaches
    // the same DEPTH and is a different SHAPE, which is the distinction the
    // silhouette exists to make and hip-versus-knee height cannot.
    if (upright) x = a.$1;
    return PoseLandmark(type: k, x: x, y: y, likelihood: 0.95);
  }

  final out = <LandmarkType, PoseLandmark>{};
  for (final k in squatTopTarget.joints.keys) {
    out[k] = lm(k, squatTopTarget.joints[k]!, squatBottomTarget.joints[k]!);
  }
  // The counter reads both hips and both knees; the targets carry the left side
  // only, so mirror it.
  out[LandmarkType.rightHip] = PoseLandmark(
      type: LandmarkType.rightHip,
      x: out[LandmarkType.leftHip]!.x + 0.04,
      y: out[LandmarkType.leftHip]!.y,
      likelihood: 0.95);
  out[LandmarkType.rightKnee] = PoseLandmark(
      type: LandmarkType.rightKnee,
      x: out[LandmarkType.leftKnee]!.x + 0.04,
      y: out[LandmarkType.leftKnee]!.y,
      likelihood: 0.95);
  out[LandmarkType.rightShoulder] = PoseLandmark(
      type: LandmarkType.rightShoulder,
      x: out[LandmarkType.leftShoulder]!.x + 0.04,
      y: out[LandmarkType.leftShoulder]!.y,
      likelihood: 0.95);
  return PoseFrame(timestampMs: ts, landmarks: out);
}

List<PoseFrame> _squatRep({required bool upright}) {
  final out = <PoseFrame>[];
  var ts = 0;
  void hold(double t, int n) {
    for (var i = 0; i < n; i++) {
      out.add(_blend(ts += 100, t, upright: upright));
    }
  }

  hold(0, 4);
  for (var t = 0.15; t < 1.0; t += 0.15) {
    out.add(_blend(ts += 100, t, upright: upright));
  }
  hold(1.0, 4);
  for (var t = 0.85; t > 0.0; t -= 0.15) {
    out.add(_blend(ts += 100, t, upright: upright));
  }
  hold(0, 4);
  return out;
}

Future<RepSessionState> _runSquat(List<PoseFrame> frames) async {
  final svc = MockPoseDetectorService(frames);
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWithValue(svc),
    voiceCoachProvider.overrideWithValue(MockVoiceCoach()),
    // Camera mode, stated rather than inherited. These tests grade a rep
    // AGAINST THE TARGET, and Gate A withdrew the target in avatar mode on
    // purpose: an undrawn target must not fail a rep for missing a shape the
    // user was never shown. Avatar mode became the default on 2026-08-15, so
    // without this line these three would be asserting that grading happens in
    // the one mode that deliberately does not grade.
    avatarModeProvider.overrideWith((_) => false),
  ]);
  addTearDown(container.dispose);
  container.read(selectedExerciseProvider.notifier).state = FormExercise.squat;
  container.read(repSessionControllerProvider);
  await svc.start();
  await pumpEventQueue();
  final s = container.read(repSessionControllerProvider);
  await svc.dispose();
  return s;
}

void silhouetteTests() {
  test('a squat done in the target shape passes', () async {
    final s = await _runSquat(_squatRep(upright: false));
    expect(s.repCount, greaterThan(0), reason: 'the rep must be counted');
    expect(s.lastRepPeakMatch, isNotNull,
        reason: 'a full body must be scorable against the target');
    expect(s.lastRepMissedTarget, isFalse,
        reason: 'peak ${s.lastRepPeakMatch}');
    expect(s.lastRepClean, isTrue);
  });

  test('the same DEPTH in the wrong SHAPE fails', () async {
    // This is the case the withdrawn depth rule could never have caught, and
    // the case the operator hit from the other side: both reps reach the same
    // hip height, so hipY-versus-kneeY cannot tell them apart. The silhouette
    // can, because it compares the whole body.
    final s = await _runSquat(_squatRep(upright: true));
    expect(s.repCount, greaterThan(0),
        reason: 'it is still a repetition -- it must be counted and then '
            'judged, not silently ignored');
    expect(s.lastRepMissedTarget, isTrue,
        reason: 'peak ${s.lastRepPeakMatch}');
    expect(s.lastRepClean, isFalse);
    expect(s.lastRepCue?.cueKey, FormCueKey.silhouetteMissed);
  });

  test('the good rep scores strictly higher than the bad one', () async {
    final good = await _runSquat(_squatRep(upright: false));
    final bad = await _runSquat(_squatRep(upright: true));
    expect(good.lastRepPeakMatch!, greaterThan(bad.lastRepPeakMatch!),
        reason: 'good=${good.lastRepPeakMatch} bad=${bad.lastRepPeakMatch}');
  });
}
