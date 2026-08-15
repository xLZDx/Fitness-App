/// What an exercise DOES, as opposed to which muscle it names.
///
/// ## Why this is derived and not stored
///
/// Measured on the shipped catalogue: 1,887 rows, and the fields present on
/// every one of them are `id`, `title`, `equipmentId`, `equipmentLabel`,
/// `muscles`, `primaryMuscles`, `difficulty`, `durationMinutes`, `summary`,
/// `steps`, `video`, `isStretch`, `vendorGroup`, `poster`. There is no
/// `movementRole`, no `pattern`, and no field of any kind that distinguishes a
/// squat from a leg curl beyond the words in the title.
///
/// A programme built by movement role therefore needs one of two things: a
/// build-time tagging pass writing a new field into 1,887 rows, or a
/// deterministic derivation from the fields that exist. This is the second.
///
/// The precedent is `scripts/catalog/tag_contraindications.py`, which derives
/// injury regions from the vendor's own words with rules a reviewer can
/// disagree with row by row. The same reasoning applies and the same discipline
/// does: these are rules over the vendor's metadata, not a clinical or
/// coaching judgement, and where they cannot decide they return null rather
/// than guessing.
///
/// ## Null is a real answer
///
/// [movementRoleOf] returns null for a row it cannot classify. The programme
/// validator treats an unclassified candidate as ineligible for a role slot
/// rather than dropping it into the nearest one — a programme that fills its
/// "horizontal pull" slot with an unrecognised row has not met the requirement,
/// it has hidden that it did not.
///
/// ## Order matters
///
/// The rules are tried in the listed order and the first match wins. Mobility
/// first, because a "squat pose" from the yoga set is mobility work and not a
/// loaded squat; single-leg before squat, because a "split squat" contains the
/// word "squat" and is not one; vertical before horizontal for pressing,
/// because "shoulder press" and "bench press" both contain "press".
library;

import '../../equipment/data/equipment_models.dart';

/// The movement patterns a programme is built from.
enum MovementRole {
  /// Knee-dominant bilateral: squat, leg press, wall sit.
  squat,

  /// Hip-dominant: deadlift, hip thrust, back extension, swing.
  hinge,

  /// Pressing away from the chest: bench, push-up, dip, fly.
  horizontalPush,

  /// Pressing overhead.
  verticalPush,

  /// Pulling towards the torso: row, face pull, rear delt.
  horizontalPull,

  /// Pulling from overhead: pull-up, pulldown.
  verticalPull,

  /// One leg at a time: lunge, step-up, split squat.
  singleLeg,

  /// Loaded carries.
  carry,

  /// Resisting spinal flexion/extension: plank, hollow, dead bug, most
  /// abdominal work.
  coreAntiExtension,

  /// Resisting rotation: twists, chops, Pallof.
  coreAntiRotation,

  /// Single-joint work that supports the patterns above rather than being one.
  accessory,

  /// Stretching, yoga, mobility.
  mobility,

  /// Cardio, agility, plyometric and conditioning work.
  conditioning,
}

/// Roles a strength programme is built AROUND, as opposed to filled out with.
///
/// [MovementRole.accessory], [MovementRole.mobility] and
/// [MovementRole.conditioning] are deliberately absent: a session made only of
/// those is not a strength session, which is the failure the shipped
/// `strength_base` programme had.
const Set<MovementRole> kPrimaryStrengthRoles = {
  MovementRole.squat,
  MovementRole.hinge,
  MovementRole.horizontalPush,
  MovementRole.verticalPush,
  MovementRole.horizontalPull,
  MovementRole.verticalPull,
  MovementRole.singleLeg,
};

String _normalise(String? raw) {
  if (raw == null) return ' ';
  final buffer = StringBuffer(' ');
  for (final rune in raw.toLowerCase().runes) {
    final c = String.fromCharCode(rune);
    buffer.write(RegExp(r'[a-z0-9]').hasMatch(c) ? c : ' ');
  }
  buffer.write(' ');
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

bool _any(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(' $n ')) return true;
  }
  return false;
}

