import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';

void main() {
  group('AssetEquipmentRepository (seeded)', () {
    late AssetEquipmentRepository repo;

    setUp(() {
      repo = AssetEquipmentRepository()
        ..seedForTests(
          equipment: const [
            EquipmentItem(
              id: 'treadmill_x',
              name: 'X',
              manufacturer: 'Acme',
              category: 'cardio',
              description: 'Test treadmill',
            ),
            EquipmentItem(
              id: 'rack_y',
              name: 'Y',
              manufacturer: 'Rogue',
              category: 'strength',
              description: 'Test rack',
            ),
          ],
          exercises: const [
            ExerciseItem(
              id: 'tread_run',
              title: 'Easy run',
              equipmentId: 'treadmill_x',
              muscles: ['quads'],
              difficulty: ExerciseDifficulty.beginner,
              durationMinutes: 20,
              summary: '',
              steps: [],
            ),
            ExerciseItem(
              id: 'pushup',
              title: 'Push-ups',
              equipmentId: null,
              muscles: ['chest'],
              difficulty: ExerciseDifficulty.beginner,
              durationMinutes: 8,
              summary: '',
              steps: [],
            ),
            ExerciseItem(
              id: 'squat',
              title: 'Squat',
              equipmentId: 'rack_y',
              muscles: ['quads'],
              difficulty: ExerciseDifficulty.intermediate,
              durationMinutes: 30,
              summary: '',
              steps: [],
            ),
          ],
        );
    });

    test('listEquipment returns the seeded items', () async {
      final list = await repo.listEquipment();
      expect(list, hasLength(2));
      expect(list.map((e) => e.id), containsAll(['treadmill_x', 'rack_y']));
    });

    test('findEquipment finds by id', () async {
      final hit = await repo.findEquipment('rack_y');
      expect(hit, isNotNull);
      expect(hit!.name, 'Y');
    });

    test('findEquipment returns null for unknown id', () async {
      expect(await repo.findEquipment('nope'), isNull);
    });

    test('exercisesFor only returns exercises for the requested equipment',
        () async {
      final list = await repo.exercisesFor('treadmill_x');
      expect(list, hasLength(1));
      expect(list.first.id, 'tread_run');
    });

    test('bodyweightExercises filters to equipmentId == null', () async {
      final list = await repo.bodyweightExercises();
      expect(list, hasLength(1));
      expect(list.first.id, 'pushup');
    });
  });

  group('ExerciseItem.fromJson', () {
    test('parses a full record', () {
      final e = ExerciseItem.fromJson(const {
        'id': 'x',
        'title': 'Test',
        'equipmentId': 'eq',
        'muscles': ['a', 'b'],
        'difficulty': 'advanced',
        'durationMinutes': 42,
        'summary': 'sum',
        'steps': ['s1', 's2'],
        'contraindications': ['knee'],
      });
      expect(e.difficulty, ExerciseDifficulty.advanced);
      expect(e.durationMinutes, 42);
      expect(e.muscles, ['a', 'b']);
      expect(e.contraindications, ['knee']);
    });
  });
}
