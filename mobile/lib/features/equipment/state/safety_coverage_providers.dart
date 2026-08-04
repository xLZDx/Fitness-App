import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/injury_regions.dart';
import '../../profile/data/profile_models.dart';
import '../data/equipment_models.dart';
import '../data/exercise_filter.dart';
import 'equipment_providers.dart';

/// Whether the catalog carries enough safety tags for the injury filter to do
/// anything at all.
///
/// ## The problem this exists to stop
///
/// `filterContraindicated` keeps every exercise that has no contraindication
/// tags, which is the only safe default for one untagged row among many. When
/// no row is tagged the same rule makes the filter a total no-op: it runs on
/// every surface, removes nothing, and reports zero hidden exercises — a
/// truthful zero for entirely the wrong reason.
///
/// That is the catalog's actual state. `safetyCoverage()` measures 0 of 1,887,
/// while eight places in the product told users their injuries were being
/// screened for. A filter that cannot fire is not a bug in the filter, so
/// nothing errored and nothing went red; the legacy catalog carrying the only
/// tagged exercises was deleted and no test noticed.
///
/// Every claim about injury filtering now reads this. One measurement with one
/// meaning, rather than eight surfaces each deciding for themselves.
class CatalogSafetyCoverage {
  const CatalogSafetyCoverage({
    required this.tagged,
    required this.total,
    this.byRegion = const {},
  });

  final int tagged;
  final int total;

  /// How many exercises carry each region's tag.
  final Map<InjuryRegion, int> byRegion;

  /// Nothing may claim to have screened an exercise below this.
  ///
  /// Zero is not the same as "any tag will do": the threshold is that at least
  /// one exercise can be filtered at all. A catalog with a handful of tags
  /// still filters honestly for the injuries those tags name — it just filters
  /// less than a user might assume, which is what the disclosure says.
  bool get filteringCanFire => tagged > 0;

  /// True when every one of [regions] has at least one tagged exercise.
  ///
  /// The per-user form of [filteringCanFire], and the one that matters from
  /// S3b's first batch onward. A batch of 50 tagged knees makes
  /// `filteringCanFire` true for everybody — including a user whose only
  /// injury is a shoulder, whose coverage is still zero. Disarming the
  /// disclosure for them would put the app straight back to the claim S0a
  /// removed, and it would be a harder version of it: the claim would now be
  /// true for most users, which is exactly the shape nobody re-checks.
  bool coversAllOf(Iterable<InjuryRegion> regions) {
    if (regions.isEmpty) return false;
    return regions.every((r) => (byRegion[r] ?? 0) > 0);
  }

  double get fraction => total == 0 ? 0 : tagged / total;

  /// Rounded down, so 0.4% reads as 0 rather than as 1.
  int get percent => (fraction * 100).floor();

  static const none = CatalogSafetyCoverage(tagged: 0, total: 0);
}

/// Measured once from the bundled catalog.
///
/// The catalog is a shipped asset parsed once and memoised, so this costs
/// nothing after the first read and never touches the network.
final catalogSafetyCoverageProvider =
    FutureProvider<CatalogSafetyCoverage>((ref) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  final equipment = await repo.listEquipment();

  // De-duplicated by id: an exercise reachable from two machines is one
  // exercise, and counting it twice would inflate both halves of the ratio.
  final unique = <String, ExerciseItem>{
    for (final e in await repo.bodyweightExercises()) e.id: e,
  };
  for (final item in equipment) {
    for (final e in await repo.exercisesFor(item.id)) {
      unique[e.id] = e;
    }
  }

  // Through the shared helper rather than counting here, so this and the
  // coverage-floor test cannot disagree about what "covered" means.
  final coverage = safetyCoverage(unique.values);
  return CatalogSafetyCoverage(
    tagged: coverage.tagged,
    total: coverage.total,
    byRegion: safetyCoverageByRegion(unique.values),
  );
});

/// Whether the safety tags have been reviewed by someone qualified.
///
/// False, and it says so on screen. The tags S3b writes come from
/// `tag_contraindications.py` — deterministic rules over the vendor's own
/// movement names and primary muscles, with the matching rule recorded per row
/// in `core/contraindications/*.csv`. That is a real screen and it is not a
/// clinical one, and the difference is exactly the kind of thing a product
/// stops mentioning once the mechanism works.
///
/// Flip this when a clinician has signed off on the tag set, and the weaker
/// disclosure disappears on its own — the same self-removing shape as S0a's
/// banner, for the same reason: nobody should have to remember to delete it.
const bool kSafetyTagsClinicallyReviewed = false;

/// How much the app may honestly claim about a user's exercise list.
enum SafetyScreeningLevel {
  /// No tags cover this user's regions. Say nothing was screened.
  none,

  /// Screened by rules, not by a clinician.
  rulesOnly,

  /// Screened, and the tag set has been reviewed.
  clinical,
}

/// The claim the app is entitled to make for the signed-in user.
final safetyScreeningLevelProvider = Provider<SafetyScreeningLevel>((ref) {
  if (!ref.watch(injuryFilteringIsRealProvider)) {
    return SafetyScreeningLevel.none;
  }
  return kSafetyTagsClinicallyReviewed
      ? SafetyScreeningLevel.clinical
      : SafetyScreeningLevel.rulesOnly;
});

/// True when a surface is allowed to say **this user's** exercise list was
/// screened.
///
/// Evaluated against the regions they actually reported, not against the
/// catalog as a whole. The global form was correct while coverage was zero and
/// becomes a lie the moment tagging starts unevenly, which it will: S3b tags in
/// batches, and the first batch cannot cover eight regions at once.
///
/// A user whose injuries are still unmapped free text falls back to the global
/// question, because there is no region to ask about yet — and until S1b runs,
/// that is every existing user. The fallback is the old behaviour, so this
/// cannot regress anyone; it can only stop the claim being made too early.
///
/// Defaults to false while loading and on error. Silence is recoverable; a
/// safety claim shown to an injured user because a future had not resolved
/// yet is not.
final injuryFilteringIsRealProvider = Provider<bool>((ref) {
  final coverage = ref.watch(catalogSafetyCoverageProvider).valueOrNull;
  if (coverage == null) return false;

  // `hasValue`, not `.valueOrNull`. A null profile means "signed out, nothing
  // to screen against"; an unresolved one means "we do not know yet", and
  // sampling collapses the two — which is the same bug S2 removed from the
  // catalog providers, and it would land here as a claim rather than as an
  // unscreened list. A test caught it doing exactly that.
  final profileAsync = ref.watch(screeningProfileProvider);
  if (!profileAsync.hasValue) return false;

  final injuries = profileAsync.value?.health.injuries ?? const <Injury>[];
  if (injuries.isEmpty) return coverage.filteringCanFire;

  // Every injury, not only the mapped ones. Collecting `injury.region` and
  // skipping the rest silently dropped the unmapped ones from the question, so
  // a user with a mapped knee (covered) and an untriaged shoulder (not) was
  // told their whole list had been screened. Until S1b runs, most users have
  // at least one unmapped injury, which made that the common case rather than
  // the edge one.
  final regions = <InjuryRegion>{};
  for (final injury in injuries) {
    final region = injury.region ?? suggestRegion(injury.bodyPart);
    // Nothing names it — a rib, a jaw, or a word no rule recognises. We cannot
    // have screened for it, so we cannot say the list was screened. The user
    // sees the disclosure until they map it or we learn the word.
    if (region == null) return false;
    regions.add(region);
  }
  return coverage.coversAllOf(regions);
});
