import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const CatalogSafetyCoverage({required this.tagged, required this.total});

  final int tagged;
  final int total;

  /// Nothing may claim to have screened an exercise below this.
  ///
  /// Zero is not the same as "any tag will do": the threshold is that at least
  /// one exercise can be filtered at all. A catalog with a handful of tags
  /// still filters honestly for the injuries those tags name — it just filters
  /// less than a user might assume, which is what the disclosure says.
  bool get filteringCanFire => tagged > 0;

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
  );
});

/// True when a surface is allowed to say an exercise list was screened.
///
/// Defaults to false while loading and on error. Silence is recoverable; a
/// safety claim shown to an injured user because a future had not resolved
/// yet is not.
final injuryFilteringIsRealProvider = Provider<bool>((ref) {
  return ref
          .watch(catalogSafetyCoverageProvider)
          .valueOrNull
          ?.filteringCanFire ??
      false;
});
