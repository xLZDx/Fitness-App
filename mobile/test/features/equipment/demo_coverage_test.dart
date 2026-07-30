import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S6: "у некоторых тренировок по прежнему нет видео".
///
/// The round-4 catalog expansion (S0) is what actually moved this: 66 of 72
/// exercises had demo imagery before, 186 of 192 do now. These tests pin
/// that coverage and pin WHICH exercises are allowed to have none, so a
/// future import cannot quietly reintroduce blank demo slots.
void main() {
  final exercises = (jsonDecode(
          File('assets/data/exercises.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  bool hasImagery(Map<String, dynamic> e) =>
      (e['frames'] as List? ?? const []).isNotEmpty ||
      (e['imageUrls'] as List? ?? const []).isNotEmpty ||
      e['videoUrl'] != null;

  test('at least 95% of exercises have something to show', () {
    final withImagery = exercises.where(hasImagery).length;
    final ratio = withImagery / exercises.length;
    expect(ratio, greaterThanOrEqualTo(0.95),
        reason: 'only $withImagery of ${exercises.length} exercises have '
            'a demo, video or stills');
  });

  test('the only exercises without imagery are the hand-authored cardio ones',
      () {
    // These six were written by hand for the treadmill and rowing machine
    // (round 3) because no public-domain source covers them. They ship with
    // NO frames deliberately -- fabricating a photo of someone running is
    // worse than the honest "no video yet, follow the steps" card, which is
    // what the workout player renders for them.
    const allowed = {
      'treadmill_warmup_walk',
      'treadmill_incline_walk',
      'treadmill_steady_run',
      'treadmill_intervals',
      'rowing_steady',
      'rowing_intervals',
    };
    final without = exercises
        .where((e) => !hasImagery(e))
        .map((e) => e['id'] as String)
        .toSet();
    expect(without.difference(allowed), isEmpty,
        reason: 'new exercises shipped with no imagery and no reason: '
            '${without.difference(allowed)}');
  });

  test('every exercise without imagery still carries steps and muscles', () {
    // This is what makes the no-video state honest rather than empty: the
    // player falls back to the muscle map and the step list, so those must
    // exist for exactly the exercises that rely on them.
    for (final e in exercises.where((e) => !hasImagery(e))) {
      expect((e['steps'] as List), isNotEmpty,
          reason: '${e['id']} has neither imagery nor steps');
      expect((e['muscles'] as List), isNotEmpty,
          reason: '${e['id']} has neither imagery nor a muscle map to show');
    }
  });
}
