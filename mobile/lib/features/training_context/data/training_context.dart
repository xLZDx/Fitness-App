import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../profile/data/profile_models.dart';
import '../../safety/data/eligibility.dart';

/// What a recommendation is FOR: where the session happens, or (for yoga) that
/// it is not tied to a place at all.
///
/// Asked at recommendation time rather than inferred from the onboarding
/// location answer, because the same person trains at a gym on Monday and in a
/// park on Saturday. The profile's own equipment answers stay the fallback when
/// the question is skipped.
enum TrainingContext {
  /// A gym: machines and free weights.
  gymMachines,

  /// Outdoors, no machines: bodyweight plus a small portable kit.
  outdoorMinimal,

  /// At home: bodyweight plus whatever the profile says the user owns.
  home,

  /// Yoga as a separate mode, NOT tied to a place or to equipment.
  yoga,
}

/// The stored answer to "what is this training for".
///
/// Three states, because "never asked" and "asked, chose to skip" are different
/// facts: the first shows the chooser before generating anything, the second
/// must not nag again and behaves exactly as the app did before the question
/// existed (the profile's own equipment answers decide).
class TrainingContextAnswer {
  const TrainingContextAnswer._(this.context, this.answered);

  /// Never asked. Surfaces show the chooser and generate nothing yet.
  static const unanswered = TrainingContextAnswer._(null, false);

  /// Asked and skipped: use the profile's equipment answers, as before.
  static const skipped = TrainingContextAnswer._(null, true);

  const TrainingContextAnswer.chosen(TrainingContext this.context)
      : answered = true;

  /// The chosen context, or null for [unanswered] / [skipped].
  final TrainingContext? context;
  final bool answered;

  @override
  bool operator ==(Object other) =>
      other is TrainingContextAnswer &&
      other.context == context &&
      other.answered == answered;

  @override
  int get hashCode => Object.hash(context, answered);

  @override
  String toString() => answered
      ? (context == null ? 'skipped' : 'chosen(${context!.name})')
      : 'unanswered';
}

/// Portable kit that counts as "minimal" outdoors, by the vendor's exact
/// lower-cased equipment label (the same exact-match rule `exercise_filter.dart`
/// uses, never substring). Bands are covered separately through
/// [EquipmentKind.bands]; the rest are the examples the product named: balls
/// and a jump rope.
const Set<String> _portableLabels = {
  'resistance band',
  'loop resistance band',
  'exercise ball',
  'stability ball',
  'medicine ball',
  'jump rope',
};

/// The vendor groups that ARE yoga / stretching / mobility work.
const Set<String> _yogaGroups = {'Yoga', 'Stretching - Mobility'};

/// Yoga, stretch and mobility work, regardless of what it needs. A yoga block
/// or strap is not a reason to withhold a pose.
bool isYogaExercise(ExerciseItem e) =>
    e.isStretch || (e.vendorGroup != null && _yogaGroups.contains(e.vendorGroup));

/// The equipment answer a [context] stands for, derived from the profile's own
/// [profileAccess]. Null for [TrainingContext.yoga], which ignores equipment
/// and place entirely, and for a null [context] it returns [profileAccess]
/// untouched (today's behaviour).
///
/// * gymMachines: a gym has machines and free weights, so everything is
///   available. Choosing it for a session is the user's statement that they
///   are at a gym, whatever the onboarding answer said.
/// * home: the profile's own kit and nothing else. A gym / mixed location or a
///   `fullGym` chip is NOT carried over: today is a home day. No answers at all
///   means bodyweight only, never "everything".
/// * outdoorMinimal: bodyweight, plus portable kit (see [_portableLabels]),
///   plus the carriable weights the profile says it owns (dumbbells,
///   kettlebells). Machines, barbells and benches are never outdoors.
EquipmentAccess? equipmentAccessFor(
  TrainingContext? context,
  EquipmentAccess? profileAccess,
) {
  switch (context) {
    case null:
      return profileAccess;
    case TrainingContext.yoga:
      return null;
    case TrainingContext.gymMachines:
      return const EquipmentAccess(location: TrainingLocation.gym);
    case TrainingContext.home:
      final owned = (profileAccess?.available ?? const <EquipmentKind>[])
          .where((k) => k != EquipmentKind.fullGym)
          .toList(growable: false);
      return EquipmentAccess(
        location: TrainingLocation.home,
        available: owned,
        homeEquipment: profileAccess?.homeEquipment ?? const [],
      );
    case TrainingContext.outdoorMinimal:
      final owned = profileAccess?.available ?? const <EquipmentKind>[];
      return EquipmentAccess(
        location: TrainingLocation.outdoor,
        available: [
          EquipmentKind.bands,
          if (owned.contains(EquipmentKind.dumbbells)) EquipmentKind.dumbbells,
          if (owned.contains(EquipmentKind.kettlebells))
            EquipmentKind.kettlebells,
        ],
      );
  }
}

