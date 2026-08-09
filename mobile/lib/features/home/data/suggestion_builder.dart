import '../../equipment/data/equipment_models.dart';
import '../../profile/data/profile_models.dart';
import '../../workouts/data/workout_log.dart';

/// Why an exercise was suggested.
///
/// An enum rather than a built string. This builder is a pure function with no
/// `BuildContext`, so any sentence it composes itself is a sentence in one
/// language — which is how `'You have not trained hamstrings this week'`
/// ended up on a Russian Home screen. The builder decides *which* reason
/// applies; the widget that has a `BuildContext` decides how to say it.
enum SuggestionReason {
  /// A primary muscle of this exercise has gone untrained this week.
  /// Carries [WorkoutSuggestion.reasonMuscle] — a catalog muscle tag, to be
  /// rendered through `CatalogLabels.muscle`.
  untrainedMuscle,
  cardioForWeightLoss,
  cardioForEndurance,
  buildsStrength,
  buildsMuscle,
  fitsSessionLength,

  /// Nothing more specific applied. Deliberately weak: the alternative was
  /// inventing a reason, and a vague true statement beats a precise false one.
  matchesProfile,
}

/// One row in the Suggestions section.
///
/// Carries a real [exerciseId] so the card can open the actual workout — the
/// previous version was five hardcoded strings with an empty onTap.
class WorkoutSuggestion {
  const WorkoutSuggestion({
    required this.exerciseId,
    required this.title,
    required this.durationMinutes,
    required this.reason,
    this.reasonMuscle,
    this.exercise,
  });

  final String exerciseId;
  final String title;
  final int durationMinutes;

  /// Why this was suggested. Shown on the card: a recommendation the user
  /// cannot interrogate is indistinguishable from a random pick.
  final SuggestionReason reason;

  /// The muscle tag for [SuggestionReason.untrainedMuscle]; null otherwise.
  final String? reasonMuscle;

  /// The catalog row this suggestion came from.
  ///
  /// Present so the card can show the exercise's bundled poster. Before this,
  /// the Home card passed `ExerciseThumb(exercise: null)` — a const, so every
  /// row rendered the fallback dumbbell tile and none of the 1764 bundled
  /// posters was ever reached. Nullable only because the pure-function tests
  /// construct suggestions directly without a catalog row.
  final ExerciseItem? exercise;

  /// Excluded from equality and [hashCode]: [exerciseId] already identifies
  /// the row, so two suggestions with the same id and different exercise
  /// objects would be a catalog bug, not two distinct suggestions.
  @override
  bool operator ==(Object other) =>
      other is WorkoutSuggestion &&
      other.exerciseId == exerciseId &&
      other.title == title &&
      other.durationMinutes == durationMinutes &&
      other.reason == reason &&
      other.reasonMuscle == reasonMuscle;

  @override
  int get hashCode =>
      Object.hash(exerciseId, title, durationMinutes, reason, reasonMuscle);

  @override
  String toString() => 'WorkoutSuggestion($exerciseId, ${reason.name})';
}

/// Equipment whose work is primarily cardiovascular.
///
/// `exercise_bike` is not in the catalog yet — listed deliberately so that
/// adding it classifies correctly on day one instead of being silently scored
/// as resistance work.
const _cardioEquipment = {'treadmill', 'rowing_machine', 'exercise_bike'};

/// Nothing done in this window is suggested again — repeating yesterday's
/// session is the fastest way for suggestions to feel dumb.
const _justDoneWindow = Duration(hours: 48);

/// Muscles trained inside this window count as "covered this week".
const _freshnessWindow = Duration(days: 7);

