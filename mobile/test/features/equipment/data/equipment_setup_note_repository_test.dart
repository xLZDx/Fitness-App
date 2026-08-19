import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_setup_note.dart';
import 'package:fitness_app/features/equipment/data/equipment_setup_note_repository.dart';

void main() {
  late MockEquipmentSetupNoteRepository repo;

  setUp(() => repo = MockEquipmentSetupNoteRepository());

  test('get() returns null for a pair that was never saved', () async {
    final result =
        await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(result, isNull);
  });

  test('save() then get() returns what was saved', () async {
    final note = EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4, pin 8',
      updatedAt: DateTime(2026, 8, 19),
    );
    await repo.save(note);
    final result =
        await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(result, note);
  });

  test('save() overwrites the previous note for the same pair, not appends',
      () async {
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19, 9),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 5',
      updatedAt: DateTime(2026, 8, 19, 10),
    ));
    final result =
        await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(result?.note, 'seat 5');
  });

  test('two different gyms for the same equipment type stay separate',
      () async {
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Planet Fitness',
      note: 'seat 6',
      updatedAt: DateTime(2026, 8, 19),
    ));
    expect((await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym'))?.note,
        'seat 4');
    expect(
        (await repo.get(equipmentId: 'leg_press', gymId: 'Planet Fitness'))?.note,
        'seat 6');
  });

  test('delete() removes only the targeted pair', () async {
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'lat_pulldown',
      gymId: 'Gold\'s Gym',
      note: 'grip wide',
      updatedAt: DateTime(2026, 8, 19),
    ));
    await repo.delete(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym'), isNull);
    expect((await repo.get(equipmentId: 'lat_pulldown', gymId: 'Gold\'s Gym'))?.note,
        'grip wide');
  });

  test('saving an empty note is a real save, not a no-op', () async {
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19, 9),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: '',
      updatedAt: DateTime(2026, 8, 19, 10),
    ));
    final result =
        await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(result, isNotNull, reason: 'clearing the note is still a saved row');
    expect(result?.note, '');
  });
}
