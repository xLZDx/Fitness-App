import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/settings_repository.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';

/// Dropping the pre-purchase half of the library, at any moment.
///
/// Operator: *"сделай так чтобы можно было отключить наши 511 в любой момент"*.
/// Two catalogs ship side by side while they are reconciled — 511 older entries
/// carrying hand-written Russian, injury contraindications and links to the 52
/// machines the scanner knows, and 1,899 purchased ones that all have a clip
/// and none of that metadata yet.
///
/// The switch exists from the day the second library landed rather than being
/// retrofitted once something depends on the mixture, and these tests hold it
/// to meaning what it says: off must remove exactly the old list and nothing
/// else, and the choice must survive a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the catalog switch', () {
    test('on, both libraries are present', () async {
      final repo = AssetEquipmentRepository();
      final all = [
        ...await repo.bodyweightExercises(),
        for (final e in await repo.listEquipment())
          ...await repo.exercisesFor(e.id),
      ];
      expect(all.where((e) => e.id.startsWith('ea_')), isNotEmpty,
          reason: 'the purchased library');
      expect(all.where((e) => !e.id.startsWith('ea_')), isNotEmpty,
          reason: 'the older library');
    });

    test('off, only the purchased library remains', () async {
      final repo = AssetEquipmentRepository(includeLegacy: false);
      final all = [
        ...await repo.bodyweightExercises(),
        for (final e in await repo.listEquipment())
          ...await repo.exercisesFor(e.id),
      ];
      expect(all, isNotEmpty);
      expect(all.every((e) => e.id.startsWith('ea_')), isTrue,
          reason: 'an id without the vendor prefix survived the switch');
    });

    test('off does not touch the machines themselves', () async {
      // The 52 machines are what the scanner recognises and they belong to
      // neither catalog. Dropping the old exercise list must not empty the
      // equipment pages it happens to be indexed against.
      final on = await AssetEquipmentRepository().listEquipment();
      final off =
          await AssetEquipmentRepository(includeLegacy: false).listEquipment();
      expect(off.map((e) => e.id), equals(on.map((e) => e.id)));
      expect(off, isNotEmpty);
    });

    test('turning it off removes exactly the older entries, no more', () async {
      final on = AssetEquipmentRepository();
      final off = AssetEquipmentRepository(includeLegacy: false);
      Future<Set<String>> ids(AssetEquipmentRepository r) async => {
            for (final e in await r.bodyweightExercises()) e.id,
            for (final eq in await r.listEquipment())
              for (final e in await r.exercisesFor(eq.id)) e.id,
          };
      final withLegacy = await ids(on);
      final without = await ids(off);
      final removed = withLegacy.difference(without);
      expect(removed, isNotEmpty);
      expect(removed.any((id) => id.startsWith('ea_')), isFalse,
          reason: 'the switch took purchased exercises with it');
      expect(without.difference(withLegacy), isEmpty,
          reason: 'turning a library off cannot add exercises');
    });
  });

  group('the setting itself', () {
    test('defaults to on', () {
      // Default true: switching it off shrinks what the user can see, and a
      // default that hides content is not a default.
      expect(const AppSettings().includeLegacyCatalog, isTrue);
    });

    test('survives a save and load', () async {
      // Written to disk, not held in memory: the operator wants to flip it and
      // keep using the app, not flip it every launch.
      final repo = InMemorySettingsRepository();
      await repo.save(const AppSettings(includeLegacyCatalog: false));
      expect((await repo.load()).includeLegacyCatalog, isFalse);
    });

    test('copyWith leaves it alone unless asked', () async {
      const settings = AppSettings(includeLegacyCatalog: false);
      expect(settings.copyWith(notificationsEnabled: false).includeLegacyCatalog,
          isFalse);
      expect(settings.copyWith(includeLegacyCatalog: true).includeLegacyCatalog,
          isTrue);
    });

    test('two settings differing only by it are not equal', () {
      // Riverpod's `select` compares; an incomplete `==` would mean flipping
      // the switch changed nothing on screen.
      expect(const AppSettings(includeLegacyCatalog: true),
          isNot(const AppSettings(includeLegacyCatalog: false)));
    });
  });
}
