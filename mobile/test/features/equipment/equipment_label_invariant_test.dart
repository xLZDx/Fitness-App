import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C3 — a card may not say it needs nothing while naming a machine.
///
/// 78 of the 1,887 rows carried `equipmentLabel: "None"` with an `equipmentId`
/// pointing at a real registry entry — 25 a weight bench, 19 a cable machine.
/// Two places read that field, and both were affected differently:
///
/// * `exercise_reference.dart:315` renders the label verbatim on the exercise
///   card, so those 78 told the user they needed nothing and then asked for a
///   cable machine in step one. That is the user-visible half.
/// * `exercise_filter.dart:459-465` already carried a workaround, with the
///   comment "the label says nothing is needed while an `equipmentId` names a
///   machine. Believe the id." So the filter was already right — but a guard
///   written around corrupt data is evidence of the corruption, not a
///   substitute for fixing it.
///
/// The guard stays. It is now belt-and-braces over data that no longer
/// contradicts itself, and the test below is what keeps that true.
///
/// The three states are kept apart deliberately, because "needs nothing" and
/// "needs something we cannot name" are different facts and writing both as
/// `None` is what produced this:
///
///   NO_EQUIPMENT      no `equipmentId`; the label is the vendor's free text
///   KNOWN_EQUIPMENT   `equipmentId` resolves in `equipment.json`
///   UNKNOWN_EQUIPMENT `equipmentId` set and absent from the registry

List<Map<String, dynamic>> _list(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

bool _saysNothing(String? label) {
  final l = (label ?? '').trim().toLowerCase();
  return l.isEmpty || l == 'none';
}

void main() {
  final rows = _list('assets/data/exercises_vendor.json');
  final registry = {
    for (final e in _list('assets/data/equipment.json'))
      e['id'] as String: e['name'] as String?
  };

  final withId = rows.where((e) => e['equipmentId'] != null).toList();
  final withoutId = rows.where((e) => e['equipmentId'] == null).toList();

  group('the equipment label agrees with the equipment id', () {
    test('no row claims to need nothing while naming a machine', () {
      final contradictory = withId
          .where((e) => _saysNothing(e['equipmentLabel'] as String?))
          .map((e) => '${e['id']} -> ${e['equipmentId']}')
          .toList();
      expect(contradictory, isEmpty,
          reason: '${contradictory.length} rows name a machine and label it '
              '"None"; run tools/catalog/repair_equipment_label.py');
    });

    test('every equipmentId resolves in the registry (no UNKNOWN_EQUIPMENT)', () {
      // An id nothing resolves cannot be given a label without inventing one,
      // which is why the repair tool refuses rather than guessing. Zero today,
      // and this is what keeps it zero.
      final unresolved = withId
          .map((e) => e['equipmentId'] as String)
          .where((id) => !registry.containsKey(id))
          .toSet();
      expect(unresolved, isEmpty);
    });

    test('a row with no equipmentId keeps its own words', () {
      // NO_EQUIPMENT is not a defect and must not be "repaired" into a machine
      // name. "Yoga Mat", "Wall", "Chair" and "None" are all legitimate here —
      // `ExerciseItem.needsEquipment` reads them and treats a mat as not
      // equipment on purpose.
      expect(withoutId, isNotEmpty);
      final invented = withoutId
          .where((e) => registry.containsValue(e['equipmentLabel']))
          .map((e) => e['id'])
          .toList();
      expect(invented, isEmpty,
          reason: 'a row with no equipmentId was given a registry machine name');
    });

    test('CONTROL: all three states are actually present in what was read', () {
      // Every assertion above passes over an empty list. These are the measured
      // 2026-08-16 populations; the point is that the file was read and both
      // branches have rows in them, not the exact split.
      expect(rows, hasLength(1887));
      expect(withId, isNotEmpty);
      expect(withoutId, isNotEmpty);
      expect(withId.length + withoutId.length, rows.length);
      // And the repair did not achieve "no contradiction" by emptying labels.
      expect(withId.where((e) => (e['equipmentLabel'] as String?) == null),
          isEmpty);
    });
  });
}
