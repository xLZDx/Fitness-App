import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/reference/joint_rom_reference.dart';
import 'package:fitness_app/features/form_check/data/measured_rep_configs.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

/// A hip-knee-ankle chain whose knee angle is exactly [deg]. Same construction
/// as `measured_rep_configs_test.dart`, and for the same reason: building the
/// geometry makes the assertion about the angle the code reads rather than
/// about coordinates somebody chose to make a test pass.
PoseFrame _leg(double deg, {int atMs = 0}) {
  final r = deg * math.pi / 180;
  return PoseFrame(
    timestampMs: atMs,
    landmarks: {
      LandmarkType.leftHip:
          const PoseLandmark(type: LandmarkType.leftHip, x: 0, y: -1, likelihood: 1),
      LandmarkType.leftKnee:
          const PoseLandmark(type: LandmarkType.leftKnee, x: 0, y: 0, likelihood: 1),
      LandmarkType.leftAnkle: PoseLandmark(
        type: LandmarkType.leftAnkle,
        x: math.sin(r),
        y: -math.cos(r),
        likelihood: 1,
      ),
    },
  );
}

/// One descent and return. Counts as a single rep under the shipped squat
/// config, whose `enterBelowDeg` is 115 and which this descent passes at 100.
const _oneSquat = [175.0, 150.0, 110.0, 100.0, 110.0, 150.0, 175.0];

int _repsUnder(MeasuredRepConfig config, List<double> degrees) {
  final counter = RepCounter(config: config.toConfig(), signal: config.signal);
  var t = 0;
  for (final deg in degrees) {
    t += 200;
    counter.update(_leg(deg, atMs: t));
  }
  return counter.reps.length;
}

/// The shipped squat config, and the same thing with ONE number moved.
MeasuredRepConfig _squat({double enterBelowDeg = 115}) => MeasuredRepConfig(
      tag: 'squat',
      driver:
          (LandmarkType.leftHip, LandmarkType.leftKnee, LandmarkType.leftAnkle),
      bottomDeg: 94.8,
      bottomP25: 70.5,
      bottomP75: 97.9,
      topDeg: 172.0,
      enterBelowDeg: enterBelowDeg,
      exitAboveDeg: 130,
      holdoutExactRate: 1.00,
      sets: 62,
      reps: 619,
    );

String _shippedJson() =>
    File('assets/data/joint_rom_reference.json').readAsStringSync();

void main() {
  group('the shipped artifact', () {
    test('makes no clinical claim', () {
      expect(JointRomReference.parse(_shippedJson()).clinicalUse, isFalse);
    });

    test('every row is typed: joint, motion, plane, method, population, provenance', () {
      for (final r in JointRomReference.parse(_shippedJson()).rows) {
        expect(r.joint, isNotEmpty, reason: r.id);
        expect(r.motion, isNotEmpty, reason: r.id);
        expect(r.plane, isNotEmpty, reason: r.id);
        expect(r.unit, 'degree', reason: r.id);
        expect(r.measurementMethod, isNotEmpty, reason: r.id);
        expect(r.population, isNotEmpty, reason: r.id);
        expect(r.provenance, isNotEmpty, reason: r.id);
        expect(r.typicalMinDeg, lessThan(r.typicalMaxDeg), reason: r.id);
      }
    });

    test('a row missing a required field is rejected, not defaulted', () {
      expect(
        () => JointRomReference.parse(
            '{"rows":[{"id":"x","joint":"hip","motion":"internal_rotation"}]}'),
        throwsFormatException,
      );
    });
  });

  group('the metric guard', () {
    // The whole reason this reference is independent. Every row is a
    // transverse-plane rotation; the rep counter measures sagittal flexion.
    // Asking about a metric no row describes must return nothing, never a
    // nearest-neighbour answer.
    test('refuses to answer about a metric no row describes', () {
      final ref = JointRomReference.parse(_shippedJson());
      expect(ref.advise(joint: 'knee', motion: 'flexion', degrees: 100), isNull);
      expect(ref.advise(joint: 'hip', motion: 'flexion', degrees: 100), isNull);
      expect(ref.row(joint: 'elbow', motion: 'flexion'), isNull);
    });

    test('answers about a metric it does describe', () {
      final ref = JointRomReference.parse(_shippedJson());
      expect(ref.advise(joint: 'hip', motion: 'internal_rotation', degrees: 35),
          RomAdvisory.withinTypical);
      expect(ref.advise(joint: 'hip', motion: 'internal_rotation', degrees: 12),
          RomAdvisory.belowTypical);
    });
  });

  // ==========================================================================
  // G2.4: consumption proven in THREE directions, because the obvious two are
  // both satisfied by a JSON file nothing reads.
  // ==========================================================================
  group('the three-way proof', () {
    // A bound that is never consulted satisfies "changing it changes no rep
    // count" perfectly. Direction (i) is the only one that can tell an
    // advisory feature apart from dead weight, so it is asserted first.
    test('(i) moving a ROM bound MOVES the advisory result for that metric', () {
      const measurement = 35.0;

      final shipped = JointRomReference.parse(_shippedJson());
      expect(
        shipped.advise(
            joint: 'hip', motion: 'internal_rotation', degrees: measurement),
        RomAdvisory.withinTypical,
        reason: 'precondition: 35 deg sits inside the shipped 30-40 range',
      );

      // One number moved: the lower bound now sits above the measurement.
      final perturbed = JointRomReference.parse(_shippedJson()
          .replaceFirst('"typicalMinDeg": 30', '"typicalMinDeg": 36'));
      expect(
        perturbed.advise(
            joint: 'hip', motion: 'internal_rotation', degrees: measurement),
        RomAdvisory.belowTypical,
        reason: 'the advisory result must follow the bound, or nothing reads it',
      );
    });

    test('(ii) the SAME perturbation leaves every rep count identical', () {
      final before = _repsUnder(_squat(), _oneSquat);

      // The perturbed reference is loaded and consulted, and the rep counter
      // runs alongside it. Independence is the claim; this is the measurement.
      final perturbed = JointRomReference.parse(_shippedJson()
          .replaceFirst('"typicalMinDeg": 30', '"typicalMinDeg": 36'));
      expect(perturbed.advise(joint: 'hip', motion: 'internal_rotation', degrees: 35),
          RomAdvisory.belowTypical);

      final after = _repsUnder(_squat(), _oneSquat);
      expect(after, before);
      expect(after, 1, reason: 'and the fixture really does produce a rep');
    });

    test('(iii) moving a MEASURED rep config DOES change a known rep count', () {
      // Without this the pair above proves only that two unrelated things are
      // unrelated. The descent reaches 100 deg; drop the entry threshold below
      // that and the same fixture stops being a repetition.
      expect(_repsUnder(_squat(), _oneSquat), 1);
      expect(_repsUnder(_squat(enterBelowDeg: 90), _oneSquat), 0);
    });
  });
}
