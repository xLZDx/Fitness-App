import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../data/asset_equipment_repository.dart';
import '../data/equipment_models.dart';
import '../data/equipment_report_service.dart';
import '../data/equipment_repository.dart';
import '../data/exercise_filter.dart';
import '../data/mock_equipment_report_service.dart';

/// The catalog, in the language the user is actually reading.
///
/// Watches the resolved language code and nothing else. Watching the whole
/// `AppSettings` object here would mean a theme switch or a notifications
/// toggle rebuilds this provider, and with it every derived FutureProvider —
/// re-reading the bundled JSON from a settings screen tap.
final equipmentRepositoryProvider = Provider<EquipmentRepository>((ref) {
  return AssetEquipmentRepository(
    languageCode: ref.watch(effectiveLanguageCodeProvider),
  );
});

/// Submits broken-equipment reports. Default is the in-memory mock so
/// unit tests don't pull in cloud_functions; production overrides in
/// `main.dart` with `CloudFunctionsEquipmentReportService`.
final equipmentReportServiceProvider =
    Provider<EquipmentReportService>((ref) {
  return MockEquipmentReportService();
});

/// Every piece of equipment in the catalog.
final equipmentListProvider = FutureProvider<List<EquipmentItem>>((ref) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.listEquipment();
});

/// All exercises that target a specific piece of equipment, looked up by id.
/// Use [recommendedExercisesProvider] when surfacing them to the user — this
/// is the raw, unfiltered list (still useful for debug or admin views).
final exercisesForEquipmentProvider =
    FutureProvider.family<List<ExerciseItem>, String>((ref, equipmentId) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.exercisesFor(equipmentId);
});

final equipmentByIdProvider =
    FutureProvider.family<EquipmentItem?, String>((ref, id) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.findEquipment(id);
});

/// Flat list of every exercise in the catalog (bodyweight + every machine).
final allExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  final body = await repo.bodyweightExercises();
  final equip = await repo.listEquipment();
  final out = <ExerciseItem>[...body];
  for (final eq in equip) {
    out.addAll(await repo.exercisesFor(eq.id));
  }
  return List.unmodifiable(out);
});

/// Result of running the recommendation pipeline for a specific equipment.
class RecommendedExercises {
  const RecommendedExercises({
    required this.items,
    required this.hiddenForInjury,
  });
  final List<ExerciseItem> items;

  /// How many exercises were dropped because they conflict with the user's
  /// injury list. Lets the UI surface a "Filtered for your injuries" hint.
  final int hiddenForInjury;
}

/// Exercises for [equipmentId] with contraindications removed and tier-fit
/// applied based on the signed-in user's profile.
final recommendedExercisesProvider =
    FutureProvider.family<RecommendedExercises, String>((ref, equipmentId) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  final raw = await repo.exercisesFor(equipmentId);
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  final items = recommended(raw, profile);
  final hidden = raw.length - items.length;
  return RecommendedExercises(
    items: items,
    hiddenForInjury: hidden < 0 ? 0 : hidden,
  );
});

/// "For you" feed for the Train tab: every exercise across the catalog,
/// filtered + tier-sorted for the signed-in user.
final forYouExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final all = await ref.watch(allExercisesProvider.future);
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return recommended(all, profile);
});
