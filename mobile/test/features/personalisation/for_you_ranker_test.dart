import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/personalisation/data/fitness_model.dart';
import 'package:fitness_app/features/personalisation/data/for_you_ranker.dart';

ExerciseItem _ex(String id, List<String> muscles) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.intermediate,
      durationMinutes: 10,
      summary: '',
      steps: const [],
    );

void main() {
  group('rankForYou', () {
    test('empty input returns empty', () {
      final out = rankForYou([], profile: FitnessProfile.empty);
      expect(out, isEmpty);
    });

    test('cold-start profile preserves input order', () {
      final input = [_ex('a', ['quads']), _ex('b', ['back'])];
      final out = rankForYou(input,
          profile: FitnessProfile.empty);
      expect(out.map((e) => e.id).toList(), ['a', 'b']);
    });

    test('weakest muscle group surfaces first', () {
      // Build a profile where 'back' has high score (strong) and
      // 'quads' has low score (weak — needs work).
      final profile = FitnessProfile(byMuscle: {
        'quads': MuscleFitness(muscle: 'quads', good: 1, total: 10),
        'back': MuscleFitness(muscle: 'back', good: 9, total: 10),
      });
      final input = [
        _ex('back-row', ['back']),
        _ex('squat', ['quads']),
      ];
      final out = rankForYou(input, profile: profile);
      // squat (weak quads) should rank higher than back-row.
      expect(out.first.id, 'squat');
    });

    test('novel exercise gets a small boost over recently-logged', () {
      final profile = FitnessProfile(byMuscle: {
        'quads': MuscleFitness(muscle: 'quads', good: 5, total: 10),
      });
      final input = [
        _ex('squat-recent', ['quads']),
        _ex('squat-novel', ['quads']),
      ];
      final out = rankForYou(
        input,
        profile: profile,
        recentExerciseIds: {'squat-recent'},
      );
      expect(out.first.id, 'squat-novel');
    });
  });
}
