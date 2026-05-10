import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_comp/data/body_comp_estimate.dart';

void main() {
  group('navyBodyFatPercent', () {
    test('returns 0 on out-of-range inputs', () {
      expect(
        navyBodyFatPercent(
          heightCm: 0,
          waistCm: 80,
          neckCm: 38,
          isMale: true,
        ),
        0,
      );
      expect(
        navyBodyFatPercent(
          heightCm: 170,
          waistCm: 80,
          neckCm: 38,
          isMale: false, // hipCm missing
        ),
        0,
      );
    });

    test('male: 178cm height / 84cm waist / 38cm neck → ~14–18%', () {
      final bf = navyBodyFatPercent(
        heightCm: 178,
        waistCm: 84,
        neckCm: 38,
        isMale: true,
      );
      expect(bf, greaterThan(13));
      expect(bf, lessThan(20));
    });

    test('female: 165cm / 70cm waist / 33cm neck / 95cm hip → ~22–28%', () {
      final bf = navyBodyFatPercent(
        heightCm: 165,
        waistCm: 70,
        neckCm: 33,
        hipCm: 95,
        isMale: false,
      );
      expect(bf, greaterThan(20));
      expect(bf, lessThan(32));
    });

    test('clamps absurd inputs into the realistic envelope', () {
      // Tiny waist - much smaller than neck would otherwise produce a
      // negative log; the clamp ensures the floor.
      final bf = navyBodyFatPercent(
        heightCm: 178,
        waistCm: 39,
        neckCm: 38,
        isMale: true,
      );
      expect(bf, greaterThanOrEqualTo(2));
      expect(bf, lessThanOrEqualTo(60));
    });
  });
}
