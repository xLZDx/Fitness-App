import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_hero.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data contract over the real catalogue and exercise assets: the picture at
/// the top of a machine's page must depict that machine.
///
/// Reported defect: the "Жим лёжа (стойка)" page showed a man seated on a
/// bench curling dumbbells, because the header was the poster of the first
/// exercise linked to the machine -- and a machine's list holds everything
/// that can merely use it.
///
/// Injury screening is not part of this contract (it runs on top of the
/// ranking at read time), so candidates here are the unscreened exercises.

/// Machines that deliberately have no header: no exercise linked to them names
/// them, or none has a poster. Pinned so a catalogue change that adds or removes
/// a header is a visible, reviewed decision rather than a silent one.
const Set<String> _expectedNoHero = {
  // No poster-bearing exercise at all.
  'recumbent_bike', 'glute_kickback_machine', 't_bar_row',
  'rotary_torso_machine',
  // Its only poster-bearing exercise is a towel-slide lunge: it never names
  // the discs, so a placeholder is the honest header.
  'sliding_disc',
};

List<Map<String, dynamic>> _list(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  final equipment =
      _list('assets/data/equipment.json').map(EquipmentItem.fromJson).toList();
  final exercises =
      _list('assets/data/exercises_vendor.json').map(ExerciseItem.fromJson).toList();
  final index = EquipmentAliasIndex.fromJson(
      (jsonDecode(File('assets/data/equipment_aliases.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>());

  List<ExerciseItem> linked(String id) =>
      exercises.where((e) => e.equipmentId == id).toList();

  ExerciseItem? heroOf(EquipmentItem m, [List<ExerciseItem>? input]) =>
      pickHeroExercise(
        equipmentId: m.id,
        candidates: input ?? linked(m.id),
        index: index,
        preferredExerciseId: m.heroExerciseId,
      );

  ExerciseItem? oldHeroOf(EquipmentItem m) {
    for (final e in linked(m.id)) {
      if (e.posterFor(null) != null) return e;
    }
    return null;
  }

  test('every heroExerciseId points at a real exercise of that machine', () {
    final bad = <String>[];
    for (final m in equipment.where((m) => m.heroExerciseId != null)) {
      final e = exercises.where((x) => x.id == m.heroExerciseId).firstOrNull;
      if (e == null) {
        bad.add('${m.id}: ${m.heroExerciseId} does not exist');
      } else if (e.equipmentId != m.id) {
        bad.add('${m.id}: ${e.id} belongs to ${e.equipmentId}');
      } else if (e.posterFor(null) == null) {
        bad.add('${m.id}: ${e.id} has no poster');
      }
    }
    expect(bad, isEmpty);
  });

  test('every chosen hero depicts its own machine', () {
    final wrong = <String>[];
    for (final m in equipment) {
      final h = heroOf(m);
      if (h == null) continue;
      expect(h.equipmentId, m.id);
      final names = index.resolve(exerciseSlug(h)) == m.id ||
          (h.equipmentLabel != null &&
              index.resolve(h.equipmentLabel!) == m.id);
      final curated = m.heroExerciseId == h.id;
      if (!names && !curated) wrong.add('${m.id}: ${h.id}');
    }
    expect(wrong, isEmpty);
  });

  test('which machines changed hero or lost it (listed, and pinned)', () {
    final changed = <String>[];
    final lost = <String>[];
    var same = 0;
    for (final m in equipment) {
      final before = oldHeroOf(m);
      final after = heroOf(m);
      if (before == null && after == null) {
        lost.add('${m.id} (no poster before either)');
      } else if (after == null) {
        lost.add('${m.id} (was ${before!.id})');
      } else if (before?.id != after.id) {
        changed.add('${m.id}: ${before?.id} -> ${after.id}');
      } else {
        same++;
      }
    }
    // ignore: avoid_print
    print('HERO CHANGES: ${changed.length} changed, ${lost.length} without a '
        'hero, $same unchanged, of ${equipment.length}\n'
        'CHANGED:\n  ${changed.join('\n  ')}\nNO HERO:\n  ${lost.join('\n  ')}');
    final noHero = equipment.where((m) => heroOf(m) == null).map((m) => m.id);
    final unexpected = noHero.toSet().difference(_expectedNoHero);
    final unpinned = _expectedNoHero.difference(noHero.toSet());
    expect(unexpected, isEmpty,
        reason: 'these machines lost their header; confirm that is intended '
            'or fix the catalogue, then add them to _expectedNoHero');
    expect(unpinned, isEmpty);
  });

  test('the pick does not depend on catalogue order', () {
    final rnd = Random(7);
    final unstable = <String>[];
    for (final m in equipment) {
      final base = heroOf(m)?.id;
      final src = linked(m.id);
      for (final variant in [
        src.reversed.toList(),
        (List.of(src)..shuffle(rnd)),
        (List.of(src)..shuffle(rnd)),
      ]) {
        if (heroOf(m, variant)?.id != base) unstable.add(m.id);
      }
    }
    expect(unstable, isEmpty);
  });

  group('bench press station (reported)', () {
    final bench = equipment.firstWhere((m) => m.id == 'bench_press');

    test('the header is a barbell bench press, not a curl or a seated move',
        () {
      final h = heroOf(bench)!;
      expect(h.id, 'ea_barbell_bench_press');
      expect(h.equipmentLabel, 'Barbell');
      expect(h.id, contains('bench_press'));
      for (final banned in ['curl', 'seated', 'dumbbell', 'band', 'stretch']) {
        expect(h.id, isNot(contains(banned)));
      }
    });

    test('the old rule really did pick the curl (the test is not vacuous)',
        () {
      expect(oldHeroOf(bench)!.id,
          'ea_alternating_biceps_curl_seated_dumbbells');
    });

    test('with the curated id removed the generic rule still names a press',
        () {
      final h = pickHeroExercise(
        equipmentId: 'bench_press',
        candidates: linked('bench_press'),
        index: index,
      )!;
      expect(h.id, contains('bench_press'));
      expect(h.id, isNot(contains('curl')));
    });
  });
}
