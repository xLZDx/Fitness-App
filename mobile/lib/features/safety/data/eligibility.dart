/// One place that decides whether a person may be shown a given piece of work,
/// and one vocabulary for saying why not.
///
/// ## The problem this replaces
///
/// Every surface decided separately. The planner filtered injuries; the home
/// feed filtered injuries differently; the programme scheduler filtered
/// nothing; the catalogue let a user tap straight into an exercise that all
/// three would have hidden. Gate M then added a screening check to three of
/// them, which made four independent opinions instead of three.
///
/// The failure mode is not that any one of them is wrong. It is that a rule
/// added to one is absent from the others, silently, and the only way to notice
/// is to try every screen.
///
/// ## Reasons are values, not sentences
///
/// [BlockReason] is an enum with a payload, not a string. Three consumers need
/// the same decision in different words — a card on the home tab, a full screen
/// in onboarding, a line in a plan's rationale — and a fourth needs it in a
/// test. English in the middle of that makes the test assert on copy and the
/// copy unable to change.
library;

import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../profile/data/profile_models.dart';
import 'health_flags.dart';
import 'par_q.dart';


/// Why a candidate was blocked or degraded.
enum BlockReason {
  /// Gate M: the pre-exercise screen refused, or was never completed.
  screening,

  /// An injury the user reported matches a region this exercise loads.
  injury,

  /// A movement restriction the user reported matches a region this exercise
  /// loads.
  movementRestriction,

  /// The user is under post-operative restrictions.
  postSurgical,

  /// A clinician advised against exercise.
  clinicianAdvice,

  /// The user does not have the equipment.
  equipment,

  /// The Form Coach cannot judge this movement.
  ///
  /// Never blocks the exercise itself — only entry into a form-coaching
  /// session, which is a different request.
  formCoachUnsupported,

  /// The user reported a restriction the catalogue carries no tag for, so
  /// nothing was filtered for it.
  ///
  /// The only reason that is an ADVISORY rather than a decision: it never
  /// removes a candidate, because there is nothing to remove it by. It exists
  /// so the surface can say what was not checked.
  unscreenableRestriction,
}

/// A machine-readable reason, with enough detail to render a sentence.
class EligibilityReason {
  const EligibilityReason(this.reason,
      {this.regionTag, this.restriction, this.question, this.unanswered = false});

  final BlockReason reason;

  /// The PAR-Q+ question responsible, when [reason] is [BlockReason.screening].
  ///
  /// Carried rather than collapsed to a bare "screening": a refusal that cannot
  /// say WHICH answer caused it cannot be corrected by the person it is about,
  /// which is the whole reason Gate M kept its own reasons structured.
  final ParQQuestion? question;

  /// True when [question] was never answered rather than answered yes.
  final bool unanswered;

  /// The `contraindications` tag that matched, when there is one.
  final String? regionTag;

  /// The restriction responsible, when [reason] is
  /// [BlockReason.movementRestriction] or
  /// [BlockReason.unscreenableRestriction].
  final MovementRestriction? restriction;

  @override
  bool operator ==(Object other) =>
      other is EligibilityReason &&
      other.reason == reason &&
      other.regionTag == regionTag &&
      other.restriction == restriction &&
      other.question == question &&
      other.unanswered == unanswered;

  @override
  int get hashCode =>
      Object.hash(reason, regionTag, restriction, question, unanswered);

  @override
  String toString() => 'EligibilityReason(${reason.name}'
      '${regionTag != null ? ', $regionTag' : ''}'
      '${restriction != null ? ', ${restriction!.name}' : ''})';
}

/// What the eligibility layer concluded about one candidate.
sealed class Eligibility {
  const Eligibility();

  /// Whether the candidate may be shown.
  ///
  /// True for [Degraded] as well as [Allowed], and the name is deliberately
  /// "allowed" rather than "is Allowed": a caveat about what could NOT be
  /// checked must not remove an exercise, because there is nothing to remove it
  /// by. A test caught the first version, which filtered every candidate out
  /// for a user whose only restriction was one the catalogue cannot express —
  /// the honest advisory turned into a silently empty catalogue.
  bool get isAllowed => this is! Blocked;

  /// Reasons, empty for [Allowed].
  List<EligibilityReason> get reasons => const [];
}

/// Show it.
final class Allowed extends Eligibility {
  const Allowed();
}

/// Show it, but something about it could not be checked.
///
/// Distinct from [Allowed] so a surface can attach a caveat, and distinct from
/// [Blocked] so an unscreenable restriction does not empty the catalogue.
final class Degraded extends Eligibility {
  const Degraded(this._reasons);
  final List<EligibilityReason> _reasons;

