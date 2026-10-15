// C18 plan_review_record_test. The stored review is immutable history: the
// classification must survive inside `inputs` (the Firestore rules close the
// top-level key set), `referProfessional` must read as null and never be
// written (D-55), and unknown reason codes are dropped instead of failing.
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';

PlanReviewRecord _record({
  ReviewClass? cls = ReviewClass.behind,
  double? slope = -0.12,
  double? bf,
}) =>
    PlanReviewRecord(
      week: kWeek,
      decidedAt: kNow,
      basePlanVersion: 3,
      decision: ReviewDecisionKind.adjustKcal,
      deltaKcal: -150,
      deltaSteps: 0,
      reasonCodes: const [ReviewReason.kcalLowered, ReviewReason.tooFast],
      inputs: ReviewInputsRecord(
        weightSlopeKgPerWeek: slope,
        intendedKgPerWeek: -0.4,
        dataPoints: 6,
        bfTrendPts: bf,
      ),
      classification: cls,
    );

void main() {
  group('fromDecision', () {
    test('copies every field of the decision and stamps week and time', () {
      final d = decisionOf(
        deltaKcal: -150,
        base: 7,
        cls: ReviewClass.driftUp,
        reasons: const [ReviewReason.kcalLowered],
      );
      final r = PlanReviewRecord.fromDecision(kWeek, d, kNow);
      expect(r.week, kWeek);
      expect(r.decidedAt, kNow);
      expect(r.basePlanVersion, 7);
      expect(r.decision, ReviewDecisionKind.adjustKcal);
      expect(r.deltaKcal, -150);
      expect(r.deltaSteps, 0);
      expect(r.reasonCodes, [ReviewReason.kcalLowered]);
      expect(r.classification, ReviewClass.driftUp);
      expect(r.inputs.dataPoints, 5);
      expect(r.inputs.intendedKgPerWeek, -0.4);
    });
  });

  group('toMap', () {
    test('the classification is stored INSIDE inputs, not at the top level', () {
      final m = _record().toMap();
      expect((m['inputs'] as Map)['classification'], 'behind');
      expect(m.containsKey('classification'), isFalse);
    });

    test('the top-level key set is closed (matches the rules)', () {
      expect(_record().toMap().keys.toSet(), {
        'schema',
        'decidedAt',
        'basePlanVersion',
        'decision',
        'deltaKcal',
        'deltaSteps',
        'reasonCodes',
        'inputs',
      });
    });

    test('reason codes are written by name; optional inputs only when present', () {
      final m = _record(slope: null, cls: null).toMap();
      expect(m['reasonCodes'], ['kcalLowered', 'tooFast']);
      final inputs = m['inputs'] as Map;
      expect(inputs.containsKey('weightSlopeKgPerWeek'), isFalse);
      expect(inputs.containsKey('classification'), isFalse);
      expect(inputs.containsKey('bfTrendPts'), isFalse);
      expect(inputs['dataPoints'], 6);
      expect(inputs['intendedKgPerWeek'], -0.4);
    });

    test('a body-fat trend is stored when present', () {
      expect((_record(bf: -0.8).toMap()['inputs'] as Map)['bfTrendPts'], -0.8);
    });

    test('the time encoder is applied to decidedAt', () {
      expect(_record().toMap(time: (t) => 'T')['decidedAt'], 'T');
    });

    test('no referProfessional appears anywhere in the written document', () {
      expect(_record().toMap().toString().toLowerCase(),
          isNot(contains('referprofessional')));
    });
  });

  group('round trip', () {
    for (final cls in ReviewClass.values) {
      test('classification ${cls.name} survives via inputs', () {
        final back = PlanReviewRecord.tryFromMap(kWeek, _record(cls: cls).toMap())!;
        expect(back.classification, cls);
      });
    }

    test('a record without classification reads back with null', () {
      final back =
          PlanReviewRecord.tryFromMap(kWeek, _record(cls: null).toMap())!;
      expect(back.classification, isNull);
    });

    test('all other fields survive', () {
      final back =
          PlanReviewRecord.tryFromMap(kWeek, _record(bf: -0.8).toMap())!;
      expect(back.week, kWeek);
      expect(back.decidedAt, kNow);
      expect(back.basePlanVersion, 3);
      expect(back.decision, ReviewDecisionKind.adjustKcal);
      expect(back.deltaKcal, -150);
      expect(back.deltaSteps, 0);
      expect(back.reasonCodes,
          [ReviewReason.kcalLowered, ReviewReason.tooFast]);
      expect(back.inputs.weightSlopeKgPerWeek, -0.12);
      expect(back.inputs.intendedKgPerWeek, -0.4);
      expect(back.inputs.dataPoints, 6);
      expect(back.inputs.bfTrendPts, -0.8);
    });

    test('the week id is taken from the document id argument', () {
      expect(PlanReviewRecord.tryFromMap('2026-W01', _record().toMap())!.week,
          '2026-W01');
    });
  });

  group('tryFromMap: referProfessional never reads as a review (D-55)', () {
    test('decision referProfessional -> null', () {
      final m = _record().toMap()..['decision'] = 'referProfessional';
      expect(PlanReviewRecord.tryFromMap(kWeek, m), isNull);
    });

    test('unknown decision, missing decision, non-map -> null', () {
      expect(
          PlanReviewRecord.tryFromMap(kWeek, _record().toMap()..['decision'] = 'x'),
          isNull);
      expect(
          PlanReviewRecord.tryFromMap(kWeek, _record().toMap()..remove('decision')),
          isNull);
      expect(PlanReviewRecord.tryFromMap(kWeek, null), isNull);
      expect(PlanReviewRecord.tryFromMap(kWeek, 'keep'), isNull);
    });

    test('the decision enum itself has no referProfessional value', () {
      expect(
        ReviewDecisionKind.values.where(
            (v) => v.name.toLowerCase().contains('refer')),
        isEmpty,
      );
    });
  });

  group('tryFromMap: tolerance', () {
    test('unknown reason codes are dropped, known ones kept in order', () {
      final m = _record().toMap()
        ..['reasonCodes'] = ['kcalLowered', 'madeUp', 5, 'tooFast'];
      final back = PlanReviewRecord.tryFromMap(kWeek, m)!;
      expect(back.reasonCodes, [ReviewReason.kcalLowered, ReviewReason.tooFast]);
    });

    test('missing reasonCodes, inputs and numbers fall back to zero values', () {
      final back = PlanReviewRecord.tryFromMap(
          kWeek, {'decision': 'keep'})!;
      expect(back.reasonCodes, isEmpty);
      expect(back.basePlanVersion, 0);
      expect(back.deltaKcal, 0);
      expect(back.deltaSteps, 0);
      expect(back.inputs.dataPoints, 0);
      expect(back.inputs.weightSlopeKgPerWeek, isNull);
      expect(back.classification, isNull);
      expect(back.decidedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('an unknown classification string reads as null, not an error', () {
      final m = _record().toMap();
      (m['inputs'] as Map)['classification'] = 'sideways';
      expect(PlanReviewRecord.tryFromMap(kWeek, m)!.classification, isNull);
    });

    test('decidedAt accepts an ISO string', () {
      final m = _record().toMap()..['decidedAt'] = '2026-10-15T09:00:00.000';
      expect(PlanReviewRecord.tryFromMap(kWeek, m)!.decidedAt, kNow);
    });
  });
}
