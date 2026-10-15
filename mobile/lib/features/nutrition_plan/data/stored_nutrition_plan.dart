/// The persisted nutrition plan `users/{uid}/nutrition_plan/main` (design s5.4)
/// and its pure helpers. No Flutter imports; the Firestore mapping lives in
/// `firestore_plan_repository.dart`.
///
/// The document is the user's CURRENT CHOICE, never the source of safety: the
/// kcal bounds are recomputed from [PlanInputsDigest] on every read and every
/// write ([StoredNutritionPlan.validated]), so a hand-edited or stale document
/// can never put a range outside the clamps (design s13).
///
/// Only an `active` plan is ever written. A plan is NEVER written for a user
/// who is not eligible, and no `referProfessional` value exists here (D-55).
library;

import 'dart:math' as math;

import '../../profile/data/profile_models.dart';
import 'energy_math.dart';
import 'plan_calculator.dart';
import 'safety_clamps.dart';
import 'weekly_review.dart';

/// Turns a [DateTime] into the stored representation (identity by default, a
/// Firestore `Timestamp` in the Firestore repository).
typedef TimeEncoder = Object Function(DateTime time);

Object _keepTime(DateTime time) => time;

/// What the plan was computed from (`inputsDigest`). Enough to recompute the
/// slider bounds and the macro bands without the profile.
class PlanInputsDigest {
  const PlanInputsDigest({
    required this.weightKg,
    required this.heightCm,
    required this.ageYears,
    required this.activityFactor,
    required this.tdee,
    required this.bmr,
    required this.sexBasis,
  });

  final double weightKg;
  final double heightCm;
  final int ageYears;
  final double activityFactor;
  final double tdee;
  final double bmr;
  final SexBasis sexBasis;

  Map<String, dynamic> toMap() => {
        'weightKg': weightKg,
        'heightCm': heightCm,
        'ageYears': ageYears,
        'activityFactor': activityFactor,
        'tdee': tdee,
        'bmr': bmr,
        'sexBasis': sexBasis.name,
      };

  static PlanInputsDigest? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final weight = _num(raw['weightKg']);
    final height = _num(raw['heightCm']);
    final age = _int(raw['ageYears']);
    final factor = _num(raw['activityFactor']);
    final tdeeKcal = _num(raw['tdee']);
    final bmrKcal = _num(raw['bmr']);
    final sex = _enumByName(SexBasis.values, raw['sexBasis']);
    if (weight == null ||
        height == null ||
        age == null ||
        factor == null ||
        tdeeKcal == null ||
        bmrKcal == null ||
        sex == null) {
      return null;
    }
    if (weight <= 0 || height <= 0 || tdeeKcal <= 0 || bmrKcal <= 0) {
      return null;
    }
    return PlanInputsDigest(
      weightKg: weight,
      heightCm: height,
      ageYears: age,
      activityFactor: factor,
      tdee: tdeeKcal,
      bmr: bmrKcal,
      sexBasis: sex,
    );
  }
}

/// The 7-day undo record of an automatically applied review (`reviewUndo`).
/// The review document itself stays immutable.
class ReviewUndo {
  const ReviewUndo({
    required this.week,
    required this.prevKcalRange,
    required this.prevStepsGoal,
    required this.prevDrift,
    required this.expiresAt,
    this.undone = false,
  });

  final String week;
  final KcalRange prevKcalRange;
  final int prevStepsGoal;
  final int prevDrift;
  final DateTime expiresAt;
  final bool undone;

  /// True while the undo may still be used.
  bool isAvailableAt(DateTime now) => !undone && now.isBefore(expiresAt);

  ReviewUndo markUndone() => ReviewUndo(
        week: week,
        prevKcalRange: prevKcalRange,
        prevStepsGoal: prevStepsGoal,
        prevDrift: prevDrift,
        expiresAt: expiresAt,
        undone: true,
      );

  Map<String, dynamic> toMap({TimeEncoder time = _keepTime}) => {
        'week': week,
        'prevKcalRange': {'low': prevKcalRange.low, 'high': prevKcalRange.high},
        'prevStepsGoal': prevStepsGoal,
        'prevDrift': prevDrift,
        'expiresAt': time(expiresAt),
        'undone': undone,
      };

