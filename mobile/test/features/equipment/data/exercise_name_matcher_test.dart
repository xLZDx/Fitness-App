import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/exercise_name_matcher.dart';

void main() {
  group('ExerciseNameMatcher', () {
    test('an exact catalogue title resolves to itself', () {
      final matcher = ExerciseNameMatcher(['Leg Press', 'Barbell Squat']);
      expect(matcher.resolve('Leg Press'), 'Leg Press');
    });

    test('case, ё/е and punctuation do not defeat a match', () {
      final matcher = ExerciseNameMatcher(['Жим ногами']);
      expect(matcher.resolve('ЖИМ  НОГАМИ!'), 'Жим ногами');
    });

    test(
        'a title appearing as a whole-word phrase inside longer, harmless '
        'elaboration resolves to the canonical title, not the model line',
        () {
      // The model tends to elaborate with dosage/target-muscle text — this
      // must still be recognised, but only the real title is ever returned.
      final matcher = ExerciseNameMatcher(['Leg Press']);
      expect(matcher.resolve('3 sets of Leg Press for quad strength'),
          'Leg Press');
    });

    test(
        'ADVERSARIAL (GPT-PM round 19): a real title embedded in an invented '
        'MODIFICATION never lets the modification through — only the '
        'canonical title is returned, the invented addition is discarded',
        () {
      // "Leg Press With Torso Rotation" contains the real title "Leg Press"
      // as a whole-word phrase. A boolean matches()-then-render-raw-line
      // design would smuggle "With Torso Rotation" past the check — an
      // invented, unvalidated modification disguised as something real.
      // resolve() must never return that full line.
      final matcher = ExerciseNameMatcher(['Leg Press']);
      expect(matcher.resolve('Leg Press With Torso Rotation'), 'Leg Press');
      expect(matcher.resolve('Leg Press With Torso Rotation'),
          isNot('Leg Press With Torso Rotation'));
    });

    test(
        'ADVERSARIAL: filter() never returns a model-invented modification '
        'verbatim, even when it contains a real title', () {
      final matcher = ExerciseNameMatcher(['Leg Press', 'Barbell Squat']);
      final result = matcher.filter(const [
        'Leg Press With Torso Rotation',
        'Squat With Overhead Twist And Weighted Vest',
      ]);
      expect(result, ['Leg Press']);
      expect(result, isNot(contains('Leg Press With Torso Rotation')));
      expect(
        result,
        isNot(contains('Squat With Overhead Twist And Weighted Vest')),
      );
    });

    test('an invented exercise with no catalogue match resolves to null', () {
      final matcher = ExerciseNameMatcher(['Leg Press', 'Barbell Squat']);
      expect(matcher.resolve('Quantum Kettlebell Flow'), isNull);
      expect(matcher.matches('Quantum Kettlebell Flow'), isFalse);
    });

    test('a short title cannot falsely license an unrelated word containing it',
        () {
      // "leg" must not make "legendary stretch" (or any text merely
      // containing the substring "leg") count as a match — only a
      // whole-word phrase boundary counts.
      final matcher = ExerciseNameMatcher(['Leg']);
      expect(matcher.resolve('Legendary stretch routine'), isNull);
    });

    test('the longest matching title wins over a shorter one it contains',
        () {
      final matcher = ExerciseNameMatcher(['Leg Press', 'Seated Leg Press']);
      expect(matcher.resolve('Seated Leg Press for beginners'),
          'Seated Leg Press');
    });

    test('empty free text never matches', () {
      final matcher = ExerciseNameMatcher(['Leg Press']);
      expect(matcher.resolve(''), isNull);
      expect(matcher.resolve('   '), isNull);
    });

    test('an empty catalogue matches nothing — fails closed, not open', () {
      final matcher = ExerciseNameMatcher(const []);
      expect(matcher.resolve('Leg Press'), isNull);
      expect(matcher.filter(const ['Leg Press']), isEmpty);
    });

    test('filter preserves order and drops only the unmatched lines', () {
      final matcher = ExerciseNameMatcher(['Leg Press', 'Barbell Squat']);
      final result = matcher.filter(const [
        'Leg Press for quads',
        'Invented Machine Twist',
        'Barbell Squat',
        'Another made-up move',
      ]);
      expect(result, ['Leg Press', 'Barbell Squat']);
    });

    test('filter on an all-invented list returns an empty, not a padded, list',
        () {
      final matcher = ExerciseNameMatcher(['Leg Press']);
      final result = matcher.filter(const [
        'Invented Move One',
        'Invented Move Two',
      ]);
      expect(result, isEmpty);
    });
  });
}
