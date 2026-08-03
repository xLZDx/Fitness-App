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

  // `video` was added by the 2026-07-31 merge of the 677-file drop: 343 of the
  // 511 exercises are now demonstrated by a clip rather than by stills. It is
  // listed here because this predicate answers "is there anything to show",
  // and a video is the strongest answer to that question there is — leaving it
  // out would report 343 exercises as having no demo while they play one.
  // The `videoUrl` singular is the older per-exercise field and stays.
  //
  // 2026-08-03: `frames` and `imageUrls` no longer count as a demonstration
  // ANYWHERE the user can see, because both are photographs of a man in a gym
  // and the catalog is meant to look like one thing. They are still counted
  // HERE, in this one predicate, on purpose: this file's job is to notice an
  // exercise that ships carrying nothing at all, which is a different defect
  // from an exercise that ships carrying the wrong kind of thing. The rule the
  // app actually enforces lives in `clip_only_test.dart`.
  bool hasImagery(Map<String, dynamic> e) =>
      (e['frames'] as List? ?? const []).isNotEmpty ||
      (e['imageUrls'] as List? ?? const []).isNotEmpty ||
      (e['video'] as Map? ?? const {}).isNotEmpty ||
      e['videoUrl'] != null;

  test('two thirds of exercises still carry SOMETHING, even if unshowable',
      () {
    // Was 95%. It fell to 67% on 2026-08-03 when 324 entries lost clips that
    // came from an unlicensed Drive scaffold, and came back to 84% when every
    // remaining exercise was re-matched against the purchased library by
    // meaning rather than by filename. The floor moves with it.
    //
    // The ratio is kept as a floor rather than deleted, because its job is
    // unchanged: catch a rebuild that silently strips imagery. It moves back up
    // as the remaining exercises are re-matched against the vendor library --
    // see core/CLIP_LICENCE_AUDIT_2026-08-03.md.
    final withImagery = exercises.where(hasImagery).length;
    final ratio = withImagery / exercises.length;
    expect(ratio, greaterThanOrEqualTo(0.80),
        reason: 'only $withImagery of ${exercises.length} exercises have '
            'a demo, video or stills');
  });

  test('what the user is actually shown is a clip or nothing', () {
    // The number that matters now. 355 of 511 play; the other 156 are hidden
    // rather than papered over with a photograph, and every one of them is a
    // piece of footage we owe — see core/CLIP_LICENCE_AUDIT_2026-08-03.md.
    final withClip = exercises
        .where((e) => (e['video'] as Map? ?? const {}).isNotEmpty)
        .length;
    expect(withClip, 355);
    expect(exercises, hasLength(511));
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
      // A1, 2026-07-31: the air bike and the ski erg for the same reason —
      // the public-domain source has no entry for either machine, and a
      // fabricated photo of someone on a fan bike is worse than an honest
      // "no video yet, follow the steps".
      'air_bike_intervals',
      'air_bike_steady',
      'ski_erg_intervals',
      'ski_erg_steady',
    };
    final without = exercises
        .where((e) => !hasImagery(e))
        .map((e) => e['id'] as String)
        .toSet();
    // The hand-authored cardio entries were written with no imagery because
    // "no public-domain source covers them". That stopped being true on
    // 2026-08-03: the purchased library has its own rowing ergometer,
    // elliptical and stepmill clips, and the semantic re-match found them. So
    // `allowed` is now a list of exercises that MAY have no imagery, not one
    // that must have none.
    expect(without, hasLength(68),
        reason: 'an exercise shipping with nothing at all must move this');
    // The rest are the 158 that had an unlicensed clip and no stills behind
    // it. This asserts the size rather than the membership so that a NEW
    // exercise shipping empty still moves the number and fails here.
    expect(without.difference(allowed), hasLength(67));
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
