// T23 plausibility_test (SCAN-20, design 12.4). Every threshold is tested on
// both sides of its boundary, with the confidence consequences.
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/plausibility.dart';
import 'package:flutter_test/flutter_test.dart';

BodyFatEstimate _est({
  double v = 25,
  double hw = 1,
  EstimateConfidence conf = EstimateConfidence.high,
  bool provisional = false,
  List<CheckCode> codes = const [],
}) =>
    BodyFatEstimate(
      value: v,
      low: v - hw,
      high: v + hw,
      confidence: conf,
      modelId: provisional ? 'provisional-anthropometric' : 'licensed-x',
      modelVersion: '1',
      provisional: provisional,
      checkCodes: codes,
    );

PlausibilityResult _eval(
  BodyFatEstimate e, {
  double? expected,
  double? weight = 80,
  double? weightAge = 0,
  double? prevWeight,
  double? gapDays,
  double? prevSmoothed,
  bool manual = false,
}) =>
    evaluatePlausibility(PlausibilityInput(
      estimate: e,
      profileExpectedPct: expected,
      recordedWeightKg: weight,
      weightAgeDays: weightAge,
      previousScanWeightKg: prevWeight,
      daysSincePreviousScan: gapDays,
      previousSmoothedPct: prevSmoothed,
      manualOverride: manual,
    ));

