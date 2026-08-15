/// Pre-exercise screening, and the state in which this app declines to hand
/// out a workout.
///
/// ## Why this exists
///
/// Before Gate M there was no such state. Every path that could produce a
/// session produced one: `buildPlan` filtered contraindicated exercises and
/// returned a plan, the onboarding preview returned a plan, the programme
/// scheduler returned a plan. A user who answered "my doctor said I should
/// only exercise under medical supervision" got the same output as a user who
/// answered nothing at all, because nothing read the answer and there was
/// nowhere for a refusal to go.
///
/// That is a product decision, not an oversight, and it was made explicitly on
/// 2026-08-15 with its cost stated: a screen that can refuse costs onboarding
/// conversion, and the operator accepted that cost rather than ship a fitness
/// app with no floor under it.
///
/// ## The instrument
///
/// The seven questions below are the PAR-Q+ general health questions
/// (Canadian Society for Exercise Physiology, `eparmedx.com`, 2024 revision).
/// They are used because they are a published, validated instrument with a
/// documented decision rule, not because they are the questions this app would
/// have invented. Where this file departs from the instrument it says so at
/// the point of departure.
///
/// PAR-Q+'s own rule: NO to all seven means the person may become more
/// physically active. YES to one or more sends them to the follow-up questions
/// on pages 2–3, or to a qualified exercise professional. This app does not
/// implement the follow-up pages — see [SafetyDecision.restricted].
///
/// ## What this file will never do
///
/// It never reads [HealthHistory.medications], [HealthHistory.conditions] or
/// [HealthHistory.otherConcerns] as text and decides what they mean. Deciding
/// that "metoprolol" is a beta blocker, and that a beta blocker caps heart
/// rate, and that the plan should therefore change, is clinical reasoning
/// performed by pattern-matching on a string. It is wrong in both directions —
/// it invents a contraindication the user does not have, and it misses one
/// they do because they spelled it differently — and the failure is silent.
///
/// The user is asked instead. Question 5 is the instrument's own way of asking
/// it: "are you taking prescribed medications for a chronic condition", a
/// yes/no the user can answer about themselves.
library;

/// The seven PAR-Q+ general health questions.
///
/// Names describe the question, not the answer. `chestPain` is "do you feel
/// pain in your chest…", so `true` means the symptom is present.
enum ParQQuestion {
  /// Q1 — "Has your doctor ever said that you have a heart condition OR high
  /// blood pressure?"
  heartConditionOrHighBloodPressure,

  /// Q2 — "Do you feel pain in your chest at rest, during your daily
  /// activities of living, OR when you do physical activity?"
  chestPain,

  /// Q3 — "Do you lose balance because of dizziness OR have you lost
  /// consciousness in the last 12 months?"
  dizzinessOrLossOfConsciousness,

  /// Q4 — "Have you ever been diagnosed with another chronic medical condition
  /// (other than heart disease or high blood pressure)?"
  otherChronicCondition,

  /// Q5 — "Are you currently taking prescribed medications for a chronic
  /// medical condition?"
  ///
  /// A yes/no the user answers about themselves. This app deliberately does
  /// not read the medication names it already stores and classify them — see
  /// the library doc.
  prescribedMedication,

  /// Q6 — "Do you currently have (or have had within the past 12 months) a
  /// bone, joint, or soft tissue problem that could be made worse by becoming
  /// more physically active?"
  musculoskeletalProblem,

  /// Q7 — "Has your doctor ever said that you should only do medically
  /// supervised physical activity?"
  medicallySupervisedOnly,
}

/// What the screen concluded.
enum SafetyDecision {
  /// NO to all seven. The instrument's own clearance.
  clear,

  /// YES to at least one question that PAR-Q+ routes to its follow-up pages.
  ///
  /// This app does not implement those pages, so it cannot reach the
  /// instrument's own "you may proceed" conclusion for these users. It does
  /// the next honest thing: it says which answer triggered it, tells the user
  /// the app has not cleared them, and requires an explicit acknowledgement
  /// before continuing at reduced intensity.
  ///
  /// This is a PRODUCT_HEURISTIC, not the instrument. Implementing the
  /// follow-up pages would let it be replaced with a real clearance decision.
  restricted,

  /// No workout is produced.
  ///
  /// Two ways to reach it, and they are different in kind:
  ///  - a [kBlockingQuestions] answer, where the honest output is a referral;
  ///  - an incomplete screen, because an unanswered question is not a "no".
  blocked,
}

/// The answers that stop a plan being produced at all.
///
/// Q7 is the instrument's: a person told to exercise only under medical
/// supervision is not someone a phone app supervises. Q2 is a PRODUCT
/// decision — PAR-Q+ routes chest pain to its follow-up pages rather than
/// halting, and this app treats "pain in your chest at rest" as the one
/// symptom it will not generate around, because the cost of being wrong is
/// asymmetric and the follow-up pages do not exist here.
///
/// Deliberately short. A screen that blocks on everything is a screen users
/// learn to lie to, and a lie makes every other answer worthless.
const Set<ParQQuestion> kBlockingQuestions = {
  ParQQuestion.chestPain,
  ParQQuestion.medicallySupervisedOnly,
};

