import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// How many exercises in the shipped catalog must carry a contraindication
/// tag. Raised by each tagging batch, never lowered.
///
/// It is whatever the catalog measures: the legacy list carried the only 144
/// tagged exercises in the product and was deleted in `0c4bf24`, which no test
/// noticed. The two assertions below pin it from both sides, so tagging even
/// one more exercise turns this file red until the number here is raised to
/// match. That is the point: the count can never drift from the code again in
/// either direction.
///
/// 1435 -> 1525 (P3): the `upper_back` batch tagged 264 exercises, of which 90
/// carried no tag at all before. The other 174 already had one for another
/// region — this floor counts ROWS with at least one tag, not tags, so a batch
/// raises it by less than it tags whenever it lands on already-tagged rows.
///
/// 1525 -> 1524 (P3, Codex round-2 fix): the one deliberate exception to
/// "never lowered". `Rear Deltoid Stretch` lost its `upper_back` tag when the
/// word list that had produced it ("rear deltoid" -> "rear deltoid fly")
/// was narrowed to stop tagging a passive stretch as a loaded pull, and it
/// carried no other region's tag, so it dropped out of the floor entirely.
/// The two rows the same fix newly tagged (`Bent Over Twist`,
/// `Cable Assisted Inverse Leg Curl`) already carried a tag for another
/// region, so they do not offset it here — see `byRegion` below, where both
/// counts move. A LOWER number reached by naming the exact row and the exact
/// reason is the rule working, not the rule breaking; what it guards against
/// is a number moving with no entry here to say why.
/// 1524 -> 1525 (full-catalog content audit, 2026-08-15). No rule changed and
/// no batch shipped. `Dumbbell Face Down Lying Shoulder Pres` had that typo in
/// its title, so the `shoulder_overhead` rule never matched its "shoulder
/// press" phrase and the row carried no tag at all. Correcting the spelling as
/// part of a copy audit made
/// the existing rule match, and the row was tagged through the normal
/// `--region shoulder --write` path. Worth leaving here as the reason the
/// number moved without a batch: the rules read the vendor's own text, so a
/// misspelt title fails open and hides nothing from anybody.
const int kSafetyCoverageFloor = 1525;

ExerciseItem _ex(String id, {List<String> contraindications = const []}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: 'eq',
      muscles: const [],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
      contraindications: contraindications,
    );

