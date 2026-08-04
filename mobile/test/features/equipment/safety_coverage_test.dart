import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// How many exercises in the shipped catalog must carry a contraindication
/// tag. Raised by each tagging batch, never lowered.
///
/// It is 0 because that is what the catalog measures: the legacy list carried
/// the only 144 tagged exercises in the product and was deleted in `0c4bf24`,
/// which no test noticed. A ratchet pinned at 0 is not a formality — the two
/// assertions below pin it from both sides, so tagging the very first exercise
/// turns this file red until the number here is raised to match. That is the
/// point: the count can never drift from the code again in either direction.
const int kSafetyCoverageFloor = 0;

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
}
