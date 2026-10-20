import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/data/gemini_equipment_service.dart';
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

/// Data contract for the scan mapping: every machine name the cloud model may
/// answer with (`CANONICAL_MACHINES` in
/// `functions/src/ai_equipment_recognition.ts`) must resolve, through the real
/// alias index and the real `parseResponse`, to the catalogue entry that is
/// actually that machine -- never to an unrelated or cross-category page.
///
/// Reported defect (operator, real phone): the scan list and the page opened
/// from it named different machines. This file pins the mapping table by hand
/// so a wrong alias, a renamed catalogue row or a new canonical name that has
/// no row fails here instead of on a gym floor.

/// canonical model name -> (catalogue id, catalogue category).
///
/// Written out by hand on purpose: deriving it from the alias file would make
/// the test agree with whatever the alias file says.
const Map<String, (String, String)> _expected = {
  'treadmill': ('treadmill', 'cardio'),
  'rowing machine': ('rowing_machine', 'cardio'),
  'squat rack': ('squat_rack', 'strength'),
  'bench press station': ('bench_press', 'strength'),
  'cable machine': ('cable_machine', 'strength'),
  'leg press': ('leg_press', 'strength'),
  'lat pulldown': ('lat_pulldown', 'strength'),
  'barbell': ('barbell', 'free_weights'),
  'dumbbells': ('dumbbell', 'free_weights'),
  'kettlebell': ('kettlebell', 'free_weights'),
  'elliptical trainer': ('elliptical', 'cardio'),
  'exercise bike': ('exercise_bike', 'cardio'),
  'recumbent bike': ('recumbent_bike', 'cardio'),
  'stair climber': ('stair_climber', 'cardio'),
  'air bike': ('air_bike', 'cardio'),
  'ski erg': ('ski_erg', 'cardio'),
  'smith machine': ('smith_machine', 'strength'),
  'hack squat machine': ('hack_squat_machine', 'strength'),
  'leg extension machine': ('leg_extension', 'strength'),
  'leg curl machine': ('leg_curl', 'strength'),
  'hip abductor machine': ('hip_abductor_adductor', 'strength'),
  'glute kickback machine': ('glute_kickback_machine', 'strength'),
  'calf raise machine': ('calf_raise_machine', 'strength'),
  'chest press machine': ('chest_press_machine', 'strength'),
  'pec deck': ('pec_deck', 'strength'),
  'shoulder press machine': ('shoulder_press_machine', 'strength'),
  'seated row machine': ('seated_row_machine', 'strength'),
  't-bar row': ('t_bar_row', 'strength'),
  'assisted pull-up machine': ('assisted_pullup_machine', 'strength'),
  'pull-up bar': ('pullup_bar', 'bodyweight'),
  'dip station': ('dip_station', 'bodyweight'),
  'preacher curl bench': ('preacher_curl_bench', 'strength'),
  'biceps curl machine': ('bicep_curl_machine', 'strength'),
  'triceps extension machine': ('tricep_extension_machine', 'strength'),
  'ab crunch machine': ('ab_crunch_machine', 'strength'),
  'rotary torso machine': ('rotary_torso_machine', 'strength'),
  'back extension bench': ('back_extension', 'strength'),
  "captain's chair": ('captains_chair', 'bodyweight'),
  'flat bench': ('adjustable_bench', 'free_weights'),
  'ez curl bar': ('ez_curl_bar', 'free_weights'),
  'weight plates': ('weight_plates', 'free_weights'),
  'resistance bands': ('resistance_bands', 'functional'),
  'suspension trainer': ('trx', 'functional'),
  'medicine ball': ('medicine_ball', 'functional'),
  'battle ropes': ('battle_ropes', 'functional'),
  'plyo box': ('plyo_box', 'functional'),
  'punching bag': ('punching_bag', 'functional'),
  'foam roller': ('foam_roller', 'functional'),
  'stability ball': ('stability_ball', 'functional'),
  'skipping rope': ('skipping_rope', 'cardio'),
  'ab wheel': ('ab_wheel', 'functional'),
  'parallettes': ('parallettes', 'bodyweight'),
  'seated dip machine': ('seated_dip_machine', 'strength'),
  'multi hip machine': ('multi_hip_machine', 'strength'),
  'lateral raise machine': ('lateral_raise_machine', 'strength'),
  'sissy squat machine': ('sissy_squat_machine', 'strength'),
  'agility ladder': ('agility_ladder', 'functional'),
  'mini trampoline': ('mini_trampoline', 'cardio'),
  'balance board': ('balance_board', 'functional'),
  'yoga blocks': ('yoga_blocks', 'functional'),
  'weighted sled': ('weighted_sled', 'functional'),
  'ab mat': ('ab_mat', 'functional'),
  'bosu ball': ('bosu_ball', 'functional'),
  'sliding discs': ('sliding_disc', 'functional'),
  'sandbag': ('sandbag', 'functional'),
  'gymnastic rings': ('gymnastic_rings', 'bodyweight'),
  'tyre': ('tyre', 'functional'),
  'vertical pole': ('vertical_pole', 'bodyweight'),
  'outdoor air walker': ('outdoor_air_walker', 'cardio'),
  'push-up blocks': ('parallettes', 'bodyweight'),
  'aerobic step': ('plyo_box', 'functional'),
};

