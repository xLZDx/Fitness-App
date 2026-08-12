import '../../profile/data/profile_models.dart';

/// Whether the user has put anything into step [index] yet.
///
/// ## Why this exists as a pure function
///
/// The redesign's primary button is not a fixed "Next". On a step the user has
/// not answered it reads "Skip" and drops to the ghost variant; once anything
/// is entered it becomes the accent "Next" (`App.tsx:1598`). That is the one
/// place the prototype gets this right — its other steps ship a separate
/// "Пропустить этот шаг" text button *underneath* an always-enabled primary
/// (`App.tsx:1565`), so both controls call the same `onNext` and differ only in
/// how they look. Two controls that do exactly the same thing is not a design;
/// it is a fork in the prototype nobody reconciled.
///
/// Keeping the rule out of the widget means the answer can be asserted
/// directly, without pumping a page and reading a label off it.
///
/// ## "Answered" means *touched*, not *complete*
///
/// Every question in this questionnaire is optional — `_submit` sends whatever
/// the draft holds. So this cannot ask "is the step valid"; there is no such
/// thing. It asks whether the user put anything in, which is the only fact the
/// button label needs.
bool isOnboardingStepAnswered(int index, UserProfile p) {
  switch (index) {
    case 0:
      final i = p.personal;
      return i.age != null ||
          i.gender != null ||
          i.heightCm != null ||
          i.weightCurrentKg != null ||
          i.weightTargetKg != null ||
          i.activityLevel != null;
    case 1:
      final h = p.health;
      return h.conditions.isNotEmpty ||
          h.allergies.isNotEmpty ||
          h.medications.isNotEmpty ||
          h.injuries.isNotEmpty ||
          h.physicalLimitations.isNotEmpty ||
          h.recentSurgeries.isNotEmpty ||
          h.bloodPressure != null ||
          (h.otherConcerns?.isNotEmpty ?? false);
    case 2:
      final g = p.goals;
      return g.weightLoss ||
          g.muscleGain ||
          g.endurance ||
          g.strength ||
          g.flexibility ||
          g.generalFitness ||
          (g.specificSport?.isNotEmpty ?? false);
    case 3:
      final l = p.level;
      return l.frequencyPerWeek != null ||
          l.currentExercises.isNotEmpty ||
          l.tier != null ||
          l.basics != null;
    case 4:
      final l = p.lifestyle;
      return l.diet.isNotEmpty ||
          l.smoking != null ||
          l.alcohol != null ||
          l.sleepHoursPerNight != null ||
          l.stressLevel != null ||
          l.occupation != null;
    case 5:
      final e = p.equipment;
      return e.hasGymAccess != null || e.homeEquipment.isNotEmpty;
    case 6:
      final m = p.motivation;
      return (m.motivation?.isNotEmpty ?? false) ||
          m.environments.isNotEmpty ||
          m.preferredDuration != null;
    default:
      // An index the page does not render. False rather than an assert: the
      // consequence is a button reading "Skip", not a crash, and O2 renumbers
      // these steps.
      return false;
  }
}
