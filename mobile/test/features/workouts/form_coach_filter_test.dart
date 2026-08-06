import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';

/// The Form Coach group can be asked for, and it contains what it claims to.
///
/// Operator: *"сделать отдельную группу с разными упражнениями которые может
/// контролировать аи тренер"*.
///
/// The interesting rule is not that the chip exists. It is which exercises go
/// in: the catalog tags 540 rows across eight movement patterns, and the coach
/// has been taught one of them. A chip named after a feature must not be filled
/// with exercises that do not have it.
void main() {
  late List<ExerciseItem> catalog;

  setUpAll(() {
    catalog = (jsonDecode(
                File('assets/data/exercises_vendor.json').readAsStringSync())
            as List)
        .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('there is a chip for it', () {
    expect(WorkoutsFilter.values, contains(WorkoutsFilter.formCoach));
  });

  test('it sits where it can be found', () {
    // Second, right after "For you". A capability nobody can find is a
    // capability nobody has, and this one is what the app is built around.
    expect(WorkoutsFilter.values.indexOf(WorkoutsFilter.formCoach), 1);
  });

  test('the group is not empty', () {
    final supported =
        catalog.where((e) => formCoachSupports(e.poseTargetId)).toList();
    expect(supported, isNotEmpty,
        reason: 'a chip that opens onto nothing is worse than no chip');
    expect(supported.length, greaterThanOrEqualTo(30));
  });

  test('it holds only what the coach can actually judge', () {
    // The rule that matters. `poseTargetId != null` would put 540 exercises
    // here; 503 of them would open a page with no coach button on it, which is
    // exactly the dishonesty `formCoachSupports` exists to prevent one screen
    // later.
    final tagged = catalog.where((e) => e.poseTargetId != null).length;
    final supported =
        catalog.where((e) => formCoachSupports(e.poseTargetId)).length;

    expect(tagged, greaterThan(supported),
        reason: 'if these were equal the distinction would be untested');
    expect(supported, lessThan(tagged ~/ 2),
        reason: 'the gap is the honest state of the feature, not a bug');
  });

  test('every member of the group is squat-tagged, today', () {
    // Not a permanent truth — it is the current state of `kPosePatternToExercise`
    // — but pinning it means authoring a second pattern's targets shows up here
    // as a deliberate change rather than silently.
    final ids = catalog
        .where((e) => formCoachSupports(e.poseTargetId))
        .map((e) => e.poseTargetId)
        .toSet();
    expect(ids, {'squat'});
  });

  test('nothing untagged sneaks in', () {
    for (final e in catalog.where((e) => e.poseTargetId == null)) {
      expect(formCoachSupports(e.poseTargetId), isFalse, reason: e.id);
    }
  });

  test('a translation does not lose the tag', () {
    // `withText` rebuilds the object field by field. A field forgotten there
    // empties this whole group the moment the app runs in Russian — which is
    // the language the operator uses.
    final e = catalog.firstWhere((e) => formCoachSupports(e.poseTargetId));
    final ru = e.withText(title: 'Присед', summary: '', steps: const []);
    expect(formCoachSupports(ru.poseTargetId), isTrue);
  });
}