/// The only canonical names allowed to share a catalogue page. Everything else
/// must be one name -> one page.
const Map<String, String> _knownSharedPages = {
  'push-up blocks': 'parallettes',
  'aerobic step': 'plyo_box',
};

/// Cardio pages. A strength/free-weight/bodyweight machine opening one of these
/// is the reported "chest press opens the elliptical" failure shape.
const Set<String> _cardioIds = {
  'treadmill',
  'rowing_machine',
  'elliptical',
  'exercise_bike',
  'recumbent_bike',
  'stair_climber',
  'air_bike',
  'ski_erg',
  'skipping_rope',
  'mini_trampoline',
  'outdoor_air_walker',
};

List<String> _canonicalMachines() {
  final src = File(_p('../functions/src/ai_equipment_recognition.ts'))
      .readAsStringSync();
  final start = src.indexOf('CANONICAL_MACHINES');
  if (start < 0) throw StateError('CANONICAL_MACHINES not found');
  final open = src.indexOf('[', src.indexOf('=', start));
  final close = src.indexOf('] as const', open);
  if (open < 0 || close < open) throw StateError('canonical list not closed');
  return RegExp(r'"([^"]*)"')
      .allMatches(src.substring(open, close))
      .map((m) => m.group(1)!)
      .toList();
}

Map<String, dynamic> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

