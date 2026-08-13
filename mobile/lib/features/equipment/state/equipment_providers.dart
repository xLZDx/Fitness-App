import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../../ai_coach/ai_exercise_generator.dart';
import '../../ai_coach/generated_exercise_repository.dart';
import '../../auth/state/auth_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/asset_equipment_repository.dart';
import '../data/clip_url_resolver.dart';
import '../data/equipment_models.dart';
import '../data/equipment_report_service.dart';
import '../data/equipment_repository.dart';
import '../data/exercise_filter.dart';
import '../data/mock_equipment_report_service.dart';

/// The catalog, in the language the user is actually reading.
///
/// Watches the language and nothing else. Watching the whole `AppSettings`
/// object here would mean a theme switch or a notifications toggle rebuilds
/// this provider, and with it every derived FutureProvider — re-reading the
/// bundled catalog from a settings screen tap.
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

/// The profile every safety decision is made against.
///
/// ## Why not `ref.watch(currentProfileProvider).valueOrNull`
///
/// That was the shape of every caller in this file, and it collapses two
/// different facts into the same `null`: "this user has no profile" and "the
/// profile has not arrived yet". [safeFor] reads null as the first and returns
/// the catalog unscreened, so during cold start — and again after every sign-in
/// and every profile refetch — an injured user was served the full catalog for
/// as long as the read took.
///
/// The collapse happened twice over, because `currentProfileProvider` samples
/// auth the same way (`profile_providers.dart:17-18`): while Firebase is still
/// restoring the session, `authUserProvider` is `AsyncLoading`, `valueOrNull`
/// is null, and the profile stream short-circuits to `Stream.value(null)` — a
/// resolved null, indistinguishable from a signed-out user. Awaiting only the
/// profile would not have been enough.
///
/// So both are awaited. Anything downstream stays [AsyncLoading] until the
/// answer is real, and the UI renders the spinner it already renders. Waiting
/// is recoverable; showing an injured user an exercise that hurts them is not.
final screeningProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) return null;
  return ref.watch(currentProfileProvider.future);
});

/// All exercises that target a specific piece of equipment, looked up by id.
///
/// Private: the raw, unscreened list. [recommendedExercisesProvider] is the
/// only thing outside this file that should be surfacing exercises for a
/// machine.
final _exercisesForEquipmentProvider =
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
///
/// Raw and unscreened, like everything else on this side of the boundary. It
/// is `@visibleForTesting` rather than `_`-private only because the
/// generate-once-and-cache economics it encodes have no other observable seam:
/// the public feed applies [withDemonstration], which drops AI text entirely,
/// so a test asserting through it could no longer tell a cache hit from a
/// generated miss. A reader in `lib/` raises
/// `invalid_use_of_visible_for_testing_member` — verified, and a warning
/// rather than an error, which is why `catalog_boundary_test.dart` fails on
/// one as well rather than trusting the annotation alone.
@visibleForTesting
final exercisesForEquipmentWithAiFallbackProvider =
    FutureProvider.family<List<ExerciseItem>, String>((ref, equipmentId) async {
  final real = await ref.watch(_exercisesForEquipmentProvider(equipmentId).future);
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
///
/// Private. This is the unscreened catalog, and it was public with a
/// doc-comment saying "use [recommendedExercisesProvider] when surfacing them
/// to the user" — which five call sites in `workouts_page.dart` and one in
/// `offline_video_providers.dart` read straight past. A comment is not a
/// boundary. [safeCatalogProvider] is the public one now.
final _allExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
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
  // One of the two places the clip-only rule is applied — this feed and
  // [recommendedExercisesProvider] are what every list in the app reads from.
  //
  // AI-generated exercises are caught by it too. They are text with no footage,
  // so under this rule a machine we have nothing real for now shows an empty
  // page rather than an invented exercise illustrated by nothing. That is the
  // honest state, and making it useful is the scan gate's job: say what the
  // machine is, record that we lack content for it, and point the user at an
  // outside video meanwhile.
  return List.unmodifiable(withDemonstration(out));
});