/// Whether [e] is allowed in [context] on its equipment (and, for yoga, on its
/// kind). Does not look at injuries or age: those stay in the safety context.
bool allowedInTrainingContext(
  ExerciseItem e,
  TrainingContext? context,
  EquipmentAccess? profileAccess,
) {
  if (context == TrainingContext.yoga) return isYogaExercise(e);
  final access = equipmentAccessFor(context, profileAccess);
  if (access == null) return true;
  if (isAvailableWith(e, access)) return true;
  if (context == TrainingContext.outdoorMinimal) return _isPortableOnly(e);
  return false;
}

/// An exercise whose whole kit is portable (balls, jump rope, bands) and that
/// does not also name a machine id.
bool _isPortableOnly(ExerciseItem e) {
  if (e.equipmentId != null) return false;
  final label = e.equipmentLabel;
  if (label == null || label.trim().isEmpty) return false;
  return label
      .split(',')
      .every((p) => _portableLabels.contains(p.trim().toLowerCase()));
}

/// The safety context a recommendation under [context] must use: identical to
/// [base] (injuries, screening, age band, gentle selection and the difficulty
/// ceiling all kept) except that the equipment question is answered by
/// [narrowToTrainingContext] on the pool, so it is dropped here (the profile's
/// own equipment answer would otherwise reject a jump rope or a yoga strap the
/// context allows). Null context returns [base] itself.
///
/// Every field of [SafetyContext] other than `equipment` is copied. The first
/// version omitted `maxDifficulty`, so a beginner who chose a context lost the
/// "nothing above your level" ceiling and the plan and programme builders could
/// hand them advanced work; a test now pins every field.
SafetyContext safetyContextForTrainingContext(
  SafetyContext base,
  TrainingContext? context,
) {
  if (context == null) return base;
  return SafetyContext(
    screening: base.screening,
    injuries: base.injuries,
    health: base.health,
    equipment: null,
    ageBand: base.ageBand,
    gentleSelection: base.gentleSelection,
    maxDifficulty: base.maxDifficulty,
  );
}

/// The pool narrowed to what [context] allows (kind for yoga, equipment for the
/// rest). Pair with [safetyContextForTrainingContext] when the caller runs the
/// eligibility layer itself (the plan builder does).
List<ExerciseItem> narrowToTrainingContext(
  Iterable<ExerciseItem> pool,
  SafetyContext safety,
  TrainingContext? context,
) {
  if (context == null) return pool.toList(growable: false);
  return [
    for (final e in pool)
      if (allowedInTrainingContext(e, context, safety.equipment)) e,
  ];
}

/// The one entry point recommendation surfaces call: the pool narrowed to the
/// context, then through the same eligibility layer as before (injuries, age
/// policy, screening all still apply in every context).
///
/// With a null [context] this is exactly `eligibleExercises(pool, safety)`.
List<ExerciseItem> eligibleForTrainingContext(
  Iterable<ExerciseItem> pool,
  SafetyContext safety,
  TrainingContext? context,
) {
  if (context == null) return eligibleExercises(pool, safety);
  return eligibleExercises(
    narrowToTrainingContext(pool, safety, context),
    safetyContextForTrainingContext(safety, context),
  );
}