List<Map<String, dynamic>> _catalogue() =>
    (jsonDecode(File(_p('assets/data/equipment.json')).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  final canonical = _canonicalMachines();
  final aliasJson = _json(_p('assets/data/equipment_aliases.json'));
  final index = EquipmentAliasIndex.fromJson(aliasJson);
  final catalogue = _catalogue();
  final byId = {for (final e in catalogue) e['id'] as String: e};
  final ru = _json(_p('assets/data/equipment.ru.json'));

  test('canonical list was parsed and the table covers exactly it', () {
    expect(canonical, isNotEmpty);
    expect(canonical.toSet().length, canonical.length,
        reason: 'a canonical name is listed twice');
    expect(canonical.toSet(), _expected.keys.toSet(),
        reason: 'a canonical machine has no expected mapping (or the table '
            'has a stale row) -- add it to _expected deliberately');
  });

  test('catalogue ids are unique and every alias id has a catalogue row', () {
    final ids = catalogue.map((e) => e['id'] as String).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate catalogue id');
    expect(aliasJson.keys.toSet(), ids.toSet());
    expect(ru.keys.toSet(), ids.toSet());
  });

  test('no normalised alias is claimed by two catalogue ids', () {
    final owner = <String, String>{};
    final clashes = <String>[];
    aliasJson.forEach((id, aliases) {
      for (final a in (aliases as List).cast<String>()) {
        final key = EquipmentAliasIndex.normalise(a);
        final prev = owner[key];
        if (prev != null && prev != id) clashes.add('$key: $prev vs $id');
        owner[key] = id;
      }
    });
    expect(clashes, isEmpty);
  });

  group('every canonical machine resolves to its own page', () {
    for (final name in canonical) {
      test(name, () {
        final want = _expected[name]!;
        final resolved = index.resolve(name);
        expect(resolved, isNotNull, reason: '"$name" did not resolve');
        expect(resolved, want.$1);
        final row = byId[resolved];
        expect(row, isNotNull, reason: '"$resolved" has no catalogue row');
        expect(row!['category'], want.$2);
        if (!_cardioIds.contains(want.$1)) {
          expect(_cardioIds.contains(resolved), isFalse,
              reason: 'non-cardio "$name" resolved to a cardio page');
        }
      });

      test('$name through the real parseResponse', () {
        final want = _expected[name]!;
        final matches = GeminiVisualEquipmentService.parseResponse(
          jsonEncode({'machine': name, 'confidence': 0.9}),
          index,
        );
        if (GeminiVisualEquipmentService.kKnownUnreliableMachineNames
            .contains(name)) {
          expect(matches, isEmpty);
          return;
        }
        expect(matches.map((m) => m.equipmentId).toList(), [want.$1]);
      });
    }
  });

  test('canonical names are one name -> one page except the known shares', () {
    final owners = <String, List<String>>{};
    for (final name in canonical) {
      owners.putIfAbsent(index.resolve(name)!, () => []).add(name);
    }
    final shared = <String, String>{
      for (final e in owners.entries)
        if (e.value.length > 1) ...{for (final n in e.value.skip(1)) n: e.key},
    };
    expect(shared, _knownSharedPages);
  });

  test('every catalogue page is reachable from some canonical name', () {
    final reachable = canonical.map((n) => index.resolve(n)).toSet();
    final unreachable =
        byId.keys.where((id) => !reachable.contains(id)).toList();
    expect(unreachable, isEmpty);
  });

  test('a catalogue row\'s own EN and RU names resolve back to that row', () {
    final wrong = <String>[];
    for (final e in catalogue) {
      final id = e['id'] as String;
      final en = index.resolve(e['name'] as String);
      if (en != id) wrong.add('en "${e['name']}" ($id) -> $en');
      final ruName = (ru[id] as Map)['name'] as String;
      final r = index.resolve(ruName);
      if (r != id) wrong.add('ru "$ruName" ($id) -> $r');
    }
    expect(wrong, isEmpty);
  });

  test('the reported scan strings resolve to their own machines', () {
    expect(index.resolve('Жим от груди (тренажёр)'), 'chest_press_machine');
    expect(index.resolve('Бабочка (пек-дек)'), 'pec_deck');
    expect(index.resolve('Эллиптический тренажёр'), 'elliptical');
    expect(index.resolve('chest press machine'), isNot('elliptical'));
  });

  test('ids hard-coded in the text anchor and on-device label map exist', () {
    final ids = byId.keys.toSet();
    final anchor = File(
            _p('lib/features/visual_equipment/data/machine_text_anchor.dart'))
        .readAsStringSync();
    final anchorBlock = anchor.substring(
        anchor.indexOf('const Map<String, String> _kPhrases'),
        anchor.indexOf('/// Normalise to lowercase words'));
    final phraseIds = RegExp(r"'[a-z ]+':\s*'([a-z_]+)'")
        .allMatches(anchorBlock)
        .map((m) => m.group(1)!)
        .toSet();
    expect(phraseIds, isNotEmpty);
    expect(phraseIds.difference(ids), isEmpty,
        reason: 'text anchor names a machine that has no catalogue page');
    expect(anchor.contains("equipmentId: 'cable_machine'"), isTrue);

    final mlkit = File(
            _p('lib/features/visual_equipment/data/mlkit_visual_equipment_service.dart'))
        .readAsStringSync();
    final labelIds = RegExp(r"'[a-z_]+':\s*'([a-z_]+)'")
        .allMatches(mlkit)
        .map((m) => m.group(1)!)
        .toSet();
    expect(labelIds, isNotEmpty);
    expect(labelIds.difference(ids), isEmpty);
  });
}
