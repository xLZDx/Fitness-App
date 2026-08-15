import '../../profile/data/profile_models.dart';
import '../../safety/data/par_q.dart';

/// The seven questionnaire sections, named rather than numbered.
///
/// O1 keyed the same logic on the page index, which was correct only while the
/// order was frozen. O2 reorders the flow, and a positional key would have gone
/// on answering confidently about a different screen than the one on display —
/// silently, because both are ints in range.
enum OnboardingStep {
  personal,

  /// Limitations AND priorities, one screen since O6.
  ///
  /// Replaced `health` rather than joining it: the medical questions did not
  /// change and did not move out of the flow — they moved *under a disclosure*
  /// on this screen. Two enum values for one screen would have left the next
  /// reader guessing which one the flow uses, the same trap O3 removed.
  body,
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

  /// O5. How often, how long, which days — what the user PLANS, as opposed to
  /// [FitnessLevel.frequencyPerWeek], which is what they do today.
  schedule,

  /// O7. What gets in the way, as a closed set. Replaced `motivation`: that
  /// screen's question was already this one, asked as free text.
  barriers,

  /// Gate N. The normalised health answers — movement restrictions, blood
  /// pressure, surgery status, clinician advice. Distinct from [body], which
  /// holds the same ground as free text nothing may read.
  healthFlags,

  /// Gate M. The PAR-Q+ pre-exercise screen — the only step whose answers can
  /// stop the app producing a workout at all.
  screening,

  /// O10. Not a question — one real session built from the answers above.
  preview,
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
  // Straight after equipment, per the design's 3/9: place and kit, then when.
  OnboardingStep.schedule,
  OnboardingStep.body,
  OnboardingStep.barriers,
  OnboardingStep.personal,
  OnboardingStep.lifestyle,
  // Straight before the screening: both are safety input, and asking them
  // together means a user answers "what can you not do" and "what has a doctor
  // told you" in one sitting rather than either side of three other screens.
  OnboardingStep.healthFlags,
  // Immediately before the preview, because the preview is the first screen in
  // this flow that produces a workout, and this is the gate on producing one.
  // Placing it first instead would ask the medical questions before the user
  // knows what the app is — a conversion cost with no safety benefit, since
  // nothing between here and there generates anything.
  OnboardingStep.screening,
  // Last, and only last: it previews the answers, so it has nothing to show
  // until they exist.
  OnboardingStep.preview,
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
      // `age` covers both since O8 — it is the birth year when there is one and
      // the legacy stored age otherwise.
      return i.age != null ||
          i.birthYear != null ||
          i.gender != null ||
          i.heightCm != null ||
          i.weightCurrentKg != null ||
          i.weightTargetKg != null ||
          i.activityLevel != null;
    case OnboardingStep.body:
      // Either tab counts, and so does anything in the medical disclosure —
      // it is one screen, so one answer anywhere on it is a touch.
      if (p.goals.focusZones.isNotEmpty) return true;
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
      // Spelled out rather than `g.hasAny`, because since O6 `hasAny` also
      // counts `focusZones` — and those are answered on the BODY screen.
      // Reusing it here would mark this screen done because the user answered
      // a different one, and the resume point would skip past it unseen.
      return g.primary != null ||
          g.weightLoss ||
          g.muscleGain ||
          g.endurance ||
          g.strength ||
          g.flexibility ||
          g.generalFitness ||
          (g.specificSport?.isNotEmpty ?? false) ||
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
    case OnboardingStep.schedule:
      final s = p.schedule;
      return s.daysPerWeek != null ||
          s.sessionMinutes != null ||
          s.preferredWeekdays.isNotEmpty;
    case OnboardingStep.healthFlags:
      // "Touched", per this file's normal rule. Unlike the PAR-Q+ screen, a
      // partial answer here is usable: each field gates independently, and an
      // unanswered one is simply absent from the context rather than a hole in
      // a decision rule.
      return !p.health.flags.isUnanswered || p.health.flags.restrictions.isNotEmpty;
    case OnboardingStep.screening:
      // The one step where this asks "complete", not "touched", and the
      // departure from the rule above is deliberate.
      //
      // Everywhere else a partial answer is a real way to use the screen and
      // "touched" is what the CTA label needs. Here a partial answer is
      // exactly the state `screen()` refuses on, so reporting it as answered
      // would let `onboardingResumeIndex` walk a returning user straight past
      // the screen that is blocking them, to a preview that tells them to go
      // and finish it. Six of seven is not answered.
      return ParQQuestion.values.every(p.health.screening.containsKey);
    case OnboardingStep.preview:
      // Always "answered", because it asks nothing. The flag drives the CTA's
      // label, and offering to "Skip" the last screen would put the word on a
      // button that actually submits the questionnaire.
      //
      // It also keeps `onboardingResumeIndex` honest: a preview can never be
      // the first gap in the answers, so a returning user is never dropped onto
      // it while a real question above is still blank.
      return true;
    case OnboardingStep.barriers:
      final m = p.motivation;
      // `preferredDuration` is deliberately NOT tested here since O5. It is no
      // longer asked on this screen — it is derived from the schedule's
      // `sessionMinutes` — so counting it would mark this step answered
      // because the user filled in a different one.
      return m.barriers.isNotEmpty ||
          (m.motivation?.isNotEmpty ?? false) ||
          m.environments.isNotEmpty;
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
