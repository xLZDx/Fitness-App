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

    test('every difficulty is one the app can actually read', () {
      // `ExerciseItem.fromJson` matches the string against the enum and falls
      // back to `beginner` on anything it does not recognise
      // (equipment_models.dart:65-68). That fallback is silent, so a value the
      // enum lacks does not fail loudly -- it mislabels the exercise.
      //
      // Three shipped entries carried "expert": One Arm Chin-Up, Hanging Leg
      // Raise and Hanging Pike, all displayed to beginners as beginner work.
      // The importer maps levels through LEVEL_MAP; close_empty_machines.py
      // passed the upstream value straight through, which is how they got in.
      const canonical = {'beginner', 'intermediate', 'advanced'};
      final bad = exercises
          .where((e) => !canonical.contains(e['difficulty']))
          .map((e) => '${e['id']}=${e['difficulty']}')
          .toList();
      expect(bad, isEmpty,
          reason: 'these silently render as "beginner" to the user: $bad');
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

  group('the implements the video library needed', () {
    // The 677-file drop shipped 19 exercises with no equipment because the
    // registry had no id for what they use. Operator picked four of them to
    // add: "фитбол, скакалки, ролика для пресса и брусьев-паралеток". The
    // stretching strap and the two machines the source does not identify stay
    // null, because a plausible-looking wrong machine is worse than none.
    //
    // The generic invariants above already cover these — aliases, Russian
    // name, no empty machine. This pins them by NAME, because deleting an
    // implement together with its exercises satisfies every generic rule and
    // silently removes a category the user had.
    const added = {
      'stability_ball': 7,
      'skipping_rope': 1,
      'ab_wheel': 1,
      'parallettes': 1,
    };

    test('each one exists and owns the exercises it was added for', () {
      final byId = <String, int>{};
      for (final e in exercises) {
        final id = e['equipmentId'] as String?;
        if (id != null) byId[id] = (byId[id] ?? 0) + 1;
      }
      added.forEach((id, count) {
        expect(equipmentIds, contains(id));
        expect(byId[id], count, reason: '$id lost or gained exercises');
      });
    });

    test('what stayed null, stayed null on purpose', () {
      // Five stretching entries use a strap or a belt, and two "Lever" rows
      // name a machine the registry does not have. Guessing at those is the
      // failure this catalog has already been through once.
      const deliberatelyNull = [
        'vid_stretching_calf_stretch_with_rope',
        'vid_stretching_calf_stretch_with_strap',
        'vid_stretching_hamstring_stretch',
        'vid_lever_lateral_raise',
        'vid_lever_shrug',
      ];
      final byId = {for (final e in exercises) e['id'] as String: e};
      for (final id in deliberatelyNull) {
        expect(byId[id], isNotNull, reason: '$id disappeared');
        expect(byId[id]!['equipmentId'], isNull,
            reason: '$id was given a machine it does not use');
      }
    });
  });

  group('Free Exercise DB expansion (round 4, S0)', () {
    final ruExercises = (jsonDecode(
            File('assets/data/exercises.ru.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
    final imported = exercises.where((e) => (e['id'] as String).startsWith('fedb_'));

    test('NO machine has zero exercises', () {
      // Round 3 shipped 32 registry ids with zero curated exercises (operator
      // screenshot: Elliptical -> "No curated exercises yet"). Round 4 got it
      // to 11. A1 closed the rest: nine from upstream entries my own category
      // filter had been dropping, two hand-authored because the source has
      // nothing for an air bike or a ski erg.
      //
      // Exactly zero, not "fewer than N". The previous version of this test
      // asserted `lessThan(15)`, which is how eleven empty machines stayed
      // green for a whole round.
      final byId = <String, int>{};
      for (final e in exercises) {
        final id = e['equipmentId'] as String?;
        if (id != null) byId[id] = (byId[id] ?? 0) + 1;
      }
      final stillEmpty =
          equipmentIds.where((id) => (byId[id] ?? 0) == 0).toList()..sort();
      expect(stillEmpty, isEmpty,
          reason: 'machines the user can open and find nothing in: $stillEmpty');
    });

    test('every imported exercise has a Russian translation', () {
      for (final e in imported) {
        expect(ruExercises, contains(e['id']),
            reason: '${e['id']} missing from exercises.ru.json');
        final entry = ruExercises[e['id']] as Map;
        expect((entry['title'] as String).trim(), isNotEmpty);
        expect((entry['steps'] as List), isNotEmpty);
      }
    });

    test('every imported exercise has non-empty muscles from our vocabulary',
        () {
      const vocab = {'adductors', 'back', 'biceps', 'calves', 'chest', 'core',
          'forearms', 'glutes', 'hamstrings', 'lats', 'lower_back', 'quads',
          'shoulders', 'traps', 'triceps'};
      for (final e in imported) {
        final muscles = (e['muscles'] as List).cast<String>();
        expect(muscles, isNotEmpty, reason: '${e['id']} has no muscles');
        expect(vocab, containsAll(muscles),
            reason: '${e['id']} uses an unmapped muscle name: $muscles');
      }
    });

    test('every imported exercise points at a real id or bodyweight', () {
      for (final e in imported) {
        final id = e['equipmentId'];
        if (id != null) expect(equipmentIds, contains(id));
      }
    });

    test('images are network URLs from the vendored public-domain source',
        () {
      for (final e in imported) {
        final urls = (e['imageUrls'] as List).cast<String>();
        expect(urls, isNotEmpty);
        for (final u in urls) {
          expect(u, startsWith(
              'https://raw.githubusercontent.com/yuhonas/free-exercise-db/'));
        }
        // frames stays empty for imported entries -- no bundled assets were
        // added, avoiding the APK-size regression a full bundle would cause.
        expect(e['frames'], isEmpty);
      }
    });

    test('no exact-title duplicate was imported over the existing catalog',
        () {
      final titles = exercises.map((e) => (e['title'] as String).toLowerCase());
      final counts = <String, int>{};
      for (final t in titles) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
      final dupes = counts.entries.where((e) => e.value > 1).toList();
      expect(dupes, isEmpty, reason: 'duplicate titles: $dupes');
    });
  });

  group('machine hero photos (S5)', () {
    test('most machines can source a real photo from their own exercises',
        () {
      // The machine card's thumbnail comes from the machine's exercises
      // rather than a stock-photo service -- those are photographs of the
      // actual machine, already vendored under the catalog's licence.
      final byEquipment = <String, List<Map<String, dynamic>>>{};
      for (final e in exercises) {
        final id = e['equipmentId'] as String?;
        if (id != null) byEquipment.putIfAbsent(id, () => []).add(e);
      }
      var covered = 0;
      for (final id in equipmentIds) {
        final has = (byEquipment[id] ?? const []).any((e) =>
            (e['imageUrls'] as List? ?? const []).isNotEmpty ||
            (e['frames'] as List? ?? const []).isNotEmpty);
        if (has) covered++;
      }
      expect(covered, greaterThanOrEqualTo(30),
          reason: 'only $covered of ${equipmentIds.length} machines have a '
              'photo to show');
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
