// T78 provisional_estimator_test (SCAN-30, SCAN-31 client half, SCAN-44).
// Deurenberg et al. 1991: BF% = 1.20 BMI + 0.23 age - 10.8 s - 5.4 with
// s = 1 male, 0 female, 0.5 unspecified. Vectors are scratch arithmetic.
//
// MAP NOTE (deviation 6): the output RANGE is clamped to 3..60 so that a valid
// reading is never rejected by the plausibility window; the VALUE is clamped
// to 5..55. The half-width is exactly 5.0 whenever no clamp touches an edge.
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/plausibility.dart';
import 'package:fitness_app/features/body_scan/data/provisional_estimator.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:flutter_test/flutter_test.dart';

EstimatorSubject _s(double h, double w, int a, SexBasis sex) =>
    EstimatorSubject(heightCm: h, weightKg: w, ageYears: a, sex: sex);

const _est = ProvisionalEstimator();

void main() {
  group('formula vectors (V-DEU)', () {
    test('V-DEU-M: male 80/180/30 = 20.33 percent, range 15.33-25.33', () {
      final e = _est.estimateNow(_s(180, 80, 30, SexBasis.male));
      expect(e.value, closeTo(20.33, 0.01));
      expect(e.low, closeTo(15.33, 0.01));
      expect(e.high, closeTo(25.33, 0.01));
    });
    test('V-DEU-F: female 60/165/30 = 27.95', () {
      expect(_est.estimateNow(_s(165, 60, 30, SexBasis.female)).value,
          closeTo(27.95, 0.01));
    });
    test('V-DEU-U: unspecified 80/180/30 = 25.73 (s = 0.5)', () {
      expect(_est.estimateNow(_s(180, 80, 30, SexBasis.unspecified)).value,
          closeTo(25.73, 0.01));
    });
    test('the raw formula function matches the same values', () {
      expect(
          deurenbergBodyFatPct(
              bmi: 80 / 3.24, ageYears: 30, sex: SexBasis.male),
          closeTo(20.3296, 1e-3));
      expect(
          deurenbergBodyFatPct(
              bmi: 22.0, ageYears: 40, sex: SexBasis.female),
          closeTo(1.2 * 22 + 0.23 * 40 - 5.4, 1e-12));
    });
    test('the sex term: male is 10.8 lower than female, unspecified 5.4 lower', () {
      final f = deurenbergBodyFatPct(bmi: 25, ageYears: 40, sex: SexBasis.female);
      final m = deurenbergBodyFatPct(bmi: 25, ageYears: 40, sex: SexBasis.male);
      final u = deurenbergBodyFatPct(
          bmi: 25, ageYears: 40, sex: SexBasis.unspecified);
      expect(f - m, closeTo(10.8, 1e-12));
      expect(f - u, closeTo(5.4, 1e-12));
    });
    test('age term 0.23 per year and BMI term 1.2 per unit', () {
      final a = deurenbergBodyFatPct(bmi: 25, ageYears: 30, sex: SexBasis.male);
      expect(deurenbergBodyFatPct(bmi: 25, ageYears: 31, sex: SexBasis.male) - a,
          closeTo(0.23, 1e-12));
      expect(deurenbergBodyFatPct(bmi: 26, ageYears: 30, sex: SexBasis.male) - a,
          closeTo(1.2, 1e-12));
    });
  });

  group('SCAN-44 weight edit re-derives the estimate', () {
    test('editing 80 -> 82 kg changes BMI and so the formula output', () {
      final a = _est.estimateNow(_s(180, 80, 30, SexBasis.male));
      final b = _est.estimateNow(_s(180, 82, 30, SexBasis.male));
      expect(b.value, closeTo(21.07, 0.01));
      expect(b.value, isNot(a.value));
    });
    test('subject weight 30 and 300 are both accepted (no 30-250 split)', () {
      for (final w in [30.0, 250.0, 251.0, 300.0]) {
        final e = _est.estimateNow(_s(175, w, 40, SexBasis.male));
        expect(e.value.isFinite, isTrue, reason: '$w');
        expect(e.value, inInclusiveRange(5, 55));
      }
    });
  });

  group('clamps (deviation 6)', () {
    test('a negative raw value is clamped to 5.0 and the low edge to 3.0', () {
      // male 200 cm 30 kg age 18: BMI 7.5 -> raw -3.06
      final e = _est.estimateNow(_s(200, 30, 18, SexBasis.male));
      expect(e.value, 5.0);
      expect(e.low, 3.0); // 5 - 5 = 0 raised to the range floor
      expect(e.high, 10.0);
    });
    test('a very high raw value is clamped to 55 and the high edge to 60', () {
      // female 140 cm 300 kg age 40: BMI 153 -> raw 187.5
      final e = _est.estimateNow(_s(140, 300, 40, SexBasis.female));
      expect(e.value, 55.0);
      expect(e.low, 50.0);
      expect(e.high, 60.0);
    });
    test('the value clamp boundary 5.0 / 55.0 is inclusive', () {
      expect(ProvisionalEstimator.minValue, 5);
      expect(ProvisionalEstimator.maxValue, 55);
      expect(ProvisionalEstimator.rangeFloor, 3);
      expect(ProvisionalEstimator.rangeCeiling, 60);
    });
    test('a low-but-valid raw 7.74 (female 200 cm 30 kg age 18) keeps its value; low edge clamps to 3', () {
      final e = _est.estimateNow(_s(200, 30, 18, SexBasis.female));
      expect(e.value, closeTo(7.74, 1e-9));
      expect(e.low, 3.0); // 2.74 -> 3.0
      expect(e.high, closeTo(12.74, 1e-9));
    });
    test('the range edges always stay inside the plausibility window 3..60', () {
      for (final h in [120.0, 150.0, 180.0, 230.0]) {
        for (final w in [30.0, 60.0, 100.0, 300.0]) {
          for (final a in [18, 50, 100]) {
            for (final sx in SexBasis.values) {
              final e = _est.estimateNow(_s(h, w, a, sx));
              expect(e.low, greaterThanOrEqualTo(3));
              expect(e.high, lessThanOrEqualTo(60));
              expect(e.low, lessThan(e.value));
              expect(e.high, greaterThan(e.value));
              final p = evaluatePlausibility(PlausibilityInput(estimate: e));
              expect(p.rejected, isFalse, reason: '$h $w $a $sx');
            }
          }
        }
      }
    });
  });

  group('shape of every provisional result', () {
    final e = _est.estimateNow(_s(180, 80, 30, SexBasis.male));
    test('half-width exactly 5.0 when no clamp touches an edge', () {
      expect(e.halfWidth, 5.0);
      expect(ProvisionalEstimator.halfWidthPts, 5.0);
    });
    test('confidence low, provisional true', () {
      expect(e.confidence, EstimateConfidence.low);
      expect(e.provisional, isTrue);
    });
    test('model id and version', () {
      expect(e.modelId, 'provisional-anthropometric');
      expect(e.modelVersion, 'deurenberg-1991-v0');
      expect(e.modelKey, 'provisional-anthropometric|deurenberg-1991-v0');
    });
    test('check codes: provisionalEstimator only', () {
      expect(e.checkCodes, [CheckCode.provisionalEstimator]);
    });
    test('manualOverride adds manualCapture', () {
      final m = _est.estimateNow(_s(180, 80, 30, SexBasis.male),
          manualOverride: true);
      expect(m.checkCodes,
          [CheckCode.provisionalEstimator, CheckCode.manualCapture]);
    });
    test('interface flags: requiresPhotos false, provisional true', () {
      expect(_est.requiresPhotos, isFalse);
      expect(_est.provisional, isTrue);
      expect(_est.id, 'provisional-anthropometric');
      expect(_est.version, 'deurenberg-1991-v0');
    });
  });

  group('async interface ignores photos entirely', () {
    test('same output regardless of scan id or manual flag', () async {
      final s = _s(180, 80, 30, SexBasis.male);
      final a = await _est.estimate(EstimatorInput(scanId: 'aaaaaaaa', subject: s));
      final b = await _est.estimate(EstimatorInput(scanId: 'bbbbbbbb', subject: s));
      expect(a.value, b.value);
      expect(a.low, b.low);
      expect(a.high, b.high);
      expect(a.toJson(), b.toJson());
    });
    test('manualOverride flows through the async path', () async {
      final r = await _est.estimate(EstimatorInput(
          scanId: 'aaaaaaaa',
          subject: _s(180, 80, 30, SexBasis.male),
          manualOverride: true));
      expect(r.checkCodes, contains(CheckCode.manualCapture));
    });
  });

  group('subject helpers', () {
    test('bmi', () {
      expect(_s(180, 80, 30, SexBasis.male).bmi!, closeTo(24.6914, 1e-4));
      expect(_s(0, 80, 30, SexBasis.male).bmi, isNull);
    });
    test('an unusable height (0) does not crash the estimator', () {
      final e = _est.estimateNow(_s(0, 80, 30, SexBasis.male));
      expect(e.value.isFinite, isTrue);
    });
  });

  group('BodyFatEstimate model', () {
    final e = _est.estimateNow(_s(180, 80, 30, SexBasis.male));
    test('toJson / tryFromJson round trip', () {
      final back = BodyFatEstimate.tryFromJson(e.toJson())!;
      expect(back.value, e.value);
      expect(back.low, e.low);
      expect(back.high, e.high);
      expect(back.confidence, e.confidence);
      expect(back.modelId, e.modelId);
      expect(back.provisional, isTrue);
      expect(back.checkCodes, e.checkCodes);
    });
    test('unreadable documents are null', () {
      expect(BodyFatEstimate.tryFromJson(null), isNull);
      expect(BodyFatEstimate.tryFromJson({'bodyFatPct': 'x'}), isNull);
      final j = e.toJson();
      expect(BodyFatEstimate.tryFromJson({...j, 'modelId': ''}), isNull);
      expect(BodyFatEstimate.tryFromJson({...j, 'modelVersion': 3}), isNull);
      expect(BodyFatEstimate.tryFromJson({...j, 'bodyFatPct': double.nan}),
          isNull);
      expect(BodyFatEstimate.tryFromJson({...j, 'rangeHighPct': double.infinity}),
          isNull);
    });
    test('unknown confidence degrades to low; unknown check codes are dropped', () {
      final back = BodyFatEstimate.tryFromJson({
        ...e.toJson(),
        'confidence': 'certain',
        'checkCodes': ['manualCapture', 'free text from a provider', 'manualCapture'],
      })!;
      expect(back.confidence, EstimateConfidence.low);
      expect(back.checkCodes, [CheckCode.manualCapture]);
    });
    test('confidence lowered: high -> medium -> low -> low', () {
      expect(EstimateConfidence.high.lowered, EstimateConfidence.medium);
      expect(EstimateConfidence.medium.lowered, EstimateConfidence.low);
      expect(EstimateConfidence.low.lowered, EstimateConfidence.low);
    });
    test('copyWith keeps the identity of the estimator', () {
      final c = e.copyWith(value: 30);
      expect(c.value, 30);
      expect(c.modelId, e.modelId);
      expect(c.provisional, isTrue);
    });
  });
}