/// The role this exercise plays, or null when the rules cannot decide.
///
/// Pure and total. No I/O, no catalogue lookup — everything it reads is on the
/// row, which is what lets the coverage test run it over all 1,887 of them.
MovementRole? movementRoleOf(ExerciseItem e) {
  final t = _normalise(e.title);
  final group = e.vendorGroup;

  // 1. Mobility first. A "squat pose" is yoga, and letting the squat rule see
  //    it would put a hip-opener in a strength programme's squat slot.
  if (e.isStretch ||
      group == 'Stretching - Mobility' ||
      group == 'Yoga' ||
      _any(t, ['stretch', 'pose'])) {
    return MovementRole.mobility;
  }

  if (_any(t, ['twist', 'woodchop', 'chop', 'pallof', 'rotation', 'oblique'])) {
    return MovementRole.coreAntiRotation;
  }
  if (_any(t, ['plank', 'hollow', 'rollout']) ||
      t.contains(' dead bug ') ||
      t.contains(' ab wheel ') ||
      group == 'Abdominals') {
    return MovementRole.coreAntiExtension;
  }
  if (_any(t, ['carry', 'farmer', 'suitcase'])) return MovementRole.carry;

  // 2. Single-leg before squat: "split squat" and "step up" are not squats,
  //    and a programme that counts them as one has no unilateral work at all.
  if (_any(t, ['lunge', 'pistol', 'curtsy']) ||
      t.contains(' step up ') ||
      t.contains(' split squat ') ||
      t.contains(' bulgarian ') ||
      t.contains(' single leg ') ||
      t.contains(' step out ')) {
    return MovementRole.singleLeg;
  }
  if (_any(t, ['deadlift', 'swing', 'rdl', 'romanian', 'hyperextension']) ||
      t.contains(' hip thrust ') ||
      t.contains(' glute bridge ') ||
      t.contains(' good morning ') ||
      t.contains(' back extension ')) {
    return MovementRole.hinge;
  }
  if (_any(t, ['squat']) ||
      t.contains(' leg press ') ||
      t.contains(' wall sit ') ||
      t.contains(' box jump ')) {
    return MovementRole.squat;
  }

  // 3. Vertical before horizontal: both contain "press".
  if (t.contains(' overhead press ') ||
      t.contains(' shoulder press ') ||
      t.contains(' military press ') ||
      t.contains(' push press ') ||
      t.contains(' arnold press ') ||
      _any(t, ['handstand']) ||
      (t.contains(' press ') && group == 'Shoulders')) {
    return MovementRole.verticalPush;
  }
  if (t.contains(' pull up ') ||
      t.contains(' pullup ') ||
      t.contains(' chin up ') ||
      t.contains(' pulldown ') ||
      t.contains(' pull down ')) {
    return MovementRole.verticalPull;
  }
  if (t.contains(' bench press ') ||
      t.contains(' push up ') ||
      t.contains(' pushup ') ||
      t.contains(' chest press ') ||
      _any(t, ['dip', 'fly', 'flye']) ||
      (t.contains(' press ') && group == 'Chest')) {
    return MovementRole.horizontalPush;
  }
  if (_any(t, ['row']) ||
      t.contains(' face pull ') ||
      t.contains(' rear delt ') ||
      t.contains(' reverse fly ')) {
    return MovementRole.horizontalPull;
  }

  // 4. Whole vendor groups whose remaining rows are single-joint work.
  switch (group) {
    case 'Biceps':
    case 'Triceps':
    case 'Forearms':
    case 'Shoulders':
    case 'Chest':
    case 'Back':
    case 'Legs':
      return MovementRole.accessory;
    case 'Calisthenics-Cardio-Plyo-Functional':
      return MovementRole.conditioning;
    case 'Powerlifting':
      // Every powerlifting row not already caught by squat/hinge/push above is
      // a variant of one of them, and guessing which would put a rack pull in
      // a bench slot. Unclassified is the honest answer.
      return null;
  }
  return null;
}

/// Groups a catalogue by role, dropping what cannot be classified.
Map<MovementRole, List<ExerciseItem>> byMovementRole(
    Iterable<ExerciseItem> exercises) {
  final out = <MovementRole, List<ExerciseItem>>{};
  for (final e in exercises) {
    final role = movementRoleOf(e);
    if (role == null) continue;
    (out[role] ??= <ExerciseItem>[]).add(e);
  }
  return out;
}
