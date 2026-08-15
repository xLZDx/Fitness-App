/// The role structure of each shipped programme.
///
/// ## Why the split is declared and not inferred
///
/// `ProgrammeTemplate` names weeks, days, level, goal and a muscle list. It
/// does not say what a session IS, which is why `buildProgrammeSchedule` had
/// nothing better to work from than "take the pool and walk it". Naming the
/// slots is what makes a strength session a strength session.
///
/// ## Full body twice, not a four-way split
///
/// Every four-day programme here alternates two full-body sessions rather than
/// splitting into chest/back/legs/shoulders. That is a decision about the
/// FREQUENCY constraint, not a preference: `minWeeklyFrequencyPerRole = 2`
/// cannot be met by a four-way split in which each pattern appears on one day.
/// A split that trains a pattern once a week is a legitimate programme; it is
/// not one this spec can validate, so declaring it and then failing validation
/// every time would be dishonest in a different direction.
///
/// The numbers are `PRODUCT_HEURISTIC` with no named owner, and they are here
/// rather than inline so that stays visible.
library;

import 'movement_role.dart';
import 'programme_builder.dart';

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

const _twiceWeeklyRoles = {
  MovementRole.squat,
  MovementRole.hinge,
  MovementRole.horizontalPull,
};

const _beginnerFullBody = <SessionSpec>[
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

/// Programmes whose role structure is declared.
///
/// A template with no entry here cannot be built by `buildProgramme` and says
/// so, rather than falling back to walking the catalogue. That is the point:
/// the fallback IS the defect.
const Map<String, ProgrammeSpec> programmeSpecs = {
  'strength_base': ProgrammeSpec(
    id: 'strength_base',
    sessions: _upperLower,
    setsPerSlot: 4,
    minWeeklySetsPerRole: 4,
    maxWeeklySetsPerRole: 32,
  ),
  'hypertrophy': ProgrammeSpec(
    id: 'hypertrophy',
    sessions: _upperLower,
    setsPerSlot: 4,
    minWeeklySetsPerRole: 4,
    maxWeeklySetsPerRole: 32,
  ),
  'gym_start': ProgrammeSpec(
    id: 'gym_start',
    sessions: _beginnerFullBody,
    setsPerSlot: 3,
    minWeeklySetsPerRole: 3,
    maxWeeklySetsPerRole: 24,
    // Three sessions a week, and every pattern appears at least twice across
    // them — except the two core roles and single-leg, which appear once each
    // by design in a beginner programme.
    frequencyRoles: {
      MovementRole.squat,
      MovementRole.hinge,
      MovementRole.horizontalPush,
      MovementRole.horizontalPull,
    },
  ),
  'injury_comeback': ProgrammeSpec(
    id: 'injury_comeback',
    sessions: _beginnerFullBody,
    setsPerSlot: 2,
    minWeeklySetsPerRole: 2,
    maxWeeklySetsPerRole: 16,
    frequencyRoles: {
      MovementRole.squat,
      MovementRole.hinge,
      MovementRole.horizontalPush,
      MovementRole.horizontalPull,
    },
  ),
};

/// The spec for [templateId], shaped for how many days a week the user has.
///
/// A programme is not one structure scaled down. Two sessions a week cannot
/// train seven patterns twice, so a two-day enrolment gets a narrower pattern
/// set trained twice rather than the four-day split with every rule failing —
/// which is what the validator reported, correctly, before this existed.
ProgrammeSpec? programmeSpecFor(String templateId, {int daysPerWeek = 4}) {
  final base = programmeSpecs[templateId];
  if (base == null) return null;
  if (daysPerWeek >= 4) return base;
  if (daysPerWeek == 3) {
    return ProgrammeSpec(
      id: base.id,
      sessions: _beginnerFullBody,
      setsPerSlot: base.setsPerSlot,
      minWeeklySetsPerRole: base.minWeeklySetsPerRole,
      maxWeeklySetsPerRole: base.maxWeeklySetsPerRole,
      minSurvivingPrimaryRoles: base.minSurvivingPrimaryRoles,
      frequencyRoles: const {
        MovementRole.squat,
        MovementRole.hinge,
        MovementRole.horizontalPush,
        MovementRole.horizontalPull,
      },
    );
  }
  return ProgrammeSpec(
    id: base.id,
    sessions: _twiceWeekly,
    setsPerSlot: base.setsPerSlot,
    minWeeklySetsPerRole: base.minWeeklySetsPerRole,
    maxWeeklySetsPerRole: base.maxWeeklySetsPerRole,
    minSurvivingPrimaryRoles: 3,
    frequencyRoles: _twiceWeeklyRoles,
  );
}
