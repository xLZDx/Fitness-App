/// Every safety clamp and numeric parameter of the nutrition coach, as named
/// constants (design s13.6 and s29). No Flutter imports.
///
/// Provenance tags in the doc comments follow design s29: **[PUB]** published
/// formula or guideline, **[OWN]** our own conservative choice. A reference
/// value from any other app is an input, never a constant here: a clamp always
/// wins over it (D-45).
///
/// A unit test asserts each constant, so an accidental edit fails loudly.
library;

abstract final class SafetyClamps {
  // --- Eligibility -------------------------------------------------------

  /// Minimum age for any nutrition target, checked against
  /// `PersonalInfo.lowestAgeAt` so the boundary year counts as the safer side
  /// [OWN]; an unknown age gets no plan.
  static const int minAdultAge = 18;

  // --- Energy ------------------------------------------------------------

  /// Mifflin-St Jeor sex constants [PUB, AJCN 51:241]; the unspecified value is
  /// the midpoint of the two [OWN].
  static const double bmrConstantMale = 5;
  static const double bmrConstantFemale = -161;
  static const double bmrConstantUnspecified = -78;

  /// Activity factors for the four-value `ActivityLevel` [PUB PAL convention,
  /// OWN mapping]. The 1.9 "extra active" level is deliberately never used.
  static const double factorSedentary = 1.2;
  static const double factorModerate = 1.375;
  static const double factorActive = 1.55;
  static const double factorVeryActive = 1.725;

  /// Daily-steps cross-check bands [OWN]: below 5,000 is sedentary, below 7,500
  /// moderate, below 10,000 active, otherwise very active. The LOWER of the
  /// questionnaire and the steps factor is used (never over-estimate TDEE).
  static const int stepsBandModerate = 5000;
  static const int stepsBandActive = 7500;
  static const int stepsBandVeryActive = 10000;

  /// Energy per kg of body-mass change [PUB, Wishnofsky].
  static const double kcalPerKg = 7700;

  // --- Calorie floor -----------------------------------------------------

  /// Absolute floors [OWN, consumer minimums]; unspecified uses the male value.
  /// The effective floor is `max(absolute, round(BMR))`.
  static const int absoluteFloorKcalFemale = 1200;
  static const int absoluteFloorKcalMale = 1500;

  // --- Deficit and surplus -----------------------------------------------

  /// Maximum daily deficit as a fraction of TDEE [OWN].
  static const double maxDeficitFractionOfTdee = 0.25;

  /// Surplus clamp [OWN]: at least 100, at most `min(500, 15 % of TDEE)`.
  static const double minSurplusKcal = 100;
  static const double maxSurplusKcal = 500;
  static const double maxSurplusFractionOfTdee = 0.15;

  // --- Weekly rates (% of bodyweight per week) ---------------------------

  /// Loss with BMI < 25 [OWN within PUB]: default, maximum, absolute kg/week.
  static const double lossRateLowBmiDefaultPct = 0.50;
  static const double lossRateLowBmiMaxPct = 0.75;
  static const double lossRateLowBmiAbsoluteKg = 0.5;

  /// Loss with BMI >= 25 (both the 25-30 and the >= 30 rows share the numbers;
  /// the >= 30 default was lowered to 0.75 by D-38).
  static const double lossRateHighBmiDefaultPct = 0.75;
  static const double lossRateHighBmiMaxPct = 1.00;
  static const double lossRateHighBmiAbsoluteKg = 1.0;

  /// BMI at which the higher loss row starts, and the second (>= 30) row.
  static const double bmiHighRowStart = 25;
  static const double bmiObeseRowStart = 30;

  /// Gain (muscle) [OWN]: default, maximum, absolute kg/week.
  static const double gainRateDefaultPct = 0.25;
  static const double gainRateMaxPct = 0.50;
  static const double gainRateAbsoluteKg = 0.5;

  /// `tooFast` threshold of the weekly review: a loss/gain faster than the
  /// row maximum times this factor is corrected immediately [OWN].
  static const double tooFastFactor = 1.25;

  // --- BMI guards --------------------------------------------------------

  /// Below this BMI a deficit goal is refused and coerced to maintain [WHO
  /// adult band]; a target weight below it is rejected.
  static const double underweightBmi = 18.5;

  /// From [underweightBmi] to this BMI a deficit is allowed only at
  /// [lowBmiMaxRatePct] [OWN].
  static const double lowBmiDeficitBand = 20;
  static const double lowBmiMaxRatePct = 0.25;

  /// A goal weight whose BMI is under this hides the ETA (D-77 [OWN]).
  static const double etaHiddenBelowGoalBmi = 20;

  // --- Calorie range -----------------------------------------------------

  /// Range around the target [OWN, D-39]: lose is asymmetric (overshooting a
  /// deficit goal costs more than undershooting; the floor still bounds the
  /// low side), maintain and gain are symmetric.
  static const int loseRangeBelowKcal = 200;
  static const int loseRangeAboveKcal = 100;
  static const int symmetricRangeHalfKcal = 150;

  /// Allowed width of the user-visible range [OWN].
  static const int minRangeWidthKcal = 100;
  static const int maxRangeWidthKcal = 400;

  /// Display rounding of calorie values [OWN].
  static const int kcalRounding = 10;

  /// Maintain slider half-width around TDEE [OWN].
  static const int maintainBoundsKcal = 300;

