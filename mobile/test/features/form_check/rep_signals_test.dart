import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/rep_signals.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// A frame standing in the given target's shape.
///
/// Targets carry left-side joints only, because from the side the far limb is
/// behind the body. The signals average left and right, so a side-on body puts
/// both at the same place — which is what is built here, and is exactly the
/// framing the outline instructs the user to adopt.
PoseFrame frameOf(PoseTarget t,
    {double scale = 1.0, double dx = 0, double dy = 0, double lk = 0.95}) {
  const mirror = {
    LandmarkType.leftShoulder: LandmarkType.rightShoulder,
    LandmarkType.leftElbow: LandmarkType.rightElbow,
    LandmarkType.leftWrist: LandmarkType.rightWrist,
    LandmarkType.leftHip: LandmarkType.rightHip,
    LandmarkType.leftKnee: LandmarkType.rightKnee,
    LandmarkType.leftAnkle: LandmarkType.rightAnkle,
  };
  final marks = <LandmarkType, PoseLandmark>{};
  for (final e in t.joints.entries) {
    final x = e.value.$1 * scale + dx;
    final y = e.value.$2 * scale + dy;
    marks[e.key] = PoseLandmark(type: e.key, x: x, y: y, likelihood: lk);
    final r = mirror[e.key];
    if (r != null) {
      marks[r] = PoseLandmark(type: r, x: x, y: y, likelihood: lk);
    }
  }
  return PoseFrame(timestampMs: 0, landmarks: marks);
}

/// A body facing the camera: shoulders and hips separated across the frame.
///
/// [torsoLength] is the SHOULDER-TO-HIP distance as it appears on the image.
/// A hinge performed front-on rotates the torso away from the lens, so that
/// number shrinks while the real torso does not — which is the whole problem.
PoseFrame frontOnFrame({
  required double torsoLength,
  double shoulderWidth = 0.20,
}) {
  PoseLandmark lm(LandmarkType t, double x, double y) =>
      PoseLandmark(type: t, x: x, y: y, likelihood: 0.95);
  const shY = 0.30;
  final hipY = shY + torsoLength;
  return PoseFrame(timestampMs: 0, landmarks: {
    LandmarkType.leftShoulder:
        lm(LandmarkType.leftShoulder, 0.5 - shoulderWidth / 2, shY),
    LandmarkType.rightShoulder:
        lm(LandmarkType.rightShoulder, 0.5 + shoulderWidth / 2, shY),
    LandmarkType.leftHip:
        lm(LandmarkType.leftHip, 0.5 - shoulderWidth / 3, hipY),
    LandmarkType.rightHip:
        lm(LandmarkType.rightHip, 0.5 + shoulderWidth / 3, hipY),
  });
}

