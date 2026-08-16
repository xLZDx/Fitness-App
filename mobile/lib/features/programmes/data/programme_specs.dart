/// The role structure of each shipped programme.
///
/// ## Why the split is declared and not inferred
///
/// `ProgrammeTemplate` names weeks, days, level, goal and a muscle list. It
/// does not say what a session IS, which is why the deleted
/// `buildProgrammeSchedule` had nothing better to work from than "take the
/// pool and walk it". Naming the slots is what makes a strength session a
/// strength session.
///
/// ## Two things, not one
///
/// A spec is a STRUCTURE (which movement patterns, on which day, how often a
/// week) and a DOSE (how many sets each slot carries, and the weekly band that
/// has to land in). They are decided by different things, so they are declared
/// separately here:
///
/// * the structure follows from **how many days a week** the person trains —
///   two sessions cannot train seven patterns twice, and this is not a matter
///   of which programme they picked;
/// * the dose follows from **which programme they picked** — `injury_comeback`
///   and `strength_base` can run the same four-day structure at deliberately
///   different volumes.
///
/// The first version of this file put both on one object per template, and
/// that is what shipped the `shred_endurance` defect G-E's own tests caught:
/// a five-day template carrying a four-session structure, so every week
/// repeated one session, and `duplicateSession` refused the enrolment for
/// every user whose eligible catalogue was too narrow to disguise it.
///
/// **The invariant this file exists to hold: a structure has exactly as many
/// sessions as the person has training days.** [_shapeFor] is total over the
/// day counts the app can actually produce and returns null outside them,
/// which enrolment reports as `noDeclaredStructure` rather than building
/// something whose weeks do not match each other.
///
/// The numbers are `PRODUCT_HEURISTIC` with no named owner, and they are here
/// rather than inline so that stays visible.
library;

import 'movement_role.dart';
import 'programme_builder.dart';
import 'programme_templates.dart' show kProfileProgrammeId;

/// One training day's movement patterns, named so a week can be assembled
/// from them.
///
/// Every shape below is built so that no two of its sessions declare the same
/// slots: `buildProgramme` refuses a week containing two identical sessions
/// (`ProgrammeFault.duplicateSession`), and with one session per training day
/// that check can only be satisfied structurally.
const _oneDay = <SessionSpec>[
  SessionSpec(name: 'A', slots: [
    MovementRole.squat,
    MovementRole.hinge,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
  ]),
];

/// Two sessions a week, both full-body.
///
/// Not a shrunken version of the four-day split, and the difference is the
/// whole reason this exists. `minWeeklyFrequencyPerRole = 2` is unachievable
/// for seven patterns across two sessions — the validator says so, correctly,
/// and the first version of this file then refused every two-day enrolment.
/// A real two-day programme narrows the pattern set instead: squat, hinge,
/// push and pull, each on both days.
const _twiceWeekly = <SessionSpec>[
  SessionSpec(name: 'A', slots: [
    MovementRole.squat,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
    MovementRole.hinge,
    MovementRole.coreAntiExtension,
  ]),
  SessionSpec(name: 'B', slots: [
    MovementRole.hinge,
    MovementRole.verticalPull,
    MovementRole.verticalPush,
    MovementRole.squat,
    MovementRole.horizontalPull,
  ]),
];

const _threeDayFullBody = <SessionSpec>[
  SessionSpec(name: 'A', slots: [
    MovementRole.squat,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
    MovementRole.coreAntiExtension,
  ]),
  SessionSpec(name: 'B', slots: [
    MovementRole.hinge,
    MovementRole.verticalPull,
    MovementRole.verticalPush,
    MovementRole.coreAntiExtension,
  ]),
  // Squat and hinge appear on this day as well, which is what makes the
  // three-day week reach twice-weekly exposure for the four patterns its
  // frequency rule names. The first draft put single-leg here instead and the
  // validator refused every three-day enrolment — correctly, because squat and
  // hinge each appeared once.
  SessionSpec(name: 'C', slots: [
    MovementRole.squat,
    MovementRole.hinge,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
  ]),
];

const _upperLower = <SessionSpec>[
  SessionSpec(name: 'A', slots: [
    MovementRole.squat,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
    MovementRole.coreAntiExtension,
  ]),
  SessionSpec(name: 'B', slots: [
    MovementRole.hinge,
    MovementRole.verticalPush,
    MovementRole.verticalPull,
    MovementRole.singleLeg,
  ]),
  SessionSpec(name: 'C', slots: [
    MovementRole.squat,
    MovementRole.verticalPull,
    MovementRole.horizontalPush,
    MovementRole.coreAntiRotation,
  ]),
  SessionSpec(name: 'D', slots: [
    MovementRole.hinge,
    MovementRole.horizontalPull,
    MovementRole.verticalPush,
    MovementRole.singleLeg,
  ]),
];