/// An image to head the machine's page, or null when nothing real exists.
///
/// **The clip's own poster, and nothing else.** Operator: *"фото должно быть
/// превью ролика"*.
///
/// This used to read `imageUrls` then `frames` — photographs of a man in a gym,
/// from the free-exercise-db import. They are properly licensed, so this was
/// never a legal problem; it was the same inconsistency the clip-only rule was
/// written to end. Every exercise list, every player and every card shows a 3D
/// render on flat white, and then the machine's header showed a photograph.
///
/// A poster is cut from its clip, so this is literally the first frame of a
/// demonstration this machine actually has. When the machine has no clip there
/// is no header, which is the honest state — and the scan gate is what makes
/// that state useful.
final equipmentHeroImageProvider =
    FutureProvider.family<String?, String>((ref, equipmentId) async {
  // Injury-screened, but NOT clip-filtered. The header sits directly above the
  // exercise list on the same page, and reading the unscreened feed let the
  // machine's photo depict the exact movement the list below correctly hides —
  // a barbell squat pictured to a user whose lower back is why it is not shown.
  //
  // Routing through `recommendedExercisesProvider` would have fixed that and
  // dragged `withDemonstration` in with it, so a machine whose posters all
  // belong to clipless entries would lose its header for a reason that has
  // nothing to do with anyone's injuries. `safeFor` is the half that was
  // actually missing.
  final profile = await ref.watch(screeningProfileProvider.future);
  final exercises = safeFor(
    await ref.watch(_exercisesForEquipmentProvider(equipmentId).future),
    profile,
  );
  for (final e in exercises) {
    final poster = e.posterFor(null);
    if (poster != null) return poster;
  }
  return null;
});

/// True for an exercise that came out of the AI generator rather than the
/// vendor catalog.
///
/// Their ids are `ai::<equipmentId>::<index>` and they are the only rows in
/// the app that no tagging pass can reach: they are generated per user, per
/// machine, per language, at read time, and `AiExerciseGenerator` never emits
/// a `contraindications` field at all.
bool isGenerated(ExerciseItem exercise) => exercise.id.startsWith('ai::');

/// True when the profile carries anything to screen against.
bool hasInjuries(UserProfile? profile) =>
    (profile?.health.injuries ?? const <Injury>[]).isNotEmpty;

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
  final profile = await ref.watch(screeningProfileProvider.future);
  // Clip-only first, injuries second, and the count is taken AFTER the first.
  // Measuring it against `raw` would report an exercise we simply cannot
  // demonstrate as one the user's injuries removed.
  final shown = withDemonstration(
    hasInjuries(profile) ? raw.where((e) => !isGenerated(e)).toList() : raw,
  );
  final items = recommended(shown, profile);
  final hidden = shown.length - items.length;
  return RecommendedExercises(
    items: items,
    hiddenForInjury: hidden < 0 ? 0 : hidden,
  );
});

/// **The public catalog.** Every exercise in the app, screened against the
/// signed-in user's injuries and otherwise in catalog order.
///
/// Order is deliberately left alone: this is the safety boundary, not a
/// ranking. Callers that want the For-you order read
/// [forYouExercisesProvider]; callers slicing by muscle or category do their
/// own slicing on top of a list that is already safe. Fusing the two is what
/// made the raw feed the path of least resistance in the first place.
/// `exerciseId` -> the catalogue's title, in the language the app is showing.
///
/// B2b. Every stored row — a scheduled session, a logged set, a programme day —
/// carries `exerciseTitle` as a SNAPSHOT taken when it was written. That is
/// correct for durability (a row whose exercise later leaves the catalogue
/// still reads as something) and wrong for display: switch the app to English
/// and the history keeps whatever language it was recorded in, which is what
/// the operator photographed — English cards listing "Боковые шаги в четыре
/// стороны".
///
/// Titles ONLY, deliberately. [_allExercisesProvider] stays private and
/// unscreened because handing out `ExerciseItem`s past the injury filter is the
/// mistake its doc describes; a NAME is not an offer, and a history row for an
/// exercise the user's injuries now screen out still has to be readable.
final exerciseTitlesProvider = Provider<Map<String, String>>((ref) {
  final all =
      ref.watch(_allExercisesProvider).valueOrNull ?? const <ExerciseItem>[];
  return {for (final e in all) e.id: e.title};
});

/// The catalogue's name for [id], falling back to the [stored] snapshot.
///
/// Pure so the fallback order is assertable: catalogue first (follows the
/// language), snapshot second (survives a removed exercise), never empty.
String resolveExerciseTitle(
  Map<String, String> titles,
  String id,
  String stored,
) {
  final live = titles[id];
  if (live != null && live.trim().isNotEmpty) return live;
  return stored;
}

final safeCatalogProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final all = await ref.watch(_allExercisesProvider.future);
  final profile = await ref.watch(screeningProfileProvider.future);
  return safeFor(all, profile);
});

