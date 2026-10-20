import 'equipment_alias_index.dart';
import 'equipment_models.dart';

/// Which exercise's poster heads a machine's page.
///
/// ## The defect this replaces
///
/// The header used to be the poster of the FIRST injury-safe exercise linked to
/// the machine. A machine's exercise list is everything that can be done ON or
/// WITH it, so "first" was an accident of file order: the bench-press page
/// showed a man curling dumbbells on a bench, the dip-station page an ab tuck, the
/// vertical-pole page a dragonfly. Measured on the shipped assets
/// (`equipment_hero_contract_test.dart` prints the list), the new rule changes
/// the header of 35 of 69 machines and leaves one that used to have a (wrong)
/// header without one.
///
/// ## The rule
///
/// A hero must be an exercise performed on the machine as designed, which the
/// catalogue lets us decide without any new tagging:
///
///  0. [preferredExerciseId], when the machine row names one and it is among
///     [candidates] -- for the machines where several equally good exercises
///     name the machine and only a human can say which one is "the" movement
///     (a bench-press station is a barbell station; a band press also names
///     it).
///  1. An exercise whose own (English, language-independent) id slug names the
///     machine, i.e. resolves through the alias index to [equipmentId].
///  2. Failing that, an exercise whose vendor equipment label names the machine
///     ("Pull Up Bar", "Biceps Curl Machine").
///  3. Otherwise NO hero. The page already draws a placeholder for null, and a
///     placeholder is honest where a wrong picture is not.
///
/// Within a tier the shortest slug wins (the plain movement before its
/// variations), then the id, so the pick is stable across runs, languages and
/// catalogue order. Ranking never reads the translated title, which is why the
/// hero does not change when the user switches language.
ExerciseItem? pickHeroExercise({
  required String equipmentId,
  required Iterable<ExerciseItem> candidates,
  required EquipmentAliasIndex index,
  String? preferredExerciseId,
}) {
  final withPoster =
      candidates.where((e) => e.posterFor(null) != null).toList();
  if (withPoster.isEmpty) return null;

  if (preferredExerciseId != null) {
    for (final e in withPoster) {
      if (e.id == preferredExerciseId) return e;
    }
  }

  int tierOf(ExerciseItem e) {
    if (index.resolve(exerciseSlug(e)) == equipmentId) return 1;
    final label = e.equipmentLabel;
    if (label != null && index.resolve(label) == equipmentId) return 2;
    return 3;
  }

  final ranked = <(int, int, String, ExerciseItem)>[
    for (final e in withPoster)
      (tierOf(e), exerciseSlug(e).split(' ').length, e.id, e),
  ]..sort((a, b) {
      final byTier = a.$1.compareTo(b.$1);
      if (byTier != 0) return byTier;
      final byLength = a.$2.compareTo(b.$2);
      if (byLength != 0) return byLength;
      return a.$3.compareTo(b.$3);
    });

  final best = ranked.first;
  return best.$1 == 3 ? null : best.$4;
}

/// The exercise id as plain English words: `ea_barbell_bench_press` ->
/// `barbell bench press`. The id is the one name every language shares.
String exerciseSlug(ExerciseItem e) {
  final id = e.id.startsWith('ea_') ? e.id.substring(3) : e.id;
  return id.replaceAll('_', ' ');
}
