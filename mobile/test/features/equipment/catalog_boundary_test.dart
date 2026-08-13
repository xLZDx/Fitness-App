import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// The catalog's safety boundary, tested at the boundary rather than at each
/// screen.
///
/// Every list in the app screened exercises against the user's injuries and
/// two paths did not: the deep link `/workout/:id`, whose lookup re-scanned
/// the repository directly, and the whole catalog during the seconds before
/// the profile arrived. Both were reachable by a user with a knee injury, and
/// neither could fail a test, because no test asked.

const _kneeExercise = ExerciseItem(
  id: 'squat',
  title: 'Back squat',
  equipmentId: 'rack',
  muscles: ['quads'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/squat.mp4',
  contraindications: ['knee'],
);

const _safeExercise = ExerciseItem(
  id: 'row',
  title: 'Seated row',
  equipmentId: 'rack',
  muscles: ['back'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/row.mp4',
);

const _rack = EquipmentItem(
  id: 'rack',
  name: 'Rack',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

UserProfile _injured() => const UserProfile(
      uid: 'u1',
      health: HealthHistory(
        injuries: [Injury(bodyPart: 'knee', type: 'strain')],
      ),
    );

const _user = AuthUser(uid: 'u1', displayName: 'U');

/// Emits profiles on demand so a test can hold the catalog in the exact state
/// the bug lived in: signed in, catalog loaded, profile not yet arrived.
class _SlowProfileRepo implements ProfileRepository {
  final _controller = StreamController<UserProfile?>.broadcast();

  void emit(UserProfile? p) => _controller.add(p);
  Future<void> close() => _controller.close();

  @override
  Stream<UserProfile?> watch(String uid) => _controller.stream;

  @override
  UserProfile? cached(String uid) => null;

  @override
  Future<UserProfile?> load(String uid) async => null;

  @override
  Future<void> save(UserProfile profile) async {}

  @override
  Future<void> delete(String uid) async {}
}

AssetEquipmentRepository _repo() => AssetEquipmentRepository()
  ..seedForTests(
    equipment: const [_rack],
    exercises: const [_kneeExercise, _safeExercise],
  );

ProviderContainer _container({UserProfile? profile}) {
  final container = ProviderContainer(overrides: [
    effectiveLanguageCodeProvider.overrideWithValue('en'),
    equipmentRepositoryProvider.overrideWithValue(_repo()),
    screeningProfileProvider.overrideWith((ref) async => profile),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the public catalog', () {
    test('an injured user is not served the exercise that hurts them',
        () async {
      final safe = await _container(profile: _injured()).read(
        safeCatalogProvider.future,
      );
      expect(safe.map((e) => e.id), ['row']);
    });

    test('a user with no injuries gets everything', () async {
      final safe = await _container().read(safeCatalogProvider.future);
      expect(safe.map((e) => e.id), containsAll(['row', 'squat']));
    });

    test('the For-you feed is ordered, not separately screened', () async {
      // Screening lives in one place. If this ever diverges from
      // safeCatalogProvider it means a second filter grew somewhere.
      final container = _container(profile: _injured());
      final forYou = await container.read(forYouExercisesProvider.future);
      final safe = await container.read(safeCatalogProvider.future);
      expect(forYou.map((e) => e.id).toSet(), safe.map((e) => e.id).toSet());
    });
  });

  group('a deep link to a contraindicated exercise', () {
    test('is withheld, and says so', () async {
      final r = await _container(profile: _injured())
          .read(exerciseResolutionProvider('squat').future);
      expect(r.hiddenForInjury, isTrue);
      expect(r.visible, isNull, reason: 'the player must not render it');
      expect(r.exercise?.title, 'Back squat',
          reason: 'the page still needs the title to name what is withheld');
    });

    test('is not the same state as a broken link', () async {
      // The whole reason [ExerciseResolution] has three cases. Telling someone
      // their own scheduled squat "could not be found" is false, and it hides
      // the one thing they can act on.
      final r = await _container(profile: _injured())
          .read(exerciseResolutionProvider('no_such_id').future);
      expect(r.hiddenForInjury, isFalse);
      expect(r.exercise, isNull);
    });

    test('resolves normally when nothing conflicts', () async {
      final r = await _container(profile: _injured())
          .read(exerciseResolutionProvider('row').future);
      expect(r.visible?.id, 'row');
    });

    test('a malformed ai:: id is not found rather than throwing', () async {
      final r = await _container()
          .read(exerciseResolutionProvider('ai::broken').future);
      expect(r.exercise, isNull);
    });
  });

  group('the cold-start window', () {
    // The gap this closes: every caller read
    // `ref.watch(currentProfileProvider).valueOrNull`, which is null both when
    // a user has no profile and when it has not loaded yet. The first means
    // "nothing to screen against", the second means "we do not know yet", and
    // treating them alike served the full catalog for as long as the read took
    // -- on every cold start, every sign-in and every refetch.
    late _SlowProfileRepo profiles;

    setUp(() => profiles = _SlowProfileRepo());
    tearDown(() => profiles.close());

    ProviderContainer racing() {
      final container = ProviderContainer(overrides: [
        effectiveLanguageCodeProvider.overrideWithValue('en'),
        equipmentRepositoryProvider.overrideWithValue(_repo()),
        authUserProvider.overrideWith((ref) => Stream.value(_user)),
        profileRepositoryProvider.overrideWithValue(profiles),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('the catalog is still loading, not unfiltered', () async {
      final container = racing();
      final sub = container.listen(safeCatalogProvider, (_, __) {});
      addTearDown(sub.close);

      // Auth has resolved and the catalog has been read; only the profile is
      // outstanding. This is the exact frame the old code rendered.
      await pumpEventQueue();

      final state = container.read(safeCatalogProvider);
      expect(state, isA<AsyncLoading<List<ExerciseItem>>>());
      expect(state.valueOrNull, isNull,
          reason: 'an unfiltered list here is what an injured user saw');
    });

    test('and screens correctly the moment the profile lands', () async {
      final container = racing();
      final sub = container.listen(safeCatalogProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      profiles.emit(_injured());
      await pumpEventQueue();

      expect(container.read(safeCatalogProvider).valueOrNull?.map((e) => e.id),
          ['row']);
    });

    test('a deep link opened mid-load is withheld too', () async {
      final container = racing();
      final sub =
          container.listen(exerciseResolutionProvider('squat'), (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      expect(container.read(exerciseResolutionProvider('squat')),
          isA<AsyncLoading<ExerciseResolution>>());

      profiles.emit(_injured());
      await pumpEventQueue();

      expect(
        container.read(exerciseResolutionProvider('squat')).valueOrNull
            ?.hiddenForInjury,
        isTrue,
      );
    });
  });

  group('the boundary itself', () {
    /// Source with line comments removed.
    ///
    /// Both scans below look for a provider name in the file text, and the
    /// first thing that broke was a doc-comment in `workout_player_page.dart`
    /// explaining that the page no longer reads the raw repository. A test
    /// that cannot tell a reference from a mention would train everyone to
    /// stop mentioning things.
    String code(File f) => f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    Iterable<File> dartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    // `_allExercisesProvider` and `_exercisesForEquipmentProvider` are
    // file-private, so a reader outside the file is a compile error and needs
    // no test. This covers the one that could not be: the AI-fallback provider
    // is `@visibleForTesting` because the generate-once economics it encodes
    // have no other observable seam.
    test('the raw fallback provider has no reader in lib/', () {
      final offenders = <String>[];
      for (final file in dartFiles()) {
        if (file.path.endsWith('equipment_providers.dart')) continue;
        if (code(file).contains('exercisesForEquipmentWithAiFallbackProvider')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'this is the unscreened per-machine feed; '
              'recommendedExercisesProvider is the one to read');
    });

    test('the raw repository is read only by the paths verified safe', () {
      // Enumerated rather than forbidden, because three of these are correct
      // and one of them is load-bearing: `fitnessProfileProvider` builds a
      // muscle map out of the whole catalog and never renders an exercise --
      // screening it would corrupt the fitness model rather than protect
      // anyone. A new name appearing here is not automatically a bug; it is a
      // decision that has to be made deliberately, which is the point.
      const allowed = {
        // The boundary itself.
        'equipment_providers.dart',
        // Muscle map for the fitness model. Never renders an exercise.
        'personalisation_providers.dart',
        // Reads EquipmentItem categories only; no ExerciseItem crosses it.
        'workouts_page.dart',
        // Counts contraindication tags across the catalog; the count must be
        // of the whole catalog, not of one user's screened view.
        'safety_coverage_providers.dart',
        // Builds the candidate pool; plan_builder filters before output.
        'ai_planner_providers.dart',
        // O10's onboarding preview. Same shape and same reason as the line
        // above — it builds a candidate pool and hands it to the same
        // `buildPlan`, whose first step is `filterContraindicated`. It exists
        // separately only because it reads the DRAFT profile: at that point in
        // the flow nothing has been saved, so `currentProfileProvider` would
        // screen against the answers the user had before they answered.
        'plan_preview_provider.dart',
      };
      final readers = <String>{};
      for (final file in dartFiles()) {
        if (code(file).contains('equipmentRepositoryProvider')) {
          readers.add(file.uri.pathSegments.last);
        }
      }
      expect(readers.difference(allowed), isEmpty,
          reason: 'a new raw-catalog reader has to be screened, or listed here '
              'with the reason it does not need to be');
    });
  });

  group('the player, for a withheld exercise', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: _container(profile: _injured()),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WorkoutPlayerPage(exerciseId: 'squat'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names the exercise instead of denying it exists',
        (tester) async {
      await open(tester);
      expect(find.textContaining('Back squat'), findsOneWidget);
      expect(find.textContaining("couldn't find"), findsNothing);
    });

    testWidgets('says why, and where to change it', (tester) async {
      await open(tester);
      expect(find.textContaining('injury you told us about'), findsOneWidget);
    });
  });

  group('AI-generated exercises', () {
    // The one class of row no tagging pass can reach. They are generated per
    // user, per machine, per language, at read time, and the generator emits
    // no `contraindications` field at all -- so `isContraindicated` returns
    // false for every one of them however the user is injured.
    //
    // While coverage was 0 that was a harmless no-op. S3b made it a hazard:
    // the app now says lists ARE screened, and these are the rows the claim is
    // false about. The plan's own answer, taken here: excluded for
    // injury-aware users until a generation-time tagging pass exists.
    const generated = ExerciseItem(
      id: 'ai::rack::0',
      title: 'Invented movement',
      equipmentId: 'rack',
      muscles: ['quads'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: 's',
      steps: ['a'],
      videoUrl: 'https://example.test/ai.mp4',
    );

    // The rack has no vendored exercises, so the machine falls through to the
    // generated cache -- the production path for the 11 cardio ids.
    Future<ProviderContainer> withGenerated({UserProfile? profile}) async {
      final repo = AssetEquipmentRepository()
        ..seedForTests(equipment: const [_rack], exercises: const []);
      final gen = MockGeneratedExerciseRepository();
      await gen.save('rack', 'en', const [generated]);
      final container = ProviderContainer(overrides: [
        effectiveLanguageCodeProvider.overrideWithValue('en'),
        equipmentRepositoryProvider.overrideWithValue(repo),
        generatedExerciseRepositoryProvider.overrideWithValue(gen),
        screeningProfileProvider.overrideWith((ref) async => profile),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('reach a user with no injuries', () async {
      // The control. Without it the exclusion below could pass because the
      // fixture never produced a generated exercise at all.
      final container = await withGenerated();
      final result =
          await container.read(recommendedExercisesProvider('rack').future);
      expect(result.items.map((e) => e.id), ['ai::rack::0']);
    });

    test('are not surfaced to a user with an injury', () async {
      final container = await withGenerated(profile: _injured());
      final result =
          await container.read(recommendedExercisesProvider('rack').future);
      expect(result.items, isEmpty);
    });

    test('a deep link to one is not found for an injured user', () async {
      final container = await withGenerated(profile: _injured());
      final r = await container
          .read(exerciseResolutionProvider('ai::rack::0').future);
      expect(r.exercise, isNull);
    });

    test('a deep link to one still works without injuries', () async {
      final container = await withGenerated();
      final r = await container
          .read(exerciseResolutionProvider('ai::rack::0').future);
      expect(r.visible?.id, 'ai::rack::0');
    });

    test('isGenerated names them by id, not by a flag nobody sets', () {
      expect(isGenerated(generated), isTrue);
      expect(isGenerated(_safeExercise), isFalse);
    });

    test('hasInjuries is what gates it', () {
      expect(hasInjuries(_injured()), isTrue);
      expect(hasInjuries(null), isFalse);
      expect(hasInjuries(const UserProfile(uid: 'u')), isFalse);
    });
  });
}