/// "For you" feed for the Train tab: every exercise across the catalog,
/// filtered + tier-sorted for the signed-in user.
final forYouExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final safe = await ref.watch(safeCatalogProvider.future);
  final profile = await ref.watch(screeningProfileProvider.future);
  // Already screened by [safeCatalogProvider]; this only orders it. Running
  // the safety filter twice would be harmless but would say, in code, that
  // nobody was sure whether the first one had happened.
  return sortByTierFit(safe, profile?.level.tier);
});

/// What a lookup by exercise id found, and whether the user may see it.
///
/// Three outcomes, not two. "We have no such exercise" and "we have it and it
/// conflicts with an injury you told us about" are different facts, and
/// collapsing them into a bare not-found — which is what a deep link did —
/// tells a user with a knee injury that the squat they were linked to does not
/// exist. It does; it is being withheld, and saying so is both more honest and
/// the only version that lets them act on it.
class ExerciseResolution {
  const ExerciseResolution._(this.exercise, this.hiddenForInjury);

  /// Found, and safe to show.
  const ExerciseResolution.found(ExerciseItem exercise)
      : this._(exercise, false);

  /// No exercise carries this id.
  const ExerciseResolution.notFound() : this._(null, false);

  /// Found, but contraindicated by the user's own injury list.
  const ExerciseResolution.hiddenForInjury(ExerciseItem exercise)
      : this._(exercise, true);

  /// The exercise, whether or not it may be shown. Null only when nothing
  /// carries the id.
  final ExerciseItem? exercise;

  /// True when [exercise] exists but conflicts with a logged injury.
  final bool hiddenForInjury;

  /// The exercise, or null when it must not be surfaced.
  ExerciseItem? get visible => hiddenForInjury ? null : exercise;
}

/// Resolves a single exercise id through the same safety boundary as every
/// list.
///
/// ## Why this had to move here
///
/// It used to live in `workout_player_page.dart` as a private provider whose
/// non-`ai::` branch re-scanned `equipmentRepositoryProvider` directly — so
/// the deep link `/workout/:id` reached the raw catalog no matter what the
/// lists did, and privatising the list providers would have closed none of it.
/// The scheduled-session screening needs exactly the same lookup, which is the
/// second reason it belongs in one place rather than two.
final exerciseResolutionProvider =
    FutureProvider.family<ExerciseResolution, String>((ref, id) async {
  final profile = await ref.watch(screeningProfileProvider.future);

  ExerciseResolution screen(ExerciseItem? found) {
    if (found == null) return const ExerciseResolution.notFound();
    final injuries = profile?.health.injuries ?? const [];
    return isContraindicated(found, injuries)
        ? ExerciseResolution.hiddenForInjury(found)
        : ExerciseResolution.found(found);
  }

  // AI-generated ids are 'ai::<equipmentId>::<index>' and live only in the
  // generated-exercise cache, never in the base repo.
  //
  // They cannot be screened at all. The generator emits no `contraindications`
  // field and never will at read time, so `isContraindicated` returns false
  // for every one of them however the user is injured — which S3b turned from
  // a harmless no-op into a live hazard, because the app now says lists ARE
  // screened. The plan's own answer is the one taken here: excluded for
  // injury-aware users until a generation-time tagging pass exists.
  if (id.startsWith('ai::')) {
    if (hasInjuries(profile)) return const ExerciseResolution.notFound();
    final parts = id.split('::');
    if (parts.length != 3) return const ExerciseResolution.notFound();
    final lang = ref.watch(effectiveLanguageCodeProvider);
    final cached =
        await ref.watch(generatedExerciseRepositoryProvider).get(parts[1], lang);
    if (cached == null) return const ExerciseResolution.notFound();
    for (final e in cached) {
      if (e.id == id) return screen(e);
    }
    return const ExerciseResolution.notFound();
  }

  final repo = ref.watch(equipmentRepositoryProvider);
  for (final e in await repo.bodyweightExercises()) {
    if (e.id == id) return screen(e);
  }
  for (final eq in await repo.listEquipment()) {
    for (final e in await repo.exercisesFor(eq.id)) {
      if (e.id == id) return screen(e);
    }
  }
  return const ExerciseResolution.notFound();
});

/// Where a clip reference becomes a playable URL.
///
/// The licensed library lives in a private bucket, so its catalog entries are
/// object paths rather than URLs and have to be signed per request — see
/// `clip_url_resolver.dart`. Overridden in tests with a passthrough so the
/// widget suite needs no Firebase.
final clipUrlResolverProvider = Provider<ClipUrlResolver>((ref) {
  return FunctionsClipUrlResolver();
});
