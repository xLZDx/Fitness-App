import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_hero.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:flutter_test/flutter_test.dart';


/// The `mobile` package directory, found from wherever the test runs (the
/// package root under `flutter test`, but not guaranteed by every runner).
final Directory _mobile = () {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(RegExp(r'^name:\s*fitness_app',
            multiLine: true))) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('mobile package root not found from '
          '${Directory.current.path}');
    }
    dir = parent;
  }
}();

/// A path relative to the `mobile` package (`../` reaches the repo root).
String _p(String relative) => '${_mobile.path}/$relative';

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

/// Reviewed header per machine: `null` is a deliberate placeholder.
const Map<String, String?> _pinnedHeroes = {
  'treadmill': 'ea_treadmill_jogging',
  'rowing_machine': 'ea_gym_rowing_machine_fast_speed',
  'squat_rack': 'ea_barbell_full_squat',
  'bench_press': 'ea_barbell_bench_press',
  'cable_machine': 'ea_cable_upper_chest_crossover',
  'leg_press': 'ea_horizontal_leg_press',
  'lat_pulldown': 'ea_cable_pulldown',
  'barbell': 'ea_barbell_deadlift',
  'dumbbell': 'ea_dumbbell_curls',
  'kettlebell': 'ea_kettlebell_curl',
  'elliptical': 'ea_gym_elliptical_machine_fast_speed',
  'exercise_bike': 'ea_stationary_exercise_bike',
  'recumbent_bike': null,
  'stair_climber': 'ea_stepmill_machine_steps',
  'air_bike': 'ea_assault_airbike_fast_speed',
  'ski_erg': 'ea_ski_ergometer_cross_country_ski_flyes',
  'smith_machine': 'ea_normal_squat_smith_machine',
  'hack_squat_machine': 'ea_hack_squat_machine_squat',
  'leg_extension': 'ea_lever_leg_extension',
  'leg_curl': 'ea_kneeling_leg_curl_machine',
  'hip_abductor_adductor': 'ea_seated_hip_abductor_machine',
  'glute_kickback_machine': null,
  'calf_raise_machine': 'ea_seated_calf_machine',
  'chest_press_machine': 'ea_chest_press_machine',
  'pec_deck': 'ea_pec_deck_fly_machine',
  'shoulder_press_machine': 'ea_iso_lateral_shoulder_press_alternate_arms',
  'seated_row_machine': 'ea_seated_row_machine_rows',
  't_bar_row': null,
  'assisted_pullup_machine': 'ea_assisted_pull_up',
  'pullup_bar': 'ea_chin_up',
  'dip_station': 'ea_chest_dip_on_dip_station',
  'preacher_curl_bench': 'ea_barbell_preacher_curl',
  'bicep_curl_machine': 'ea_hammer_strength_mts_iso_lateral_biceps_curl_alternate_arm',
  'tricep_extension_machine': 'ea_tricep_extension_machine',
  'ab_crunch_machine': 'ea_abdominal_crunches_machine',
  'rotary_torso_machine': null,
  'back_extension': 'ea_back_extension_machine',
  'captains_chair': 'ea_captains_chair_leg_raise',
  'adjustable_bench': 'ea_chest_dip_on_bench',
  'ez_curl_bar': 'ea_upright_row_ez_bar',
  'weight_plates': 'ea_plate_front_raise',
  'resistance_bands': 'ea_resistance_band_clam',
  'trx': 'ea_suspension_trainer_with_grips_pike',
  'medicine_ball': 'ea_medicine_ball_jumps',
  'battle_ropes': 'ea_sled_battle_rope_pull',
  'plyo_box': 'ea_box_jump',
  'punching_bag': 'ea_heavy_bag_sled_drag',
  'foam_roller': 'ea_foam_roller_back',
  'stability_ball': 'ea_crunch_on_stability_ball',
  'skipping_rope': 'ea_jump_rope_row',
  'ab_wheel': 'ea_ab_wheel_plank',
  'parallettes': 'ea_l_sit_hold',
  'seated_dip_machine': 'ea_chest_dip_machine',
  'multi_hip_machine': 'ea_multi_hip_glute_extension',
  'lateral_raise_machine': 'ea_machine_lateral_raise',
  'sissy_squat_machine': 'ea_dumbbell_supported_sissy_squat',
  'agility_ladder': 'ea_agility_ladder_advanced_hop_position',
  'mini_trampoline': 'ea_rebounder_knee_jumps',
  'balance_board': 'ea_balance_board_lateral_squat',
  'yoga_blocks': 'ea_pyramid_pose_blocks',
  'weighted_sled': 'ea_lateral_sled_drag',
  'ab_mat': 'ea_ab_mat_sit_up',
  'bosu_ball': 'ea_crunch_on_bosu_ball',
  'sliding_disc': null,
  'sandbag': 'ea_sandbag_cleans',
  'gymnastic_rings': 'ea_ring_dips',
  'tyre': 'ea_tyre_flip',
  'vertical_pole': 'ea_fixed_bar_stretch',
  'outdoor_air_walker': 'ea_air_swing_running',
};

