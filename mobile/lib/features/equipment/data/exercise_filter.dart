import '../../profile/data/profile_models.dart';
import 'equipment_models.dart';

/// Pure recommendation utilities for the equipment catalog.
///
/// All inputs are treated as immutable and the returned lists are fresh
/// copies — callers can sort/insert without mutating shared state.

/// Normalises a free-text body part / contraindication tag so that
/// "left knee", "Knee (Right)", and "knee" all collapse to the same token.
String _normaliseTag(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
}

/// True when [injury] should hide an exercise tagged with [contraindication].
/// Match is symmetric and substring-aware so "lower_back" matches "back" and
/// vice versa, but unrelated parts ("ankle" vs "shoulder") never collide.
bool _injuryHits(String injury, String contraindication) {
  final a = _normaliseTag(injury);
  final b = _normaliseTag(contraindication);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return a.contains(b) || b.contains(a);
}

/// Drops any exercise whose [ExerciseItem.contraindications] overlaps the
/// user's reported injuries. Exercises with no contraindication tags are
/// always kept.
List<ExerciseItem> filterContraindicated(
  Iterable<ExerciseItem> exercises,
  Iterable<Injury> injuries,
) {
  if (injuries.isEmpty) return exercises.toList(growable: false);
  final injuryTokens = injuries.map((i) => i.bodyPart).toList(growable: false);
  return exercises
      .where((ex) {
        if (ex.contraindications.isEmpty) return true;
        for (final c in ex.contraindications) {
          for (final i in injuryTokens) {
            if (_injuryHits(i, c)) return false;
          }
        }
        return true;
      })
      .toList(growable: false);
}

int _difficultyRank(ExerciseDifficulty d) {
  switch (d) {
    case ExerciseDifficulty.beginner:
      return 0;
    case ExerciseDifficulty.intermediate:
      return 1;
    case ExerciseDifficulty.advanced:
      return 2;
  }
}

int _tierRank(FitnessTier t) {
  switch (t) {
    case FitnessTier.beginner:
      return 0;
    case FitnessTier.intermediate:
      return 1;
    case FitnessTier.advanced:
      return 2;
  }
}

/// Stable-sorts so exercises closest to [tier] come first. Beginners see
/// beginner → intermediate → advanced; advanced users see the inverse so
/// challenging work surfaces first.
List<ExerciseItem> sortByTierFit(
  Iterable<ExerciseItem> exercises,
  FitnessTier? tier,
) {
  final list = exercises.toList();
  if (tier == null) return list;
  final target = _tierRank(tier);
  list.sort((a, b) {
    final da = (_difficultyRank(a.difficulty) - target).abs();
    final db = (_difficultyRank(b.difficulty) - target).abs();
    if (da != db) return da.compareTo(db);
    // Within the same distance, prefer the easier one for beginners and
    // the harder one for advanced users.
    if (target == 0) {
      return _difficultyRank(a.difficulty).compareTo(_difficultyRank(b.difficulty));
    }
    if (target == 2) {
      return _difficultyRank(b.difficulty).compareTo(_difficultyRank(a.difficulty));
    }
    return 0;
  });
  return list;
}

/// Only the exercises the app can demonstrate with a moving picture.
///
/// ## Why a photograph is not an acceptable fallback
///
/// The catalog used to demonstrate an exercise three ways: a clip, two bundled
/// frames looped by `ExerciseDemo`, or two network stills shown the same way.
/// The last two look like a fallback in code and like a different app on
/// screen — they are photographs of a man in a gym, while every clip is a 3D
/// render on flat white. Operator, twice: *"я до сих пор вижу старые картинки
/// место роликов, я просил их всех убрать чтобы было все одинаково"*.
///
/// Measured before writing this: of 511 exercises, 365 carry a clip, 94 are
/// demonstrated by network photographs, 42 by bundled photographs, and 10 by
/// nothing at all. Both sets of "frames" are photographs — the bundled ones
/// came from the same free-exercise-db import as the network ones, so calling
/// them animation was only ever true of the mechanism, never of the content.
///
/// That leaves exactly one rule that satisfies "only animation": an exercise
/// the app cannot play is an exercise the app does not show. 146 entries of the
/// 511 fall out, which is the honest size of the gap rather than a number
/// softened by putting a photograph in front of it.
///
/// The test mirrors the player's own chain exactly —
/// `playableVideoFor(body) ?? videoUrl` — rather than `hasVideo`. An entry must
/// never pass this filter and then fail to produce anything on screen, and it
/// must never be hidden while the player would happily have played it.
///
/// The `videoUrl` half matters even though no shipped row uses it today: it is
/// the older singular field, the player still honours it, and leaving it out
/// here made a perfectly playable exercise vanish from every list. Two tests
/// caught that within a minute of the filter being written.
List<ExerciseItem> withDemonstration(Iterable<ExerciseItem> exercises) =>
    exercises
        .where((e) => e.playableVideoFor(null) != null || e.videoUrl != null)
        .toList(growable: false);

/// Full pipeline: hide contraindicated exercises, then surface tier-fit ones
/// first. Profile may be null (returns the input untouched, copied).
///
/// Deliberately does NOT apply [withDemonstration]. The two filters answer
/// different questions and their counts are reported separately —
/// `RecommendedExercises.hiddenForInjury` means "hidden because of your
/// injuries", and folding an undemonstrable exercise into that number would
/// tell the user their knee is why a treadmill walk is missing.
List<ExerciseItem> recommended(
  Iterable<ExerciseItem> exercises,
  UserProfile? profile,
) {
  if (profile == null) return exercises.toList(growable: false);
  final filtered = filterContraindicated(exercises, profile.health.injuries);
  return sortByTierFit(filtered, profile.level.tier);
}
