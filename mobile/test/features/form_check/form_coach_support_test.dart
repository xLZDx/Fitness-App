import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// T1 — the rail that separates "tagged" from "works".
///
/// The catalog tags 570 exercises across eight movement patterns. One pattern
/// has both authored targets and a rep signal. Everything the user is offered
/// has to come from the second number, never the first, or the coach draws a
/// silhouette for a movement it cannot score and teaches them the feature is
/// broken.
void main() {
  group('formCoachSupports', () {
    test('offers the squat, which has targets and a countable rep', () {
      expect(formCoachSupports('squat'), isTrue);
    });

    /// The case the gate exists for. `pushupTopTarget` and
    /// `pushupBottomTarget` are both authored, so a check on "is there a
    /// target" would pass — and the rep counter's only signal is hip-versus-
    /// knee height, which does not track a push-up at all.
    test('refuses the push-up: shapes authored, reps uncountable', () {
      expect(poseTargetsFor(FormExercise.pushup), isNotNull);
      expect(countsRepsFor(FormExercise.pushup), isFalse);
      expect(formCoachSupports('pushup'), isFalse);
    });

    test('refuses patterns the coach was never taught', () {
      for (final id in const [
        'hinge',
        'lunge',
        'overhead_press',
        'curl',
        'situp',
        'calf_raise',
      ]) {
        expect(formCoachSupports(id), isFalse, reason: id);
      }
    });

    test('refuses an untagged exercise and an unknown tag', () {
      expect(formCoachSupports(null), isFalse);
      expect(formCoachSupports('kettlebell-juggling'), isFalse);
    });

    /// Adding a pattern to the map is meant to be the LAST step of authoring
    /// it. If someone adds one without targets or a rep signal, this catches
    /// the mismatch rather than letting the button appear.
    test('every mapped pattern really is complete', () {
      for (final entry in kPosePatternToExercise.entries) {
        expect(poseTargetsFor(entry.value), isNotNull, reason: entry.key);
        expect(countsRepsFor(entry.value), isTrue, reason: entry.key);
      }
    });
  });

  group('ExerciseItem.poseTargetId', () {
    test('is read from the catalog row', () {
      final item = ExerciseItem.fromJson(const {
        'id': 'ea_barbell_squat',
        'title': 'Barbell Squat',
        'poseTargetId': 'squat',
      });
      expect(item.poseTargetId, 'squat');
      expect(formCoachSupports(item.poseTargetId), isTrue);
    });

    test('is null for a row that carries no tag', () {
      final item = ExerciseItem.fromJson(const {
        'id': 'ea_bench_press',
        'title': 'Barbell Bench Press',
      });
      expect(item.poseTargetId, isNull);
      expect(formCoachSupports(item.poseTargetId), isFalse);
    });

    /// The translation path rebuilds the item from scratch, and a field it
    /// forgets is a field that silently disappears in Russian.
    test('survives withText', () {
      final item = ExerciseItem.fromJson(const {
        'id': 'ea_air_squat',
        'title': 'Air Squat',
        'poseTargetId': 'squat',
      }).withText(title: 'Приседание', summary: '', steps: const []);
      expect(item.poseTargetId, 'squat');
    });
  });
}