  @override
  List<EligibilityReason> get reasons => _reasons;
}

/// Do not show it.
final class Blocked extends Eligibility {
  const Blocked(this._reasons);
  final List<EligibilityReason> _reasons;

  @override
  List<EligibilityReason> get reasons => _reasons;
}

/// Everything an eligibility decision is allowed to read.
///
/// Assembled once per surface, from providers, and passed down. It carries the
/// normalised [HealthFlags] rather than `HealthHistory` on purpose: the free
/// text is not in scope here, and a type that does not contain it cannot grow a
/// rule that reads it.
class SafetyContext {
  const SafetyContext({
    required this.screening,
    this.injuries = const [],
    this.health = HealthFlags.empty,
    this.equipment,
  });

  /// Gate M's verdict.
  final SafetyVerdict screening;

  final List<Injury> injuries;
  final HealthFlags health;

  /// What the user can train with, or null to skip the question entirely.
  ///
  /// Null means "this surface is not a recommendation" — the catalogue browse
  /// legitimately shows a gym machine to someone at home, because looking is
  /// not being prescribed. Every surface that RECOMMENDS passes it.
  ///
  /// `EquipmentAccess` rather than a set of ids, so the decision runs through
  /// `isAvailableWith` — the one implementation, with its "nothing selected is
  /// two different answers" rule and its 89 self-contradicting catalogue rows
  /// already reasoned about. A set of ids here would have been a second, worse
  /// copy of that.
  final EquipmentAccess? equipment;

  /// The unscreenable-restriction advisories for this user.
  ///
  /// A property of the person, not of any exercise, which is why it is here and
  /// not in a per-candidate verdict.
  List<EligibilityReason> get advisories => [
        for (final r in health.unenforceableRestrictions)
          EligibilityReason(BlockReason.unscreenableRestriction, restriction: r),
      ];

  /// Whether ANY training may be produced for this person.
  ///
  /// The whole-person gate, evaluated before any candidate is looked at. Three
  /// states reach it, and all three are stated rather than inferred:
  /// the screening refused; a clinician advised against exercise; the user is
  /// under post-operative restrictions.
  List<EligibilityReason> get wholePersonBlocks => [
        if (!screening.allowsTraining)
          for (final r in screening.reasons)
            EligibilityReason(BlockReason.screening,
                question: r.question, unanswered: r.incomplete),
        if (health.clinicianAdvice ==
            ClinicianExerciseAdvice.advisedAgainstExercise)
          const EligibilityReason(BlockReason.clinicianAdvice),
        if (health.surgery == SurgeryStatus.underRestrictions)
          const EligibilityReason(BlockReason.postSurgical),
      ];

  bool get allowsAnyTraining => wholePersonBlocks.isEmpty;

  /// The intensity ceiling this context imposes, or null for none.
  ///
  /// Composed from the screening verdict and the health answers by taking the
  /// LOWEST opinion. Reasons that cannot say which movements are risky can
  /// still say the dose should be smaller, and that is the only lever available
  /// without inventing clinical knowledge.
  ///
  /// PRODUCT_HEURISTIC throughout. Owner: unassigned. The figures are stated so
  /// they can be argued with; what is defensible is their ORDER, not their
  /// value.
  double? get intensityCeiling {
    final candidates = <double>[
      if (screening.intensityCeiling != null) screening.intensityCeiling!,
      // Uncertainty about blood pressure is not a clean bill of health, and a
      // diagnosis being managed still warrants less than an unrestricted one.
      if (health.bloodPressure == BloodPressureStatus.diagnosedHigh ||
          health.bloodPressure == BloodPressureStatus.diagnosedLow ||
          health.bloodPressure == BloodPressureStatus.unsure)
        0.8,
      if (health.bloodPressure == BloodPressureStatus.managedWithClinician) 0.9,
      if (health.clinicianAdvice == ClinicianExerciseAdvice.limitsGiven) 0.8,
      // Cleared, but the user has never asked anyone: the commonest state, and
      // a small margin rather than a penalty.
      if (health.clinicianAdvice == ClinicianExerciseAdvice.notAsked) 0.95,
      if (health.surgery == SurgeryStatus.unsure) 0.8,
    ];
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a < b ? a : b);
  }
}

