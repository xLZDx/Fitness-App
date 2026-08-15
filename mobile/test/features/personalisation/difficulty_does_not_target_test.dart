import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/personalisation/data/for_you_ranker.dart';

/// A difficulty rating must not decide what the user is shown next.
///
/// This file replaces `adaptive_priority_direction_test.dart`, which existed to
/// stop the ranking direction being flipped by accident while the question was
/// open. The question is closed: a post-set difficulty rating is evidence about
/// how a dose landed, and selection comes from the weekly set deficit instead.
///
/// So the assertion changes shape. It is no longer "the direction is X" — it is
/// "no difficulty history changes the order at all". That is strictly stronger
/// and it cannot be satisfied by flipping a sign, which is what makes it the
/// right guard for a decision whose whole content was that the two signals are
/// separate.
///
/// If someone routes difficulty back into ranking — in either direction — the
/// tests here fail. That is the point.

ExerciseItem _ex(String id, {List<String> primary = const ['chest']}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      primaryMuscles: primary,
      muscles: primary,
      difficulty: ExerciseDifficulty.intermediate,
      durationMinutes: 10,
      summary: '',
      steps: const [],
    );

void main() {
  group('ranking follows the deficit, and nothing else', () {
    test('the most neglected muscle comes first', () {
      final ranked = rankForYou(
        [_ex('chest_row', primary: ['chest']), _ex('back_row', primary: ['back'])],
        deficit: const {'chest': 0.1, 'back': 0.9},
      );

      expect(ranked.first.id, 'back_row',
          reason: 'back is nine-tenths short of its weekly target; chest is '
              'nearly met');
    });

    test('and the reverse, so this is a comparison and not a fixed order', () {
      final ranked = rankForYou(
        [_ex('chest_row', primary: ['chest']), _ex('back_row', primary: ['back'])],
        deficit: const {'chest': 0.9, 'back': 0.1},
      );

      expect(ranked.first.id, 'chest_row');
    });

    test('an exercise with no muscle attribution sorts last, not mid-range', () {
      // 182 catalogue rows carry no muscle tag. When they scored neutral they
      // tied with every untrained muscle, and a greedy top-N could take a
      // whole session from them.
      final ranked = rankForYou(
        [
          _ex('untagged', primary: const []),
          _ex('met', primary: ['chest']),
        ],
        deficit: const {'chest': 0.05},
      );

      expect(ranked.last.id, 'untagged',
          reason: 'no signal must rank below a muscle that is nearly done, '
              'because "unknown" is not "urgent"');
    });

    test('an empty deficit returns input order rather than inventing one', () {
      final input = [_ex('a'), _ex('b'), _ex('c')];
      expect(rankForYou(input, deficit: const {}).map((e) => e.id),
          ['a', 'b', 'c']);
    });

    test('ties resolve by input order, reproducibly', () {
      // `List.sort` is not stable in Dart. Without an explicit index
      // tie-break the cold-start order is an artefact of the sort
      // implementation and cannot be reproduced from a bug report.
      //
      // 64 items, and the number is load-bearing. At 30 this test passed with
      // the tie-break deleted: `List.sort` runs an insertion sort below a
      // length threshold of 32, and insertion sort happens to be stable, so
      // the assertion was satisfied by an implementation detail rather than by
      // the code under test. A mutation run caught that. Above the threshold
      // the dual-pivot quicksort path takes over and reorders equal elements.
      final input = [for (var i = 0; i < 64; i++) _ex('e$i')];
      final a = rankForYou(input, deficit: const {'chest': 0.5});
      final b = rankForYou(input, deficit: const {'chest': 0.5});

      expect(a.map((e) => e.id), b.map((e) => e.id));
      expect(a.map((e) => e.id), input.map((e) => e.id));
    });
  });

  test('the ranker takes no difficulty input at all', () {
    // The structural version of the decision. `rankForYou` used to require a
    // `FitnessProfile`, which is built entirely from difficulty ratings; its
    // parameters are now a deficit map and a novelty set, neither of which any
    // rating can reach. A future change that reintroduces the coupling has to
    // change this call signature, which is a deliberate act rather than an
    // edit inside a function body.
    //
    // Expressed as a compiling call rather than a comment: if a difficulty
    // parameter is ever added as required, this stops compiling.
    final ranked = rankForYou(
      [_ex('a')],
      deficit: const {'chest': 0.5},
      recentExerciseIds: const {'a'},
    );

    expect(ranked, hasLength(1));
  });
}
