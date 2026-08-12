import '../../profile/data/profile_models.dart';

/// The seven questionnaire sections, named rather than numbered.
///
/// O1 keyed the same logic on the page index, which was correct only while the
/// order was frozen. O2 reorders the flow, and a positional key would have gone
/// on answering confidently about a different screen than the one on display —
/// silently, because both are ints in range.
enum OnboardingStep {
  personal,
  health,
  /// Goal AND starting level, one screen since O3.
  ///
  /// Replaced the separate `goals` and `level` values rather than joining them:
  /// leaving both in the enum would have left two names for one screen, and the
  /// next reader would have had to work out which of them the flow actually
  /// uses. The underlying model is untouched — [FitnessGoals] and [FitnessLevel]
  /// are still separate, because they answer different questions.
  goalAndLevel,
  lifestyle,
  equipment,
  motivation,
}

/// The order the screens are shown in.
///
/// Traced to the design's sequence (`App.tsx`, steps 1-9), collapsed onto the
/// seven screens that exist today: goal, then level (the design merges these
/// into 1/9 — merging is O3, not this gate), place and equipment (2/9), body
/// limitations (4/9), barriers (5/9), about you (6-7/9). Lifestyle has no home
/// in the design's flow and stays its own screen by the operator's decision, at
/// the end where it reads as supporting detail rather than as a gate.
///
/// Health Connect (8/9) is deliberately absent: the operator removed it from
/// onboarding entirely, and connecting watches and trackers becomes its own
/// gate later. The `HealthService` seam is untouched — a step was dropped, not
/// the interface.
///
/// This list IS the flow. Changing it changes the order, and nothing else has
/// to move.
const List<OnboardingStep> kOnboardingOrder = [
  OnboardingStep.goalAndLevel,
  OnboardingStep.equipment,
  OnboardingStep.health,
  OnboardingStep.motivation,
  OnboardingStep.personal,
  OnboardingStep.lifestyle,
];

/// Whether the user has put anything into [step] yet.
///
/// ## Why this exists as a pure function
///
/// The redesign's primary button is not a fixed "Next". On a step the user has
/// not answered it reads "Skip" and drops to the ghost variant; once anything
/// is entered it becomes the accent "Next" (`App.tsx:1598`). That is the one
/// place the prototype gets this right — its other steps ship a separate
/// "Пропустить этот шаг" text button *underneath* an always-enabled primary
/// (`App.tsx:1565`), so both controls call the same `onNext` and differ only in
/// how they look.
///
/// Keeping the rule out of the widget means the answer can be asserted
/// directly, without pumping a page and reading a label off it. It also gives
/// [onboardingResumeIndex] something to be built from.
///
/// ## "Answered" means *touched*, not *complete*
///
/// Every question in this questionnaire is optional — `_submit` sends whatever
/// the draft holds. So this cannot ask "is the step valid"; there is no such
/// thing. It asks whether the user put anything in, which is the only fact the
/// button label and the resume point need.
bool isOnboardingStepAnswered(OnboardingStep step, UserProfile p) {
  switch (step) {
    case OnboardingStep.personal:
      final i = p.personal;
      return i.age != null ||
          i.gender != null ||
          i.heightCm != null ||
          i.weightCurrentKg != null ||
          i.weightTargetKg != null ||
          i.activityLevel != null;
    case OnboardingStep.health:
      final h = p.health;
      return h.conditions.isNotEmpty ||
          h.allergies.isNotEmpty ||
          h.medications.isNotEmpty ||
          h.injuries.isNotEmpty ||
          h.physicalLimitations.isNotEmpty ||
          h.recentSurgeries.isNotEmpty ||
          h.bloodPressure != null ||
          (h.otherConcerns?.isNotEmpty ?? false);
    case OnboardingStep.goalAndLevel:
      // One screen, so ONE answer is enough to count it as touched — picking a
      // goal and leaving the level blank is a real, intentional way to use this
      // screen, and calling it unanswered would put "Skip" on a button that
      // would discard a choice the user just made.
      final g = p.goals;
      final l = p.level;
      return g.hasAny ||
          l.frequencyPerWeek != null ||
          l.currentExercises.isNotEmpty ||
          l.tier != null ||
          l.basics != null;
    case OnboardingStep.lifestyle:
      final l = p.lifestyle;
      return l.diet.isNotEmpty ||
          l.smoking != null ||
          l.alcohol != null ||
          l.sleepHoursPerNight != null ||
          l.stressLevel != null ||
          l.occupation != null;
    case OnboardingStep.equipment:
      final e = p.equipment;
      // `hasGymAccess` is derived from `location` since O4, so testing it alone
      // would still be correct — but only by accident, and it would stop being
      // correct the moment a fifth location did not map cleanly onto a boolean.
      // The fields the screen writes are the ones asked about here.
      return e.location != null ||
          e.available.isNotEmpty ||
          e.hasGymAccess != null ||
          e.homeEquipment.isNotEmpty;
    case OnboardingStep.motivation:
      final m = p.motivation;
      return (m.motivation?.isNotEmpty ?? false) ||
          m.environments.isNotEmpty ||
          m.preferredDuration != null;
  }
}

/// Where to drop the user when they open onboarding again.
///
/// The draft is already persisted on every advance (`_next` saves before it
/// moves) and rehydrates from the cached profile, so a returning user's answers
/// survive. What did not survive was their *place*: the flow always restarted
/// at screen one, and the only way past the questions they had already answered
/// was to walk through all of them again.
///
/// Derived rather than stored. A saved cursor is a second source of truth that
/// can disagree with the answers — a user who clears a section would resume
/// past a screen that is now empty. The first gap in the answers cannot
/// disagree with the answers, because it *is* them.
///
/// The first unanswered screen, not the furthest reached: skipping screen two
/// and answering screen three should bring you back to two, which is the one
/// still missing. A fully answered draft returns the last screen, so the user
/// lands on Done rather than being bounced out of a flow they never finished.
int onboardingResumeIndex(UserProfile draft,
    [List<OnboardingStep> order = kOnboardingOrder]) {
  if (order.isEmpty) return 0;
  for (var i = 0; i < order.length; i++) {
    if (!isOnboardingStepAnswered(order[i], draft)) return i;
  }
  return order.length - 1;
}
