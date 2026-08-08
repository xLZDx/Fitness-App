import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/posture/data/measured_posture_config.dart';
import 'package:fitness_app/features/posture/data/posture_metrics.dart';

PoseLandmark _lm(LandmarkType type, double x, double y, {double lk = 0.95}) =>
    PoseLandmark(type: type, x: x, y: y, likelihood: lk);

PoseFrame _frame({
  required (double, double) leftShoulder,
  required (double, double) rightShoulder,
  required (double, double) leftHip,
  required (double, double) rightHip,
  (double, double)? leftEar,
  (double, double)? rightEar,
}) {
  final marks = <LandmarkType, PoseLandmark>{
    LandmarkType.leftShoulder:
        _lm(LandmarkType.leftShoulder, leftShoulder.$1, leftShoulder.$2),
    LandmarkType.rightShoulder:
        _lm(LandmarkType.rightShoulder, rightShoulder.$1, rightShoulder.$2),
    LandmarkType.leftHip: _lm(LandmarkType.leftHip, leftHip.$1, leftHip.$2),
    LandmarkType.rightHip:
        _lm(LandmarkType.rightHip, rightHip.$1, rightHip.$2),
  };
  if (leftEar != null) {
    marks[LandmarkType.leftEar] =
        _lm(LandmarkType.leftEar, leftEar.$1, leftEar.$2);
  }
  if (rightEar != null) {
    marks[LandmarkType.rightEar] =
        _lm(LandmarkType.rightEar, rightEar.$1, rightEar.$2);
  }
  return PoseFrame(timestampMs: 0, landmarks: marks);
}

void main() {
  group('shoulderAsymmetrySignal', () {
    test('level shoulders read close to zero', () {
      final f = _frame(
        leftShoulder: (0.4, 0.3),
        rightShoulder: (0.6, 0.3),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
      );
      expect(shoulderAsymmetrySignal(f, 0.5), closeTo(0.0, 0.001));
    });

    test('right shoulder physically higher (smaller y) reads positive', () {
      // Image y grows downward, so "higher" is a SMALLER y. The right
      // shoulder here is drawn 0.05 above the left -- positive is the
      // convention `measured_posture_config.dart` documents as "right
      // higher", so this is the regression test for not flipping that sign.
      final f = _frame(
        leftShoulder: (0.4, 0.32),
        rightShoulder: (0.6, 0.27),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
      );
      expect(shoulderAsymmetrySignal(f, 0.5), greaterThan(0));
    });

    test('right shoulder physically lower reads negative', () {
      final f = _frame(
        leftShoulder: (0.4, 0.27),
        rightShoulder: (0.6, 0.32),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
      );
      expect(shoulderAsymmetrySignal(f, 0.5), lessThan(0));
    });

    test('null when a shoulder is missing or below the likelihood floor',
        () {
      final missing = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.4, 0.3),
      });
      expect(shoulderAsymmetrySignal(missing, 0.5), isNull);

      final unsure = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder:
            _lm(LandmarkType.leftShoulder, 0.4, 0.3, lk: 0.2),
        LandmarkType.rightShoulder:
            _lm(LandmarkType.rightShoulder, 0.6, 0.3),
      });
      expect(shoulderAsymmetrySignal(unsure, 0.5), isNull);
    });
  });

  group('pelvisTiltSignal', () {
    test('right hip higher reads positive, same convention as shoulders',
        () {
      final f = _frame(
        leftShoulder: (0.4, 0.3),
        rightShoulder: (0.6, 0.3),
        leftHip: (0.42, 0.52),
        rightHip: (0.58, 0.47),
      );
      expect(pelvisTiltSignal(f, 0.5), greaterThan(0));
    });
  });

  group('forwardHeadSignal', () {
    test('ears directly above the shoulder midpoint read close to zero', () {
      final f = _frame(
        leftShoulder: (0.4, 0.3),
        rightShoulder: (0.6, 0.3),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
        leftEar: (0.48, 0.15),
        rightEar: (0.52, 0.15),
      );
      expect(forwardHeadSignal(f, 0.5), closeTo(0.0, 0.01));
    });

    test('ears displaced from the shoulder midpoint read nonzero', () {
      final f = _frame(
        leftShoulder: (0.4, 0.3),
        rightShoulder: (0.6, 0.3),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
        leftEar: (0.68, 0.15),
        rightEar: (0.72, 0.15),
      );
      expect(forwardHeadSignal(f, 0.5), isNot(closeTo(0.0, 0.01)));
    });

    test('null without both ears', () {
      final f = _frame(
        leftShoulder: (0.4, 0.3),
        rightShoulder: (0.6, 0.3),
        leftHip: (0.42, 0.5),
        rightHip: (0.58, 0.5),
      );
      expect(forwardHeadSignal(f, 0.5), isNull);
    });
  });

  group('MeasuredPostureRange.verdictFor', () {
    test('inside the interquartile band is typical', () {
      expect(shoulderAsymmetryRange.verdictFor(shoulderAsymmetryRange.median),
          PostureVerdict.typical);
    });

    test('between the IQR and the 5th/95th percentile is mild', () {
      final justBelowP25 = shoulderAsymmetryRange.p25 - 0.001;
      expect(justBelowP25, greaterThan(shoulderAsymmetryRange.p05));
      expect(
          shoulderAsymmetryRange.verdictFor(justBelowP25),
          PostureVerdict.mild);
    });

    test('beyond the 5th/95th percentile is notable', () {
      expect(
          shoulderAsymmetryRange.verdictFor(shoulderAsymmetryRange.p95 + 1),
          PostureVerdict.notable);
      expect(
          shoulderAsymmetryRange.verdictFor(shoulderAsymmetryRange.p05 - 1),
          PostureVerdict.notable);
    });

    test('the three measured ranges are ordered p05<p25<median<p75<p95', () {
      for (final r in [
        shoulderAsymmetryRange,
        pelvisTiltRange,
        forwardHeadRange,
      ]) {
        expect(r.p05, lessThan(r.p25));
        expect(r.p25, lessThan(r.median));
        expect(r.median, lessThan(r.p75));
        expect(r.p75, lessThan(r.p95));
      }
    });
  });
}