/// Five days: the four-day split plus a fifth day that re-exposes the four
/// patterns a five-day week has room to train three times.
///
/// G-E shipped `shred_endurance` (five days) on `_upperLower` (four sessions)
/// and the rolling session cursor then repeated one template every week. This
/// is the fifth session that mismatch needed.
const _fiveDay = <SessionSpec>[
  ..._upperLower,
  SessionSpec(name: 'E', slots: [
    MovementRole.squat,
    MovementRole.hinge,
    MovementRole.horizontalPush,
    MovementRole.horizontalPull,
  ]),
];

/// Six days. The sixth is the vertical/unilateral day, which is what the
/// five-day week trains only twice.
const _sixDay = <SessionSpec>[
  ..._fiveDay,
  SessionSpec(name: 'F', slots: [
    MovementRole.verticalPush,
    MovementRole.verticalPull,
    MovementRole.singleLeg,
    MovementRole.coreAntiExtension,
  ]),
];

/// A week's structure: the sessions plus the rules that structure can meet.
///
/// The frequency rule belongs here rather than on the programme because it is
/// a property of the shape — a two-day week cannot train seven patterns twice
/// no matter which programme is asking.
class _Shape {
  const _Shape(
    this.sessions, {
    this.minFrequency = 2,
    this.frequencyRoles = kPrimaryStrengthRoles,
    this.minSurvivingPrimaryRoles = 4,
  });

  final List<SessionSpec> sessions;
  final int minFrequency;
  final Set<MovementRole> frequencyRoles;
  final int minSurvivingPrimaryRoles;
}

/// The four patterns every full-body shape trains twice a week.
///
/// Single-leg, and both core roles, appear once — by design in a week with
/// three or fewer sessions, and asserting otherwise would refuse every such
/// enrolment.
const _fourPatterns = {
  MovementRole.squat,
  MovementRole.hinge,
  MovementRole.horizontalPush,
  MovementRole.horizontalPull,
};

/// The structure for a week of [daysPerWeek] sessions, or null when the app
/// has not declared one.
///
/// Null for 0 and for 7 or more. Neither is reachable from the product: the
/// questionnaire offers 2..6 (`step_schedule.dart`), `programmeDaysPerWeek`
/// floors at 1 and never raises the template's own figure, and the highest
/// shipped template is `shred_endurance` at 5. A stored row saying 7 is
/// therefore hand-written or from a build that no longer exists, and refusing
/// it is the honest answer — a seven-session structure is a training design
/// nobody here has made, and inventing one silently is the class of thing this
/// gate removed.
_Shape? _shapeFor(int daysPerWeek) {
  switch (daysPerWeek) {
    case 1:
      // One session cannot expose anything twice. The frequency rule drops to
      // once rather than the shape being refused: a single full-body day is a
      // real, if minimal, programme, and it is what a user who ticked one
      // weekday has asked for.
      return const _Shape(_oneDay,
          minFrequency: 1,
          frequencyRoles: _fourPatterns,
          minSurvivingPrimaryRoles: 3);
    case 2:
      return const _Shape(_twiceWeekly,
          frequencyRoles: {
            MovementRole.squat,
            MovementRole.hinge,
            MovementRole.horizontalPull,
          },
          minSurvivingPrimaryRoles: 3);
    case 3:
      return const _Shape(_threeDayFullBody, frequencyRoles: _fourPatterns);
    case 4:
      return const _Shape(_upperLower);
    case 5:
      return const _Shape(_fiveDay);
    case 6:
      return const _Shape(_sixDay);
    default:
      return null;
  }
}

/// How much work a programme puts in each slot, and the weekly band the total
/// has to land in.
///
/// Volume, not structure — see the library doc. `injury_comeback` and
/// `strength_base` run the same three- or four-day shape at deliberately
/// different doses, and that difference is the programme.
class _Dose {
  const _Dose({
    required this.setsPerSlot,
    required this.minWeeklySetsPerRole,
    required this.maxWeeklySetsPerRole,
  });

  final int setsPerSlot;
  final int minWeeklySetsPerRole;
  final int maxWeeklySetsPerRole;
}

