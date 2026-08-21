import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_setup_note.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_card.dart'
    show machineCardId;

void main() {
  group('machineCardId pins (Gate G coupling regression)', () {
    // equipmentSetupNoteId reuses machineCardId to slug the gym half of its
    // key -- see the coupling note on both functions. A future edit to
    // machineCardId for a machine-card reason that changes any of these
    // outputs will fail HERE, in this unrelated feature's suite, rather than
    // silently orphaning real users' saved setup notes in production.
    test('pinned outputs', () {
      expect(machineCardId('Gold\'s Gym'), 'gold_s_gym');
      expect(machineCardId('  GOLD\'S  GYM  '), 'gold_s_gym');
      expect(machineCardId('Planet Fitness'), 'planet_fitness');
      expect(machineCardId('A/B Gym'), 'a_b_gym');
      expect(machineCardId(''), 'machine');
      expect(machineCardId('   '), 'machine');
    });
  });

  group('equipmentSetupNoteId', () {
    test('throws on an empty or whitespace-only gymId rather than silently '
        "colliding into machineCardId's own empty-input fallback", () {
      expect(
        () => equipmentSetupNoteId(equipmentId: 'leg_press', gymId: ''),
        throwsArgumentError,
      );
      expect(
        () => equipmentSetupNoteId(equipmentId: 'leg_press', gymId: '   '),
        throwsArgumentError,
      );
    });

    test('is stable for the same (equipmentId, gymId) pair', () {
      final a = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
      final b = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
      expect(a, b);
    });

    test('differs when either half of the pair differs', () {
      final base = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
      expect(equipmentSetupNoteId(equipmentId: 'lat_pulldown', gymId: 'Gold\'s Gym'),
          isNot(base));
      expect(equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Planet Fitness'),
          isNot(base));
    });

    test('slugs the gym half so it is a safe Firestore doc id component', () {
      // A raw '/' in a doc id is a path separator to Firestore, not a
      // character -- if this ever regresses, save() would silently write
      // into a nested subcollection instead of one flat document.
      final id = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'A/B Gym');
      expect(id, isNot(contains('/')));
    });

    test('two spellings of the same gym name collapse to one id, matching '
        "machineCardId's own normalisation", () {
      final a = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
      final b = equipmentSetupNoteId(equipmentId: 'leg_press', gymId: '  GOLD\'S  GYM  ');
      expect(a, b);
    });
  });

  group('EquipmentSetupNote', () {
    test('the constructor rejects an empty or whitespace-only gymId', () {
      expect(
        () => EquipmentSetupNote(
          equipmentId: 'leg_press',
          gymId: '',
          note: 'seat 4',
          updatedAt: DateTime(2026, 8, 19),
        ),
        throwsAssertionError,
      );
      expect(
        () => EquipmentSetupNote(
          equipmentId: 'leg_press',
          gymId: '   ',
          note: 'seat 4',
          updatedAt: DateTime(2026, 8, 19),
        ),
        throwsAssertionError,
      );
    });

    test('fromJson returns null for a document with a missing/blank gymId '
        '-- corrupted or hand-edited data reads as "no note found", not a '
        'note whose own invariant is already broken', () {
      expect(
        EquipmentSetupNote.fromJson({
          'equipmentId': 'leg_press',
          'note': 'seat 4',
          'updatedAt': DateTime(2026, 8, 19).toUtc().toIso8601String(),
        }),
        isNull,
      );
      expect(
        EquipmentSetupNote.fromJson({
          'equipmentId': 'leg_press',
          'gymId': '   ',
          'note': 'seat 4',
          'updatedAt': DateTime(2026, 8, 19).toUtc().toIso8601String(),
        }),
        isNull,
      );
    });

    test('fromJson returns null for a document with a missing/blank '
        'equipmentId too', () {
      expect(
        EquipmentSetupNote.fromJson({
          'gymId': 'Gold\'s Gym',
          'note': 'seat 4',
          'updatedAt': DateTime(2026, 8, 19).toUtc().toIso8601String(),
        }),
        isNull,
      );
    });

    test('id getter matches the top-level function', () {
      final note = EquipmentSetupNote(
        equipmentId: 'leg_press',
        gymId: 'Gold\'s Gym',
        note: 'seat 4, pin 8',
        updatedAt: DateTime(2026, 8, 19),
      );
      expect(note.id,
          equipmentSetupNoteId(equipmentId: 'leg_press', gymId: 'Gold\'s Gym'));
    });

    test('round-trips through toJson/fromJson', () {
      final note = EquipmentSetupNote(
        equipmentId: 'leg_press',
        gymId: 'Gold\'s Gym',
        note: 'seat 4, pin 8',
        updatedAt: DateTime.utc(2026, 8, 19, 12, 30),
      );
      final restored = EquipmentSetupNote.fromJson(note.toJson());
      expect(restored, isNotNull);
      expect(restored!.equipmentId, note.equipmentId);
      expect(restored.gymId, note.gymId);
      expect(restored.note, note.note);
      expect(restored.updatedAt.toUtc(), note.updatedAt.toUtc());
    });

    test('an explicit empty note round-trips as empty, not lost', () {
      // The clear-the-box case: a user who deletes their reminder and saves
      // must get back an empty note next time, not their old one reappearing
      // because an empty string was treated as "nothing to write".
      final note = EquipmentSetupNote(
        equipmentId: 'leg_press',
        gymId: 'Gold\'s Gym',
        note: '',
        updatedAt: DateTime.utc(2026, 8, 19),
      );
      final restored = EquipmentSetupNote.fromJson(note.toJson());
      expect(restored?.note, '');
    });

    test('equality and hashCode are field-based', () {
      final a = EquipmentSetupNote(
        equipmentId: 'leg_press',
        gymId: 'Gold\'s Gym',
        note: 'seat 4',
        updatedAt: DateTime(2026, 8, 19),
      );
      final b = EquipmentSetupNote(
        equipmentId: 'leg_press',
        gymId: 'Gold\'s Gym',
        note: 'seat 4',
        updatedAt: DateTime(2026, 8, 19),
      );
      final c = b.copyWithNote('seat 5');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}

extension on EquipmentSetupNote {
  EquipmentSetupNote copyWithNote(String note) => EquipmentSetupNote(
        equipmentId: equipmentId,
        gymId: gymId,
        note: note,
        updatedAt: updatedAt,
      );
}
