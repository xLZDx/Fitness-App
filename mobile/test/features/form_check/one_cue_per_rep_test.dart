import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
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