/// Programmes this app can build.
///
/// A template with no entry here cannot be built and says so, rather than
/// falling back to walking the catalogue. That is the point: the fallback IS
/// the defect.
const Map<String, _Dose> _doses = {
  'strength_base': _Dose(
      setsPerSlot: 4, minWeeklySetsPerRole: 4, maxWeeklySetsPerRole: 32),
  'hypertrophy': _Dose(
      setsPerSlot: 4, minWeeklySetsPerRole: 4, maxWeeklySetsPerRole: 32),
  'gym_start': _Dose(
      setsPerSlot: 3, minWeeklySetsPerRole: 3, maxWeeklySetsPerRole: 24),
  'injury_comeback': _Dose(
      setsPerSlot: 2, minWeeklySetsPerRole: 2, maxWeeklySetsPerRole: 16),
  // G-E. The last three ids without a declared structure, and the whole reason
  // `buildProgrammeSchedule` still existed: no entry here routed the enrolment
  // to the alphabetical filler (F021) and its three-of-four day repetition
  // (F022).
  //
  // ## Why these declare a dose and not a bespoke split
  //
  // Designing a session split is a programming decision, not a refactor. The
  // shapes above were reviewed when they landed; inventing a purpose-built
  // shoulders/arms split here would put an unreviewed training design into the
  // app under cover of a defect fix, which is the kind of scope drift this
  // audit exists to catch.
  //
  // Reusing them is not a compromise on the emphasis the user asked for.
  // Emphasis arrives through RANKING, not through slot selection: enrolment
  // passes `programme.muscles` as the `rank` callback, which orders the
  // candidates inside each role. That is the design decision Gate P already
  // made and wrote down — "a user who asks for core work still needs a squat
  // in the squat slot" — so `shoulders_arms` gets shoulder and arm work first
  // within every slot while still being a programme rather than a list.
  //
  // A purpose-designed split for `shoulders_arms` remains a legitimate open
  // product question. It is left open deliberately rather than answered here.
  //
  // The band is wider than the four-day programmes': five sessions a week put
  // three exposures into the patterns a four-day week trains twice, so the
  // same per-slot figure produces a larger weekly total.
  'shred_endurance': _Dose(
      setsPerSlot: 3, minWeeklySetsPerRole: 3, maxWeeklySetsPerRole: 32),
  'shoulders_arms': _Dose(
      setsPerSlot: 3, minWeeklySetsPerRole: 3, maxWeeklySetsPerRole: 24),
  // The questionnaire-built programme. `programmeFromProfile` mints it with a
  // goal and level read from the answers, and its day count is whatever the
  // user ticked, so this is the id whose structure varies most — which is
  // exactly what [_shapeFor] is for.
  //
  // Sets sit between `gym_start`'s 3 and `strength_base`'s 4 at 3: this is
  // built for someone whose training history is whatever they typed, and the
  // lower figure is the recoverable direction to be wrong in.
  kProfileProgrammeId: _Dose(
      setsPerSlot: 3, minWeeklySetsPerRole: 3, maxWeeklySetsPerRole: 32),
};

/// The ids this app can build a programme for, in no particular order.
///
/// Exposed for the test that asserts every shipped `ProgrammeTemplate` has an
/// entry; nothing in `lib/` needs it.
Iterable<String> get programmeSpecIds => _doses.keys;

/// The spec for [templateId], shaped for how many days a week the user has.
///
/// A programme is not one structure scaled down, and it is not one structure
/// stretched either. Both directions were bugs: two sessions cannot train
/// seven patterns twice (the validator refused every two-day enrolment), and
/// five days on a four-session structure repeats a session every week (it
/// refused every five-day one). The shape is chosen by the day count and has
/// exactly that many sessions.
///
/// Null when the id is not one this app builds, or when [daysPerWeek] is
/// outside the range a structure has been declared for. Enrolment reports both
/// as `ProgrammeFault.noDeclaredStructure`.
ProgrammeSpec? programmeSpecFor(String templateId, {int daysPerWeek = 4}) {
  final dose = _doses[templateId];
  if (dose == null) return null;
  final shape = _shapeFor(daysPerWeek);
  if (shape == null) return null;
  return ProgrammeSpec(
    id: templateId,
    sessions: shape.sessions,
    setsPerSlot: dose.setsPerSlot,
    minWeeklySetsPerRole: dose.minWeeklySetsPerRole,
    maxWeeklySetsPerRole: dose.maxWeeklySetsPerRole,
    minWeeklyFrequencyPerRole: shape.minFrequency,
    frequencyRoles: shape.frequencyRoles,
    minSurvivingPrimaryRoles: shape.minSurvivingPrimaryRoles,
  );
}