const int _changedCount = 35;
const int _sameCount = 29;

List<Map<String, dynamic>> _list(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  final equipment =
      _list(_p('assets/data/equipment.json')).map(EquipmentItem.fromJson).toList();
  final exercises =
      _list(_p('assets/data/exercises_vendor.json')).map(ExerciseItem.fromJson).toList();
  final index = EquipmentAliasIndex.fromJson(
      (jsonDecode(File(_p('assets/data/equipment_aliases.json')).readAsStringSync())
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

  test('every machine hero is exactly the pinned exercise', () {
    // Not derived from the ranker, so a new alias, a looser label rule or a
    // catalogue change that re-points a header fails here and has to be
    // reviewed (open the poster, check it depicts the machine, update the row).
    final actual = {
      for (final m in equipment) m.id: heroOf(m)?.id,
    };
    expect(actual.keys.toSet(), _pinnedHeroes.keys.toSet(),
        reason: 'a machine was added or removed: pin its header');
    final diff = <String>[
      for (final e in _pinnedHeroes.entries)
        if (actual[e.key] != e.value)
          '${e.key}: pinned ${e.value}, now ${actual[e.key]}',
    ];
    expect(diff, isEmpty);
  });

  test('how many machines changed hero or lost it versus the old rule', () {
    var changed = 0, lost = 0, same = 0;
    for (final m in equipment) {
      final before = oldHeroOf(m);
      final after = heroOf(m);
      if (after == null) {
        if (before != null) lost++;
      } else if (before?.id == after.id) {
        same++;
      } else {
        changed++;
      }
    }
    expect((changed: changed, lost: lost, same: same),
        (changed: _changedCount, lost: 1, same: _sameCount));
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

    // DOCUMENTED LIMIT. The generic ranking only knows "this exercise names
    // the machine": 'dumbbell bench press' and 'band bench press' resolve to
    // bench_press exactly like the barbell press does (the alias index takes
    // the longest alias in the text), and the shortest slug wins, so without a
    // curated id the pick is a band press. Rejecting implements generically
    // would need per-machine "designed implement" data, which is exactly what
    // heroExerciseId is. The barbell stations therefore MUST stay curated, and
    // this test fails if one of those ids is dropped.
    test('the barbell stations keep their curated header exercise', () {
      final byId = {for (final m in equipment) m.id: m.heroExerciseId};
      expect(byId['bench_press'], 'ea_barbell_bench_press');
      expect(byId['squat_rack'], 'ea_barbell_full_squat');
      expect(byId['barbell'], 'ea_barbell_deadlift');
      final uncurated = pickHeroExercise(
        equipmentId: 'bench_press',
        candidates: linked('bench_press'),
        index: index,
      )!;
      expect(uncurated.id, isNot('ea_barbell_bench_press'),
          reason: 'if the generic rule now picks the barbell press by itself, '
              'this documented limit is gone and the curation can be removed');
    });
  });
}
