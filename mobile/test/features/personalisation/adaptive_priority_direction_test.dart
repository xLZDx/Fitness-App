import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/personalisation/data/fitness_model.dart';

/// Which way the adaptive ranking points, stated once and out loud.
///
/// The direction was implemented twice and documented three times, and the
/// documentation disagreed with the implementation:
///
/// - `fitness_model.dart` said, of this very function, "Lower score → ranker
///   downweights to give the muscle group recovery time".
/// - `for_you_ranker.dart` said the opposite — "muscles the user is weakest in
///   surface higher" — and implemented it.
/// - `plan_builder.dart` implemented the same thing again, and no document
///   about the ranking mentioned that copy at all.
///
/// Both readings are coherent training philosophies. "Back off what you found
/// too hard" and "attack what you are weakest at" are real, opposed positions,
/// and picking between them is a product decision rather than a bug fix.
///
/// So this file does not argue for either. It makes the live direction
/// impossible to change by accident: whoever settles the question has to come
/// here and say so, which is exactly the deliberate act that a silent `1.0 -`
/// spread across two files was not.

FitnessProfile profileWith(Map<String, double> scores) => FitnessProfile(
      byMuscle: {
        for (final e in scores.entries)
          // `score` is good/total, so a total of 1 makes `good` the score.
          e.key: MuscleFitness(muscle: e.key, good: e.value, total: 1),
      },
    );

void main() {
  group('the live direction: struggle raises priority', () {
    test('a muscle group rated "too hard" outranks one rated "too easy"', () {
      // THIS IS THE CONTESTED ASSERTION. `fitness_model.dart`'s own class
      // comment described the reverse until 2026-08-15. If the product
      // decision goes the other way, this is the line that flips, and it must
      // flip on purpose.
      final profile = profileWith({'quads': 0.1, 'chest': 0.9});

      expect(
        profile.adaptivePriorityFor(['quads']),
        greaterThan(profile.adaptivePriorityFor(['chest'])),
        reason: 'quads are rated hard (0.1), chest easy (0.9). What ships '
            'surfaces the hard one first',
      );
    });

    test('and the ordering is strict, not a coin toss on equal scores', () {
      final profile = profileWith({'quads': 0.5, 'chest': 0.5});

      expect(
        profile.adaptivePriorityFor(['quads']),
        profile.adaptivePriorityFor(['chest']),
      );
    });
  });

  group('one definition, not three copies', () {
    test('a composite movement averages its groups before inverting', () {
      // Inverting each group and then averaging gives the same number here,
      // but not in general once anything non-linear is added. Pinning the
      // order of operations is what keeps a future change to one of them from
      // meaning two different things on two surfaces.
      final profile = profileWith({'quads': 0.2, 'glutes': 0.8});

      expect(profile.adaptivePriorityFor(['quads', 'glutes']), closeTo(0.5, 1e-9));
    });

    test('an unlogged muscle group sits at neutral, not at either extreme', () {
      // A brand-new user must not have every exercise ranked as maximally
      // urgent, nor as maximally uninteresting. `scoreFor` supplies the
      // Beta(2,2) prior for this.
      final priority = FitnessProfile.empty.adaptivePriorityFor(['deltoids']);

      expect(priority, closeTo(0.5, 1e-9));
    });

    test('no muscles named is neutral rather than an error or a zero', () {
      expect(FitnessProfile.empty.adaptivePriorityFor(const []),
          closeTo(0.5, 1e-9));
    });
  });
}
