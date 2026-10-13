/// What the questionnaire says about HOW a recommendation should be shaped,
/// beyond which exercises are safe.
///
/// `SafetyContext` answers "may this person be shown this"; this answers "what
/// should the mix look like". Both are derived from the same `UserProfile`, and
/// both are consumed by the plan, the home feed and the programme builder, so a
/// questionnaire answer cannot steer one surface and be ignored by another.
///
/// ## Inputs deliberately NOT used (and why)
///
/// A questionnaire answer is allowed to be unused only when using it would be a
/// guess the app cannot back. The audit of the 100-profile ratchet lists them;
/// each reason is the evidence-based one:
///
///  * `personal.gender` - nothing in the catalogue or the evidence the app
///    holds changes exercise selection by gender; cycle-related adjustment is
///    driven by the user's own self-report, never by gender.
///  * `personal.heightCm`, `weightCurrentKg`, `weightTargetKg` - no selection
///    rule in the catalogue depends on body size, and deriving a "BMI" or a
///    weight-loss rate would be a health claim this app does not make.
///  * `goals.specificSport` - free text with no sport taxonomy in the
///    catalogue; mapping "boxing" to exercises would invent a personalisation
///    the data cannot support (and any reason shown for it would be untrue).
///  * `level.currentExercises` - free-text names, not catalogue ids.
///  * `lifestyle.smoking`, `alcohol`, `diet`, `occupation` - no evidence-based
///    effect on which exercises to pick; diet is nutrition, not training.
///  * `motivation.motivation` (text), `barriers`, `environments` - preference
///    and coaching signals; training location is taken from the equipment
///    answers, which are the enforceable ones.
///  * `health.conditions`, `medications`, `allergies`, `recentSurgeries`,
///    `physicalLimitations`, `otherConcerns` (free text) and the legacy
///    `health.bloodPressure` chip - free text is never parsed into safety
///    decisions (a parse that misses would read as "screened"); their
///    structured successors in `HealthFlags` ARE used.
///  * `equipment.gymId`, `homeEquipment` (free text) - the typed
///    `EquipmentKind` list is what availability reads.
///
/// Everything else is wired: age (policy band), activity level, sleep and
/// stress (starting volume), `level.basics`, `level.frequencyPerWeek` and
/// `schedule.preferredWeekdays` (programme days), `goals.primary`,
/// `flexibility` and `generalFitness` (mobility / conditioning share).
library;

import '../../equipment/data/equipment_models.dart';
import '../../profile/data/profile_models.dart';
import '../../programmes/data/programme.dart' show ProgrammeGoal;
import '../../safety/data/age_policy.dart';

/// Why the starting volume is capped. Each cause is a statement the user can
/// verify against their own answers.
enum VolumeCapCause { lowActivity, recovery, basics }

/// Conditioning (cardio) work: the cardio machines and the vendor's
/// conditioning/functional group.
bool isConditioningExercise(ExerciseItem e) =>
    e.vendorGroup == 'Calisthenics-Cardio-Plyo-Functional' ||
    const {'treadmill', 'rowing_machine', 'exercise_bike'}.contains(e.equipmentId);

class RecommendationHints {
  const RecommendationHints({
    this.wantsMobility = false,
    this.wantsConditioning = false,
    this.volumeCap,
    this.volumeCapCause,
  });

  /// No profile-driven shaping.
  static const none = RecommendationHints();

  /// The goal asks for flexibility/mobility work (flexibility goal, comeback,
  /// general fitness).
  final bool wantsMobility;

  /// The goal asks for cardio/conditioning work (weight loss, endurance,
  /// general fitness).
  final bool wantsConditioning;

  /// Upper bound on the plan's intensity factor from activity level, recovery
  /// answers or "cannot do the basics"; null for none.
  final double? volumeCap;
  final VolumeCapCause? volumeCapCause;

  factory RecommendationHints.fromProfile(UserProfile? p) {
    if (p == null) return none;
    final g = p.goals;
    final mobility = g.flexibility ||
        g.primary == ProgrammeGoal.comeback ||
        g.generalFitness;
    final conditioning = g.weightLoss ||
        g.endurance ||
        g.generalFitness ||
        g.primary == ProgrammeGoal.weightLoss ||
        g.primary == ProgrammeGoal.endurance;

    double? cap;
    VolumeCapCause? cause;
    void consider(double v, VolumeCapCause c) {
      if (cap == null || v < cap!) {
        cap = v;
        cause = c;
      }
    }

    // PRODUCT_HEURISTIC starting-volume caps; only ever lower the dose.
    if (p.personal.activityLevel == ActivityLevel.sedentary) {
      consider(0.85, VolumeCapCause.lowActivity);
    }
    if (p.level.basics == BasicExerciseAbility.no) {
      consider(0.9, VolumeCapCause.basics);
    }
    final sleep = p.lifestyle.sleepHoursPerNight;
    final stress = p.lifestyle.stressLevel;
    if ((sleep != null && sleep < 6) || (stress != null && stress >= 8)) {
      consider(0.9, VolumeCapCause.recovery);
    }
    return RecommendationHints(
      wantsMobility: mobility,
      wantsConditioning: conditioning,
      volumeCap: cap,
      volumeCapCause: cause,
    );
  }
}

/// Whether the profile asks for a gentle selection (no maximal-effort or
/// advanced work): a comeback or flexibility goal, or "cannot do the basics".
bool gentleSelectionFor(UserProfile p) =>
    p.goals.primary == ProgrammeGoal.comeback ||
    p.goals.flexibility ||
    p.level.basics == BasicExerciseAbility.no;

/// Training days per week this profile should START with, given the template's
/// own figure.
///
/// Only ever lowers [templateDays]: the questionnaire day count, the age band's
/// recovery-spacing cap, and for beginners the current training frequency
/// (a person who trains 0-1 times a week does not start at six).
int cappedProgrammeDays(int templateDays, UserProfile? profile, AgeBand band) {
  var days = templateDays;
  final answered = profile?.schedule.daysPerWeek;
  if (answered != null && answered < days) days = answered;
  final ageCap = band.maxDaysPerWeek;
  if (ageCap != null && ageCap < days) days = ageCap;
  final tier = profile?.level.tier;
  final freq = profile?.level.frequencyPerWeek;
  if (freq != null &&
      (tier == null || tier == FitnessTier.never || tier == FitnessTier.beginner)) {
    final startCap = freq + 2 < 2 ? 2 : freq + 2;
    if (startCap < days) days = startCap;
  }
  return days < 1 ? 1 : days;
}
