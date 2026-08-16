import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';

/// C1 — the withheld-exercise list, and whether it has any effect.
///
/// The 2026-08-15 audit found five cards that are wrong. Four are wrong in their
/// text and were corrected by `tools/catalog/correct_exercise_text.py`. The
/// fifth, `ea_major_groups_muscle_body`, cannot be corrected: it is a single
/// step describing a standing position, with no movement after it, no muscles,
/// no equipment and no purpose. There is nothing behind it to describe.
///
/// A list of withheld ids is worth exactly as much as its effect on what a user
/// can reach, so this file asserts the effect rather than the list. The
/// repository is the single load path for every surface — equipment browsing,
/// the player, the For You feed, the generated plan — which is why the filter
/// lives there and not on the screens.
///
/// The row is deliberately still IN the catalogue file. The external audit is
/// pinned to all 1,887 ids and matches them in both directions; deleting a row
/// would break that correspondence for a reason a later reader could not
/// reconstruct from the diff.

const String _withheldId = 'ea_major_groups_muscle_body';

List<Map<String, dynamic>> _readJsonList(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final quarantine = _readJsonList('assets/data/exercises_quarantine.json');
  final catalogue = _readJsonList('assets/data/exercises_vendor.json');
  final catalogueIds = catalogue.map((e) => e['id'] as String).toSet();

  group('the quarantine list itself', () {
    test('is not empty', () {
      // An empty list would make every assertion below vacuously true.
      expect(quarantine, isNotEmpty);
    });

    test('every withheld id exists in the catalogue', () {
      // A typo'd id withholds nothing and reports success, which is the
      // failure mode a list of strings invites.
      for (final entry in quarantine) {
        expect(catalogueIds, contains(entry['id']),
            reason: '${entry['id']} is withheld and is not in the catalogue');
      }
    });

    test('every entry records why, and when', () {
      for (final entry in quarantine) {
        expect((entry['reason'] as String?) ?? '', isNotEmpty,
            reason: '${entry['id']} is withheld with no reason recorded');
        expect((entry['since'] as String?) ?? '', isNotEmpty);
      }
    });

    test('the row is still in the catalogue file', () {
      // Withheld, not deleted -- see the file header.
      expect(catalogueIds, contains(_withheldId));
    });
  });

  group('the repository', () {
    // `ea_major_groups_muscle_body` carries no `equipmentId`, so the surface it
    // actually reached users through is the bodyweight list. Asserting against
    // that rather than against a test-only accessor is the difference between
    // proving the filter runs and proving it runs where it matters.
    final bodyweightIds = catalogue
        .where((e) => e['equipmentId'] == null)
        .map((e) => e['id'] as String)
        .toList();

    test('does not offer a withheld exercise', () async {
      final repo = AssetEquipmentRepository();
      final offered = await repo.bodyweightExercises();
      final withheld = quarantine.map((e) => e['id'] as String).toSet();
      expect(
        offered.where((e) => withheld.contains(e.id)),
        isEmpty,
        reason: 'a withheld exercise is reachable from the bodyweight list',
      );
    });

    test('withholds in Russian too', () async {
      // The overlay is text-only and cannot add an exercise back, but the
      // filter runs before translation and that ordering is worth pinning.
      final repo = AssetEquipmentRepository(languageCode: 'ru');
      final offered = await repo.bodyweightExercises();
      expect(offered.map((e) => e.id), isNot(contains(_withheldId)));
    });

    test('withholds only what is listed', () async {
      // CONTROL. Every assertion above is satisfied by a repository that
      // returns nothing at all, which would "fix" the defect by emptying the
      // library.
      final repo = AssetEquipmentRepository();
      final offered = await repo.bodyweightExercises();
      final withheldBodyweight = quarantine
          .map((e) => e['id'] as String)
          .where(bodyweightIds.contains)
          .length;
      expect(offered, hasLength(bodyweightIds.length - withheldBodyweight));
      expect(offered, isNotEmpty);
    });
  });
}