/// Builds the Suggestions list.
///
/// [candidates] is expected to have been through `recommended()` already, so
/// contraindicated exercises are gone and tier fit is reflected in the order.
/// This function adds the parts that need history and goals: skip what was just
/// done, prefer muscles that have gone untrained, honour the stated goal and
/// preferred session length, and keep the list varied.
///
/// Deterministic by construction — no randomness — so the list does not
/// reshuffle on every rebuild and can be asserted on in tests.
List<WorkoutSuggestion> buildSuggestions({
  required List<ExerciseItem> candidates,
  required UserProfile? profile,
  required List<WorkoutLogEntry> recentLogs,
  DateTime? now,
  int limit = 5,
}) {
  if (candidates.isEmpty) return const [];
  final at = now ?? DateTime.now();

  final justDid = <String>{
    for (final log in recentLogs)
      if (at.difference(log.completedAt) < _justDoneWindow) log.exerciseId,
  };

  // Which muscles the recent log already covers. Derived from the catalog
  // rather than the log, because a log entry stores no muscle information.
  final byId = {for (final e in candidates) e.id: e};
  final trainedMuscles = <String>{
    for (final log in recentLogs)
      if (at.difference(log.completedAt) < _freshnessWindow)
        ...?byId[log.exerciseId]?.primaryMuscles,
  };

  final goals = profile?.goals;
  final wantsCardio =
      goals != null && (goals.weightLoss || goals.endurance);
  final wantsStrength =
      goals != null && (goals.strength || goals.muscleGain);
  final targetMinutes = _targetMinutes(profile?.motivation.preferredDuration);

  final scored = <_Scored>[];
  for (var i = 0; i < candidates.length; i++) {
    final ex = candidates[i];
    if (justDid.contains(ex.id)) continue;

    final isCardio = _cardioEquipment.contains(ex.equipmentId);
    final untrained = ex.primaryMuscles
        .where((m) => !trainedMuscles.contains(m))
        .toList(growable: false);

    var score = 0;
    SuggestionReason? reason;
    String? reasonMuscle;

    if (untrained.isNotEmpty && trainedMuscles.isNotEmpty) {
      score += 3;
      reason = SuggestionReason.untrainedMuscle;
      reasonMuscle = untrained.first;
    }
    if (wantsCardio && isCardio) {
      score += 2;
      reason ??= goals.weightLoss
          ? SuggestionReason.cardioForWeightLoss
          : SuggestionReason.cardioForEndurance;
    }
    if (wantsStrength && !isCardio) {
      score += 2;
      reason ??= goals.strength
          ? SuggestionReason.buildsStrength
          : SuggestionReason.buildsMuscle;
    }
    if (targetMinutes != null &&
        (ex.durationMinutes - targetMinutes).abs() <= 4) {
      score += 1;
      reason ??= SuggestionReason.fitsSessionLength;
    }
    // Removed: `reason ??= 'Safe with the injuries you listed'`.
    //
    // The comment justifying it was true about the code and false about the
    // world. `candidates` is indeed post-filter, so an exercise reaching here
    // has passed `filterContraindicated` -- but passing a filter that keeps
    // every untagged exercise, in a catalog where nothing is tagged, means it
    // passed a check that examined nothing. "Safe with the injuries you
    // listed" was the strongest claim in the product and the least supported.
    //
    // Nothing replaces it here. A suggestion card is the wrong place for a
    // disclosure -- see SafetyDisclosure, which sits on the surfaces that
    // list exercises -- and the remaining reasons are all things the app can
    // actually verify.

    // Earlier candidates fit the user's tier better (recommended() sorted
    // them), so use position as the tie-breaker instead of leaving ties to
    // arbitrary map order.
    scored.add(_Scored(
      exercise: ex,
      score: score,
      order: i,
      reason: reason ?? SuggestionReason.matchesProfile,
      reasonMuscle: reasonMuscle,
    ));
  }

  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return a.order.compareTo(b.order);
  });

  // One per primary muscle, so the list is not five variations on the same
  // movement.
  final out = <WorkoutSuggestion>[];
  final usedMuscles = <String>{};
  for (final s in scored) {
    if (out.length >= limit) break;
    final key = s.exercise.primaryMuscles.isEmpty
        ? s.exercise.id
        : s.exercise.primaryMuscles.first;
    if (!usedMuscles.add(key)) continue;
    out.add(WorkoutSuggestion(
      exerciseId: s.exercise.id,
      title: s.exercise.title,
      durationMinutes: s.exercise.durationMinutes,
      reason: s.reason,
      reasonMuscle: s.reasonMuscle,
      exercise: s.exercise,
    ));
  }

  // A short catalog can leave the list thin after the one-per-muscle pass;
  // top it up in score order rather than showing two rows.
  if (out.length < limit) {
    final taken = out.map((s) => s.exerciseId).toSet();
    for (final s in scored) {
      if (out.length >= limit) break;
      if (taken.contains(s.exercise.id)) continue;
      out.add(WorkoutSuggestion(
        exerciseId: s.exercise.id,
        title: s.exercise.title,
        durationMinutes: s.exercise.durationMinutes,
        reason: s.reason,
      ));
    }
  }

  return List.unmodifiable(out);
}

int? _targetMinutes(WorkoutDuration? d) => switch (d) {
      null => null,
      WorkoutDuration.under15 => 12,
      WorkoutDuration.m15to30 => 22,
      WorkoutDuration.m30to45 => 37,
      WorkoutDuration.m45to60 => 52,
      WorkoutDuration.over60 => 65,
    };

class _Scored {
  const _Scored({
    required this.exercise,
    required this.score,
    required this.order,
    required this.reason,
    this.reasonMuscle,
  });

  final ExerciseItem exercise;
  final int score;
  final int order;
  final SuggestionReason reason;
  final String? reasonMuscle;
}
