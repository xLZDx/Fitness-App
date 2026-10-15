/// Nutrition-aware programme level (design s30): the data contract and ONE pure
/// decision function. Pure Dart, no Flutter imports.
///
/// Boundary: nutrition may only LOWER training load. It never raises a cap that
/// safety set (age band, screening ceiling, injury filter), and it acts only on
/// data it actually has; missing data or an ineligible user gives a neutral
/// result. All numbers are [OWN] and conservative (design s29 rule); the
/// deficit rule follows the published advice to keep load and trim volume in a
/// deficit (Helms et al. 2014).
library;

import 'nutrition_eligibility.dart';

enum EnergyPhase { deficit, maintenance, surplus }

enum DeloadSuggestion {
  none,
  consider,
  recommended;

  /// The stronger of two suggestions.
  DeloadSuggestion max(DeloadSuggestion o) => index >= o.index ? this : o;
}

/// Closed, localisable, non-clinical reason codes. No energy-availability or
/// RED-S wording is used anywhere: the app does not compute true energy
/// availability and makes no such claim.
enum TrainingNutritionReason {
  deficitVolumeTrim,
  surplusVolumeBoost,
  proteinLow,
  sleepLow,
  lossTooFast,
  lowIntakeHighLoad,
  recoveryDeload,
}

/// Tunables [OWN] (design 30.3).
abstract final class TrainingNutritionLimits {
  static const double deepDeficitPct = 0.20;
  static const double moderateDeficitPct = 0.10;
  static const double deepDeficitVolume = 0.85;
  static const double moderateDeficitVolume = 0.95;
  static const double surplusVolume = 1.05;
  static const double surplusMinSleepHours = 7.0;
  static const double surplusMinProteinAdherence = 0.7;

  /// Protein adherence needs at least this many LOGGED days in the last 14.
  static const int minLoggedDays = 4;
  static const double proteinLowAdherence = 0.5;

  static const double lowSleepHours = 6.0;
  static const double lowSleepIntensityDelta = -0.05;

  /// Weight loss faster than this multiple of the plan's maximum rate.
  static const double fastLossFactor = 1.25;
  static const double fastLossVolume = 0.90;

  /// Intake within this factor of the floor, with at least this many sessions.
  static const double lowIntakeFloorFactor = 1.05;
  static const int highLoadSessionsPerWeek = 5;

  static const double volumeMin = 0.70;
  static const double volumeMax = 1.05;
  static const double intensityDeltaMin = -0.10;
}

class NutritionTrainingInput {
  const NutritionTrainingInput({
    required this.eligibility,
    this.phase,
    this.deficitPct,
    this.surplusPct,
    this.proteinAdherence,
    this.loggedDays14 = 0,
    this.avgSleepHours,
    this.weightRatePctPerWeek,
    this.planMaxRatePctPerWeek,
    this.sessionsPerWeek = 0,
    this.recoveryDeloadSignal = false,
    this.kcalMid,
    this.floorKcal,
  });

  /// Anything but `Eligible` gives a neutral result.
  final NutritionEligibility eligibility;
  final EnergyPhase? phase;

  /// `(TDEE - kcalMid) / TDEE`, >= 0 in a deficit; null if unknown.
  final double? deficitPct;
  final double? surplusPct;

  /// Fraction of LOGGED days meeting the protein minimum.
  final double? proteinAdherence;
  final int loggedDays14;
  final double? avgSleepHours;

  /// From the Theil-Sen slope; negative while losing.
  final double? weightRatePctPerWeek;

  /// The plan's maximum weekly rate in percent of bodyweight, for the fast-loss
  /// rule.
  final double? planMaxRatePctPerWeek;
  final int sessionsPerWeek;

  /// The existing recovery/deload detector's output.
  final bool recoveryDeloadSignal;
  final double? kcalMid;
  final double? floorKcal;
}

class TrainingNutritionAdvice {
  const TrainingNutritionAdvice({
    this.volumeFactor = 1.0,
    this.intensityCapDelta = 0.0,
    this.deload = DeloadSuggestion.none,
    this.reasons = const [],
    this.showProfessionalLine = false,
  });

  /// Multiplier on weekly working sets, 0.70 .. 1.05.
  final double volumeFactor;

  /// 0 or negative; added to an existing intensity cap, never raising it.
  final double intensityCapDelta;
  final DeloadSuggestion deload;
  final List<TrainingNutritionReason> reasons;

  /// Show the generic "talk to a professional if you feel unwell or train hard
  /// on low intake" line.
  final bool showProfessionalLine;

  /// True when nothing is applied.
  bool get neutral =>
      volumeFactor == 1.0 &&
      intensityCapDelta == 0.0 &&
      deload == DeloadSuggestion.none &&
      reasons.isEmpty;

  static const TrainingNutritionAdvice neutralAdvice = TrainingNutritionAdvice();
}

const double _eps = 1e-6;

