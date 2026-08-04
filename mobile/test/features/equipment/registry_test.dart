import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';

/// The machine registry (defect round 3): 69 machines, ru overlay, alias
/// index.
///
/// Round 3 built this against `exercises.json`, and roughly half the file was
/// about that catalog's own contents — the reassignments that took ab crunches
/// off the treadmill page, the hand-authored cardio entries, the
/// free-exercise-db import, the photographs a machine card could source. That
/// catalog was removed on 2026-08-04 and those tests went with it rather than
/// being rewritten into assertions about a file that no longer exists. What
/// stays is what the registry itself promises, now measured against the one
/// catalog that ships.
void main() {
  final equipment = (jsonDecode(
          File('assets/data/equipment.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final exercises = (jsonDecode(
          File('assets/data/exercises_vendor.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final ruEquipment = (jsonDecode(
          File('assets/data/equipment.ru.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final aliases = (jsonDecode(
          File('assets/data/equipment_aliases.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final equipmentIds = equipment.map((e) => e['id'] as String).toSet();

  group('catalog integrity', () {
    test('equipment ids are unique and plentiful', () {
      expect(equipmentIds.length, equipment.length);
      expect(equipmentIds.length, greaterThanOrEqualTo(45),
          reason: 'the registry covers a real gym, not 10 machines');
    });

    test('every exercise points at a machine that exists (or bodyweight)', () {
      for (final e in exercises) {
        final id = e['equipmentId'];
        if (id == null) continue;
        expect(equipmentIds, contains(id),
            reason: '${e['title']} points at missing equipment $id');
      }
    });

    test('every machine has a Russian name and description', () {
      for (final id in equipmentIds) {
        final entry = ruEquipment[id] as Map?;
        expect(entry, isNotNull, reason: '$id missing from equipment.ru.json');
        expect((entry!['name'] as String).trim(), isNotEmpty);
        expect((entry['description'] as String).trim(), isNotEmpty);
      }
    });

    test('every difficulty is one the app can actually read', () {
      // `ExerciseItem.fromJson` matches the string against the enum and falls
      // back to `beginner` on anything it does not recognise
      // (equipment_models.dart:65-68). That fallback is silent, so a value the
      // enum lacks does not fail loudly -- it mislabels the exercise.
      const canonical = {'beginner', 'intermediate', 'advanced'};
      final bad = exercises
          .where((e) => !canonical.contains(e['difficulty']))
          .map((e) => '${e['id']}=${e['difficulty']}')
          .toList();
      expect(bad, isEmpty,
          reason: 'these silently render as "beginner" to the user: $bad');
    });

    test('exactly four machines are empty, and for a reason we know', () {
      // Round 3 shipped 32 registry ids with zero exercises (operator
      // screenshot: Elliptical -> "No curated exercises yet") and this test
      // was written to hold the number at zero. It could, while the
      // pre-purchase catalog was there to cover the gaps.
      //
      // Removing that catalog on 2026-08-04 exposed which machines only it
      // covered. These four have no vendor clip at all -- confirmed by hand,
      // not inferred from the null count (core/VENDOR_EQUIPMENT_LINK
      // _2026-08-03.md): the library's only stationary bike is upright, every
      // kickback uses a cable or a band, and nothing matches a T-bar row or a
      // rotary torso machine. They need footage, not a linking pass.
      //
      // Named rather than counted, so a FIFTH machine going empty -- which
      // would be a real regression -- still fails here.
      const knownEmpty = {
        'recumbent_bike',
        'glute_kickback_machine',
        't_bar_row',
        'rotary_torso_machine',
      };
      final byId = <String, int>{};
      for (final e in exercises) {
        final id = e['equipmentId'] as String?;
        if (id != null) byId[id] = (byId[id] ?? 0) + 1;
      }
      final empty =
          equipmentIds.where((id) => (byId[id] ?? 0) == 0).toSet();
      expect(empty, equals(knownEmpty),
          reason: 'machines the user can open and find nothing in: '
              '${(empty.difference(knownEmpty).toList()..sort())}');
    });
  });

  group('EquipmentAliasIndex', () {
    final index = EquipmentAliasIndex.fromJson(aliases);

    test('every catalog id owns at least two aliases', () {
      for (final id in equipmentIds) {
        expect((aliases[id] as List).length, greaterThanOrEqualTo(2),
            reason: '$id needs en + ru aliases');
      }
    });

    test('resolves Russian and English names', () {
      expect(index.resolve('Беговая дорожка'), 'treadmill');
      expect(index.resolve('гравитрон'), 'assisted_pullup_machine');
      expect(index.resolve('Smith machine'), 'smith_machine');
      expect(index.resolve('гакк-машина'), 'hack_squat_machine');
      expect(index.resolve('ЭЛЛИПС'), 'elliptical');
    });

    test('finds an alias inside a prose answer', () {
      // The cloud recogniser answers in prose; the index must dig the
      // machine out of the sentence.
      expect(index.resolve('This looks like a lat pulldown station'),
          'lat_pulldown');
      expect(index.resolve('Похоже, это машина Смита у стены'),
          'smith_machine');
    });

    test('the longest matching alias wins', () {
      expect(index.resolve('a seated leg curl machine'), 'leg_curl');
      expect(index.resolve('standing calf raise machine'),
          'calf_raise_machine');
    });

    test('normalisation folds case, ё and punctuation', () {
      expect(EquipmentAliasIndex.normalise('Гакк-Машина!'), 'гакк машина');
      expect(EquipmentAliasIndex.normalise('елка'),
          EquipmentAliasIndex.normalise('ёлка'));
      expect(index.resolve('беговая  дорожка'), 'treadmill');
    });

    test('unknown text resolves to null, never a guess', () {
      expect(index.resolve('квантовый телепорт'), isNull);
      expect(index.resolve(''), isNull);
    });
  });

  group('equipment translation overlay', () {
    test('applies name + description, keeps structure', () {
      const base = [
        EquipmentItem(
          id: 'treadmill',
          name: 'Treadmill',
          manufacturer: 'Any',
          category: 'cardio',
          description: 'Motorised running belt.',
        ),
      ];
      final out = AssetEquipmentRepository.applyEquipmentTranslations(base, {
        'treadmill': {'name': 'Беговая дорожка', 'description': 'Полотно.'},
      });
      expect(out.single.name, 'Беговая дорожка');
      expect(out.single.description, 'Полотно.');
      expect(out.single.id, 'treadmill');
      expect(out.single.category, 'cardio');
    });

    test('missing id keeps English rather than disappearing', () {
      const base = [
        EquipmentItem(
          id: 'x',
          name: 'X',
          manufacturer: 'Any',
          category: 'strength',
          description: 'd',
        ),
      ];
      final out =
          AssetEquipmentRepository.applyEquipmentTranslations(base, const {});
      expect(out, same(base));
    });
  });
}
