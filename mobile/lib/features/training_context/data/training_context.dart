import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../personalisation/data/recommendation_hints.dart' show isConditioningExercise;
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

const Set<String> _machineLabels = {
  'sled',
  'treadmill',
  'airbike',
  'ski ergometer',
  'stationary exercise bike',
  'hyperextension bench',
};

const Set<String> _barbellLabels = {
  'barbell',
  'bar',
  'ez bar',
  'trap bar',
  'fixed pole bar',
  'weight plate',
  'landmine',
  'smith machine',
};

const Set<String> _freeWeightLabels = {
  'dumbbells',
  'dumbbell',
  'kettlebells',
  'kettlebell',
};

/// Bar / rig kit that is found in a park as well as in a gym.
const Set<String> _outdoorKitLabels = {
  'pull up bar',
  'pull-up bar',
  'dip bar',
  'dip bars',
  'parallel bars',
  'rings',
  'suspension trainer',
  'trx',
  'dip pull up station',
  'dip station',
  'gymnastic rings',
  'parallettes',
};

/// Title words of movements that suit a park: running, jumping, calisthenics.
///
/// Word-boundary match at the start of a word (so "Crunch" and "Trunk" do not
/// match "run"), with an optional plural / -ing / -s ending.
final RegExp _outdoorTitle = RegExp(
  r'\b(run(s|ning)?|sprint(s|ing)?|jump(s|ing)?|burpees?|pull[- ]?ups?|'
  r'chin[- ]?ups?|dips?|push[- ]?ups?|lunges?|mountain climbers?|skipping|'
  r'bear crawls?)\b',
  caseSensitive: false,
);

/// Equipment ids that are machines in the shipped catalogue
/// (`assets/data/exercises_vendor.json`, 1887 rows). Consulted only when no
/// label class matched; the vendor label wins otherwise.
const Set<String> _machineEquipmentIds = {
  'cable_machine',
  'lat_pulldown',
  'ski_erg',
  'smith_machine',
  'chest_press_machine',
  'leg_press',
  'back_extension',
  'assisted_pullup_machine',
  'leg_curl',
  'seated_row_machine',
  'bicep_curl_machine',
  'leg_extension',
  'pec_deck',
  'hip_abductor_adductor',
  'air_bike',
  'elliptical',
  'rowing_machine',
  'shoulder_press_machine',
  'treadmill',
  'hack_squat_machine',
  'seated_dip_machine',
  'weighted_sled',
  'ab_crunch_machine',
  'lateral_raise_machine',
  'multi_hip_machine',
  'calf_raise_machine',
  'exercise_bike',
  'stair_climber',
  'tricep_extension_machine',
  'sissy_squat_machine',
};

