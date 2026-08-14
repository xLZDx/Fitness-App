import '../../equipment/data/equipment_models.dart' show ExerciseDifficulty;
import 'programme.dart';

/// The catalogue a user enrols FROM. [Programme] is one user's enrolment;
/// this is the offer.
///
/// Source: the real Figma Make prototype's `PROGRAMS` constant
/// (`App.tsx:4726-4733`, `xLZDx/ReviewExistingExamples` @ `8209787`) — six
/// programmes, title/weeks/days/level/goal/muscles each. Two fields are
/// deliberately NOT a verbatim copy of the prototype's:
///
/// * **level** — the prototype uses four free-text levels including "Любой"
///   ("any"). This app already has a three-tier vocabulary
///   (`ExerciseDifficulty`, shared with every exercise in the catalogue);
///   reusing it means a programme card and an exercise card never disagree
///   about what "intermediate" means. "Любой" (the injury-comeback
///   programme) maps to `beginner` — the gentlest tier, which is what a
///   comeback programme should default new users into regardless of their
///   general training level.
/// * **muscles** — the prototype's tags include "Всё тело" (full body) and
///   "Кардио" (cardio), neither of which is a muscle the catalogue tags
///   exercises with (`kFilterMuscles`, `workouts_page.dart`). An empty list
///   here means "full body / no muscle filter" ([ProgrammeTemplate.isFullBody]);
///   "Кардио" is represented by its nearest real muscle tag (`core`) rather
///   than invented, since inventing a `cardio` muscle key would make this
///   catalogue disagree with the one everything else in the app reads.
/// **Titles are NOT here.** They live in the ARB files and are resolved by
/// [ProgrammeLabels] (`programme_labels.dart`) from [id]. Until 2026-08-13 each
/// template carried its title as a Russian string literal, so an English UI
/// rendered "Силовая база" under the header "Current programme" — which is what
/// the operator photographed. Same rule as the exercise catalogue: the data
/// layer keeps a stable English key, only the label is translated.
class ProgrammeTemplate {
  const ProgrammeTemplate({
    required this.id,
    required this.goal,
    required this.level,
    required this.weeks,
    required this.daysPerWeek,
    this.muscles = const [],
  });

  final String id;
  final ProgrammeGoal goal;
  final ExerciseDifficulty level;
  final int weeks;
  final int daysPerWeek;
  final List<String> muscles;

  /// See the class doc — an empty [muscles] list is the full-body sentinel,
  /// not "no data yet".
  bool get isFullBody => muscles.isEmpty;
}

/// The id a questionnaire-built programme carries in place of a template's.
///
/// Not in [programmeTemplates] — it is not something anyone browses to; it is
/// the id stamped on a [Programme] assembled by `programmeFromProfile`
/// (`programme_providers.dart`). It lives here rather than beside that builder
/// because [ProgrammeLabels] has to match on it, and a data-layer label table
/// reaching into a state file to learn an id is the wrong direction.
///
/// Deliberately NOT expressed as a null `Programme.templateId`: that field is
/// non-nullable and drives the "is this the programme I am already on"
/// comparisons (`workouts_page.dart:1132`, `:1293`), so making it nullable
/// would push a null check into every one of those call sites to say what one
/// sentinel says once.
const String kProfileProgrammeId = 'from_answers';

const List<ProgrammeTemplate> programmeTemplates = [
  ProgrammeTemplate(
    id: 'strength_base',
    goal: ProgrammeGoal.strength,
    level: ExerciseDifficulty.intermediate,
    weeks: 8,
    daysPerWeek: 4,
  ),
  ProgrammeTemplate(
    id: 'hypertrophy',
    goal: ProgrammeGoal.muscle,
    level: ExerciseDifficulty.intermediate,
    weeks: 10,
    daysPerWeek: 4,
    muscles: ['chest', 'back', 'quads', 'hamstrings'],
  ),
  ProgrammeTemplate(
    id: 'gym_start',
    goal: ProgrammeGoal.form,
    level: ExerciseDifficulty.beginner,
    weeks: 6,
    daysPerWeek: 3,
  ),
  ProgrammeTemplate(
    id: 'shred_endurance',
    goal: ProgrammeGoal.weightLoss,
    level: ExerciseDifficulty.intermediate,
    weeks: 8,
    daysPerWeek: 5,
    muscles: ['core'],
  ),
  ProgrammeTemplate(
    id: 'injury_comeback',
    goal: ProgrammeGoal.comeback,
    level: ExerciseDifficulty.beginner,
    weeks: 4,
    daysPerWeek: 3,
  ),
  ProgrammeTemplate(
    id: 'shoulders_arms',
    goal: ProgrammeGoal.muscle,
    level: ExerciseDifficulty.intermediate,
    weeks: 6,
    daysPerWeek: 3,
    muscles: ['shoulders', 'biceps', 'triceps'],
  ),
];

ProgrammeTemplate? findProgrammeTemplate(String id) {
  for (final t in programmeTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
