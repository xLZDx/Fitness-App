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
import '../../safety/data/eligibility.dart';
import '../../safety/data/health_flags.dart' show MovementRestriction;
import '../../safety/data/par_q.dart' as par_q;
import '../../safety/state/eligibility_providers.dart';

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

/// Every `exerciseId` mapped to this equipment type, unscreened.
///
/// Deliberately reads [_exercisesForEquipmentProvider] rather than
/// [recommendedExercisesProvider]: this set is used to match *past* logged
/// workouts against an equipment type (`summarizeEquipmentTypeHistory`), and
/// injury screening can change after a workout was logged (an exercise done
/// safely last month can be hidden today because of an injury logged since).
/// Screening what is safe to *recommend* must not also decide what counts as
/// history that actually happened.
///
/// Also unions in cached AI-generated exercise ids (Gate D review finding):
/// the vendored catalog alone is empty for the 11 registry machines with no
/// real exercises, which [_exercisesForEquipmentProvider] falls through to
/// nothing for -- see [exercisesForEquipmentWithAiFallbackProvider]'s doc
/// comment. A workout logged against one of those machines is logged under
/// a generated `ai::$equipmentId::$i` id (`ai_exercise_generator.dart`), so
/// without this, history matching would silently and permanently fail for
/// every one of them. Reads [GeneratedExerciseRepository.get] -- the CACHE
/// only, never [AiExerciseGenerator.generate] -- a background history
/// lookup must not trigger a new billed generation; that belongs to the
/// page actually showing the exercise list, which already caches it there.
final equipmentExerciseIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, equipmentId) async {
  final items = await ref.watch(_exercisesForEquipmentProvider(equipmentId).future);
  final ids = items.map((e) => e.id).toSet();
  if (ids.isNotEmpty) return ids;

  final lang = ref.watch(effectiveLanguageCodeProvider);
  final genRepo = ref.watch(generatedExerciseRepositoryProvider);
  final cached = await genRepo.get(equipmentId, lang);
  return {for (final e in cached ?? const <ExerciseItem>[]) e.id};
});

/// Generates AI exercises once per (user, machine, language) and caches the
/// result. Default is the in-memory mock so widget tests never touch
/// Firebase; `main.dart` overrides with [FirestoreGeneratedExerciseRepository].
final generatedExerciseRepositoryProvider =
    Provider<GeneratedExerciseRepository>((_) => MockGeneratedExerciseRepository());

final aiExerciseGeneratorProvider =
    Provider<AiExerciseGenerator>((_) => AiExerciseGenerator());

