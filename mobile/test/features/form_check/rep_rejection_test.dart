import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat, squatFrame;

/// What the screen does when a repetition does NOT happen.
///
/// [RepCounter] has always distinguished three outcomes — a phase change, a
/// counted rep, and a discarded attempt — and the controller collapsed the
/// last two categories into "not finished, republish the numbers". So a lap
/// that came back up short produced no count, no colour, and no words. From
/// where the user stands that is indistinguishable from the tracker losing
/// their body, and the reasonable conclusion is that the number is junk.
///
/// The same silence covered a second state: before the counter has seen the
/// lifter standing at the top it refuses to start a lap at all, and refuses in
/// perfect silence. Both are correct behaviour that has to be visible to be
/// tolerable.

/// Down, but not to depth, and back up. The counter's `bottomEnter` is -0.04
/// (hips level with the knees); this bottoms out at -0.08, so the lap starts
/// and is then thrown away as incomplete.
List<PoseFrame> halfSquat(int startTs) {
  final out = <PoseFrame>[];
  var ts = startTs;
  void hold(double hipY, int frames) {
    for (var i = 0; i < frames; i++) {
      out.add(squatFrame(ts, hipY));
      ts += 100;
    }
  }

  hold(0.42, 4); // standing, well above the knee: this is what arms the counter
  for (var hipY = 0.46; hipY <= 0.64; hipY += 0.04) {
    out.add(squatFrame(ts, hipY));
    ts += 100;
  }
  hold(0.64, 3); // as low as it goes, still short of depth
  for (var hipY = 0.60; hipY > 0.42; hipY -= 0.04) {
    out.add(squatFrame(ts, hipY));
    ts += 100;
  }
  hold(0.42, 4);
  return out;
}

/// Someone who opens the camera already sitting in the bottom and stays there.
/// The counter never sees the top, so it never arms.
List<PoseFrame> neverStands(int startTs) =>
    [for (var i = 0; i < 25; i++) squatFrame(startTs + i * 100, 0.68)];

/// Faults for a fixed number of frames and then goes quiet. Used to prove that
/// a fault seen during a discarded attempt is not charged to the next rep.
class _FaultsFirst implements FormClassifier {
  _FaultsFirst(this.frames);
  int frames;

  @override
  bool get canFault => true;

  @override
  String get rule => 'test.first';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftHip,
        LandmarkType.rightHip,
        LandmarkType.leftKnee,
        LandmarkType.rightKnee,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) {
    if (frames <= 0) return null;
    frames--;
    return const FormFeedback(
      rule: 'test.first',
      severity: 2,
      cueKey: FormCueKey.pushupAlignSagging,
    );
  }
}

Future<(RepSessionState, MockVoiceCoach)> run(
  List<PoseFrame> frames, {
  List<FormClassifier> rules = const [],
  bool withTarget = false,
}) async {
  final svc = MockPoseDetectorService(frames);
  final coach = MockVoiceCoach();
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWithValue(svc),
    voiceCoachProvider.overrideWithValue(coach),
    activeClassifiersProvider.overrideWithValue(rules),
    // Off by default: these tests are about the counter's own outcomes, and a
    // stick-figure fixture would fail a silhouette it was never drawn for.
    if (!withTarget) poseTargetProvider.overrideWithValue(null),
    // Camera mode, stated rather than inherited from a default that flipped on
    // 2026-08-15. `withTarget: true` exists to exercise the silhouette verdict,
    // and Gate A withdrew the target in avatar mode — so the one case in this
    // file that asks for a target would otherwise be handed nothing to grade
    // against and would quietly stop testing what it names.
    avatarModeProvider.overrideWith((_) => false),
  ]);
  addTearDown(container.dispose);

  container.read(repSessionControllerProvider);
  await svc.start();
  await pumpEventQueue();
  final state = container.read(repSessionControllerProvider);
  await svc.dispose();
  return (state, coach);
}

void main() {
  group('an attempt that was thrown away', () {
    test('is not counted, and the screen is told why', () async {
      final (state, _) = await run(halfSquat(0));

      expect(state.repCount, 0, reason: 'a half rep is not a rep');
      expect(state.lastReject, RepRejectReason.incomplete,
          reason: 'the counter knew this all along and nothing read it');
    });

    test('the same fixture, taken to depth, IS counted', () async {
      // The positive control. "0 reps and a reject reason" is also what a
      // completely broken pipeline produces.
      final (state, _) = await run(oneSquat(0));
      expect(state.repCount, 1);
      expect(state.lastReject, isNull,
          reason: 'a counted rep clears the rejection banner');
    });

    test('is not narrated when nothing trustworthy measured it', () async {
      // The counter rejects on hip-height-minus-knee-height, which depends on
      // where the phone is standing. Blaming the user with that number is the
      // mistake that produced "прогнись ниже" at the bottom of a full squat.
      final (_, coach) = await run(halfSquat(0));
      expect(coach.spoken, isEmpty);
    });

    test('IS narrated when the silhouette says the shape was missed', () async {
      // With a target on screen there is a measurement that does not depend on
      // the camera's position, so there is something true to say.
      final (_, coach) = await run(halfSquat(0), withTarget: true);
      expect(coach.spoken.length, 1,
          reason: 'once for the attempt, not once per frame');
    });

    test('does not charge its faults to the next repetition', () async {
      // The counter clears its own severity log when it discards a lap. The
      // controller's `_worstThisRep` lives outside the counter and did not, so
      // a fault seen during a half rep was spoken at the end of the NEXT one
      // and shown as that rep's verdict.
      final half = halfSquat(0);
      final frames = [...half, ...oneSquat(half.last.timestampMs + 1000)];
      final (state, coach) =
          await run(frames, rules: [_FaultsFirst(half.length)]);

      expect(state.repCount, 1, reason: 'the second lap did reach depth');
      expect(state.lastRepCue, isNull,
          reason: 'the clean rep must not inherit the discarded one\'s fault');
      expect(state.lastRepClean, isTrue);
      expect(coach.spoken, isEmpty);
    });
  });

  group('before the counter has armed', () {
    test('it says what it is waiting for', () async {
      final (state, _) = await run(neverStands(0));

      expect(state.repCount, 0);
      expect(state.isArmed, isFalse,
          reason: 'the count physically cannot move until this is true, and a '
              'frozen zero with no explanation reads as a broken app');
    });

    test('and stops saying it once the lifter stands up', () async {
      final (state, _) = await run(oneSquat(0));
      expect(state.isArmed, isTrue);
    });

    test('arming alone republishes, even though it raises no event', () async {
      // Arming happens on a frame the counter reports nothing for. If the
      // controller only republished on events, the badge would keep showing
      // the waiting hint through an entire descent.
      final standing = [for (var i = 0; i < 6; i++) squatFrame(i * 100, 0.42)];
      final (state, _) = await run(standing);

      expect(state.isArmed, isTrue);
      expect(state.repCount, 0, reason: 'standing still is not a repetition');
    });
  });
}
