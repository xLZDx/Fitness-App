import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../profile/data/profile_models.dart';
import 'programme_templates.dart';

/// B5d-3. How well one [ProgrammeTemplate] answers what the user told the
/// questionnaire.
///
/// Five independent yes/no matches, not a percentage. Four come straight
/// from the questionnaire — goal, level, how many days a week, which zones —
/// and each either lines up or does not; the fifth, equipment, is derived
/// instead of asked: whether the catalogue can actually support what the
/// template names. Presenting the result as "87% match" would claim a
/// precision that five booleans do not have; the UI names the dimensions
/// that matched instead, which is also the only form a user can check
/// against their own answers.
class ProgrammeFit {
  const ProgrammeFit({
    this.goal = false,
    this.level = false,
    this.schedule = false,
    this.zones = false,
    this.equipment = false,
  });

  /// The template's goal is the one the user named as primary.
  final bool goal;

  /// The template's difficulty is the tier the user reported.
  final bool level;

  /// The template asks for no more days a week than the user said they have.
  final bool schedule;

  /// The template names at least one muscle inside a zone the user chose.
  final bool zones;

  /// H2. Every muscle the template names has at least one exercise the user
  /// can actually do — already screened for their injuries and narrowed to
  /// their equipment (`availableWith`, the same catalogue `enroll` schedules
  /// from). False, not true, when no catalogue was passed in: this dimension
  /// needs real data to make a claim, and "unanswered" reads the same as
  /// "unknown" everywhere else in this type.
  final bool equipment;

  /// Number of matched dimensions.
  ///
  /// Used ONLY for ordering, never shown. The five are deliberately
  /// unweighted: any weighting ("goal counts double") would be a claim about
  /// training methodology that this project has no source for. Ties are
  /// broken by catalogue order, not by a tiebreak rule invented here — see
  /// [rankTemplates].
  int get score =>
      (goal ? 1 : 0) +
      (level ? 1 : 0) +
      (schedule ? 1 : 0) +
      (zones ? 1 : 0) +
      (equipment ? 1 : 0);

  bool get hasAny => score > 0;
}

/// The [ProgrammeFit] of [template] against [profile].
///
/// An unanswered question never counts as a match. This is the whole reason the
/// dimensions are separate booleans rather than a single number: a user who
/// answered only "three days a week" gets templates ordered by the one thing
/// they said, and a card that claims a matching goal they never gave would be
/// the app inventing an answer on their behalf.
///
/// [catalogue] is the same shape `enroll` schedules from — injury-screened
/// and equipment-narrowed (`safeCatalogProvider` then `availableWith`) —
/// passed in rather than resolved here because this function is synchronous
/// and both of those are async providers; the caller resolves them once for
/// every template in the list instead of each fit computing its own.
ProgrammeFit programmeFit(
  ProgrammeTemplate template,
  UserProfile? profile, {
  List<ExerciseItem>? catalogue,
}) {
  final equipmentFit = _equipmentFit(template, catalogue);
  if (profile == null) return ProgrammeFit(equipment: equipmentFit);

  final tier = profile.level.tier;
  final days = profile.schedule.daysPerWeek;
  final zones = profile.goals.focusZones;

  // A zone match needs the template to NAME muscles: the full-body templates
  // (`isFullBody`) match every zone trivially, and "matches your focus areas"
  // on a programme that targets nothing in particular is noise dressed as a
  // recommendation. Their fit is expressed through the other three dimensions.
  var zoneMatch = false;
  if (template.muscles.isNotEmpty) {
    final wanted = <String>{};
    for (final zone in zones) {
      wanted.addAll(focusZoneMuscles(zone));
    }
    zoneMatch = template.muscles.any(wanted.contains);
  }

  return ProgrammeFit(
    goal:
        profile.goals.primary != null && template.goal == profile.goals.primary,
    // Exact tier only. An "adjacent tiers half-match" rule would need a claim
    // about how far outside their level it is safe to put someone, which is a
    // training decision, not a display one — and the wrong direction of that
    // guess puts a beginner into advanced work.
    level: tier != null && template.level == _difficultyFor(tier),
    // `<=`, not `==`: a 3-day programme genuinely fits someone with four days.
    // The reverse does not — a 5-day programme for someone with three schedules
    // two sessions a week they will not do, and the overdue count climbs on its
    // own. Same asymmetry `programmeDaysPerWeek` already applies when enrolling.
    schedule: days != null && template.daysPerWeek <= days,
    zones: zoneMatch,
    equipment: equipmentFit,
  );
}