void main() {
  group('safetyCoverage', () {
    test('counts tagged rows against the whole list', () {
      final out = safetyCoverage([
        _ex('a', contraindications: ['knee']),
        _ex('b'),
        _ex('c', contraindications: ['shoulder', 'lower_back']),
        _ex('d'),
      ]);
      expect(out.tagged, 2);
      expect(out.total, 4);
      expect(out.fraction, 0.5);
    });

    test('a row with an empty tag list is not covered', () {
      // The distinction the whole gate turns on: `contraindications: []` is
      // indistinguishable from "checked and cleared" everywhere else in the
      // app, and it is the value 1,887 of 1,887 exercises ship with.
      expect(safetyCoverage([_ex('a')]).tagged, 0);
    });

    test('an empty catalog is uncovered, not vacuously complete', () {
      final out = safetyCoverage(const <ExerciseItem>[]);
      expect(out.total, 0);
      expect(out.fraction, 0.0);
    });
  });

  group('the shipped catalog', () {
    late List<ExerciseItem> catalog;

    setUpAll(() {
      final raw = File('assets/data/exercises_vendor.json').readAsStringSync();
      catalog = (jsonDecode(raw) as List)
          .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });

    test('carries at least the floor number of safety tags', () {
      final out = safetyCoverage(catalog);
      expect(out.tagged, greaterThanOrEqualTo(kSafetyCoverageFloor),
          reason: 'safety tags fell from $kSafetyCoverageFloor to '
              '${out.tagged} of ${out.total}. Tagged exercises have been '
              'deleted or overwritten — find out by what before lowering the '
              'floor, because this is the exact failure `0c4bf24` shipped.');
    });

    test('the floor is raised as soon as coverage rises', () {
      final out = safetyCoverage(catalog);
      expect(out.tagged, lessThanOrEqualTo(kSafetyCoverageFloor),
          reason: 'coverage rose to ${out.tagged} of ${out.total}. Raise '
              'kSafetyCoverageFloor in this file to ${out.tagged} in the same '
              'commit as the tagging batch — an unraised floor cannot detect '
              'the batch being lost again.');
    });

    test('at this coverage the injury filter cannot remove anything', () {
      // Not a restatement of the number: this is what the number means on
      // screen, and it stays here so the day it starts failing is the day the
      // filter genuinely began working.
      final out = safetyCoverage(catalog);
      if (out.tagged > 0) return;

      final everyBodyPart = [
        for (final part in [
          'knee',
          'shoulder',
          'lower back',
          'wrist',
          'ankle',
          'neck',
          'hip',
          'elbow',
        ])
          Injury(bodyPart: part, type: 'strain'),
      ];
      final filtered = filterContraindicated(catalog, everyBodyPart);
      expect(filtered, hasLength(catalog.length),
          reason: 'a user reporting eight injuries at once still sees the '
              'entire catalog, because no exercise carries a tag to match');
    });
  });

  group('safetyCoverageByRegion', () {
    // The total answers "can the filter fire at all", which was the right
    // question while the answer was zero and becomes the wrong one with S3b's
    // first batch: 50 tagged knees make `tagged > 0` true for a user whose only
    // injury is a shoulder, whose coverage is still nothing.
    test('counts each region separately', () {
      final out = safetyCoverageByRegion([
        _ex('a', contraindications: ['knee']),
        _ex('b', contraindications: ['knee', 'shoulder']),
        _ex('c'),
      ]);
      expect(out[InjuryRegion.knee], 2);
      expect(out[InjuryRegion.shoulder], 1);
      expect(out[InjuryRegion.ankle], 0);
    });

    test('every region is present, including the uncovered ones', () {
      // Absent-means-zero would work until a caller used `[]` on a map that
      // had never seen the region, and a null there reads as "unknown" rather
      // than "none".
      final out = safetyCoverageByRegion([_ex('a', contraindications: ['knee'])]);
      expect(out.keys.toSet(), InjuryRegion.values.toSet());
    });

    test('normalises the tag the same way the filter does', () {
      final out =
          safetyCoverageByRegion([_ex('a', contraindications: ['Lower Back'])]);
      expect(out[InjuryRegion.lowerBack], 1);
    });

    test('a tag matching no region is counted for none of them', () {
      // It is not silently attributed to the nearest one. The builder refuses
      // to write such a tag at all; this is what the app does if one arrives
      // anyway.
      final out =
          safetyCoverageByRegion([_ex('a', contraindications: ['kneee'])]);
      expect(out.values.every((n) => n == 0), isTrue);
    });

    test('the shipped catalog covers exactly the regions batched so far', () {
      // The ratchet, per region rather than per row. A batch that tags 200
      // knees and no shoulders raises the total exactly as much as a balanced
      // one, and "screened for your injuries" is only ever true per injury --
      // so the batches are recorded here by name, and adding one turns this
      // red until it is.
      const batched = {
        InjuryRegion.knee: 362, // S3b-1
        InjuryRegion.lowerBack: 312, // S3b-2
        InjuryRegion.shoulder: 487, // S3b-2, +1 from a title typo fix (2026-08-15)
        InjuryRegion.hip: 404, // S3b-3
        InjuryRegion.ankle: 229, // S3b-3
        InjuryRegion.wrist: 188, // S3b-3
        InjuryRegion.elbow: 371, // S3b-3
        InjuryRegion.neck: 117, // S3b-3
        // The ninth and last region to be batched. It had been selectable on
        // the body diagram since 2026-08-12 and screening nothing, because the
        // tagger had no rule key for it and no guard read a legal-but-ruleless
        // region as wrong — `test_every_legal_region_has_rules`
        // (`scripts/catalog/test_tag_contraindications.py`) is what now does.
        InjuryRegion.upperBack: 265, // P3, then the Codex round-2 fix (+2/-1)
      };
      final raw = File('assets/data/exercises_vendor.json').readAsStringSync();
      final catalog = (jsonDecode(raw) as List)
          .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final byRegion = safetyCoverageByRegion(catalog);
      for (final region in InjuryRegion.values) {
        expect(byRegion[region], batched[region] ?? 0,
            reason: '${region.name} coverage moved. If a batch shipped, add it '
                'to `batched` above and to kSafetyCoverageFloor in the same '
                'commit; if it did not, tags have been lost, which is the '
                'exact failure 0c4bf24 shipped.');
      }
    });
  });
}