  /// Last-line-of-defence bounds mirrored by the rules backstop [OWN].
  static const int hardKcalMin = 1200;
  static const int hardKcalMax = 6000;

  // --- Protein (g per kg of reference weight) ----------------------------

  /// [PUB ranges (Jager 2017, Morton 2018), OWN picks].
  static const double proteinMinMaintainPerKg = 1.4;
  static const double proteinMinChangePerKg = 1.6;
  static const double proteinTargetMaintainPerKg = 1.6;
  static const double proteinTargetLosePerKg = 2.0;
  static const double proteinTargetGainPerKg = 1.8;
  static const double proteinMaxPerKg = 2.2;

  /// Absolute protein cap in grams and as a fraction of the mid calories [OWN].
  static const int proteinMaxGrams = 220;
  static const double proteinMaxFractionOfKcal = 0.40;

  /// Above this BMI the reference weight is `30 * (H/100)^2`, so protein is
  /// not scaled to excess mass [OWN].
  static const double referenceWeightBmiCap = 30;

  /// Lean-mass protein variant (D-42): grams per kg of lean mass [PUB-ish],
  /// used only with a non-provisional, confident body-fat trend; the min/max
  /// clamps still win.
  static const double proteinPerKgLeanMass = 2.2;

  // --- Fat and carbohydrate ----------------------------------------------

  /// Fat range as a fraction of energy [PUB, IOM AMDR 20-35 %] and the
  /// per-kg floor [OWN]; the point target is 25 % of the mid calories [OWN].
  static const double fatMinFractionOfKcal = 0.20;
  static const double fatMaxFractionOfKcal = 0.35;
  static const double fatPointFractionOfKcal = 0.25;
  static const double fatMinPerKg = 0.6;

  /// Carbohydrate floor in grams [OWN].
  static const int carbMinGrams = 100;

  /// Energy density of the macros [PUB, Atwater].
  static const double kcalPerGramProtein = 4;
  static const double kcalPerGramCarb = 4;
  static const double kcalPerGramFat = 9;

  /// Point-target display rounding [OWN]: protein rounds UP to 5 g, carbs to
  /// the nearest 5 g, fat to 1 g.
  static const int proteinDisplayStepGrams = 5;
  static const int carbDisplayStepGrams = 5;

  /// Atwater consistency tolerance: `max(25 %, 10 kcal)` [PUB + FINDINGS, D-39].
  static const double atwaterTolerance = 0.25;
  static const double atwaterToleranceFloorKcal = 10;

  // --- Steps -------------------------------------------------------------

  /// Computed steps goal range and rounding [OWN].
  static const int stepsGoalMin = 6000;
  static const int stepsGoalMax = 12000;
  static const int stepsGoalRounding = 500;

  /// Added to the base before rounding, and added by each automatic review.
  static const int stepsGoalIncrement = 1000;

  /// Range a user-set goal may take (the rules backstop) [OWN].
  static const int stepsUserMin = 2000;
  static const int stepsUserMax = 30000;

  /// Base steps by activity when no typical steps are known [OWN].
  static const int stepsBaseSedentary = 6000;
  static const int stepsBaseModerate = 7500;
  static const int stepsBaseActive = 9000;
  static const int stepsBaseVeryActive = 10000;

  /// Midpoints of the self-reported daily-steps buckets
  /// (<3k, 3-5k, 5-8k, 8-11k, 11k+) [OWN].
  static const List<int> stepsBucketMidpoints = [2500, 4000, 6500, 9500, 12500];

  // --- Target body fat ---------------------------------------------------

  /// Allowed target body-fat percent [OWN]: floor 10 male, 16 female and
  /// unspecified; ceiling 40. The reference slider reached 6 % and is NOT
  /// adopted; raising a floor is deferred (D-77).
  static const double targetBodyFatMinMale = 10;
  static const double targetBodyFatMinOther = 16;
  static const double targetBodyFatMax = 40;

  // --- Weight inputs -----------------------------------------------------

  /// A weigh-in older than this many days is "stale" and the profile weight
  /// is used instead (D-72).
  static const int currentWeightFreshDays = 14;

  /// Plausible recorded weight in kg, the same range everywhere (D-52).
  static const double weightMinKg = 30;
  static const double weightMaxKg = 300;

  // --- Weekly review -----------------------------------------------------

  /// Bounded kcal step per review [OWN].
  static const int reviewStepKcal = 150;

  /// Minimum days between kcal adjustments [OWN].
  static const int reviewCooldownDays = 14;

  /// Cumulative drift from the initial range that triggers a recalculation
  /// request [OWN].
  static const int reviewDriftCapKcal = 400;

  /// Maintain-mode drift correction [OWN].
  static const int maintainDriftStepKcal = 100;

  /// Review deadband: `max(reviewToleranceMinKgPerWeek, 25 % of intended)`.
  static const double reviewToleranceMinKgPerWeek = 0.15;
  static const double reviewToleranceFraction = 0.25;

  /// Maintain: drift when the slope exceeds this % of bodyweight per week.
  static const double maintainDriftPctPerWeek = 0.25;

  /// Data sufficiency for a review: at least this many weigh-ins over at least
  /// this many days [OWN].
  static const int reviewMinWeightPoints = 3;
  static const int reviewMinSpanDays = 7;
}
