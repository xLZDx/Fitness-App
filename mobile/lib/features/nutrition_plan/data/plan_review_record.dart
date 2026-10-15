/// The stored weekly review `users/{uid}/nutrition_plan_reviews/{isoWeek}`
/// (design s5.5). Immutable once written; the "always explain why" history.
/// No Flutter imports.
///
/// `referProfessional` is not a valid decision anywhere here (D-55): an
/// ineligible or unanswered user gets no review document at all.
library;

import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';

class PlanReviewRecord {
  const PlanReviewRecord({
    required this.week,
    required this.decidedAt,
    required this.basePlanVersion,
    required this.decision,
    required this.deltaKcal,
    required this.deltaSteps,
    required this.reasonCodes,
    required this.inputs,
    this.classification,
  });

  /// `yyyy-Www`, the document id.
  final String week;
  final DateTime decidedAt;
  final int basePlanVersion;
  final ReviewDecisionKind decision;
  final int deltaKcal;
  final int deltaSteps;
  final List<ReviewReason> reasonCodes;
  final ReviewInputsRecord inputs;

  /// The classification the decision was based on. Stored INSIDE `inputs`
  /// (the rules allow any map there and the top-level key set is closed), and
  /// read back as `previousClass` by the next review.
  final ReviewClass? classification;

  /// Builds the record of [decision] decided at [at] for [week].
  factory PlanReviewRecord.fromDecision(
    String week,
    WeeklyReviewDecision decision,
    DateTime at,
  ) =>
      PlanReviewRecord(
        week: week,
        decidedAt: at,
        basePlanVersion: decision.basePlanVersion,
        decision: decision.kind,
        deltaKcal: decision.deltaKcal,
        deltaSteps: decision.deltaSteps,
        reasonCodes: decision.reasonCodes,
        inputs: decision.inputs,
        classification: decision.classification,
      );

  Map<String, dynamic> toMap({TimeEncoder time = _keepTime}) => {
        'schema': 1,
        'decidedAt': time(decidedAt),
        'basePlanVersion': basePlanVersion,
        'decision': decision.name,
        'deltaKcal': deltaKcal,
        'deltaSteps': deltaSteps,
        'reasonCodes': [for (final r in reasonCodes) r.name],
        'inputs': {
          if (inputs.weightSlopeKgPerWeek != null)
            'weightSlopeKgPerWeek': inputs.weightSlopeKgPerWeek,
          'intendedKgPerWeek': inputs.intendedKgPerWeek,
          if (inputs.bfTrendPts != null) 'bfTrendPts': inputs.bfTrendPts,
          'dataPoints': inputs.dataPoints,
          if (classification != null) 'classification': classification!.name,
        },
      };

  /// Tolerant read: null when the document cannot be a review (unknown
  /// decision, which includes any `referProfessional`). Unknown reason codes
  /// are dropped.
  static PlanReviewRecord? tryFromMap(String week, Object? raw) {
    if (raw is! Map) return null;
    final decision =
        readEnumTolerant(ReviewDecisionKind.values, raw['decision']);
    if (decision == null) return null;
    final inputsRaw = raw['inputs'];
    final inputs = inputsRaw is Map ? inputsRaw : const {};
    return PlanReviewRecord(
      week: week,
      decidedAt: readTimeTolerant(raw['decidedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      basePlanVersion: readIntTolerant(raw['basePlanVersion']) ?? 0,
      decision: decision,
      deltaKcal: readIntTolerant(raw['deltaKcal']) ?? 0,
      deltaSteps: readIntTolerant(raw['deltaSteps']) ?? 0,
      reasonCodes: [
        for (final r in (raw['reasonCodes'] as List?) ?? const [])
          if (readEnumTolerant(ReviewReason.values, r) case final v?) v,
      ],
      inputs: ReviewInputsRecord(
        weightSlopeKgPerWeek: readNumTolerant(inputs['weightSlopeKgPerWeek']),
        intendedKgPerWeek: readNumTolerant(inputs['intendedKgPerWeek']) ?? 0,
        dataPoints: readIntTolerant(inputs['dataPoints']) ?? 0,
        bfTrendPts: readNumTolerant(inputs['bfTrendPts']),
      ),
      classification:
          readEnumTolerant(ReviewClass.values, inputs['classification']),
    );
  }
}

Object _keepTime(DateTime time) => time;