/// The decision function (design 30.3, rules 1-9).
TrainingNutritionAdvice adviseTrainingFromNutrition(NutritionTrainingInput i) {
  // 1. Never act on missing data or for a user who may not get numbers.
  if (!i.eligibility.allowsNumbers || i.kcalMid == null || i.phase == null) {
    return TrainingNutritionAdvice.neutralAdvice;
  }

  var volume = 1.0;
  var delta = 0.0;
  var deload = DeloadSuggestion.none;
  var professional = false;
  final reasons = <TrainingNutritionReason>[];
  void add(TrainingNutritionReason r) {
    if (!reasons.contains(r)) reasons.add(r);
  }

  final adherence = i.loggedDays14 >= TrainingNutritionLimits.minLoggedDays
      ? i.proteinAdherence
      : null;

  // 2. Deficit depth trims volume, never intensity.
  if (i.phase == EnergyPhase.deficit && i.deficitPct != null) {
    final d = i.deficitPct!;
    if (d >= TrainingNutritionLimits.deepDeficitPct) {
      volume = TrainingNutritionLimits.deepDeficitVolume;
      add(TrainingNutritionReason.deficitVolumeTrim);
    } else if (d >= TrainingNutritionLimits.moderateDeficitPct) {
      volume = TrainingNutritionLimits.moderateDeficitVolume;
      add(TrainingNutritionReason.deficitVolumeTrim);
    }
  }

  // 3. A small boost only when sleep and protein are both good.
  if (i.phase == EnergyPhase.surplus &&
      i.avgSleepHours != null &&
      adherence != null &&
      i.avgSleepHours! >= TrainingNutritionLimits.surplusMinSleepHours &&
      adherence >= TrainingNutritionLimits.surplusMinProteinAdherence) {
    volume = TrainingNutritionLimits.surplusVolume;
    add(TrainingNutritionReason.surplusVolumeBoost);
  }

  // 4. Low protein in a deficit: a nudge and a deload to consider.
  if (i.phase == EnergyPhase.deficit &&
      adherence != null &&
      adherence < TrainingNutritionLimits.proteinLowAdherence) {
    add(TrainingNutritionReason.proteinLow);
    deload = deload.max(DeloadSuggestion.consider);
  }

  // 5. Short sleep lowers the intensity cap.
  if (i.avgSleepHours != null &&
      i.avgSleepHours! < TrainingNutritionLimits.lowSleepHours) {
    delta = TrainingNutritionLimits.lowSleepIntensityDelta;
    add(TrainingNutritionReason.sleepLow);
  }

  // 6. Losing weight faster than the plan allows.
  final rate = i.weightRatePctPerWeek;
  final maxRate = i.planMaxRatePctPerWeek;
  if (rate != null &&
      maxRate != null &&
      rate < -TrainingNutritionLimits.fastLossFactor * maxRate - _eps) {
    if (volume > TrainingNutritionLimits.fastLossVolume) {
      volume = TrainingNutritionLimits.fastLossVolume;
    }
    deload = deload.max(DeloadSuggestion.consider);
    add(TrainingNutritionReason.lossTooFast);
  }

  // 7. Low intake with high load: a screening proxy only. True energy
  // availability is deliberately NOT computed and no such claim is made.
  final floor = i.floorKcal;
  if (floor != null &&
      i.kcalMid! <= floor * TrainingNutritionLimits.lowIntakeFloorFactor + _eps &&
      i.sessionsPerWeek >= TrainingNutritionLimits.highLoadSessionsPerWeek) {
    deload = DeloadSuggestion.recommended;
    professional = true;
    add(TrainingNutritionReason.lowIntakeHighLoad);
  }

  // 8. The existing recovery signal is preserved.
  if (i.recoveryDeloadSignal) {
    deload = DeloadSuggestion.recommended;
    add(TrainingNutritionReason.recoveryDeload);
  }

  // 9. Clamps; the factors multiply, they do not stack past the clamp.
  volume = volume
      .clamp(TrainingNutritionLimits.volumeMin, TrainingNutritionLimits.volumeMax)
      .toDouble();
  delta = delta.clamp(TrainingNutritionLimits.intensityDeltaMin, 0.0).toDouble();

  return TrainingNutritionAdvice(
    volumeFactor: volume,
    intensityCapDelta: delta,
    deload: deload,
    reasons: List.unmodifiable(reasons),
    showProfessionalLine: professional,
  );
}

/// The intensity ceiling after nutrition: the MOST CONSERVATIVE of every cap
/// that safety set (age band, screening ceiling, answer-driven hint cap) and the
/// base ceiling, then lowered by the nutrition delta. Nutrition can only lower
/// the result; it can never raise a cap safety set. The result never falls
/// under [floor] (the planner's own clamp floor).
double combinedIntensityCeiling({
  required double baseCeiling,
  double? ageCap,
  double? screeningCeiling,
  double? hintCap,
  TrainingNutritionAdvice advice = TrainingNutritionAdvice.neutralAdvice,
  double floor = 0.5,
}) {
  var c = baseCeiling;
  for (final cap in [ageCap, screeningCeiling, hintCap]) {
    if (cap != null && cap < c) c = cap;
  }
  final lowered = c + (advice.intensityCapDelta > 0 ? 0.0 : advice.intensityCapDelta);
  return lowered < floor ? (c < floor ? c : floor) : lowered;
}
