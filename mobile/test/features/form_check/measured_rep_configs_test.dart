import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/form_check/data/measured_rep_configs.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

/// A hip-knee-ankle chain whose knee angle is exactly [deg].
///
/// The knee is at the origin, the hip straight above it, the ankle rotated
/// [deg] away. Building the geometry rather than hand-picking coordinates is
/// what makes the test assert on the angle the code reads, not on numbers that
/// happen to work.
PoseFrame _leg(double deg, {int atMs = 0, double likelihood = 1.0}) {
  final r = deg * math.pi / 180;
  return PoseFrame(
    timestampMs: atMs,
    landmarks: {
      LandmarkType.leftHip: PoseLandmark(
          type: LandmarkType.leftHip, x: 0, y: -1, likelihood: likelihood),
      LandmarkType.leftKnee: PoseLandmark(
          type: LandmarkType.leftKnee, x: 0, y: 0, likelihood: likelihood),
      LandmarkType.leftAnkle: PoseLandmark(
        type: LandmarkType.leftAnkle,
        x: math.sin(r),
        y: -math.cos(r),
        likelihood: likelihood,
      ),
    },
  );
}

void main() {
  group('jointAngleDeg', () {
    test('reads the constructed angle back', () {
      for (final deg in [30.0, 90.0, 135.0, 175.0]) {
        final f = _leg(deg);
        final got = jointAngleDeg(
          f.landmarks[LandmarkType.leftHip]!,
          f.landmarks[LandmarkType.leftKnee]!,
          f.landmarks[LandmarkType.leftAnkle]!,
        );
        expect(got, closeTo(deg, 0.01), reason: 'at $deg');
      }
    });
  });

  group('MeasuredRepConfig.signal', () {
    final squat = measuredRepConfigs['squat']!;

    test('is negated, so it rises as the joint closes', () {
      // The sign convention the state machine depends on. If this ever flips,
      // the counter treats the top of each rep as the bottom -- silently.
      final tall = squat.signal(_leg(175), 0.5)!;
      final deep = squat.signal(_leg(95), 0.5)!;
      expect(deep, greaterThan(tall));
      expect(tall, closeTo(-175, 0.01));
    });

    test('drops frames below the likelihood floor', () {
      expect(squat.signal(_leg(120, likelihood: 0.2), 0.5), isNull);
      expect(squat.signal(_leg(120, likelihood: 0.9), 0.5), isNotNull);
    });

    test('drops frames with a missing joint rather than reading it as zero', () {
      // Reading an absent landmark as an angle of 0 would put the signal past
      // every threshold and manufacture a rep each time the user stepped out
      // of frame.
      const frame = PoseFrame(timestampMs: 0, landmarks: {});
      expect(squat.signal(frame, 0.5), isNull);
    });
  });

  group('toConfig', () {
    test('produces an ordered ladder for every measured movement', () {
      for (final m in measuredRepConfigs.values) {
        expect(m.toConfig().isOrdered, isTrue, reason: m.tag);
      }
    });

    test('RepCounter accepts every countable config', () {
      // RepCounter throws ArgumentError on an unordered ladder, so this is the
      // end-to-end version of the assertion above.
      for (final tag in countableTags) {
        expect(counterFor(tag), isNotNull, reason: tag);
      }
    });
  });

  group('counterFor', () {
    test('counts a full descent and return as one rep', () {
      final c = counterFor('squat')!;
      var t = 0;
      RepEvent? last;
      for (final deg in [175.0, 150.0, 110.0, 100.0, 110.0, 150.0, 175.0]) {
        t += 200;
        last = c.update(_leg(deg, atMs: t)) ?? last;
      }
      expect(c.reps.length, 1);
      expect(last, isNotNull);
    });

    test('a shallow rep that never reaches depth is not counted', () {
      final c = counterFor('squat')!;
      var t = 0;
      for (final deg in [175.0, 140.0, 175.0, 140.0, 175.0]) {
        t += 200;
        c.update(_leg(deg, atMs: t));
      }
      expect(c.reps, isEmpty);
    });

    test('returns null for movements that failed the accuracy bar', () {
      // Not a counter with guessed thresholds -- nothing. The caller shows no
      // number, which is the honest outcome at 29% and 41% exact.
      expect(counterFor('pushup'), isNull);
      expect(counterFor('situp'), isNull);
    });

    test('returns null for a movement with no measurement at all', () {
      expect(counterFor('hinge'), isNull);
      expect(counterFor('not_a_tag'), isNull);
    });
  });

  group('measuredRepConfigs', () {
    test('every key is a real pose target tag', () {
      const tags = {
        'squat', 'pushup', 'curl', 'hinge', 'lunge', 'situp', 'overhead_press'
      };
      for (final key in measuredRepConfigs.keys) {
        expect(tags, contains(key), reason: '$key is not a pose target tag');
      }
    });

    test('countsReps follows the measured rate, not the tag', () {
      expect(measuredRepConfigs['squat']!.countsReps, isTrue);
      expect(measuredRepConfigs['curl']!.countsReps, isTrue);
      expect(measuredRepConfigs['overhead_press']!.countsReps, isTrue);
      expect(measuredRepConfigs['lunge']!.countsReps, isTrue);
      // Measured 29% and 41% on held-out sessions.
      expect(measuredRepConfigs['pushup']!.countsReps, isFalse);
      expect(measuredRepConfigs['situp']!.countsReps, isFalse);
    });

    test('countableTags lists exactly the four that passed', () {
      expect(countableTags.toSet(),
          {'squat', 'curl', 'overhead_press', 'lunge'});
    });

    test('every entry is internally consistent and physically plausible', () {
      for (final m in measuredRepConfigs.values) {
        expect(m.bottomDeg, lessThan(m.topDeg), reason: m.tag);
        expect(m.bottomDeg, greaterThan(0), reason: m.tag);
        expect(m.topDeg, lessThanOrEqualTo(180), reason: m.tag);
        expect(m.bottomP25, lessThanOrEqualTo(m.bottomDeg), reason: m.tag);
        expect(m.bottomDeg, lessThanOrEqualTo(m.bottomP75), reason: m.tag);
        expect(m.enterBelowDeg, lessThan(m.exitAboveDeg), reason: m.tag);
        expect(m.holdoutExactRate, inInclusiveRange(0, 1), reason: m.tag);
        expect(m.reps, greaterThan(500), reason: m.tag);
      }
    });
  });
}
