import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';

/// The muscles a machine is for, as catalogue tags, most-cited first.
///
/// SCAN-G1: the reference's match card reads "Strength · Lats, Biceps"
/// (`Sunset.dc.html:211`) -- the category, then the muscles. The catalogue
/// keeps muscles on exercises, not on equipment (`ExerciseItem.muscles` /
/// `primaryMuscles`; `EquipmentItem` has none), so a machine's muscles are
/// what its exercises train: each exercise votes with its primary muscles
/// (all its muscles when it names no primary ones), and the two most-voted
/// tags are the line. Ties break alphabetically so the line is stable
/// between builds.
///
/// Raw tags; the caller localises them (`CatalogLabels.muscle`). Empty when
/// the catalogue has no exercises for the id -- the card then shows the
/// category alone rather than inventing a muscle.
final scanMatchMusclesProvider =
    FutureProvider.autoDispose.family<List<String>, String>(
        (ref, equipmentId) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  final List<ExerciseItem> exercises;
  try {
    exercises = await repo.exercisesFor(equipmentId);
  } catch (e) {
    // Fails open to "no muscles" (the card falls back to the category
    // alone), same as a machine that genuinely has no exercises -- but
    // logged, so a real catalogue/asset regression is not indistinguishable
    // from that legitimate case. Caught here, not left to the caller's
    // AsyncValue.error/`valueOrNull ?? []`, which would swallow it the same
    // way with no trace at all.
    debugPrint('scan match muscles: $equipmentId failed: $e');
    return const <String>[];
  }
  final Map<String, int> votes = <String, int>{};
  for (final e in exercises) {
    final List<String> tags =
        e.primaryMuscles.isNotEmpty ? e.primaryMuscles : e.muscles;
    for (final String m in tags) {
      votes[m] = (votes[m] ?? 0) + 1;
    }
  }
  final List<String> ordered = votes.keys.toList()
    ..sort((String a, String b) {
      final int byVotes = votes[b]!.compareTo(votes[a]!);
      return byVotes != 0 ? byVotes : a.compareTo(b);
    });
  return ordered.take(2).toList(growable: false);
});