  static ReviewUndo? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final week = raw['week'];
    final range = _range(raw['prevKcalRange']);
    final steps = _int(raw['prevStepsGoal']);
    final drift = _int(raw['prevDrift']);
    final expires = _time(raw['expiresAt']);
    if (week is! String ||
        range == null ||
        steps == null ||
        drift == null ||
        expires == null) {
      return null;
    }
    return ReviewUndo(
      week: week,
      prevKcalRange: range,
      prevStepsGoal: steps,
      prevDrift: drift,
      expiresAt: expires,
      undone: raw['undone'] == true,
    );
  }
}

/// The stored plan. Immutable; every change goes through [copyWith] and the
/// repository, which bumps [planVersion].
class StoredNutritionPlan {
  const StoredNutritionPlan({
    required this.planVersion,
    required this.ownership,
    required this.autoAdjust,
    required this.goal,
    required this.ratePctPerWeek,
    required this.kcalRange,
    required this.kcalBounds,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.stepsGoal,
    required this.digest,
    required this.computedAt,
    this.lastKcalAdjustAt,
    this.driftFromInitialKcal = 0,
    this.reviewUndo,
  });

  /// Monotonic; incremented by every plan write. The review transaction
  /// refuses a decision made against another version (D-57).
  final int planVersion;
  final PlanOwnership ownership;
  final AutoAdjust autoAdjust;

  /// The goal actually planned (a lose goal may have been coerced).
  final GoalDirection goal;
  final double ratePctPerWeek;
  final KcalRange kcalRange;

  /// Stored for audit only; [validated] recomputes it.
  final PlanBounds kcalBounds;
  final ProteinBand protein;
  final GramBand fat;
  final GramBand carbs;
  final int stepsGoal;
  final PlanInputsDigest digest;
  final DateTime computedAt;

  /// The last time a review CHANGED the plan (kcal or steps); drives the
  /// 14-day cooldown. Null means never adjusted.
  final DateTime? lastKcalAdjustAt;

  /// Cumulative review adjustment since the initial range (signed kcal).
  final int driftFromInitialKcal;
  final ReviewUndo? reviewUndo;

  /// Builds the first stored plan from a computed one (version 1).
  factory StoredNutritionPlan.fromComputed(
    NutritionPlan plan, {
    required DateTime now,
    required PlanInputsDigest digest,
    PlanOwnership ownership = PlanOwnership.coached,
    AutoAdjust autoAdjust = const AutoAdjust(),
    int planVersion = 1,
  }) =>
      StoredNutritionPlan(
        planVersion: planVersion,
        ownership: ownership,
        autoAdjust: autoAdjust,
        goal: plan.goal,
        ratePctPerWeek: plan.ratePctPerWeek,
        kcalRange: plan.kcalRange,
        kcalBounds: plan.bounds,
        protein: plan.macros.protein,
        fat: plan.macros.fat,
        carbs: plan.macros.carbs,
        stepsGoal: plan.stepsGoal,
        digest: digest,
        computedAt: now,
      );

  /// The digest of a computed plan and its inputs.
  static PlanInputsDigest digestOf(NutritionPlan plan, double weightKg,
          double heightCm, int ageYears, SexBasis sex) =>
      PlanInputsDigest(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: ageYears,
        activityFactor: plan.activityFactor,
        tdee: plan.tdee,
        bmr: plan.bmr,
        sexBasis: sex,
      );

  StoredNutritionPlan copyWith({
    int? planVersion,
    PlanOwnership? ownership,
    AutoAdjust? autoAdjust,
    double? ratePctPerWeek,
    KcalRange? kcalRange,
    PlanBounds? kcalBounds,
    ProteinBand? protein,
    GramBand? fat,
    GramBand? carbs,
    int? stepsGoal,
    DateTime? computedAt,
    DateTime? lastKcalAdjustAt,
    int? driftFromInitialKcal,
    ReviewUndo? reviewUndo,
    bool clearReviewUndo = false,
  }) =>
      StoredNutritionPlan(
        planVersion: planVersion ?? this.planVersion,
        ownership: ownership ?? this.ownership,
        autoAdjust: autoAdjust ?? this.autoAdjust,
        goal: goal,
        ratePctPerWeek: ratePctPerWeek ?? this.ratePctPerWeek,
        kcalRange: kcalRange ?? this.kcalRange,
        kcalBounds: kcalBounds ?? this.kcalBounds,
        protein: protein ?? this.protein,
        fat: fat ?? this.fat,
        carbs: carbs ?? this.carbs,
        stepsGoal: stepsGoal ?? this.stepsGoal,
        digest: digest,
        computedAt: computedAt ?? this.computedAt,
        lastKcalAdjustAt: lastKcalAdjustAt ?? this.lastKcalAdjustAt,
        driftFromInitialKcal:
            driftFromInitialKcal ?? this.driftFromInitialKcal,
        reviewUndo: clearReviewUndo ? null : (reviewUndo ?? this.reviewUndo),
      );

