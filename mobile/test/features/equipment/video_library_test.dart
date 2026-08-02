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
  final exercises =
      (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final ru =
      (jsonDecode(File('assets/data/exercises.ru.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>();
  final equipmentIds =
      (jsonDecode(File('assets/data/equipment.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['id'] as String)
          .toSet();

  /// The single point of truth for the host, mirrored from
  /// `scripts/catalog/set_video_host.py`. Moving hosts is one run of that
  /// script plus one edit here.
  ///
  /// A plain public Cloud Storage bucket rather than Firebase Storage: the
  /// Firebase-managed bucket needs the project's DEFAULT RESOURCE LOCATION,
  /// which is permanent and decides where Firestore lives too. Choosing that
  /// as a side effect of hosting some demonstration clips would settle
  /// something much larger than the task.
  const base =
      'https://storage.googleapis.com/traidingbot-b4061-videos-eu/exercises';

  /// The twelve folders the ORIGINAL drop is organised by. The two gender trees
  /// disagree on case ('Abs' vs 'abs'), which is why this is compared
  /// lowercased.
  const groups = {
    'abs',
    'back',
    'biceps',
    'calves',
    'cardio',
    'chest',
    'forearms',
    'hips',
    'mix',
    'shoulders',
    'trapezius',
    'triceps',
  };

  /// Exactly the pattern `functions/src/video_urls.ts` will sign, character for
  /// character. A key this rejects is a clip that can never play: the function
  /// answers `invalid-argument`, the block keeps its poster up, and nothing
  /// anywhere reports a fault. Mirrored deliberately rather than shared —
  /// TypeScript and Dart cannot import one regex, and a copy that is checked
  /// against the real catalog on every run is better than a shared constant
  /// nothing exercises.
  final licensedKey =
      RegExp(r'^exercises/(girl|men)/[^/]{1,120}/[^/]{1,160}\.mp4$');

  List<Map<String, dynamic>> withVideo() =>
      exercises.where((e) => e['video'] != null).toList();

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

    test('the two-gender exercises really carry both references', () {
      // Counts, not ratios, because losing one gender is exactly the kind of
      // regression a ratio would round away.
      //
      // Moved 343 -> 365 by the licensed import of 2026-08-02: 142 exercises
      // now point at the purchased library and 22 of them had no clip at all
      // before. `one` grew from 33 to 36 because the bundle filmed some
      // movements on a single body.
      //
      // Only exact name matches were applied. 48 subset candidates are strong
      // but unproven and sit in core/bundle_import_report.csv awaiting an eye
      // that knows a front squat from a back squat; `--include-subset` applies
      // them and moves these three numbers.
      final both = withVideo().where((e) => (e['video'] as Map).length == 2);
      final one = withVideo().where((e) => (e['video'] as Map).length == 1);
      expect(both, hasLength(329));
      expect(one, hasLength(36));
      expect(withVideo(), hasLength(365));

      for (final e in both) {
        final v = (e['video'] as Map).cast<String, dynamic>();
        expect(v.keys.toSet(), {'girl', 'men'}, reason: '${e['id']}');
      }
    });

    test('every reference is either a public url or a signable object key', () {
      // The catalog holds two shapes on purpose, and this is the invariant
      // that replaced "everything is on one public host".
      //
      //   public    <base>/<gender>/<Group>/<file>.mp4 — the original drop,
      //             still served straight from a world-readable bucket
      //   licensed  exercises/<gender>/<Group>/<file>.mp4 — the purchased
      //             library, private, signed per request because the vendor's
      //             permission forbids permanent downloadable links
      //
      // `ClipUrlResolver.isDirect` is the whole seam between them, so the one
      // thing that must hold for BOTH is that the gender segment agrees with
      // the key it is filed under. A mismatch shows a man the women's clip,
      // and no test of the app's logic would ever catch it.
      final broken = <String>[];
      var publicCount = 0;
      var licensedCount = 0;

      for (final e in withVideo()) {
        final v = (e['video'] as Map).cast<String, String>();
        v.forEach((gender, ref) {
          if (ref.startsWith('http')) {
            publicCount++;
            if (!ref.startsWith('$base/')) {
              broken.add('${e['id']}/$gender is not on the base host: $ref');
              return;
            }
            final parts = ref.substring(base.length + 1).split('/');
            if (parts.length != 3) {
              broken.add('${e['id']}/$gender is not gender/group/file: $ref');
              return;
            }
            if (parts[0] != gender) {
              broken
                  .add('${e['id']} keyed $gender but the path says ${parts[0]}');
            }
            if (!groups.contains(parts[1].toLowerCase())) {
              broken
                  .add('${e['id']}/$gender is in an unknown folder ${parts[1]}');
            }
            if (!parts[2].endsWith('.mp4')) {
              broken.add('${e['id']}/$gender is not an .mp4: ${parts[2]}');
            }
            return;
          }

          licensedCount++;
          if (!licensedKey.hasMatch(ref)) {
            // The function would answer invalid-argument and the exercise
            // would show its poster forever, looking like a slow network.
            broken.add('${e['id']}/$gender is a key clipUrl will not sign: $ref');
            return;
          }
          if (ref.split('/')[1] != gender) {
            broken.add('${e['id']} keyed $gender but the object says '
                '${ref.split('/')[1]}');
          }
        });
      }

      expect(broken, isEmpty);
      // Pinned so a botched re-import that quietly reverts every licensed
      // entry to a public url still passes every shape check above and fails
      // right here.
      expect(licensedCount, 166, reason: 'licensed object keys');
      expect(publicCount, 528, reason: 'public urls still being served');
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
        final rs =
            (entry['steps'] as List).where((s) => '$s'.trim().isNotEmpty);
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
      //
      // 65, not the 61 that arrived with the library. `widen_stretch_flag.py`
      // marked four more the importer had missed — three Pilates movements and
      // one older free-exercise-db stretch — because they were about to be
      // hidden by the very filter that was added to surface them.
      final stretches = exercises.where((e) => e['isStretch'] == true).toList();
      expect(stretches, hasLength(65));

      // The clip check applies to the 61 from the library. The four widened
      // ones are older rows and one of them predates the video library
      // entirely, so demanding a clip of them would be asserting something
      // that was never true.
      const widened = {
        'all_fours_quad_stretch',
        'vid_corkscrew_pilates',
        'vid_hundred_pilates',
        'vid_jackknife_pilates',
      };
      for (final e in stretches) {
        if (!widened.contains(e['id'])) {
          expect(e['video'], isNotNull,
              reason: '${e['id']} is a stretch with no clip to show');
        }
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
      final chinUp = exercises.firstWhere((e) => e['id'] == 'fedb_chin-up');
      expect(chinUp['video'], isNotNull);
    });

    test('exercises with no clip still have their photographs', () {
      // The older exercises no library covers keep their stills. If a rebuild
      // ever dropped `frames`, they would render as blank cards and this is
      // the only place that would notice.
      //
      // 168 -> 146 with the licensed import of 2026-08-02: 22 of these had no
      // clip at all and now have one. The remaining 146 are the honest gap.
      // Many have a subset or fuzzy vendor candidate that was deliberately not
      // applied — see core/bundle_import_report.csv.
      final stillsOnly = exercises.where((e) => e['video'] == null).toList();
      expect(stillsOnly, hasLength(146));
      const noImageryByDesign = {
        'treadmill_warmup_walk',
        'treadmill_incline_walk',
        'treadmill_steady_run',
        'treadmill_intervals',
        'rowing_steady',
        'rowing_intervals',
        'air_bike_intervals',
        'air_bike_steady',
        'ski_erg_intervals',
        'ski_erg_steady',
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

    test('every public url parses, with nothing left to escape', () {
      final bad = <String>[];
      for (final e in withVideo()) {
        for (final ref in (e['video'] as Map).values.cast<String>()) {
          if (!ref.startsWith('http')) continue;
          if (Uri.tryParse(ref) == null || ref.contains(' ')) {
            bad.add('${e['id']}: $ref');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('every licensed key is RAW, not encoded', () {
      // The exact opposite requirement, and it is easy to get backwards.
      //
      // A public url is fetched by a browser, so its spaces must be escaped. A
      // licensed key is not fetched — it is the object's NAME, handed to
      // `clipUrl` and used verbatim to look the object up. Percent-encode it
      // and the lookup asks for an object literally called
      // `Barbell%20Squat.mp4`, which does not exist. The bucket says no such
      // object, the function says internal error, and the exercise shows its
      // poster forever.
      //
      // 297 delivered filenames also carry stray spaces, so this is not a
      // theoretical hazard — it is the same hazard from the other end.
      final bad = <String>[];
      for (final e in withVideo()) {
        for (final ref in (e['video'] as Map).values.cast<String>()) {
          if (ref.startsWith('http')) continue;
          if (ref.contains('%')) bad.add('${e['id']}: encoded key $ref');
          if (Uri.decodeFull(ref) != ref) {
            bad.add('${e['id']}: key does not survive a decode: $ref');
          }
          if (ref != ref.trim()) bad.add('${e['id']}: key has stray space');
        }
      }
      expect(bad, isEmpty);
    });

    test('the encoding round-trips to the file on disk', () {
      // The path has to survive decoding back to the drop's real filename, or
      // a re-upload that mirrors the directory tree will 404 on every clip.
      for (final e in withVideo()) {
        for (final ref in (e['video'] as Map).values.cast<String>()) {
          if (!ref.startsWith('http')) {
            // The licensed tree is laid out under the object key itself, so
            // there is no encoding to undo — the key IS the path on disk.
            expect(ref, endsWith('.mp4'), reason: e['id'] as String);
            expect(ref, startsWith('exercises/'), reason: e['id'] as String);
            continue;
          }
          final decoded = Uri.decodeFull(ref);
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
    //
    // When this was written those 293 showed the user nothing — `ExerciseItem`
    // parsed `videoUrl` and not `video`, and every url pointed at a host that
    // did not exist. Both are fixed: the host went live 2026-08-01 and every
    // one of these now carries a bundled poster as well, so the count is no
    // longer a debt. It is kept as a count because it is the number of
    // exercises whose ONLY moving demonstration is the clip, and if a rebuild
    // ever loses their posters again this is where it shows.

    test('293 exercises are demonstrated by the clip alone', () {
      final videoOnly = exercises
          .where((e) =>
              e['video'] != null &&
              (e['frames'] as List? ?? const []).isEmpty &&
              (e['imageUrls'] as List? ?? const []).isEmpty &&
              e['videoUrl'] == null)
          .length;
      expect(videoOnly, 293);
    });

    test('the library is part public, part licensed, and both are served', () {
      // This started life asserting the host was still a placeholder, written
      // to fail the day one was chosen. It did, on 2026-08-01. It then
      // asserted every url was on the real host, and failed again on
      // 2026-08-02 when the licensed library arrived somewhere else — which is
      // the same note doing the same job a second time.
      //
      // The library is now genuinely two things and will be for a while: 528
      // public urls from the original drop, and 166 object keys signed per
      // request because the vendor forbids permanent downloadable links. This
      // pins the split so that finishing the migration is a deliberate edit
      // here rather than something that drifts.
      final refs = [
        for (final e in withVideo())
          ...(e['video'] as Map).values.cast<String>(),
      ];
      expect(refs, hasLength(694));
      expect(refs.where((u) => u.startsWith(base)), hasLength(528));
      expect(refs.where((u) => u.startsWith('exercises/')), hasLength(166));
      expect(
        refs.every((u) => u.startsWith(base) || u.startsWith('exercises/')),
        isTrue,
        reason: 'a reference that is neither can never be played',
      );
    });
  });
}