/// Real catalog first; the machines with nothing real fall through to AI
/// generation, cached so a machine is billed once per (user, language) rather
/// than on every page visit. Measured on the shipped assets: 69 registry ids,
/// **4** with no exercise linked — `recumbent_bike`, `glute_kickback_machine`,
/// `t_bar_row`, `rotary_torso_machine`. (The doc here used to say "11
/// mostly-cardio ids" against a 48-machine registry; both numbers were stale.)
///
/// **This provider has no consumer in `lib/`, deliberately, since C14.** What
/// it generates is text: a title, muscles and steps, and
/// `ai_exercise_generator.dart:135-149` passes neither `video` nor `videoUrl`,
/// so [withDemonstration] drops all of it.
///
/// Scope that precisely: **every list and feed** applies the clip-only rule —
/// this provider's former caller and [_allExercisesProvider] are the two
/// places it is applied, and between them they are what every list in the app
/// reads from. The one surface that does *not* is [exerciseResolutionProvider]
/// (`:472`), which resolves an `ai::` id straight from the cache; the player
/// then renders the text with `ExerciseNoVideoFallback`
/// (`workout_player_page.dart:250-257`, whose own comment says as much). That
/// path needs an `ai::` id to already exist client-side — an entry cached
/// before this change, or a row in a workout history written when lists still
/// showed clipless exercises, since no list has offered one since 2026-08-03.
/// It is untouched here and shrinks over time rather than growing, because
/// nothing creates new ones.
///
/// Generating anyway cost a Gemini call and a cache write per empty
/// machine per language for output that provably could not be rendered, and
/// its *failure* was worse than its success: the thrown Future reached
/// `equipment_detail_page.dart:156` as "couldn't load exercises", so a Gemini
/// outage turned an honest "nothing curated yet" into an error card about work
/// whose result nobody would have seen either way.
///
/// It is kept rather than deleted because the capability is only unrenderable,
/// not wrong: the day these four machines have footage, this is the seam that
/// fills them. Deleting the generator, its cache and the Firestore repository
/// is a product call, recorded as open in the scope rather than taken here.
///
/// Raw and unscreened, like everything else on this side of the boundary. It
/// is `@visibleForTesting` rather than `_`-private because the
/// generate-once-and-cache economics it encodes have no other observable seam.
/// A reader in `lib/` raises `invalid_use_of_visible_for_testing_member` —
/// verified, and a warning rather than an error, which is why
/// `catalog_boundary_test.dart` fails on one as well rather than trusting the
/// annotation alone.
@visibleForTesting
final exercisesForEquipmentWithAiFallbackProvider =
    FutureProvider.family<List<ExerciseItem>, String>((ref, equipmentId) async {
  final real = await ref.watch(_exercisesForEquipmentProvider(equipmentId).future);
  if (real.isNotEmpty) return real;

  final lang = ref.watch(effectiveLanguageCodeProvider);
  final genRepo = ref.watch(generatedExerciseRepositoryProvider);
  final cached = await genRepo.get(equipmentId, lang);
  if (cached != null) return cached;

  // The server now resolves the canonical machine name from equipmentId
  // itself (functions/src/ai_exercise_generation.ts) -- this lookup is kept
  // only as a client-side short-circuit against calling the AI for an
  // equipmentId that isn't even in the local catalog, redundant-but-harmless
  // against the server's own independent unknown-id rejection.
  final machine = await ref.watch(equipmentByIdProvider(equipmentId).future);
  if (machine == null) return const [];
  final generated = await ref.watch(aiExerciseGeneratorProvider).generate(
        equipmentId: equipmentId,
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
/// миллион апиай запросов на 1 фото/тренажёр"). This used to add that a
/// machine's generated exercises join the feed once its detail page has been
/// opened, "which is what actually triggers generation+save". **Since C14
/// nothing in `lib/` triggers it**, so the only entries this can read are ones
/// cached before that change — and [withDemonstration] at the bottom of this
/// provider drops them anyway.
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

/// True when this person has told us something that per-exercise screening
/// acts on, and which a generated exercise therefore cannot honour.
///
/// F023 (G-B/B6). This used to be [hasInjuries] at both call sites, which read
/// the injury list and nothing else. A movement restriction is the same kind of
/// fact — a statement that some movements are unsafe for this person, enforced
/// by `evaluateExercise` against `contraindications` tags — and generated rows
/// carry no tags at all, so `isContraindicated` returns false for every one of
/// them however the user is restricted. Excluding on injuries but not on
/// restrictions meant a user whose only entry was "no overhead work" was served
/// untagged AI rows while the app told them their list was screened.
///
/// Restrictions are read from the normalised [HealthFlags], never from the free
/// text beside them — same boundary `health_flags.dart` draws.
bool cannotScreenGeneratedFor(UserProfile? profile) =>
    hasInjuries(profile) ||
    (profile?.health.flags.restrictions ?? const <MovementRestriction>{})
        .isNotEmpty;

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
  // The real catalog, not the AI fallback. See that provider's doc: its output
  // carries no clip, so `withDemonstration` below discarded 100% of it, and a
  // generation failure surfaced to the user as an error about exercises they
  // were never going to be shown.
  final raw = await ref.watch(_exercisesForEquipmentProvider(equipmentId).future);
  final profile = await ref.watch(screeningProfileProvider.future);
  // Clip-only first, injuries second, and the count is taken AFTER the first.
  // Measuring it against `raw` would report an exercise we simply cannot
  // demonstrate as one the user's injuries removed.
  // F023 widened the predicate here for consistency with the `ai::` branch of
  // [exerciseResolutionProvider], NOT because this call site leaks.
  //
  // Stated precisely, because the first version of this comment claimed a
  // second live hazard and a mutation test proved it wrong: `raw` above is
  // `_exercisesForEquipmentProvider`, the vendor catalogue, which never
  // carries an `ai::` row — so `isGenerated` is false for everything in this
  // pool and the branch cannot currently fire. It is kept, and kept in step
  // with the other one, because the pool's source is exactly the kind of
  // thing a later change swaps for a feed that does include generated rows,
  // and a filter that disagrees with its twin is how that lands unnoticed.
  final shown = withDemonstration(
    cannotScreenGeneratedFor(profile)
        ? raw.where((e) => !isGenerated(e)).toList()
        : raw,
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
/// Gate N. This is a RECOMMENDATION feed, so it runs the whole eligibility
/// layer — screening, injuries, normalised health restrictions and equipment —
/// where [safeCatalogProvider] runs only the injury filter.
///
/// The two are deliberately different. Browsing the catalogue and being offered
/// a session are different acts: looking at a leg press you do not own is
/// information, and being handed it as today's work is a broken recommendation.
/// That distinction is why equipment reached two of six surfaces before this —
/// it was applied where somebody remembered, not where the question arises.
final forYouExercisesProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final safe = await ref.watch(safeCatalogProvider.future);
  final profile = await ref.watch(screeningProfileProvider.future);
  final context = await ref.watch(safetyContextProvider.future);
  return sortByTierFit(
    eligibleExercises(safe, context),
    profile?.level.tier,
  );
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
  const ExerciseResolution._(this.exercise, this.withheldFor);

  /// Found, and safe to show.
  const ExerciseResolution.found(ExerciseItem exercise)
      : this._(exercise, const []);

  /// No exercise carries this id.
  const ExerciseResolution.notFound() : this._(null, const []);

  /// Found, but contraindicated by the user's own injury list.
  const ExerciseResolution.hiddenForInjury(ExerciseItem exercise)
      : this._(exercise, const [EligibilityReason(BlockReason.injury)]);

  /// Found, and withheld for reasons the eligibility layer named.
  ///
  /// Gate N. Catalogue navigation was the last surface where a user could
  /// reach work the generators would have refused them: the deep link screened
  /// injuries and nothing else, so someone whose PAR-Q+ answers blocked every
  /// generated plan could still tap an exercise out of the Train tab and be
  /// taken straight into the player.
  const ExerciseResolution.withheld(
      ExerciseItem exercise, List<EligibilityReason> reasons)
      : this._(exercise, reasons);

  /// The exercise, whether or not it may be shown. Null only when nothing
  /// carries the id.
  final ExerciseItem? exercise;

  /// Why it is being withheld, empty when it is not.
  ///
  /// Machine-readable, so the player can say which answer is responsible
  /// without this file owning any English.
  final List<EligibilityReason> withheldFor;

  /// True when [exercise] exists but conflicts with a logged injury.
  ///
  /// Kept as a named question rather than replaced by `withheldFor.isNotEmpty`:
  /// the player draws a different card for an injury (which names the body
  /// part the user themselves reported) than for a screening refusal, and
  /// callers that only ever cared about injuries keep reading true/false.
  bool get hiddenForInjury =>
      withheldFor.any((r) => r.reason == BlockReason.injury);

  /// The exercise, or null when it must not be surfaced.
  ExerciseItem? get visible => withheldFor.isEmpty ? exercise : null;
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
    FutureProvider.family<ExerciseResolution, String>((ref, id) =>
        _resolveExercise(ref, id, includeWholePerson: true));

/// The same lookup, for a surface that only ever DISPLAYS an id — never a tap,
/// never a deep link, never a session about to start.
///
/// D-09: `workouts_page.dart`'s current-programme-day thumbnail strip reads an
/// exercise id straight out of a scheduled day to draw its picture, the same
/// "which of these are suitable" shape `eligibleExercises` already exists for
/// (`eligibility.dart`), not the "may this person do THIS, now" shape
/// `exerciseResolutionProvider` is for. Sharing that provider meant an
/// unscreened user's every thumbnail in an already-scheduled day silently
/// turned into the "no clip filmed" gradient tile — the D-01 failure shape,
/// just at exercise-thumbnail granularity instead of list granularity. A
/// STATED refusal (an injury, a movement restriction, an answered PAR-Q+
/// "yes") still withholds the picture here; only the fail-closed
/// unanswered-screening gate does not.
final exercisePreviewResolutionProvider =
    FutureProvider.family<ExerciseResolution, String>((ref, id) =>
        _resolveExercise(ref, id, includeWholePerson: false));

Future<ExerciseResolution> _resolveExercise(
  Ref ref,
  String id, {
  required bool includeWholePerson,
}) async {
  final profile = await ref.watch(screeningProfileProvider.future);

  // Gate N: the whole eligibility layer, not just the injury filter. This is a
  // "may this person do THIS, now" question — the user has tapped a specific
  // exercise — so the whole-person gate applies, unlike in a feed.
  //
  // Equipment is deliberately NOT part of this context. A user who taps a leg
  // press they do not own has said something explicit about what they want to
  // look at, and refusing it would turn a browse into a prescription.
  final context = profile == null
      ? SafetyContext(screening: par_q.kUnscreened)
      : SafetyContext(
          screening: par_q.screen(profile.health.screening),
          injuries: profile.health.injuries,
          health: profile.health.flags,
        );

  ExerciseResolution screenOne(ExerciseItem? found) {
    if (found == null) return const ExerciseResolution.notFound();
    final verdict = evaluateExercise(found, context,
        includeWholePerson: includeWholePerson);
    if (verdict.isAllowed || verdict is Degraded) {
      return ExerciseResolution.found(found);
    }
    return ExerciseResolution.withheld(found, verdict.reasons);
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
  //
  // F023 widened "injury-aware" to include movement restrictions — see
  // [cannotScreenGeneratedFor].
  if (id.startsWith('ai::')) {
    if (cannotScreenGeneratedFor(profile)) {
      return const ExerciseResolution.notFound();
    }
    final parts = id.split('::');
    if (parts.length != 3) return const ExerciseResolution.notFound();
    final lang = ref.watch(effectiveLanguageCodeProvider);
    final cached =
        await ref.watch(generatedExerciseRepositoryProvider).get(parts[1], lang);
    if (cached == null) return const ExerciseResolution.notFound();
    for (final e in cached) {
      if (e.id == id) return screenOne(e);
    }
    return const ExerciseResolution.notFound();
  }

  final repo = ref.watch(equipmentRepositoryProvider);
  for (final e in await repo.bodyweightExercises()) {
    if (e.id == id) return screenOne(e);
  }
  for (final eq in await repo.listEquipment()) {
    for (final e in await repo.exercisesFor(eq.id)) {
      if (e.id == id) return screenOne(e);
    }
  }
  return const ExerciseResolution.notFound();
}

/// Where a clip reference becomes a playable URL.
///
/// The licensed library lives in a private bucket, so its catalog entries are
/// object paths rather than URLs and have to be signed per request — see
/// `clip_url_resolver.dart`. Overridden in tests with a passthrough so the
/// widget suite needs no Firebase.
final clipUrlResolverProvider = Provider<ClipUrlResolver>((ref) {
  return FunctionsClipUrlResolver();
});