  /// The bounds recomputed from the digest (design s13.3), the same function
  /// the calculator uses. Never read from the stored `kcalBounds`.
  PlanBounds recomputeBounds() {
    final bmi = bmiOf(digest.weightKg, digest.heightCm) ?? 0;
    final row = weeklyRateRow(goal, bmi);
    return computeBounds(
      goal: goal,
      tdee: digest.tdee,
      floorKcal: calorieFloor(digest.bmr, digest.sexBasis),
      maxKgPerWeek: kgPerWeekFor(row, row.maxPct, digest.weightKg),
    );
  }

  /// The row maximum in kg per week for this plan's inputs.
  double get maxKgPerWeek {
    final bmi = bmiOf(digest.weightKg, digest.heightCm) ?? 0;
    final row = weeklyRateRow(goal, bmi);
    return kgPerWeekFor(row, row.maxPct, digest.weightKg);
  }

  /// The signed intended weekly rate in kg (loss negative).
  double get intendedKgPerWeek {
    final bmi = bmiOf(digest.weightKg, digest.heightCm) ?? 0;
    final row = weeklyRateRow(goal, bmi);
    return intendedKgPerWeekFor(
      goal,
      kgPerWeekFor(row, ratePctPerWeek, digest.weightKg),
    );
  }

  /// Macro bands re-derived for [range] (used when a range changes).
  MacroPlan macrosFor(KcalRange range) => computeMacros(
        weightKg: digest.weightKg,
        heightCm: digest.heightCm,
        goal: goal,
        kcal: range,
      );

  /// This plan with the safety clamps re-applied: bounds recomputed, the range
  /// pulled inside them (and the macros re-derived when it moved), the steps
  /// goal and rate clamped. Applied on EVERY read and EVERY write.
  StoredNutritionPlan validated() {
    final bounds = recomputeBounds();
    final range = clampRangeToBounds(kcalRange, bounds);
    final moved = range != kcalRange;
    final macros = moved ? macrosFor(range) : null;
    final bmi = bmiOf(digest.weightKg, digest.heightCm) ?? 0;
    final maxPct = weeklyRateRow(goal, bmi).maxPct;
    return StoredNutritionPlan(
      planVersion: planVersion,
      ownership: ownership,
      autoAdjust: autoAdjust,
      goal: goal,
      ratePctPerWeek: math.max(0.0, math.min(ratePctPerWeek, maxPct)),
      kcalRange: range,
      kcalBounds: bounds,
      protein: macros?.protein ?? protein,
      fat: macros?.fat ?? fat,
      carbs: macros?.carbs ?? carbs,
      stepsGoal: stepsGoal
          .clamp(SafetyClamps.stepsUserMin, SafetyClamps.stepsUserMax)
          .toInt(),
      digest: digest,
      computedAt: computedAt,
      lastKcalAdjustAt: lastKcalAdjustAt,
      driftFromInitialKcal: driftFromInitialKcal,
      reviewUndo: reviewUndo,
    );
  }

  /// Whole days since the last review adjustment, or null when never adjusted.
  int? daysSinceLastAdjust(DateTime now) => lastKcalAdjustAt == null
      ? null
      : now.difference(lastKcalAdjustAt!).inDays;

  Map<String, dynamic> toMap({TimeEncoder time = _keepTime}) => {
        'schema': 1,
        'status': 'active',
        'planVersion': planVersion,
        'ownership': ownership.name,
        'autoAdjust': {'steps': autoAdjust.steps, 'kcal': autoAdjust.kcal},
        'goalDirection': goal.name,
        'ratePctPerWeek': ratePctPerWeek,
        'kcalRange': {'low': kcalRange.low, 'high': kcalRange.high},
        'kcalBounds': {'min': kcalBounds.minKcal, 'max': kcalBounds.maxKcal},
        'protein': {
          'minG': protein.minG,
          'targetG': protein.targetG,
          'maxG': protein.maxG,
        },
        'fat': {'minG': fat.minG, 'maxG': fat.maxG},
        'carbs': {'minG': carbs.minG, 'maxG': carbs.maxG},
        'stepsGoal': stepsGoal,
        'inputsDigest': digest.toMap(),
        'computedAt': time(computedAt),
        if (lastKcalAdjustAt != null)
          'lastKcalAdjustAt': time(lastKcalAdjustAt!),
        'driftFromInitialKcal': driftFromInitialKcal,
        if (reviewUndo != null) 'reviewUndo': reviewUndo!.toMap(time: time),
      };