/// One reason a verdict came out the way it did.
class SafetyReason {
  const SafetyReason.question(this.question) : incomplete = false;
  const SafetyReason.incomplete(this.question) : incomplete = true;

  /// The question responsible.
  final ParQQuestion question;

  /// True when the question was never answered, false when it was answered
  /// yes. These produce the same decision and must not produce the same
  /// message: "you told us X" and "you have not told us whether X" are
  /// different things to say to a person.
  final bool incomplete;

  @override
  bool operator ==(Object other) =>
      other is SafetyReason &&
      other.question == question &&
      other.incomplete == incomplete;

  @override
  int get hashCode => Object.hash(question, incomplete);

  @override
  String toString() =>
      'SafetyReason(${question.name}${incomplete ? ', unanswered' : ''})';
}

/// The screen's conclusion, and everything needed to explain it.
class SafetyVerdict {
  const SafetyVerdict({required this.decision, required this.reasons});

  final SafetyDecision decision;

  /// In declaration order of [ParQQuestion], so the same input always produces
  /// the same message. Empty exactly when [decision] is [SafetyDecision.clear].
  final List<SafetyReason> reasons;

  /// Whether a workout may be produced at all.
  bool get allowsTraining => decision != SafetyDecision.blocked;

  /// The intensity ceiling this verdict imposes, as a multiplier, or null when
  /// it imposes none.
  ///
  /// **Null, not 1.0.** The first version returned 1.0 for a clear screen, and
  /// a test caught what that did: the planner's own ceiling is 1.10, so a
  /// clean bill of health silently capped the user below where they were
  /// before this gate existed. "No opinion" and "an opinion that happens to be
  /// 1.0" are different claims, and a safety type that cannot express the
  /// first will keep making that mistake.
  ///
  /// `restricted` caps at 0.8. PRODUCT_HEURISTIC with no evidence behind the
  /// figure: there is no study saying "cap an unscreened user at 80%". What
  /// can be said is the direction — someone the app could not clear should not
  /// be pushed at the same intensity as someone it could — and that a cap is
  /// the only lever available, since the app cannot know which movements are
  /// the risk. Stated so it can be argued with.
  ///
  /// Owner: unassigned.
  double? get intensityCeiling =>
      decision == SafetyDecision.restricted ? 0.8 : null;

  @override
  String toString() => 'SafetyVerdict(${decision.name}, $reasons)';
}

/// Runs the screen. Pure; no I/O, no clock, no text interpretation.
///
/// **Fail-closed.** A question with no entry in [answers] produces
/// [SafetyDecision.blocked] with an `incomplete` reason, not a pass. This is
/// the whole design and it is the opposite of what every other optional field
/// in this app does — an unanswered goal means "no preference", an unanswered
/// injury means "none", and both defaults are harmless. An unanswered "does
/// your chest hurt" is not "no".
///
/// The practical consequence is that a user who skips the screen gets no
/// workout, which is the accepted conversion cost. The alternative — treat
/// silence as clearance — makes the screen decorative, and a decorative safety
/// screen is worse than none because the product then truthfully says it
/// screens.
SafetyVerdict screen(Map<ParQQuestion, bool> answers) {
  final blocking = <SafetyReason>[];
  final restricting = <SafetyReason>[];

  // Declaration order, not map order: `answers` may be any Map implementation,
  // and iteration order of a literal is insertion order, which is the caller's
  // business. The output order must be the app's.
  for (final q in ParQQuestion.values) {
    final answer = answers[q];
    if (answer == null) {
      blocking.add(SafetyReason.incomplete(q));
      continue;
    }
    if (!answer) continue;
    if (kBlockingQuestions.contains(q)) {
      blocking.add(SafetyReason.question(q));
    } else {
      restricting.add(SafetyReason.question(q));
    }
  }

  if (blocking.isNotEmpty) {
    // Blocking reasons first, then the restricting ones — the user is owed the
    // full picture, not only the first thing that stopped it. Both lists are
    // already in declaration order.
    return SafetyVerdict(
      decision: SafetyDecision.blocked,
      reasons: List.unmodifiable([...blocking, ...restricting]),
    );
  }
  if (restricting.isNotEmpty) {
    return SafetyVerdict(
      decision: SafetyDecision.restricted,
      reasons: List.unmodifiable(restricting),
    );
  }
  return const SafetyVerdict(decision: SafetyDecision.clear, reasons: []);
}

/// The verdict for a user who has not been screened at all.
///
/// Named rather than written as `screen(const {})` at each call site, because
/// the call sites are the places where someone would later be tempted to
/// substitute a permissive default.
final SafetyVerdict kUnscreened = screen(const {});
