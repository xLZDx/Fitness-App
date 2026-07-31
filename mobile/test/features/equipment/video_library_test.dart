import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the video library merged in from the 677-file drop
/// (`scripts/catalog/merge_video_library.py`).
///
/// The catalog is now two kinds of row sharing one schema: 168 older exercises
/// demonstrated by photographs, and 343 demonstrated by a clip of a woman and a
/// man performing it. `video` is therefore OPTIONAL, and the failure modes
/// worth pinning are the ones that are invisible at runtime — a row that claims
/// a video with an empty object, a url that points somewhere other than the one
/// host constant, a path that stops mirroring the drop so a re-upload silently
/// 404s, and a row that lost the text it needs when there is no clip to play.
void main() {
  final exercises = (jsonDecode(
          File('assets/data/exercises.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final ru = (jsonDecode(
          File('assets/data/exercises.ru.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final equipmentIds = (jsonDecode(
          File('assets/data/equipment.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .map((e) => e['id'] as String)
      .toSet();

  /// The single point of truth for the host, mirrored from
  /// `merge_video_library.py`. Moving hosts is one edit there plus one here.
  const base = 'https://VIDEO_HOST_PLACEHOLDER/exercises';

  /// The twelve folders the drop is organised by. The two gender trees disagree
  /// on case ('Abs' vs 'abs'), which is why this is compared lowercased.
  const groups = {
    'abs', 'back', 'biceps', 'calves', 'cardio', 'chest', 'forearms',
    'hips', 'mix', 'shoulders', 'trapezius', 'triceps',
  };

  List<Map<String, dynamic>> withVideo() => exercises
      .where((e) => e['video'] != null)
      .toList();

  group('video library', () {
    test('every video is a non-empty map of gender to url', () {
      final broken = <String>[];
      for (final e in withVideo()) {
        final v = (e['video'] as Map).cast<String, dynamic>();
        if (v.isEmpty) broken.add('${e['id']} has an empty video object');
        for (final entry in v.entries) {
          if (entry.key != 'girl' && entry.key != 'men') {
            broken.add('${e['id']} has an unknown gender "${entry.key}"');
          }
          if (entry.value is! String || (entry.value as String).isEmpty) {
            broken.add('${e['id']} has an empty ${entry.key} url');
          }
        }
      }
      expect(broken, isEmpty);
    });

    test('the two-gender exercises really carry both urls', () {
      // 310 of the 343 were filmed twice. This is a count, not a ratio,
      // because losing one gender is exactly the kind of regression a ratio
      // would round away.
      final both = withVideo().where((e) => (e['video'] as Map).length == 2);
      final one = withVideo().where((e) => (e['video'] as Map).length == 1);
      expect(both, hasLength(310));
      expect(one, hasLength(33));
      expect(withVideo(), hasLength(343));

      for (final e in both) {
        final v = (e['video'] as Map).cast<String, dynamic>();
        expect(v.keys.toSet(), {'girl', 'men'}, reason: '${e['id']}');
      }
    });

    test('every url is on the base host and mirrors the drop layout', () {
      // The path is `<gender>/<Group>/<file>.mp4` relative to the base, exactly
      // as the files sit on disk, so re-uploading the drop is a directory copy
      // rather than a rename pass. A url whose gender segment disagrees with
      // its own key would 404 on a host that never had the old layout.
      final broken = <String>[];
      for (final e in withVideo()) {
        final v = (e['video'] as Map).cast<String, String>();
        v.forEach((gender, url) {
          if (!url.startsWith('$base/')) {
            broken.add('${e['id']}/$gender is not on the base host: $url');
            return;
          }
          final parts = url.substring(base.length + 1).split('/');
          if (parts.length != 3) {
            broken.add('${e['id']}/$gender is not gender/group/file: $url');
            return;
          }
          if (parts[0] != gender) {
            broken.add('${e['id']} keyed $gender but the path says ${parts[0]}');
          }
          if (!groups.contains(parts[1].toLowerCase())) {
            broken.add('${e['id']}/$gender is in an unknown folder ${parts[1]}');
          }
          if (!parts[2].endsWith('.mp4')) {
            broken.add('${e['id']}/$gender is not an .mp4: ${parts[2]}');
          }
        });
      }
      expect(broken, isEmpty);
    });

    test('no exercise ships without text in either language', () {
      // Whatever the demo is — clip, stills or neither — the steps are the
      // fallback the workout player renders, so an empty list is a blank card.
      final broken = <String>[];
      for (final e in exercises) {
        final id = e['id'] as String;
        final en = (e['steps'] as List).where((s) => '$s'.trim().isNotEmpty);
        if (en.isEmpty) broken.add('$id has no English steps');
        final entry = ru[id] as Map?;
        if (entry == null) {
          broken.add('$id has no Russian entry at all');
          continue;
        }
        final rs = (entry['steps'] as List).where((s) => '$s'.trim().isNotEmpty);
        if (rs.isEmpty) broken.add('$id has no Russian steps');
        if ((entry['title'] as String).trim().isEmpty) {
          broken.add('$id has an empty Russian title');
        }
      }
      expect(broken, isEmpty);
    });

    test('the stretching category arrived and is the size it was authored at',
        () {
      // Stretching and mobility is a new category: the previous importer
      // filtered it out of the upstream source entirely, so before this merge
      // the catalog had none. Asserting the exact count is what makes a silent
      // loss — a group file that stops being merged, say — visible.
      final stretches =
          exercises.where((e) => e['isStretch'] == true).toList();
      expect(stretches, hasLength(61));
      for (final e in stretches) {
        expect(e['video'], isNotNull,
            reason: '${e['id']} is a stretch with no clip to show');
        expect((e['muscles'] as List), isNotEmpty, reason: '${e['id']}');
      }
    });

    test('equipmentId is null or a machine that exists', () {
      // Null is a legitimate answer here and covers two cases: bodyweight
      // exercises, and movements whose implement has no id in the registry
      // (a skipping rope, a stability ball, an ab wheel). Those are listed in
      // data/staging/library/UNSURE.txt rather than pointed at a neighbouring
      // machine, which is what the previous importer did.
      final broken = <String>[];
      for (final e in exercises) {
        final id = e['equipmentId'];
        if (id == null) continue;
        if (!equipmentIds.contains(id)) {
          broken.add('${e['id']} points at missing equipment $id');
        }
      }
      expect(broken, isEmpty);
    });

    test('the merge kept every existing id and added, never replaced', () {
      // A saved programme stores exercise ids. Renaming one during a catalog
      // rebuild breaks it silently, so the 69 exercises the drop also covers
      // kept their original id and only gained a `video` field.
      final ids = exercises.map((e) => e['id'] as String).toSet();
      expect(ids, hasLength(exercises.length), reason: 'duplicate ids');
      for (final legacy in [
        'barbell_bench_press_medium_grip',
        'calf_press_on_the_leg_press_machine',
        'fedb_chin-up',
        'fedb_bodyweight_squat',
        'fedb_machine_triceps_extension',
        'treadmill_warmup_walk',
      ]) {
        expect(ids, contains(legacy),
            reason: '$legacy disappeared in the merge');
      }
      // …and the ones that gained a clip really did gain it.
      final chinUp =
          exercises.firstWhere((e) => e['id'] == 'fedb_chin-up');
      expect(chinUp['video'], isNotNull);
    });

    test('exercises with no clip still have their photographs', () {
      // The ~150 older exercises the drop does not cover keep their stills.
      // If a rebuild ever dropped `frames`, they would render as blank cards
      // and this is the only place that would notice.
      final stillsOnly =
          exercises.where((e) => e['video'] == null).toList();
      expect(stillsOnly, hasLength(168));
      const noImageryByDesign = {
        'treadmill_warmup_walk', 'treadmill_incline_walk',
        'treadmill_steady_run', 'treadmill_intervals',
        'rowing_steady', 'rowing_intervals',
        'air_bike_intervals', 'air_bike_steady',
        'ski_erg_intervals', 'ski_erg_steady',
      };
      final blank = stillsOnly
          .where((e) =>
              (e['frames'] as List? ?? const []).isEmpty &&
              (e['imageUrls'] as List? ?? const []).isEmpty)
          .map((e) => e['id'] as String)
          .toSet();
      expect(blank.difference(noImageryByDesign), isEmpty);
    });
  });

  group('the urls are urls', () {
    // Almost every file in the drop is named like "Decline Dumbbell Bench
    // Press (45 degree).mp4". Those names went into the catalog verbatim, so
    // 637 of the 653 urls contained a raw space and 75 contained brackets or
    // an apostrophe. A space is not legal in a url at all — the library would
    // have failed to load in its entirety on the day the real host went live,
    // and nothing before that moment could have noticed.

    test('every url parses, with nothing left to escape', () {
      final bad = <String>[];
      for (final e in withVideo()) {
        for (final url in (e['video'] as Map).values.cast<String>()) {
          if (Uri.tryParse(url) == null || url.contains(' ')) {
            bad.add('${e['id']}: $url');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('the encoding round-trips to the file on disk', () {
      // The path has to survive decoding back to the drop's real filename, or
      // a re-upload that mirrors the directory tree will 404 on every clip.
      for (final e in withVideo()) {
        for (final url in (e['video'] as Map).values.cast<String>()) {
          final decoded = Uri.decodeFull(url);
          expect(decoded, endsWith('.mp4'), reason: e['id'] as String);
          expect(decoded, startsWith('$base/'), reason: e['id'] as String);
        }
      }
    });
  });

  group('what the user can actually see today', () {
    // On the record, because it is otherwise hidden by a redefinition. Adding
    // 293 exercises with no photographs would have dropped `demo_coverage_test`
    // from ~95% to 40.7%; counting `video` as imagery kept that test green.
    // Counting it is right in principle — a clip is the strongest demo there
    // is — but as of this commit those 293 exercises show the user nothing:
    // `ExerciseItem` parses `videoUrl` and not `video`, and every url points
    // at a host that does not exist.
    //
    // This test exists so that stops being invisible. It is meant to FAIL the
    // day either of those changes, as a prompt to check the other one.

    test('293 exercises depend on a video that is not yet playable', () {
      final videoOnly = exercises
          .where((e) =>
              e['video'] != null &&
              (e['frames'] as List? ?? const []).isEmpty &&
              (e['imageUrls'] as List? ?? const []).isEmpty &&
              e['videoUrl'] == null)
          .length;
      expect(videoOnly, 293);
    });

    test('the host is still a placeholder', () {
      final urls = [
        for (final e in withVideo())
          ...(e['video'] as Map).values.cast<String>(),
      ];
      expect(urls, hasLength(653));
      expect(urls.every((u) => u.startsWith(base)), isTrue,
          reason: 'when this fails the host has been chosen — at that point '
              'confirm ExerciseItem actually reads `video`, or those 293 '
              'exercises will still display nothing, on a real host');
    });
  });
}
