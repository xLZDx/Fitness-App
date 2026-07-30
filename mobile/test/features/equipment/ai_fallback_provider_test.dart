import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/ai_coach/ai_exercise_generator.dart';
import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';

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
);

const _genJson = '[{"title": "AI Elliptical Warm-up", "steps": ["a", "b"], '
    '"muscles": ["quads"], "primaryMuscles": ["quads"], '
    '"difficulty": "beginner", "durationMinutes": 8}]';

ProviderContainer _makeContainer({
  required int Function() askCallCount,
  GeneratedExerciseRepository? generatedRepo,
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
    generatedExerciseRepositoryProvider
        .overrideWithValue(generatedRepo ?? MockGeneratedExerciseRepository()),
    aiExerciseGeneratorProvider.overrideWithValue(AiExerciseGenerator(ask: (_) async {
      askCallCount();
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

  group('allExercisesProvider', () {
    test('includes cached AI exercises for a real-empty machine, without generating',
        () async {
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
      final out = await container.read(allExercisesProvider.future);
      expect(out.map((e) => e.title), contains('Cached AI exercise'));
      expect(calls, 0,
          reason: 'the Train tab feed reads the cache, it must never generate');
    });

    test('a machine that was never visited stays absent from the feed',
        () async {
      final container = _makeContainer(askCallCount: () => 0);
      final out = await container.read(allExercisesProvider.future);
      expect(out.where((e) => e.equipmentId == 'elliptical'), isEmpty);
    });
  });
}