/// The one decision. Every surface calls this and nothing else.
///
/// [forFormCoaching] adds the Form Coach's own capability check. It is a
/// separate request — "may I be shown this exercise" and "may I be coached
/// through it by the camera" have different answers, and folding them together
/// would hide 1,347 perfectly safe exercises from the catalogue because the
/// pose targets for them have not been authored.
Eligibility evaluateExercise(
  ExerciseItem exercise,
  SafetyContext context, {
  bool forFormCoaching = false,
  bool Function(ExerciseItem)? formCoachSupports,
  /// Whether to fold [SafetyContext.wholePersonBlocks] into the verdict.
  ///
  /// True when the question is "may this person do THIS, right now" — a deep
  /// link, a tap from the catalogue, a scheduled session about to start. False
  /// when the question is "which of these are suitable for this person", where
  /// the whole-person answer is constant across every candidate and folding it
  /// in produces an empty list where a stated refusal belongs.
  bool includeWholePerson = true,
}) {
  final blocks = <EligibilityReason>[];

  // 1. The whole-person gate. Nothing about the exercise can lift it.
  if (includeWholePerson) blocks.addAll(context.wholePersonBlocks);

  // 2. Injuries — the existing filter, reused rather than re-implemented. Its
  //    exact/substring matching rules are the moat and there must be one copy.
  if (isContraindicated(exercise, context.injuries)) {
    blocks.add(const EligibilityReason(BlockReason.injury));
  }

  // 3. Movement restrictions, via the same tag vocabulary.
  for (final tag in exercise.contraindications) {
    for (final r in context.health.restrictions) {
      if (r.regionTags.contains(tag)) {
        blocks.add(EligibilityReason(BlockReason.movementRestriction,
            regionTag: tag, restriction: r));
      }
    }
  }

  // 4. Equipment, through the one implementation.
  final access = context.equipment;
  if (access != null && !isAvailableWith(exercise, access)) {
    blocks.add(const EligibilityReason(BlockReason.equipment));
  }

  // 5. Form-coach capability, only when that is what was asked.
  if (forFormCoaching &&
      formCoachSupports != null &&
      !formCoachSupports(exercise)) {
    blocks.add(const EligibilityReason(BlockReason.formCoachUnsupported));
  }

  if (blocks.isNotEmpty) return Blocked(List.unmodifiable(blocks));

  final advisories = context.advisories;
  if (advisories.isNotEmpty) return Degraded(List.unmodifiable(advisories));
  return const Allowed();
}

/// Why this person may not be given any work at all.
///
/// `PlanRefused` originally carried Gate M's `SafetyReason` — the PAR-Q+
/// vocabulary. Gate N added two more ways to be refused, a clinician's stated
/// advice and unexpired post-operative restrictions, and neither has a PAR-Q+
/// question behind it. Keeping the narrow type would have meant silently
/// dropping the reason for two of the three refusals the app can now issue.
List<EligibilityReason> safetyReasonsFrom(SafetyContext context) =>
    List.unmodifiable(context.wholePersonBlocks);

/// Every allowed candidate, in input order.
///
/// [Degraded] counts as allowed — an unscreenable restriction removes nothing,
/// because there is nothing to remove it by. The caveat travels separately, via
/// [SafetyContext.advisories], so that a surface renders it once rather than
/// once per card.
///
/// ## This does NOT enforce the whole-person gate, and that is the design
///
/// The first version returned `const []` when [SafetyContext.allowsAnyTraining]
/// was false. It made the Train tab render an empty catalogue to any user who
/// had not completed the screening — no exercises, no reason, no way to act.
/// That is the exact failure this whole layer exists to remove: a silent empty
/// list instead of a stated refusal.
///
/// So the two gates are split by KIND, not by caller:
///
///  * the whole-person gate ([SafetyContext.allowsAnyTraining]) is a SCREEN
///    STATE. A surface checks it and renders a refusal that names the reason.
///  * this function is the per-candidate filter. It removes exercises that are
///    wrong for this person, and says nothing about whether this person may
///    train at all.
///
/// A generator must do both — `buildPlan` refuses on the first before it looks
/// at a pool — and a feed must do both too, by rendering the refusal instead of
/// the list. Neither may do only this one.
List<ExerciseItem> eligibleExercises(
  Iterable<ExerciseItem> exercises,
  SafetyContext context, {
  bool forFormCoaching = false,
  bool Function(ExerciseItem)? formCoachSupports,
}) {
  return [
    for (final e in exercises)
      if (evaluateExercise(e, context,
              forFormCoaching: forFormCoaching,
              formCoachSupports: formCoachSupports,
              includeWholePerson: false)
          .isAllowed)
        e,
  ];
}
