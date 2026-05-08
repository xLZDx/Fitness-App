import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

ExerciseItem _ex({
  required String id,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  List<String> contraindications = const [],
}) {
  return ExerciseItem(
    id: id,
    title: id,
    equipmentId: 'eq',
    muscles: const [],
    difficulty: difficulty,
    durationMinutes: 10,
    summary: '',
    steps: const [],
    contraindications: contraindications,
  );
}

void main() {
  group('filterContraindicated', () {
    test('returns the input unchanged when injuries are empty', () {
      final list = [_ex(id: 'a', contraindications: ['knee'])];
      final out = filterContraindicated(list, const []);
      expect(out, hasLength(1));
      expect(out.first.id, 'a');
    });

    test('removes exercises whose contraindication matches an injury', () {
      final list = [
        _ex(id: 'safe'),
        _ex(id: 'knee_risk', contraindications: ['knee']),
        _ex(id: 'back_risk', contraindications: ['lower_back']),
      ];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'knee', type: 'sprain')],
      );
      expect(out.map((e) => e.id), ['safe', 'back_risk']);
    });

    test('matches "left knee" against "knee" contraindication', () {
      final list = [_ex(id: 'risk', contraindications: ['knee'])];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'Left Knee', type: 'tear')],
      );
      expect(out, isEmpty);
    });

    test('matches "lower_back" injury against "back" tag and vice versa', () {
      final list = [
        _ex(id: 'a', contraindications: ['back']),
        _ex(id: 'b', contraindications: ['lower_back']),
        _ex(id: 'c', contraindications: ['knee']),
      ];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'lower back', type: 'strain')],
      );
      // a and b both match "lower back" via substring; c is unrelated.
      expect(out.map((e) => e.id), ['c']);
    });

    test('does not collide unrelated tags', () {
      final list = [_ex(id: 'shoulder', contraindications: ['shoulder'])];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'ankle', type: 'sprain')],
      );
      expect(out, hasLength(1));
    });

    test('keeps exercises with no contraindications regardless of injuries',
        () {
      final list = [_ex(id: 'free')];
      final out = filterContraindicated(
        list,
        const [Injury(bodyPart: 'knee', type: 'sprain')],
      );
      expect(out, hasLength(1));
    });
  });

  group('sortByTierFit', () {
    final beginner = _ex(id: 'b', difficulty: ExerciseDifficulty.beginner);
    final intermediate =
        _ex(id: 'i', difficulty: ExerciseDifficulty.intermediate);
    final advanced = _ex(id: 'a', difficulty: ExerciseDifficulty.advanced);

    test('returns a copy, not the original list reference', () {
      final input = [advanced, beginner, intermediate];
      final out = sortByTierFit(input, FitnessTier.beginner);
      expect(identical(input, out), isFalse);
    });

    test('beginner user surfaces beginner exercises first', () {
      final out =
          sortByTierFit([advanced, beginner, intermediate], FitnessTier.beginner);
      expect(out.map((e) => e.id), ['b', 'i', 'a']);
    });

    test('advanced user surfaces advanced exercises first', () {
      final out =
          sortByTierFit([beginner, advanced, intermediate], FitnessTier.advanced);
      expect(out.map((e) => e.id), ['a', 'i', 'b']);
    });

    test('intermediate user surfaces intermediate first', () {
      final out =
          sortByTierFit([beginner, advanced, intermediate], FitnessTier.intermediate);
      expect(out.first.id, 'i');
    });

    test('null tier preserves order', () {
      final out = sortByTierFit([advanced, beginner, intermediate], null);
      expect(out.map((e) => e.id), ['a', 'b', 'i']);
    });
  });

  group('recommended (full pipeline)', () {
    test('null profile passes through unchanged', () {
      final list = [
        _ex(id: 'a', contraindications: ['knee']),
        _ex(id: 'b'),
      ];
      expect(recommended(list, null).map((e) => e.id), ['a', 'b']);
    });

    test('filters contraindicated then sorts by tier', () {
      final list = [
        _ex(id: 'beg_safe', difficulty: ExerciseDifficulty.beginner),
        _ex(id: 'adv_risk',
            difficulty: ExerciseDifficulty.advanced,
            contraindications: ['knee']),
        _ex(id: 'adv_safe', difficulty: ExerciseDifficulty.advanced),
      ];
      final profile = UserProfile(
        uid: 'u1',
        health: const HealthHistory(injuries: [
          Injury(bodyPart: 'knee', type: 'sprain'),
        ]),
        level: const FitnessLevel(tier: FitnessTier.advanced),
      );
      final out = recommended(list, profile);
      expect(out.map((e) => e.id), ['adv_safe', 'beg_safe']);
    });
  });
}
