import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';

/// REGRESSION (Gate D7 silent-failure review) -- `equipmentExerciseIdsProvider`
/// used to read ONLY the vendored catalog (`EquipmentRepository.exercisesFor`),
/// which is empty for the 11 registry machines with nothing real, per
/// `exercisesForEquipmentWithAiFallbackProvider`'s own doc comment. Every
/// workout logged against one of those machines is logged under a generated
/// `ai::$equipmentId::$i` id, so history matching for them silently and
/// permanently failed -- indistinguishable from "never used this equipment".
class _EmptyEquipmentRepository implements EquipmentRepository {
  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => const [];
  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => const [];
  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;
  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
}

ExerciseItem _generated(String equipmentId, int i) => ExerciseItem.fromJson({
      'id': 'ai::$equipmentId::$i',
      'title': 'Generated $i',
      'equipmentId': equipmentId,
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': const <String>[],
      'steps': const ['Step'],
    });

void main() {
  test(
      'includes cached AI-generated exercise ids when the vendored catalog is empty',
      () async {
    final genRepo = MockGeneratedExerciseRepository();
    await genRepo.save('rowing_erg', 'en', [
      _generated('rowing_erg', 0),
      _generated('rowing_erg', 1),
    ]);

    final container = ProviderContainer(overrides: [
      equipmentRepositoryProvider.overrideWithValue(_EmptyEquipmentRepository()),
      generatedExerciseRepositoryProvider.overrideWithValue(genRepo),
      effectiveLanguageCodeProvider.overrideWithValue('en'),
    ]);
    addTearDown(container.dispose);

    final ids = await container.read(equipmentExerciseIdsProvider('rowing_erg').future);

    expect(ids, {'ai::rowing_erg::0', 'ai::rowing_erg::1'},
        reason: 'a workout logged under a generated id must be matchable '
            'once its exercises have been generated at least once');
  });

  test('an equipment type with a real catalog never falls through to the cache',
      () async {
    final genRepo = MockGeneratedExerciseRepository();
    // Seeded to prove it is NOT read when the real catalog already answers --
    // if it were read, this wrong id would leak into the result.
    await genRepo.save('leg_press', 'en', [_generated('leg_press', 0)]);

    final container = ProviderContainer(overrides: [
      equipmentRepositoryProvider.overrideWithValue(
        _RealCatalogEquipmentRepository({
          'leg_press': ['leg_press_machine'],
        }),
      ),
      generatedExerciseRepositoryProvider.overrideWithValue(genRepo),
      effectiveLanguageCodeProvider.overrideWithValue('en'),
    ]);
    addTearDown(container.dispose);

    final ids = await container.read(equipmentExerciseIdsProvider('leg_press').future);

    expect(ids, {'leg_press_machine'});
  });

  test('nothing cached yet for a generated-only type -> empty, not a throw', () async {
    final container = ProviderContainer(overrides: [
      equipmentRepositoryProvider.overrideWithValue(_EmptyEquipmentRepository()),
      generatedExerciseRepositoryProvider
          .overrideWithValue(MockGeneratedExerciseRepository()),
      effectiveLanguageCodeProvider.overrideWithValue('en'),
    ]);
    addTearDown(container.dispose);

    final ids = await container.read(equipmentExerciseIdsProvider('rowing_erg').future);

    expect(ids, isEmpty);
  });
}

class _RealCatalogEquipmentRepository implements EquipmentRepository {
  _RealCatalogEquipmentRepository(this._byEquipment);
  final Map<String, List<String>> _byEquipment;

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => [
        for (final id in _byEquipment[equipmentId] ?? const <String>[])
          ExerciseItem.fromJson({
            'id': id,
            'title': id,
            'equipmentId': equipmentId,
            'durationMinutes': 10,
            'difficulty': 'beginner',
            'muscles': const <String>[],
            'steps': const ['Step'],
          }),
      ];

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => const [];
  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;
  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
}
