import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';

/// The machine registry (defect round 3): 48 machines, ru overlay, alias
/// index, and the exercise reassignments that took ab crunches off the
/// treadmill page.
void main() {
  final equipment = (jsonDecode(
          File('assets/data/equipment.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final exercises = (jsonDecode(
          File('assets/data/exercises.json').readAsStringSync()) as List)
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

    test('treadmill exercises are treadmill exercises', () {
      // Regression for the operator's screenshot: the treadmill page
      // recommended Ab Crunch Machine, Barbell Walking Lunge and Cable Crunch.
      final titles = exercises
          .where((e) => e['equipmentId'] == 'treadmill')
          .map((e) => (e['title'] as String).toLowerCase())
          .toList();
      expect(titles, isNotEmpty);
      for (final t in titles) {
        expect(t, isNot(anyOf(contains('crunch'), contains('lunge'),
            contains('cable'), contains('barbell'), contains('bench'))));
        expect(t, anyOf(contains('walk'), contains('run'), contains('interval')),
            reason: 'a treadmill exercise walks or runs; got "$t"');
      }
    });

    test('the rowing machine no longer teaches hack squats', () {
      final titles = exercises
          .where((e) => e['equipmentId'] == 'rowing_machine')
          .map((e) => (e['title'] as String).toLowerCase());
      for (final t in titles) {
        expect(t, contains('row'));
      }
    });

    test('new cardio exercises use the shared muscle vocabulary', () {
      final vocab = exercises
          .expand((e) => (e['muscles'] as List? ?? const []).cast<String>())
          .toSet();
      // Sanity that the vocabulary itself did not fork.
      expect(vocab, containsAll(['quads', 'lats', 'glutes', 'core']));
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
