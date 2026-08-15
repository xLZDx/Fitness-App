import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// T1 — the rail that separates "tagged" from "works".
///
/// The catalogue tags 540 exercises across eight movement patterns. SIX of
/// those patterns now have both authored targets and a rep signal — the squat
/// from the start, and `curl` / `hinge` / `lunge` / `situp` / `overhead_press`
/// added 2026-08-08 with body-relative signals in `rep_signals.dart`.
///
/// What the user is offered still has to come from the second number, never
/// the first, or the coach draws a silhouette for a movement it cannot score
/// and teaches them the feature is broken. The two patterns below that are
/// still refused are refused for reasons, not for want of work.
void main() {
  group('formCoachSupports', () {
    test('offers the squat, which has targets and a countable rep', () {
      expect(formCoachSupports('squat'), isTrue);
    });

    test('offers the five movements taught 2026-08-08', () {
      for (final id in const [
        'curl',
        'hinge',
        'lunge',
        'situp',
        'overhead_press',
      ]) {
        expect(poseTargetsFor(kPosePatternToExercise[id]!), isNotNull,
            reason: '$id: no shape');
        expect(countsRepsFor(kPosePatternToExercise[id]!), isTrue,
            reason: '$id: no rep signal');
        expect(formCoachSupports(id), isTrue, reason: id);
      }
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

    /// `calf_raise` is the last untaught pattern, and it stays that way. The
    /// movement is a vertical translation of an unchanging skeleton, and
    /// `poseMatchScore` normalises position away — so both ends of it are the
    /// same shape and no target pair can tell a rep from standing still. Full
    /// reasoning lives beside `poseTargetsByTag`.
    test('refuses calf_raise, which cannot be represented at all', () {
      expect(formCoachSupports('calf_raise'), isFalse);
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

  /// The Form Coach's own picker was the one surface that did not ask.
  ///
  /// Every other entry point — the Train tab's `formCoach` chip, the exercise
  /// page, the player — gates on `formCoachSupports`. `_ExercisePicker`
  /// offered all eight `FormExercise` values, so selecting the push-up there
  /// produced a silhouette over a counter that cannot move, and the deadlift
  /// produced no shape at all.
  group('formCoachTeaches', () {
    test('agrees with formCoachSupports for every tagged pattern', () {
      kPosePatternToExercise.forEach((tag, e) {
        expect(formCoachTeaches(e), formCoachSupports(tag), reason: tag);
      });
    });

    test('refuses exactly the movements with no shape or no countable rep',
        () {
      for (final e in FormExercise.values) {
        final teaches = formCoachTeaches(e);
        expect(teaches, poseTargetsFor(e) != null && countsRepsFor(e),
            reason: e.name);
      }
      expect(formCoachTeaches(FormExercise.pushup), isFalse);
      expect(formCoachTeaches(FormExercise.deadlift), isFalse);
      expect(formCoachTeaches(FormExercise.squat), isTrue);
    });

    test('at least one movement is offered and at least one is refused', () {
      // Both halves matter. All-refused would make the picker empty with a
      // hint and no way in; all-offered would make the gate untestable from
      // the screen and is how the bypass survived.
      expect(FormExercise.values.where(formCoachTeaches), isNotEmpty);
      expect(FormExercise.values.where((e) => !formCoachTeaches(e)), isNotEmpty);
    });
  });
}
