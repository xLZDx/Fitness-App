import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../profile/data/profile_models.dart';
import 'programme_templates.dart';

/// B5d-3. How well one [ProgrammeTemplate] answers what the user told the
/// questionnaire.
///
/// Four independent yes/no matches, not a percentage. The questionnaire asks
/// four things a template can be compared against — goal, level, how many days
/// a week, which zones — and each either lines up or does not. Presenting the
/// result as "87% match" would claim a precision that four booleans do not
/// have; the UI names the dimensions that matched instead, which is also the
/// only form a user can check against their own answers.
class ProgrammeFit {
  const ProgrammeFit({
    this.goal = false,
    this.level = false,
    this.schedule = false,
    this.zones = false,
  });

  /// The template's goal is the one the user named as primary.
  final bool goal;

  /// The template's difficulty is the tier the user reported.
  final bool level;

  /// The template asks for no more days a week than the user said they have.
  final bool schedule;

  /// The template names at least one muscle inside a zone the user chose.
  final bool zones;

  /// Number of matched dimensions.
  ///
  /// Used ONLY for ordering, never shown. The four are deliberately unweighted:
  /// any weighting ("goal counts double") would be a claim about training
  /// methodology that this project has no source for. Ties are broken by
  /// catalogue order, not by a tiebreak rule invented here — see [rankTemplates].
  int get score =>
      (goal ? 1 : 0) + (level ? 1 : 0) + (schedule ? 1 : 0) + (zones ? 1 : 0);

  bool get hasAny => score > 0;
}

/// The [ProgrammeFit] of [template] against [profile].
///
/// An unanswered question never counts as a match. This is the whole reason the
/// dimensions are separate booleans rather than a single number: a user who
/// answered only "three days a week" gets templates ordered by the one thing
/// they said, and a card that claims a matching goal they never gave would be
/// the app inventing an answer on their behalf.
ProgrammeFit programmeFit(ProgrammeTemplate template, UserProfile? profile) {
  if (profile == null) return const ProgrammeFit();

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
  );
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
/// With no profile, or a profile that answers none of the four questions, the
/// order is left exactly as it was. Reordering a catalogue on the strength of
/// nothing, and calling the result a recommendation, is worse than not
/// recommending — the user cannot tell the two apart from the outside.
List<({ProgrammeTemplate template, ProgrammeFit fit})> rankTemplates(
  List<ProgrammeTemplate> templates,
  UserProfile? profile,
) {
  final scored = [
    for (final t in templates) (template: t, fit: programmeFit(t, profile)),
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
