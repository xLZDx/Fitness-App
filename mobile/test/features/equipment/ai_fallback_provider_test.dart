import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/ai_coach/ai_exercise_generator.dart';
import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

const _elliptical = EquipmentItem(
  id: 'elliptical',
  name: 'Elliptical',
  manufacturer: 'Any',
  category: 'cardio',
  description: 'd',
);
const _treadmill = EquipmentItem(
  id: 'treadmill',
  name: 'Treadmill',
  manufacturer: 'Any',
  category: 'cardio',
  description: 'd',
);
const _realExercise = ExerciseItem(
  id: 'treadmill_walk',
  title: 'Walk',
  equipmentId: 'treadmill',
  muscles: ['quads'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 8,
  summary: 's',
  steps: ['a'],
  // A catalog exercise the app can actually demonstrate. Stated on the fixture
  // because `recommendedExercisesProvider` applies `withDemonstration`, and a
  // clipless fixture would make the control below pass for the wrong reason.
  videoUrl: 'https://example.invalid/walk.mp4',
);

const _genJson = '[{"title": "AI Elliptical Warm-up", "steps": ["a", "b"], '
    '"muscles": ["quads"], "primaryMuscles": ["quads"], '
    '"difficulty": "beginner", "durationMinutes": 8}]';

ProviderContainer _makeContainer({
  required int Function() askCallCount,
  GeneratedExerciseRepository? generatedRepo,
  Future<String> Function(String equipmentId, String languageCode)? ask,
  UserProfile? profile,
}) {
  final repo = AssetEquipmentRepository()
    ..seedForTests(
      equipment: const [_elliptical, _treadmill],
      exercises: const [_realExercise],
    );
  final container = ProviderContainer(overrides: [
    // Pinned so the test does not depend on the host machine's locale --
    // effectiveLanguageCodeProvider otherwise resolves from the device
    // locales the test runner happens to report.
    effectiveLanguageCodeProvider.overrideWithValue('en'),
    equipmentRepositoryProvider.overrideWithValue(repo as EquipmentRepository),
    // No signed-in user, so nothing to screen against. Stated rather than
    // inherited: the safe catalog now waits on auth AND the profile, and a
    // container that resolved neither would hang instead of failing.
    screeningProfileProvider.overrideWith((ref) async => profile),
    generatedExerciseRepositoryProvider
        .overrideWithValue(generatedRepo ?? MockGeneratedExerciseRepository()),
    aiExerciseGeneratorProvider.overrideWithValue(
        AiExerciseGenerator(ask: (equipmentId, languageCode) async {
      askCallCount();
      if (ask != null) return ask(equipmentId, languageCode);
      return _genJson;
    })),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('exercisesForEquipmentWithAiFallbackProvider', () {
    test('a machine WITH real exercises never calls the generator', () async {
      var calls = 0;
      final container = _makeContainer(askCallCount: () => calls++);
      final out = await container
          .read(exercisesForEquipmentWithAiFallbackProvider('treadmill').future);
      expect(out, [_realExercise]);
      expect(calls, 0);
    });

    test('a machine with nothing real generates, then saves to the cache',
        () async {
      var calls = 0;
      final genRepo = MockGeneratedExerciseRepository();
      final container =
          _makeContainer(askCallCount: () => calls++, generatedRepo: genRepo);
      final out = await container
          .read(exercisesForEquipmentWithAiFallbackProvider('elliptical').future);
      expect(calls, 1);
      expect(out.single.title, 'AI Elliptical Warm-up');
      expect(await genRepo.get('elliptical', 'en'), isNotNull,
          reason: 'the result must be cached for next time');
    });

    test('a second call reads the cache instead of asking Gemini again',
        () async {
      var calls = 0;
      final genRepo = MockGeneratedExerciseRepository();
      final container =
          _makeContainer(askCallCount: () => calls++, generatedRepo: genRepo);
      await container
          .read(exercisesForEquipmentWithAiFallbackProvider('elliptical').future);
      // A fresh container simulates "reopen the page" without the
      // FutureProvider's own request-scoped cache masking a re-ask.
      final container2 =
          _makeContainer(askCallCount: () => calls++, generatedRepo: genRepo);
      final out = await container2
          .read(exercisesForEquipmentWithAiFallbackProvider('elliptical').future);
      expect(calls, 1, reason: 'only the first call should hit Gemini');
      expect(out.single.title, 'AI Elliptical Warm-up');
    });
  });

  group('safeCatalogProvider', () {
    test('a cached AI exercise is NOT surfaced — it has no footage', () async {
      // A behaviour change, not a broken test. AI-generated exercises are text:
      // a title, muscles and steps, with nothing to play. Since 2026-08-03 the
      // catalog shows a moving demonstration or it shows nothing, so these
      // never reach a list.
      //
      // The cache-not-generate half of this test still matters and is asserted
      // below — the Train tab must not fan out a Gemini call per empty machine
      // whether or not the result would be displayed.
      //
      // What replaces this for the user is the scan gate: name the machine,
      // record that we have no content for it, and point at an outside video
      // until we do. Operator: *"если этого нет в каталоге то помечать что надо
      // добавить, а клиенту посоветовать ролик на ютюбе"*.
      var calls = 0;
      final genRepo = MockGeneratedExerciseRepository();
      await genRepo.save('elliptical', 'en', const [
        ExerciseItem(
          id: 'ai::elliptical::0',
          title: 'Cached AI exercise',
          equipmentId: 'elliptical',
          muscles: ['quads'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 8,
          summary: 's',
          steps: ['a'],
        ),
      ]);
      final container =
          _makeContainer(askCallCount: () => calls++, generatedRepo: genRepo);
      final out = await container.read(safeCatalogProvider.future);
      expect(out.map((e) => e.title), isNot(contains('Cached AI exercise')),
          reason: 'text with no clip must not appear as a demonstrable exercise');
      expect(calls, 0,
          reason: 'the Train tab feed reads the cache, it must never generate');
    });

    test('a machine that was never visited stays absent from the feed',
        () async {
      final container = _makeContainer(askCallCount: () => 0);
      final out = await container.read(safeCatalogProvider.future);
      expect(out.where((e) => e.equipmentId == 'elliptical'), isEmpty);
    });
  });

  /// F023 (G-B/B6) — a movement restriction excludes generated exercises for
  /// the same reason an injury does.
  ///
  /// Generated rows carry no `contraindications` field and nothing can attach
  /// one, so `isContraindicated` returns false for every one of them however
  /// the user is restricted. The exclusion used to read the injury list and
  /// nothing else, which served untagged AI rows to a user whose only entry was
  /// a restriction — while the app told them the list was screened.
  ///
  /// A clip is stated on the fixtures below because both surfaces under test
  /// apply `withDemonstration`; a clipless one would pass for the wrong reason.
  group('F023: generated exercises and movement restrictions', () {
    const generated = ExerciseItem(
      id: 'ai::elliptical::0',
      title: 'AI elliptical intervals',
      equipmentId: 'elliptical',
      muscles: ['quads'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: 's',
      steps: ['a'],
      videoUrl: 'https://example.invalid/ai.mp4',
    );

    UserProfile profileWith({
      Set<MovementRestriction> restrictions = const {},
      List<Injury> injuries = const [],
    }) =>
        UserProfile(
          uid: 'u1',
          health: HealthHistory(
            injuries: injuries,
            screening: {for (final q in ParQQuestion.values) q: false},
            flags: HealthFlags(restrictions: restrictions),
          ),
        );

    Future<GeneratedExerciseRepository> seeded() async {
      final genRepo = MockGeneratedExerciseRepository();
      await genRepo.save('elliptical', 'en', const [generated]);
      return genRepo;
    }

    test('a restriction-only profile cannot resolve one by id', () async {
      // `exerciseResolutionProvider` is the only live path by which an `ai::`
      // row reaches a user: every list applies `withDemonstration` and
      // generated rows carry no clip, so this is what answers
      // `/workout/ai::elliptical::0` from a deep link or a history row. It is
      // terminal -- nothing downstream re-screens it.
      //
      // There is deliberately no companion test against
      // `recommendedExercisesProvider`: its pool is the vendor catalogue,
      // which holds no `ai::` rows at all, so such a test would pass against
      // the unfixed code and prove nothing. Verified by mutation, not assumed.
      final container = _makeContainer(
        askCallCount: () => 0,
        generatedRepo: await seeded(),
        profile: profileWith(restrictions: {MovementRestriction.overhead}),
      );

      final res = await container
          .read(exerciseResolutionProvider('ai::elliptical::0').future);
      expect(res.exercise, isNull);
    });

    test('an injury-only profile is still excluded, as it always was',
        () async {
      // The control for the pre-existing half of the rule: widening it must
      // not have replaced the injury case with the restriction one.
      final container = _makeContainer(
        askCallCount: () => 0,
        generatedRepo: await seeded(),
        profile: profileWith(
          injuries: const [Injury(bodyPart: 'shoulder', type: 'strain')],
        ),
      );

      final res = await container
          .read(exerciseResolutionProvider('ai::elliptical::0').future);
      expect(res.exercise, isNull);
    });

    test('a profile with neither still sees them', () async {
      // The feature must survive its own fix. Someone who has told us nothing
      // to screen against has nothing this rule can act on.
      final container = _makeContainer(
        askCallCount: () => 0,
        generatedRepo: await seeded(),
        profile: profileWith(),
      );

      final res = await container
          .read(exerciseResolutionProvider('ai::elliptical::0').future);
      expect(res.exercise?.id, 'ai::elliptical::0');
    });
  });

  /// C14 — the machine page must not buy what it cannot show.
  ///
  /// Measured on the shipped assets: 69 registry machines, 4 with no exercise
  /// linked. Opening one of those pages used to run the AI fallback, so a
  /// Gemini call and a cache write happened for text that
  /// `ai_exercise_generator.dart:135-149` builds with no `video` and no
  /// `videoUrl` — which `withDemonstration` then dropped in full. The user saw
  /// "nothing curated yet" either way, so the only observable effects of the
  /// call were the bill and the failure mode below.
  group('recommendedExercisesProvider', () {
    test('a machine with nothing curated does not reach the generator',
        () async {
      var calls = 0;
      final genRepo = MockGeneratedExerciseRepository();
      final container =
          _makeContainer(askCallCount: () => calls++, generatedRepo: genRepo);

      final rec = await container.read(recommendedExercisesProvider('elliptical').future);

      expect(rec.items, isEmpty, reason: 'nothing curated, and nothing invented');
      expect(calls, 0, reason: 'a paid call whose result withDemonstration drops');
      expect(await genRepo.get('elliptical', 'en'), isNull,
          reason: 'and nothing written to the cache either');
    });

    test('a generator that would fail changes nothing the user sees', () async {
      // The sharper half of the defect. The thrown Future used to reach
      // `equipment_detail_page.dart:156` and render "couldn't load exercises",
      // so a Gemini outage turned an honest empty state into an error card
      // about exercises that would have been discarded on success.
      var calls = 0;
      final container = _makeContainer(
        askCallCount: () => calls++,
        ask: (_, __) async => throw Exception('quota exhausted'),
      );

      final rec = await container.read(recommendedExercisesProvider('elliptical').future);

      expect(rec.items, isEmpty);
      expect(rec.hiddenForInjury, 0,
          reason: 'nothing was hidden — there was nothing to hide');
      expect(calls, 0);
    });

    test('CONTROL: a machine with curated exercises still serves them',
        () async {
      var calls = 0;
      final container = _makeContainer(askCallCount: () => calls++);

      final rec = await container.read(recommendedExercisesProvider('treadmill').future);

      expect(rec.items.map((e) => e.id), ['treadmill_walk']);
      expect(calls, 0);
    });
  });
}