/// How well [item] suits [context], as a signed preference: higher is better,
/// 0 is neutral. Used ONLY to order candidates that already passed every hard
/// filter (equipment, injuries, age, difficulty); it never admits or removes
/// anything, so a strongly negative value means "later", not "excluded".
///
/// Pure and deterministic; derived from existing [ExerciseItem] fields only.
/// [access] is the equipment answer for [context] (see [equipmentAccessFor]);
/// it is read for [TrainingContext.home] only, and may be null.
///
/// Weights (a stretch / mobility / yoga item is always 0 here, so goal and age
/// logic about mobility keeps deciding those):
///
/// * gymMachines: machine / cable / cardio machine +3, barbell +3,
///   dumbbell / kettlebell +2, other loaded kit +1.5, bands / portable 0,
///   bodyweight -3.
/// * home: kit the person owns +3 (an item that needs equipment and is
///   available with [access]), bodyweight +1.5, mat / floor work +0.5 extra,
///   anything not available -3.
/// * outdoorMinimal: bodyweight +2, jump rope +3, bands / portable +2,
///   dumbbell / kettlebell +1, outdoor kit (pull-up / dip bar) +2, other
///   loaded kit -1, barbell -3, machine / cable -4; plus +2 for outdoor-friendly
///   movements (conditioning group or a running / jumping / calisthenics
///   title).
/// * yoga or null context: 0 (current behaviour).
double contextAffinity(
  ExerciseItem item,
  TrainingContext? context,
  EquipmentAccess? access,
) {
  if (context == null || context == TrainingContext.yoga) return 0;
  if (item.isStretch) return 0;

  final label = item.equipmentLabel?.toLowerCase().trim() ?? '';
  final parts = label.isEmpty
      ? const <String>[]
      : label.split(',').map((p) => p.trim()).toList(growable: false);
  bool any(bool Function(String) test) => parts.any(test);

  final bodyweight = !item.needsEquipment;
  // Label classes first: the vendor label says what is physically used. An
  // "equipmentId" alone is NOT a machine signal (dumbbell, barbell, bands, trx,
  // pullup_bar and skipping_rope are all ids too).
  final labelMachine = any((p) =>
      p.contains('machine') ||
      (p.contains('cable') && !p.contains('resistance')) ||
      _machineLabels.contains(p));
  final barbell = any(_barbellLabels.contains);
  final freeWeight = any(_freeWeightLabels.contains);
  final portable = !bodyweight &&
      !labelMachine &&
      parts.isNotEmpty &&
      parts.every((p) => _portableLabels.contains(p) || p == 'resistance cable');
  final outdoorKit = any(_outdoorKitLabels.contains);
  final labelClassified =
      labelMachine || barbell || freeWeight || portable || outdoorKit;
  // Only when no label class matched does the id decide, and only for ids that
  // are machines in the shipped catalogue.
  final machine = labelMachine ||
      (!bodyweight &&
          !labelClassified &&
          _machineEquipmentIds.contains(item.equipmentId));

  switch (context) {
    case TrainingContext.yoga:
      return 0;
    case TrainingContext.gymMachines:
      if (bodyweight) return -3;
      if (machine || barbell) return 3;
      if (freeWeight) return 2;
      if (portable) return 0;
      return 1.5;
    case TrainingContext.home:
      if (access != null && !isAvailableWith(item, access)) return -3;
      var v = bodyweight ? 1.5 : 3.0;
      if (any((p) => p.contains('mat'))) v += 0.5;
      return v;
    case TrainingContext.outdoorMinimal:
      var v = 0.0;
      if (bodyweight) {
        v = 2;
      } else if (machine) {
        v = -4;
      } else if (barbell) {
        v = -3;
      } else if (parts.contains('jump rope')) {
        v = 3;
      } else if (portable) {
        v = 2;
      } else if (outdoorKit) {
        v = 2;
      } else if (freeWeight) {
        v = 1;
      } else {
        v = -1;
      }
      if (isConditioningExercise(item) ||
          _outdoorTitle.hasMatch(item.title)) {
        v += 2;
      }
      return v;
  }
}

/// Orders [pool] for a programme slot: [contextAffinity] first (best first),
/// then exercises that hit a [focus] muscle, then the incoming pool order.
///
/// Always a permutation of [pool]; nothing is added or dropped. Deterministic:
/// the sort is keyed on the original index, so ties never depend on the
/// (unstable) sort algorithm. With a null [context] and an empty [focus] the
/// input order is returned unchanged.
List<ExerciseItem> rankForContext(
  List<ExerciseItem> pool, {
  required Set<String> focus,
  required TrainingContext? context,
  required EquipmentAccess? access,
}) {
  bool hitsFocus(ExerciseItem e) =>
      focus.isNotEmpty &&
      (e.primaryMuscles.any(focus.contains) || e.muscles.any(focus.contains));
  final keyed = [
    for (var i = 0; i < pool.length; i++)
      (
        item: pool[i],
        index: i,
        affinity: contextAffinity(pool[i], context, access),
        focus: hitsFocus(pool[i]),
      ),
  ];
  keyed.sort((a, b) {
    if (a.affinity != b.affinity) return b.affinity.compareTo(a.affinity);
    if (a.focus != b.focus) return a.focus ? -1 : 1;
    return a.index.compareTo(b.index);
  });
  return [for (final k in keyed) k.item];
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
