import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';

void main() {
  group('MockGeneratedExerciseRepository', () {
    test('a machine with nothing cached returns null, not an empty list',
        () async {
      final repo = MockGeneratedExerciseRepository();
      expect(await repo.get('elliptical', 'ru'), isNull);
    });

    test('save then get round-trips', () async {
      final repo = MockGeneratedExerciseRepository();
      const item = ExerciseItem(
        id: 'ai::elliptical::0',
        title: 'X',
        equipmentId: 'elliptical',
        muscles: ['quads'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 8,
        summary: 's',
        steps: ['a'],
      );
      await repo.save('elliptical', 'ru', [item]);
      final out = await repo.get('elliptical', 'ru');
      expect(out!.single.id, 'ai::elliptical::0');
    });

    test('language is part of the cache key -- ru and en do not collide',
        () async {
      final repo = MockGeneratedExerciseRepository();
      const ru = ExerciseItem(
        id: 'ai::elliptical::0',
        title: 'Русский',
        equipmentId: 'elliptical',
        muscles: [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 8,
        summary: 's',
        steps: ['a'],
      );
      const en = ExerciseItem(
        id: 'ai::elliptical::0',
        title: 'English',
        equipmentId: 'elliptical',
        muscles: [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 8,
        summary: 's',
        steps: ['a'],
      );
      await repo.save('elliptical', 'ru', [ru]);
      await repo.save('elliptical', 'en', [en]);
      expect((await repo.get('elliptical', 'ru'))!.single.title, 'Русский');
      expect((await repo.get('elliptical', 'en'))!.single.title, 'English');
    });
  });
}
