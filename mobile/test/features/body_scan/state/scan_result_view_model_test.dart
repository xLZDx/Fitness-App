import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_source.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_view_model.dart';

import '../support/scan_test_support.dart';

const _measurementOnly = ScanPlanContext.measurementOnly;

void main() {
  group('full mode, photo estimator (not provisional)', () {
    final data = scanData(values: [22, 21, 20], slope: -0.4);
    final vm = buildScanResultViewModel(data, kFullPlan);

    test('shows goal figures, change, plan decision, no see-plan action', () {
      expect(vm.provisional, isFalse);
      expect(vm.weightFirst, isFalse);
      expect(vm.showGoalFigures, isTrue);
      expect(vm.showChange, isTrue);
      expect(vm.showPlanDecision, isTrue);
      expect(vm.showSeePlanAction, isFalse);
    });

    test('points to goal is the smoothed value minus the target', () {
      final s = vm.smoothedNow!;
      expect(s, inInclusiveRange(20.0, 22.0));
      expect(vm.pointsToGoal, closeTo(s - 15, 1e-9));
    });

    test('trend split uses the smoothed value and the estimate half width',
        () {
      final s = vm.smoothedNow!;
      final t = vm.trendSplit!;
      expect(t.fatKg, closeTo(80 * s / 100, 1e-9));
      expect(t.fatLowKg, closeTo(80 * (s - 2) / 100, 1e-9));
      expect(t.fatHighKg, closeTo(80 * (s + 2) / 100, 1e-9));
      expect(t.leanKg, closeTo(80 - 80 * s / 100, 1e-9));
    });

    test('reading split uses the raw single reading', () {
      final r = vm.readingSplit!;
      expect(r.fatKg, closeTo(16.0, 1e-9)); // 80 kg * 20 %
      expect(r.fatLowKg, closeTo(14.4, 1e-9));
      expect(r.fatHighKg, closeTo(17.6, 1e-9));
      expect(r.leanKg, closeTo(64.0, 1e-9));
      expect(r.leanLowKg, closeTo(62.4, 1e-9));
      expect(r.leanHighKg, closeTo(65.6, 1e-9));
    });

    test('noise threshold is sqrt(hw^2 + hw^2) of the two readings', () {
      expect(vm.noisePts, closeTo(math.sqrt(8), 1e-9));
    });
  });

  group('full mode gating of single pieces', () {
    test('no decision hides the plan decision card only', () {
      final vm = buildScanResultViewModel(
          scanData(values: [22, 21, 20]), kFullPlanNoDecision);
      expect(vm.showPlanDecision, isFalse);
      expect(vm.showGoalFigures, isTrue);
    });

    test('no target body fat hides goal figures and points to goal', () {
      const plan = ScanPlanContext(
          surfaceMode: ScanSurfaceMode.full, decision: kDecision);
      final vm = buildScanResultViewModel(scanData(values: [22, 21, 20]), plan);
      expect(vm.showGoalFigures, isFalse);
      expect(vm.pointsToGoal, isNull);
      expect(vm.showPlanDecision, isTrue);
    });

    test('a single reading has no change label, no noise and no change line',
        () {
      final vm = buildScanResultViewModel(scanData(values: [20]), kFullPlan);
      expect(vm.changeLabel, isNull);
      expect(vm.noisePts, isNull);
      expect(vm.showChange, isFalse);
      expect(vm.showGoalFigures, isTrue);
    });

    test('a move inside the noise reads as no meaningful change', () {
      final vm =
          buildScanResultViewModel(scanData(values: [20, 22]), kFullPlan);
      expect(vm.changeLabel, ChangeLabel.noMeaningfulChange);
    });

    test('a move beyond the noise reads down or up', () {
      final down =
          buildScanResultViewModel(scanData(values: [26, 20]), kFullPlan);
      expect(down.changeLabel, ChangeLabel.down);
      final up =
          buildScanResultViewModel(scanData(values: [20, 26]), kFullPlan);
      expect(up.changeLabel, ChangeLabel.up);
    });

    test('missing recorded weight gives no mass split at all', () {
      final vm = buildScanResultViewModel(
          scanData(values: [22, 21, 20], weightKg: null), kFullPlan);
      expect(vm.readingSplit, isNull);
      expect(vm.trendSplit, isNull);
    });
  });

  group('provisional estimator (D-73)', () {
    final data = scanData(
        values: [22, 21, 20], provisional: true, halfWidth: 5, slope: -0.3);
    final vm = buildScanResultViewModel(data, kFullPlan);

    test('is weight first and hides ring, points, change, ETA source, plan',
        () {
      expect(vm.provisional, isTrue);
      expect(vm.weightFirst, isTrue);
      expect(vm.showGoalFigures, isFalse);
      expect(vm.pointsToGoal, isNull);
      expect(vm.showChange, isFalse);
      expect(vm.showPlanDecision, isFalse);
    });

    test('offers the See your plan action instead of the decision', () {
      expect(vm.showSeePlanAction, isTrue);
    });

    test('trend split is hidden but the single reading split stays', () {
      expect(vm.trendSplit, isNull);
      expect(vm.readingSplit, isNotNull);
    });

    test('provisional check code is prepended when missing', () {
      expect(vm.checks, [CheckCode.provisionalEstimator]);
    });

    test('provisional check code is not duplicated and the order is kept', () {
      final d = scanData(
        values: [20],
        provisional: true,
        halfWidth: 5,
        checks: [CheckCode.provisionalEstimator, CheckCode.wideRange],
      );
      final v = buildScanResultViewModel(d, kFullPlan);
      expect(v.checks, [CheckCode.provisionalEstimator, CheckCode.wideRange]);
    });

    test('provisional code goes first before other estimate codes', () {
      final d = scanData(
          values: [20],
          provisional: true,
          halfWidth: 5,
          checks: [CheckCode.weightStale]);
      final v = buildScanResultViewModel(d, kFullPlan);
      expect(v.checks, [CheckCode.provisionalEstimator, CheckCode.weightStale]);
    });

    test('a non-provisional estimate never gets the provisional code', () {
      final v = buildScanResultViewModel(
          scanData(values: [20], checks: [CheckCode.poorLighting]), kFullPlan);
      expect(v.checks, [CheckCode.poorLighting]);
    });

    test('provisional in measurement only shows no see-plan action', () {
      final v = buildScanResultViewModel(
          scanData(values: [20], provisional: true, halfWidth: 5),
          _measurementOnly);
      expect(v.showSeePlanAction, isFalse);
    });
  });

  group('measurement only (D-74)', () {
    final vm = buildScanResultViewModel(
        scanData(values: [22, 21, 20], slope: -0.4), _measurementOnly);

    test('no goal figure, no change, no decision, no see-plan action', () {
      expect(vm.measurementOnly, isTrue);
      expect(vm.showGoalFigures, isFalse);
      expect(vm.pointsToGoal, isNull);
      expect(vm.showChange, isFalse);
      expect(vm.showPlanDecision, isFalse);
      expect(vm.showSeePlanAction, isFalse);
    });

    test('no fat or lean split of either kind', () {
      expect(vm.trendSplit, isNull);
      expect(vm.readingSplit, isNull);
    });

    test('the estimate and the series are still available to the view', () {
      expect(vm.estimate.value, 20);
      expect(vm.series, isNotNull);
    });

    test('even with a target and a decision supplied, nothing leaks', () {
      const plan = ScanPlanContext(
        surfaceMode: ScanSurfaceMode.measurementOnly,
        decision: kDecision,
        targetBodyFatPct: 12,
      );
      final v = buildScanResultViewModel(scanData(values: [22, 21, 20]), plan);
      expect(v.showGoalFigures, isFalse);
      expect(v.showPlanDecision, isFalse);
      expect(v.pointsToGoal, isNull);
    });
  });

  group('weight trend direction', () {
    WeightTrendDirection dir(double? slope) => buildScanResultViewModel(
            scanData(values: [20], slope: slope), kFullPlan)
        .weightTrend;

    test('null slope is unknown', () => expect(dir(null), WeightTrendDirection.unknown));
    test('-0.4 is down', () => expect(dir(-0.4), WeightTrendDirection.down));
    test('+0.4 is up', () => expect(dir(0.4), WeightTrendDirection.up));
    test('0.09 magnitude is steady', () {
      expect(dir(0.09), WeightTrendDirection.flat);
      expect(dir(-0.09), WeightTrendDirection.flat);
    });
    test('exactly 0.1 magnitude is no longer steady', () {
      expect(dir(0.1), WeightTrendDirection.up);
      expect(dir(-0.1), WeightTrendDirection.down);
    });
    test('zero is steady', () => expect(dir(0), WeightTrendDirection.flat));
  });

  group('estimator segmentation (D-54)', () {
    test('only the latest estimator forms the active series', () {
      final readings = [
        reading(kScanDay, 30, halfWidth: 5, provisional: true),
        reading(kScanDay.add(const Duration(days: 7)), 29,
            halfWidth: 5, provisional: true),
        reading(kScanDay.add(const Duration(days: 14)), 20),
        reading(kScanDay.add(const Duration(days: 21)), 19),
      ];
      final data = ScanResultData(
        scanId: 's',
        takenAt: readings.last.at,
        estimate: estimate(value: 19),
        readings: readings,
        weightKg: 80,
      );
      final vm = buildScanResultViewModel(data, kFullPlan);
      expect(vm.series!.points, hasLength(2));
      expect(vm.series!.points.first.reading.value, 20);
      expect(vm.modelChangeAt, [readings[2].at]);
      // The change compares only same-estimator readings (20 -> 19).
      expect(vm.changeLabel, ChangeLabel.noMeaningfulChange);
    });

    test('no readings: no series, no trend label, no change', () {
      final data = ScanResultData(
        scanId: 's',
        takenAt: kScanDay,
        estimate: estimate(),
        readings: const [],
        weightKg: 80,
      );
      final vm = buildScanResultViewModel(data, kFullPlan);
      expect(vm.series, isNull);
      expect(vm.trendLabel, isNull);
      expect(vm.showGoalFigures, isFalse);
      expect(vm.smoothedNow, isNull);
      expect(vm.trendSplit, isNull);
    });
  });
}