  /// Tolerant read. Null for a document that is not a readable ACTIVE plan
  /// (a `needsProfile` or unreadable document is "no plan"). The result is NOT
  /// yet [validated]; repositories call that.
  static StoredNutritionPlan? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    if (raw['status'] != 'active') return null;
    final version = _int(raw['planVersion']);
    final digest = PlanInputsDigest.tryFromMap(raw['inputsDigest']);
    final goal = _enumByName(GoalDirection.values, raw['goalDirection']);
    final range = _range(raw['kcalRange']);
    final steps = _int(raw['stepsGoal']);
    if (version == null ||
        version < 1 ||
        digest == null ||
        goal == null ||
        range == null ||
        steps == null) {
      return null;
    }
    final autoRaw = raw['autoAdjust'];
    final auto = autoRaw is Map
        ? AutoAdjust(
            steps: autoRaw['steps'] != false,
            kcal: autoRaw['kcal'] != false,
          )
        : const AutoAdjust();
    final boundsRaw = raw['kcalBounds'];
    final storedBounds = boundsRaw is Map &&
            _int(boundsRaw['min']) != null &&
            _int(boundsRaw['max']) != null
        ? PlanBounds(_int(boundsRaw['min'])!, _int(boundsRaw['max'])!)
        : PlanBounds(range.low, range.high);

    // Macro bands: stored when readable, otherwise re-derived for the range.
    final proteinRaw = raw['protein'];
    final fatRaw = raw['fat'];
    final carbsRaw = raw['carbs'];
    final fallback = computeMacros(
      weightKg: digest.weightKg,
      heightCm: digest.heightCm,
      goal: goal,
      kcal: range,
    );
    final protein = proteinRaw is Map &&
            _int(proteinRaw['minG']) != null &&
            _int(proteinRaw['targetG']) != null &&
            _int(proteinRaw['maxG']) != null
        ? ProteinBand(
            minG: _int(proteinRaw['minG'])!,
            targetG: _int(proteinRaw['targetG'])!,
            maxG: _int(proteinRaw['maxG'])!,
          )
        : fallback.protein;
    GramBand band(Object? r, GramBand alt) =>
        r is Map && _int(r['minG']) != null && _int(r['maxG']) != null
            ? GramBand(minG: _int(r['minG'])!, maxG: _int(r['maxG'])!)
            : alt;

    return StoredNutritionPlan(
      planVersion: version,
      ownership: _enumByName(PlanOwnership.values, raw['ownership']) ??
          PlanOwnership.coached,
      autoAdjust: auto,
      goal: goal,
      ratePctPerWeek: _num(raw['ratePctPerWeek']) ?? 0,
      kcalRange: range,
      kcalBounds: storedBounds,
      protein: protein,
      fat: band(fatRaw, fallback.fat),
      carbs: band(carbsRaw, fallback.carbs),
      stepsGoal: steps,
      digest: digest,
      computedAt: _time(raw['computedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastKcalAdjustAt: _time(raw['lastKcalAdjustAt']),
      driftFromInitialKcal: _int(raw['driftFromInitialKcal']) ?? 0,
      reviewUndo: ReviewUndo.tryFromMap(raw['reviewUndo']),
    );
  }
}

// --- tolerant readers (shared with plan_review_record.dart) -----------------

double? _num(Object? v) =>
    v is num && v.isFinite ? v.toDouble() : null;

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v.isFinite && v == v.roundToDouble()) return v.toInt();
  return null;
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

KcalRange? _range(Object? raw) {
  if (raw is! Map) return null;
  final low = _int(raw['low']);
  final high = _int(raw['high']);
  if (low == null || high == null || low > high) return null;
  return KcalRange(low, high);
}

DateTime? _time(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  return null;
}

/// Shared with the review record reader.
int? readIntTolerant(Object? v) => _int(v);
double? readNumTolerant(Object? v) => _num(v);
DateTime? readTimeTolerant(Object? v) => _time(v);
T? readEnumTolerant<T extends Enum>(List<T> values, Object? name) =>
    _enumByName(values, name);