void main() {
  group('limits (design 29)', () {
    test('constants', () {
      expect(PlausibilityLimits.valueMin, 3);
      expect(PlausibilityLimits.valueMax, 60);
      expect(PlausibilityLimits.farFromProfilePts, 12);
      expect(PlausibilityLimits.weightJumpKg, 3);
      expect(PlausibilityLimits.weightJumpDays, 7);
      expect(PlausibilityLimits.wideHalfWidthPts, 4);
      expect(PlausibilityLimits.largeJumpFloorPts, 4);
      expect(PlausibilityLimits.largeJumpHwFactor, 2.5);
    });
  });

  group('estimateOutOfRange rejects (value outside [3, 60])', () {
    test('2.9 and 60.1 are rejected, 3.0 and 60.0 are accepted', () {
      expect(_eval(_est(v: 2.9)).rejected, isTrue);
      expect(_eval(_est(v: 60.1)).rejected, isTrue);
      expect(_eval(_est(v: 3.0)).rejected, isFalse);
      expect(_eval(_est(v: 60.0)).rejected, isFalse);
    });
    test('NaN and infinity are rejected', () {
      expect(_eval(_est(v: double.nan)).rejected, isTrue);
      expect(_eval(_est(v: double.infinity)).rejected, isTrue);
      expect(_eval(_est(v: -1)).rejected, isTrue);
    });
    test('a rejected result carries only the estimate\'s own codes and confidence', () {
      final r = _eval(_est(v: 2.0, codes: [CheckCode.poorLighting]),
          weight: null);
      expect(r.rejected, isTrue);
      expect(r.codes, [CheckCode.poorLighting]); // no weightMissing etc.
      expect(r.confidence, EstimateConfidence.high);
    });
  });

  group('estimateFarFromProfile', () {
    test('|v - expected| = 12.0 -> no chip; 12.1 -> chip and confidence one lower', () {
      final at = _eval(_est(v: 37), expected: 25);
      expect(at.codes, isNot(contains(CheckCode.estimateFarFromProfile)));
      expect(at.confidence, EstimateConfidence.high);
      final over = _eval(_est(v: 37.1), expected: 25);
      expect(over.codes, contains(CheckCode.estimateFarFromProfile));
      expect(over.confidence, EstimateConfidence.medium);
    });
    test('works downward too (13 below)', () {
      final r = _eval(_est(v: 12), expected: 25);
      expect(r.codes, contains(CheckCode.estimateFarFromProfile));
    });
    test('without a profile expectation the check is skipped', () {
      expect(_eval(_est(v: 55)).codes,
          isNot(contains(CheckCode.estimateFarFromProfile)));
    });
    test('skipped for the provisional estimator (it IS the formula)', () {
      final r = _eval(_est(v: 55, provisional: true), expected: 20);
      expect(r.codes, isNot(contains(CheckCode.estimateFarFromProfile)));
    });
    test('confidence never drops below low', () {
      final r = _eval(_est(v: 40, conf: EstimateConfidence.low), expected: 20);
      expect(r.confidence, EstimateConfidence.low);
    });
  });

  group('wideRange', () {
    test('half-width 4.0 -> no chip; 4.1 -> chip and confidence low', () {
      expect(_eval(_est(hw: 4.0)).codes, isNot(contains(CheckCode.wideRange)));
      expect(_eval(_est(hw: 4.0)).confidence, EstimateConfidence.high);
      final w = _eval(_est(hw: 4.1));
      expect(w.codes, contains(CheckCode.wideRange));
      expect(w.confidence, EstimateConfidence.low);
    });
    test('the provisional half-width 5 always raises it', () {
      final r = _eval(_est(hw: 5, provisional: true));
      expect(r.codes, contains(CheckCode.wideRange));
      expect(r.codes, contains(CheckCode.provisionalEstimator));
      expect(r.confidence, EstimateConfidence.low);
    });
  });

  group('weight checks', () {
    test('weightJump: 3.0 kg in 7 d -> none; 3.1 kg -> chip', () {
      final none = _eval(_est(), weight: 83.0, prevWeight: 80.0, gapDays: 7);
      expect(none.codes, isNot(contains(CheckCode.weightJump)));
      final jump = _eval(_est(), weight: 83.1, prevWeight: 80.0, gapDays: 7);
      expect(jump.codes, contains(CheckCode.weightJump));
    });
    test('weightJump works downward and only inside 7 days', () {
      expect(_eval(_est(), weight: 76.5, prevWeight: 80.0, gapDays: 3).codes,
          contains(CheckCode.weightJump));
      expect(_eval(_est(), weight: 90.0, prevWeight: 80.0, gapDays: 7.5).codes,
          isNot(contains(CheckCode.weightJump)));
    });
    test('weightJump needs both previous weight and gap', () {
      expect(_eval(_est(), weight: 90, prevWeight: 80).codes,
          isNot(contains(CheckCode.weightJump)));
      expect(_eval(_est(), weight: 90, gapDays: 2).codes,
          isNot(contains(CheckCode.weightJump)));
    });
    test('weightMissing when no weight was recorded; no stale/jump then', () {
      final r = _eval(_est(), weight: null, prevWeight: 80, gapDays: 1);
      expect(r.codes, contains(CheckCode.weightMissing));
      expect(r.codes, isNot(contains(CheckCode.weightStale)));
      expect(r.codes, isNot(contains(CheckCode.weightJump)));
    });
    test('weightStale only above 7 days', () {
      expect(_eval(_est(), weightAge: 7).codes,
          isNot(contains(CheckCode.weightStale)));
      expect(_eval(_est(), weightAge: 7.01).codes,
          contains(CheckCode.weightStale));
      expect(CheckCode.weightStaleAfterDays, 7);
    });
    test('a fresh recorded weight raises neither', () {
      final r = _eval(_est());
      expect(r.codes, isEmpty);
    });
  });

  group('largeJumpVsTrend: |v - S| > max(4, 2.5 * hw)', () {
    test('hw 1 (2.5 < 4): threshold 4.0 -> 4.0 none, 4.01 chip', () {
      expect(_eval(_est(v: 29, hw: 1), prevSmoothed: 25).codes,
          isNot(contains(CheckCode.largeJumpVsTrend)));
      expect(_eval(_est(v: 29.01, hw: 1), prevSmoothed: 25).codes,
          contains(CheckCode.largeJumpVsTrend));
    });
    test('hw 3 (2.5 * 3 = 7.5): 7.5 none, 7.6 chip', () {
      expect(_eval(_est(v: 32.5, hw: 3), prevSmoothed: 25).codes,
          isNot(contains(CheckCode.largeJumpVsTrend)));
      expect(_eval(_est(v: 32.6, hw: 3), prevSmoothed: 25).codes,
          contains(CheckCode.largeJumpVsTrend));
    });
    test('downward jumps count; no previous smoothed value skips it', () {
      expect(_eval(_est(v: 20, hw: 1), prevSmoothed: 25).codes,
          contains(CheckCode.largeJumpVsTrend));
      expect(_eval(_est(v: 50, hw: 1)).codes,
          isNot(contains(CheckCode.largeJumpVsTrend)));
    });
  });

  group('manual capture', () {
    test('adds manualCapture and lowers confidence one level', () {
      final r = _eval(_est(), manual: true);
      expect(r.codes, contains(CheckCode.manualCapture));
      expect(r.confidence, EstimateConfidence.medium);
    });
    test('not manual: no chip, no change', () {
      final r = _eval(_est());
      expect(r.codes, isNot(contains(CheckCode.manualCapture)));
      expect(r.confidence, EstimateConfidence.high);
    });
  });

  group('combination and ordering', () {
    test('far + wide + manual: high -> medium -> low -> low', () {
      final r = _eval(_est(v: 40, hw: 4.5), expected: 20, manual: true);
      expect(r.confidence, EstimateConfidence.low);
      expect(r.codes, containsAll([
        CheckCode.estimateFarFromProfile,
        CheckCode.wideRange,
        CheckCode.manualCapture,
      ]));
    });
    test('codes come out in the stable CheckCode declaration order, without duplicates', () {
      final r = _eval(
        _est(v: 40, hw: 4.5, codes: [CheckCode.wideRange, CheckCode.poorLighting]),
        expected: 20,
        weight: null,
        prevSmoothed: 25,
        manual: true,
      );
      final order = CheckCode.values;
      final idx = [for (final c in r.codes) order.indexOf(c)];
      expect([...idx]..sort(), idx);
      expect(r.codes.toSet().length, r.codes.length);
      expect(r.codes, containsAll([
        CheckCode.poorLighting,
        CheckCode.wideRange,
        CheckCode.weightMissing,
        CheckCode.estimateFarFromProfile,
        CheckCode.largeJumpVsTrend,
        CheckCode.manualCapture,
      ]));
    });
    test('codes the estimate already carries are preserved', () {
      final r = _eval(_est(codes: [CheckCode.partialBody]));
      expect(r.codes, [CheckCode.partialBody]);
    });
    test('the result list is a stable, accepted estimate when nothing is wrong', () {
      final r = _eval(_est(v: 22, hw: 2), expected: 25, prevSmoothed: 23);
      expect(r.rejected, isFalse);
      expect(r.codes, isEmpty);
      expect(r.confidence, EstimateConfidence.high);
    });
  });
}
