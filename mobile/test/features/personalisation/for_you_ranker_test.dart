import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/personalisation/data/for_you_ranker.dart';
// No `fitness_model.dart` import. The ranker's own test file no longer needs
// the difficulty model to construct a case, which is the cheapest available
// evidence that the two are actually separated.

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
      final out = rankForYou([], deficit: const <String, double>{});
      expect(out, isEmpty);
    });

    test('cold-start profile preserves input order', () {
      final input = [_ex('a', ['quads']), _ex('b', ['back'])];
      final out = rankForYou(input,
          deficit: const <String, double>{});
      expect(out.map((e) => e.id).toList(), ['a', 'b']);
    });

    test('the most neglected muscle group surfaces first', () {
      // Rewritten 2026-08-15. This case used to build a profile where quads
      // scored low on DIFFICULTY and assert the squat ranked first, calling
      // that muscle "weak". A low difficulty score means the user reported
      // the work as too hard, which is not the same claim — and acting on it
      // gave them more of what they could not tolerate. The measure is now
      // the weekly set deficit, so the fixture says what it means: quads have
      // been trained least this week.
      final input = [
        _ex('back-row', ['back']),
        _ex('squat', ['quads']),
      ];
      final out = rankForYou(
        input,
        deficit: const {'quads': 0.9, 'back': 0.1},
      );
      expect(out.first.id, 'squat');
    });

    test('novel exercise gets a small boost over recently-logged', () {
      final input = [
        _ex('squat-recent', ['quads']),
        _ex('squat-novel', ['quads']),
      ];
      final out = rankForYou(
        input,
        deficit: const {'quads': 0.5},
        recentExerciseIds: {'squat-recent'},
      );
      expect(out.first.id, 'squat-novel');
    });
  });
}