void main() {
  group('the hinge refuses a camera that cannot see it', () {
    test('standing front-on still reads, because nothing is foreshortened',
        () {
      final s = hingeSignal(frontOnFrame(torsoLength: 0.30), 0.5);
      expect(s, isNotNull);
      expect(s, closeTo(1.0, 0.05), reason: 'upright');
    });

    test('folded front-on returns null instead of reporting upright', () {
      // The defect. Filmed from the front, a hinge shortens the numerator and
      // the denominator together: the ratio stays near 1.0 and the signal
      // claims a lifter folded to horizontal is standing bolt upright. Not
      // noise — a confident wrong answer.
      final folded = frontOnFrame(torsoLength: 0.06);
      expect(hingeSignal(folded, 0.5), isNull);

      // And the proof that the old definition would have lied rather than
      // simply been noisy: the ratio it computed is still ~1.0.
      final sh = folded.landmarks[LandmarkType.leftShoulder]!;
      final hip = folded.landmarks[LandmarkType.leftHip]!;
      expect((hip.y - sh.y) / 0.06, closeTo(1.0, 0.01));
    });

    test('and the sit-up inherits the same refusal', () {
      expect(situpSignal(frontOnFrame(torsoLength: 0.06), 0.5), isNull);
    });

    test('a side-on frame is unaffected at any depth of hinge', () {
      // Shoulders at one x, which is what a side-on body looks like and what
      // every authored target here is. The guard must never fire on it.
      for (final t in [hingeTopTarget, hingeBottomTarget]) {
        expect(hingeSignal(frameOf(t), 0.5), isNotNull, reason: '$t');
      }
    });
  });


  // The property that makes these different from `squatDepthSignal`, whose
  // thresholds are fractions of the FRAME and therefore change when the user
  // steps back. Every signal below divides by a length measured on the same
  // body in the same frame.
  group('signals do not care where the body is or how big it looks', () {
    final cases = <String, (PoseTarget, double? Function(PoseFrame, double))>{
      'curl': (curlTopTarget, curlSignal),
      'hinge': (hingeBottomTarget, hingeSignal),
      'lunge': (lungeBottomTarget, lungeSignal),
      'situp': (situpTopTarget, situpSignal),
      'overhead_press': (overheadPressTopTarget, overheadPressSignal),
    };

    for (final e in cases.entries) {
      test('${e.key} scores the same at any distance and position', () {
        final (target, signal) = e.value;
        final base = signal(frameOf(target), 0.5);
        expect(base, isNotNull, reason: '${e.key}: no signal from its own '
            'target — the joints it needs are missing from the shape');
        for (final s in [0.45, 0.8, 1.7, 2.4]) {
          for (final d in [-0.15, 0.0, 0.22]) {
            final moved =
                signal(frameOf(target, scale: s, dx: d, dy: -d), 0.5);
            expect(moved, closeTo(base!, 1e-9),
                reason: '${e.key}: scale $s offset $d changed the signal');
          }
        }
      });
    }
  });

  // The decisive one. Thresholds were chosen by reasoning about each movement;
  // this checks they actually bracket the shapes that were authored for it. A
  // config that does not reach its own targets produces a counter stuck in one
  // phase — on screen, indistinguishable from a camera that cannot see anyone.
  group('every movement can complete a rep against its own targets', () {
    for (final tag in repSignalsByTag.keys) {
      test('$tag travels from top past bottom and back', () {
        final pair = poseTargetsByTag[tag]!;
        final (signal, config) = repSignalsByTag[tag]!;
        final top = signal(frameOf(pair.$1), config.minLikelihood);
        final bottom = signal(frameOf(pair.$2), config.minLikelihood);
        expect(top, isNotNull, reason: '$tag: top shape yields no signal');
        expect(bottom, isNotNull, reason: '$tag: bottom shape yields no signal');

        expect(top!, lessThanOrEqualTo(config.topEnter),
            reason: '$tag: the authored top pose scores '
                '${top.toStringAsFixed(3)}, which never enters the top phase '
                '(needs <= ${config.topEnter})');
        expect(bottom!, greaterThanOrEqualTo(config.bottomEnter),
            reason: '$tag: the authored bottom pose scores '
                '${bottom.toStringAsFixed(3)}, which never reaches the bottom '
                'phase (needs >= ${config.bottomEnter})');
        expect(config.topExit, lessThan(config.bottomExit),
            reason: '$tag: hysteresis bands overlap');
      });
    }
  });

  group('a rep is actually counted end to end', () {
    for (final tag in repSignalsByTag.keys) {
      test('$tag counts one rep for one full lap', () {
        final pair = poseTargetsByTag[tag]!;
        final (signal, config) = repSignalsByTag[tag]!;
        final counter = RepCounter(signal: signal, config: config);

        // Slow enough to clear minRepDurationMs: a lap faster than a body can
        // move is discarded by design, and a test that ignored that would be
        // testing a path users never take.
        //
        // 200 ms a frame, not 100. At 100 the lap took 700 ms and the three
        // movements configured at 800 ms were rejected as `tooFast` — the
        // counter behaving exactly as specified while this test read it as a
        // broken signal. The first version of this test was the thing that was
        // wrong, which is worth leaving written down: a green suite would have
        // been reached just as easily by lowering the production threshold.
        var t = 0;
        RepEvent? last;
        for (final target in [pair.$1, pair.$2, pair.$1]) {
          for (var i = 0; i < 6; i++) {
            t += 200;
            final f = frameOf(target);
            last = counter.update(
                PoseFrame(timestampMs: t, landmarks: f.landmarks));
          }
        }
        expect(counter.repCount, 1,
            reason: '$tag: a full lap produced ${counter.repCount} reps '
                '(last event: ${last?.kind})');
      });
    }
  });

  group('the coach only offers what it can both draw and count', () {
    test('the five movements added 2026-08-08 are offered', () {
      for (final tag in ['curl', 'hinge', 'lunge', 'situp', 'overhead_press']) {
        expect(formCoachSupports(tag), isTrue, reason: tag);
      }
    });

    test('pushup is still refused — shapes authored, reps uncountable', () {
      // Not a gap to close later. `RepCounter`'s squat signal barely moves
      // during a push-up, and offering a silhouette that counts nothing is the
      // lesson `formCoachSupports` exists to avoid teaching.
      expect(formCoachSupports('pushup'), isFalse);
    });

    test('calf_raise is refused because it has no shape at all', () {
      expect(formCoachSupports('calf_raise'), isFalse);
      expect(poseTargetsByTag.containsKey('calf_raise'), isFalse);
    });

    test('an unknown tag is refused rather than guessed at', () {
      expect(formCoachSupports('bench_press'), isFalse);
      expect(formCoachSupports(null), isFalse);
    });
  });
}