/// Every muscle [template] names has real support in [catalogue] — no
/// catalogue means no claim, same as every other dimension here.
///
/// A full-body template needs no specific muscle covered — it draws from the
/// WHOLE catalogue (`buildProgrammeSchedule`'s `fullBodyPool`) — so it would
/// find something there almost by construction, the same reason [zones]
/// excludes full-body templates above: a claim every template can trivially
/// earn is not information, it is noise dressed as a recommendation.
///
/// `every`, not `any`, for the templates that DO name muscles:
/// `buildProgrammeSchedule` falls back to the whole catalogue for any single
/// muscle it cannot fill, so a partial gap never breaks the schedule
/// outright — but the template's OWN premise (a chest/back split, an arm
/// day) is what silently gives way to generic full-body substitutions when
/// even one of its named muscles has nothing behind it. `any` would call
/// that a match; this dimension exists to say when it is not one.
bool _equipmentFit(ProgrammeTemplate template, List<ExerciseItem>? catalogue) {
  if (catalogue == null || template.isFullBody) return false;
  return template.muscles
      .every((m) => catalogue.any((e) => e.muscles.contains(m)));
}

/// [ExerciseDifficulty] for a reported [FitnessTier].
///
/// Same mapping as `programmeFromProfile` (`programme_providers.dart`) —
/// `FitnessTier.never` is a beginner, because the catalogue has three
/// difficulties and the tier vocabulary has four.
ExerciseDifficulty _difficultyFor(FitnessTier tier) => switch (tier) {
      FitnessTier.advanced => ExerciseDifficulty.advanced,
      FitnessTier.intermediate => ExerciseDifficulty.intermediate,
      FitnessTier.beginner || FitnessTier.never => ExerciseDifficulty.beginner,
    };

/// [templates] ordered best-fitting first, each paired with why.
///
/// Stable: templates with equal scores keep their catalogue order
/// (`programmeTemplates`), so the list does not reshuffle between builds and
/// two equally-fitting programmes are not implicitly ranked against each other
/// by something the user cannot see.
///
/// With no profile and no catalogue, or a profile that answers none of the
/// four questionnaire dimensions, the order is left exactly as it was. (A
/// null profile with a non-null [catalogue] is the one combination that can
/// still reorder, on the equipment dimension alone — [programmeFit] scores
/// it before the profile-null check. Unreached in production: every caller
/// that resolves a catalogue only does so once it also has a profile.)
/// Reordering a catalogue on the strength of nothing, and calling the result
/// a recommendation, is worse than not recommending — the user cannot tell
/// the two apart from the outside.
List<({ProgrammeTemplate template, ProgrammeFit fit})> rankTemplates(
  List<ProgrammeTemplate> templates,
  UserProfile? profile, {
  List<ExerciseItem>? catalogue,
}) {
  final scored = [
    for (final t in templates)
      (template: t, fit: programmeFit(t, profile, catalogue: catalogue)),
  ];
  // `List.sort` is NOT stable in Dart, so equal scores would be free to swap on
  // any rebuild. Sorting on (score, original index) is what makes it stable.
  final indexed = [
    for (var i = 0; i < scored.length; i++) (row: scored[i], index: i),
  ];
  indexed.sort((a, b) {
    final byScore = b.row.fit.score.compareTo(a.row.fit.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [for (final e in indexed) e.row];
}
