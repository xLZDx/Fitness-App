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
/// in: the catalogue tags 540 rows across eight movement patterns, and the
/// coach has been taught SIX of them (2026-08-08 — the squat from the start,
/// plus curl / hinge / lunge / situp / overhead_press). A chip named after a
/// feature must not be filled with exercises that do not have it, and the
/// gap between "tagged" and "coachable" is what these tests pin.
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
    // The rule that matters, and the one that must survive the group growing.
    // `poseTargetId != null` would put every tagged row here; the ones whose
    // pattern has no shape or no rep signal would open a page with no coach
    // button on it, which is exactly the dishonesty `formCoachSupports` exists
    // to prevent one screen later.
    //
    // The bound is no longer a fraction. It was `supported < tagged ~/ 2`,
    // which passed only while the coach knew one pattern out of eight; on
    // 2026-08-08 it knew six and the check failed at 450 of 540 — reporting
    // success as a defect. What is actually being asserted is that the two
    // numbers are DIFFERENT, i.e. that something tagged is still refused.
    final tagged = catalog.where((e) => e.poseTargetId != null).length;
    final supported =
        catalog.where((e) => formCoachSupports(e.poseTargetId)).length;

    expect(tagged, greaterThan(supported),
        reason: 'if these were equal the distinction would be untested — '
            'today the difference is calf_raise, which cannot be represented');
    expect(supported, greaterThan(0));
  });

  test('the group holds exactly the patterns the coach was taught', () {
    // Not a permanent truth — it is the current state of
    // `kPosePatternToExercise` — but pinning it means teaching a new pattern
    // shows up here as a deliberate change rather than silently.
    //
    // `calf_raise` is the one tagged pattern absent on purpose: a vertical
    // translation of an unchanging skeleton, which `poseMatchScore` normalises
    // away. Full reasoning sits beside `poseTargetsByTag`.
    final ids = catalog
        .where((e) => formCoachSupports(e.poseTargetId))
        .map((e) => e.poseTargetId)
        .toSet();
    expect(ids, {'squat', 'curl', 'hinge', 'lunge', 'situp', 'overhead_press'});
    expect(ids, isNot(contains('calf_raise')));
    expect(ids, isNot(contains('pushup')),
        reason: 'shapes authored, reps uncountable — still refused');
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
