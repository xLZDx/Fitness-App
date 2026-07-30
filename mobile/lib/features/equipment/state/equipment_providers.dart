import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../../ai_coach/ai_exercise_generator.dart';
import '../../ai_coach/generated_exercise_repository.dart';
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

/// Generates AI exercises once per (user, machine, language) and caches the
/// result. Default is the in-memory mock so widget tests never touch
/// Firebase; `main.dart` overrides with [FirestoreGeneratedExerciseRepository].
final generatedExerciseRepositoryProvider =
    Provider<GeneratedExerciseRepository>((_) => MockGeneratedExerciseRepository());

final aiExerciseGeneratorProvider =
    Provider<AiExerciseGenerator>((_) => AiExerciseGenerator());

/// Real catalog first (round 4 (S0) covers 37 of 48 registry machines with
/// vendored public-domain exercises); only the machines with nothing real —
/// 11 mostly-cardio ids — fall through to AI generation, cached so a machine
/// is billed once per (user, language) rather than on every page visit.
///
/// A generation failure (offline, quota, malformed answer) surfaces as a
/// thrown Future — [recommendedExercisesProvider]'s `.when()` renders that as
/// an error card, which is honest: "no exercises" and "couldn't generate any"
/// are different facts and must not read the same to the user.
final exercisesForEquipmentWithAiFallbackProvider =
    FutureProvider.family<List<ExerciseItem>, String>((ref, equipmentId) async {
  final real = await ref.watch(exercisesForEquipmentProvider(equipmentId).future);
  if (real.isNotEmpty) return real;

  final lang = ref.watch(effectiveLanguageCodeProvider);
  final genRepo = ref.watch(generatedExerciseRepositoryProvider);
  final cached = await genRepo.get(equipmentId, lang);
  if (cached != null) return cached;

  final machine = await ref.watch(equipmentByIdProvider(equipmentId).future);
  if (machine == null) return const [];
  final generated = await ref.watch(aiExerciseGeneratorProvider).generate(
        equipmentId: equipmentId,
        machineName: machine.name,
        languageCode: lang,
      );
  try {
    await genRepo.save(equipmentId, lang, generated);
  } catch (e) {
    // The exercises are still returned to the user this call; only the
    // cache write failed, so the next visit just regenerates. Logged rather
    // than surfaced as an error -- a cache miss is not a user-facing failure.
    debugPrint('failed to cache AI-generated exercises for $equipmentId: $e');
  }
  return generated;
});

final equipmentByIdProvider =
    FutureProvider.family<EquipmentItem?, String>((ref, id) {
  final repo = ref.watch(equipmentRepositoryProvider);
  return repo.findEquipment(id);
});

/// Flat list of every exercise in the catalog (bodyweight + every machine),
/// plus any AI-generated exercises already cached for a machine that has
/// none of its own.
///
/// Reads the cache ONLY — visiting the Train tab must never fan out a
/// generation call per empty machine (operator: "чтобы мы не генерили
/// миллион апиай запросов на 1 фото/тренажёр"). A machine's generated
/// exercises join this feed only after its own detail page has been opened
/// at least once, which is what actually triggers generation+save.
final allExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final repo = ref.watch(equipmentRepositoryProvider);
  final body = await repo.bodyweightExercises();
  final equip = await repo.listEquipment();
  final genRepo = ref.watch(generatedExerciseRepositoryProvider);
  final lang = ref.watch(effectiveLanguageCodeProvider);
  final out = <ExerciseItem>[...body];
  for (final eq in equip) {
    final real = await repo.exercisesFor(eq.id);
    if (real.isNotEmpty) {
      out.addAll(real);
      continue;
    }
    final cached = await genRepo.get(eq.id, lang);
    if (cached != null) out.addAll(cached);
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
  final raw = await ref
      .watch(exercisesForEquipmentWithAiFallbackProvider(equipmentId).future);
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
