import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';

/// The purchased library, as its own catalog.
///
/// Operator: *"мы же вроде договорились использовать только вендор ресурсы,
/// какой смысл сравнивать с тем что было"*. This list exists so coverage stops
/// depending on a name comparison — 1,899 movements arrive whole, each with the
/// clip it was filmed as, and nothing is matched onto anything.
///
/// What is worth pinning here is not the count for its own sake but the three
/// properties that were wrong when the generator was first written and are
/// invisible by inspection: muscle tags outside the app's vocabulary, entries
/// that claim to need no equipment, and object keys the signing function will
/// not accept.
void main() {
  final rows =
      (jsonDecode(File('assets/data/exercises_vendor.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final parsed = rows.map(ExerciseItem.fromJson).toList();
  final registry =
      (jsonDecode(File('assets/data/equipment.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  final registryIds = registry.map((e) => e['id'] as String).toSet();

  /// Exactly the tags the muscle map draws, the chips filter on and
  /// `filterContraindicated` reads.
  const appMuscles = {
    'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
    'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
    'traps', 'triceps',
  };

  group('the vendor catalog', () {
    test('is the whole library and every entry can be played', () {
      // 1,899 -> 1,887 when the gender suffix rule learned to read a SPACE
      // separator: thirteen women's clips stopped being separate men-only
      // exercises and paired up with their twins, which is what they always
      // were.
      expect(parsed, hasLength(1887));
      expect(withDemonstration(parsed), hasLength(1887),
          reason: 'a vendor entry with no clip has no reason to exist');
    });

    test('ids are unique and consistently prefixed', () {
      // This used to also assert no collision with `exercises.json`, because
      // the two catalogs were loaded into one list and a shared id would have
      // made one exercise silently replace another. That catalog was removed
      // on 2026-08-04; uniqueness within this one is what is left to protect,
      // and it is still the property a rebuild can break.
      final vendor = parsed.map((e) => e.id).toSet();
      expect(vendor, hasLength(parsed.length), reason: 'ids are unique');
      expect(vendor.every((id) => id.startsWith('ea_')), isTrue);
    });

    test('no muscle tag is outside what the app can render', () {
      // The generator invented `full_body` and `mobility` on its first run.
      // Neither is drawn by the muscle map and neither is understood by the
      // injury filter, so an exercise carrying one would show a blank chip and
      // slip past a user's injury.
      final used = <String>{};
      for (final e in parsed) {
        used.addAll(e.muscles);
        used.addAll(e.primaryMuscles);
      }
      expect(used.difference(appMuscles), isEmpty);
    });

    test('an untagged entry is allowed, and is the honest minority', () {
      // Four of the vendor's folders — Calisthenics, Powerlifting, Stretching,
      // Yoga — name no muscle, and guessing one is worse than leaving it out.
      final untagged = parsed.where((e) => e.muscles.isEmpty).length;
      expect(untagged, lessThan(parsed.length ~/ 5),
          reason: 'if most entries lost their tags, the parser broke');
      expect(untagged, greaterThan(0));
    });

    test('«Без оборудования» is a real group, and only what belongs is in it',
        () {
      // Every vendor entry used to have `equipmentId == null` because the
      // library knew nothing of our machines, and the filter selected on
      // exactly that — so it offered barbell squats as bodyweight work. It
      // selects on `needsEquipment` now, and 1,383 of these entries carry a
      // real machine link, which is what makes the group meaningful rather
      // than "everything we have not got round to".
      //
      // Operator, 2026-08-04: *"создай отдельную группу для 436 и назови «без
      // оборудования»"*, then *"перенести все в группу"* for the 28 rows still
      // outside it. 503, not 436: the 436 was a status count in the equipment
      // audit, and the group is what the app can actually select — the floor
      // stretches whose only listed "equipment" is a mat, and the ones whose
      // only prop is a wall, a chair or a training partner.
      //
      // Pinned as a range so re-linking one exercise does not fail this, but
      // emptying or doubling the group does.
      final noEquipment = parsed.where((e) => !e.needsEquipment).toList();
      expect(noEquipment.length, inInclusiveRange(470, 540));
      expect(noEquipment.length, lessThan(parsed.length ~/ 2),
          reason: 'most of a gym library needs equipment');
      for (final e in noEquipment) {
        expect(e.equipmentId, isNull,
            reason: '${e.id} is in the no-equipment group but links to a '
                'machine');
      }
    });

    test('nothing is left in between: every exercise is linked or in the group',
        () {
      // The property the two halves have to add up to. An exercise that
      // neither links to a machine nor reads as equipment-free is invisible
      // in both places — not on a machine page, not under «Без оборудования»
      // — and nothing else would notice.
      final orphans = parsed
          .where((e) => e.equipmentId == null && e.needsEquipment)
          .map((e) => '${e.id} (${e.equipmentLabel})')
          .toList();
      expect(orphans, isEmpty,
          reason: '${orphans.length} exercises belong to neither half');
    });

    test('a mat does not count as equipment', () {
      // Nobody filtering for "no equipment" means to exclude yoga.
      const yoga = ExerciseItem(
        id: 'ea_x', title: 'X', equipmentId: null, muscles: [],
        difficulty: ExerciseDifficulty.beginner, durationMinutes: 10,
        summary: '', steps: [], equipmentLabel: 'Yoga Mat',
      );
      expect(yoga.needsEquipment, isFalse);
    });

    test('every clip reference is a key clipUrl will sign', () {
      // A key the function rejects is an exercise that shows its poster
      // forever and reports nothing.
      final pattern =
          RegExp(r'^exercises/(girl|men)/[^/]{1,120}/[^/]{1,160}\.mp4$');
      final broken = <String>[];
      for (final e in parsed) {
        e.video.forEach((body, ref) {
          if (!pattern.hasMatch(ref)) broken.add('${e.id}/$body: $ref');
          if (ref.split('/')[1] != body) broken.add('${e.id} keyed $body');
        });
      }
      expect(broken, isEmpty);
    });

    test('every entry carries a bundled poster for each body it was filmed on',
        () {
      // The poster is what makes the first frame instant and offline. One per
      // clip, or the promise only holds for some exercises.
      final missing = <String>[];
      for (final e in parsed) {
        for (final body in e.video.keys) {
          if (e.poster[body] == null) missing.add('${e.id}/$body');
        }
      }
      expect(missing, isEmpty);
    });

    test('a poster path resolves to a file that is really there', () {
      // Spot-checked on disk rather than trusted from the JSON: the catalog
      // says `assets/posters/...` and a typo there is a blank card.
      for (final e in parsed.take(40)) {
        for (final path in e.poster.values) {
          expect(File(path).existsSync(), isTrue, reason: '${e.id}: $path');
        }
      }
    });
  });

  group('the Russian overlay', () {
    final file = File('assets/data/exercises_vendor.ru.json');

    test('covers the whole catalog', () {
      // Operator: Russian is mandatory and nothing is to be hidden, so a
      // partial overlay is a partial answer and this is where it shows.
      expect(file.existsSync(), isTrue);
      final ru = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, dynamic>();
      final ids = parsed.map((e) => e.id).toSet();
      final untranslated = ids.difference(ru.keys.toSet());
      expect(untranslated, isEmpty,
          reason: '${untranslated.length} exercises would show English');
    });

    test('never changes the number of steps', () {
      // A merged or invented step is instructions that no longer match the
      // movement, and it is invisible in a diff of three thousand paragraphs.
      final ru = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, dynamic>();
      final wrong = <String>[];
      for (final e in parsed) {
        final entry = ru[e.id] as Map<String, dynamic>?;
        if (entry == null) continue;
        final steps = (entry['steps'] as List?) ?? const [];
        if (steps.length != e.steps.length) wrong.add(e.id);
      }
      expect(wrong, isEmpty);
    });

    test('is actually Russian', () {
      // A model that answers in English on a hard title fails silently
      // otherwise -- the field is filled, the app is not translated.
      final ru = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, dynamic>();
      final cyrillic = RegExp(r'[а-яё]', caseSensitive: false);
      final english = <String>[];
      for (final entry in ru.entries) {
        final title = (entry.value as Map)['title'] as String? ?? '';
        if (title.isNotEmpty && !cyrillic.hasMatch(title)) {
          english.add('${entry.key}: $title');
        }
      }
      // A handful are legitimately Latin -- brand names like Hammer Strength,
      // and poses kept in Sanskrit transliteration.
      expect(english.length, lessThan(ru.length ~/ 20),
          reason: 'too many untranslated titles: ${english.take(5)}');
    });
  });

  group('linked to the 52-machine registry', () {
    // Every vendor exercise carried `equipmentId: null` -- the purchase never
    // assigned one -- so `exercisesFor(machineId)`, which is what fills a
    // machine's detail page, returned nothing for any of the 52 pages and
    // fell back to AI-generated, clip-less text. Operator: *"привязка к
    // тренажёрам ... иначе скан для вендорских упражнений не работает"*.
    //
    // Verified by an independent look at each exercise's own poster --
    // operator: *"верить никому нельзя все надо проверять"* -- not by trusting
    // the vendor's metadata sheet or the `equipmentLabel` already derived from
    // it. core/vendor_equipment_visual_audit.csv has the full trail; the ones
    // that stayed unresolved are core/vendor_equipment_needs_review.csv.
    test('most exercises resolve, most machines get at least one', () {
      final linked = parsed.where((e) => e.equipmentId != null).length;
      // 58% by name alone; the visual pass reached 1,330/1,887, then 1,372
      // once the registry grew from 52 to 67 machines (2026-08-03) -- kept as
      // a floor so a regression is caught without re-pinning an exact count
      // every time the review list moves it by one or two.
      expect(linked, greaterThanOrEqualTo(1370));

      final machinesCovered =
          parsed.map((e) => e.equipmentId).whereType<String>().toSet();
      // 4 of 67 are a genuine gap in the purchased library, not a pipeline
      // miss -- confirmed by hand: recumbent_bike (only an upright exercise
      // bike exists), glute_kickback_machine (only cable/dumbbell/band
      // variants), t_bar_row, rotary_torso_machine.
      expect(machinesCovered.length, greaterThanOrEqualTo(63));
    });

    test('every equipmentId assigned is a real registry machine', () {
      // The model was given the 52 real names and told to answer with one of
      // them or "none" -- this is the check that an answer which wasn't one of
      // those names verbatim never made it into the catalog as a guess.
      final bad = parsed
          .where((e) => e.equipmentId != null && !registryIds.contains(e.equipmentId))
          .map((e) => '${e.id}: ${e.equipmentId}');
      expect(bad, isEmpty);
    });

    test('a barbell squat links to the squat rack, not the generic barbell',
        () {
      // The registry mixes a generic implement (Barbell) with the specific
      // station it is normally used at (Squat rack, Weight bench). The first
      // pass answered "Barbell" for a barbell squat -- true but useless, since
      // squat_rack is the page a user actually opens after scanning the rack.
      // This is the fixed prompt's whole point, pinned so it cannot regress.
      final squat = parsed.firstWhere((e) => e.id == 'ea_barbell_squat_back_pov',
          orElse: () => parsed.firstWhere((e) => e.title == 'Barbell Squat'));
      expect(squat.equipmentId, 'squat_rack');
    });

    test('with no dedicated station, the generic implement is used', () {
      // A barbell deadlift has no "deadlift platform" in the registry, so it
      // correctly stays on the generic implement rather than being forced
      // onto an unrelated station.
      final deadlift =
          parsed.where((e) => e.title.toLowerCase().contains('barbell') &&
              e.title.toLowerCase().contains('deadlift'));
      expect(deadlift, isNotEmpty);
      for (final e in deadlift) {
        expect(e.equipmentId, anyOf(isNull, 'barbell'));
      }
    });
  });

  group('a title that claims a distinction, and the steps that must carry it',
      () {
    // The vendor shipped whole clusters of exercises whose Steps text is
    // byte-identical to a differently-named sibling. Most are harmless -- a
    // camera angle, a plural, a synonym. Four were not: the title promised a
    // grip, a tempo, a travel pattern or a lift that the Steps then described
    // as something else, so a user following the instructions did a different
    // exercise from the one they chose.
    //
    // Pinned per pair rather than as a blanket "no two rows share Steps",
    // because sharing Steps is legitimate for the POV variants and a blanket
    // rule would have to whitelist them all.
    ExerciseItem byId(String id) => parsed.firstWhere((e) => e.id == id);

    test('a close grip is described as close, not as shoulder-width', () {
      final close = byId('ea_assisted_close_grip_underhand_chin_up');
      final normal = byId('ea_assisted_chin_up_normal_width_reverse_grip');
      expect(close.steps, isNot(equals(normal.steps)),
          reason: 'the close-grip variant repeated its sibling verbatim');
      expect(close.steps.first.toLowerCase(), contains('close together'));
    });

    test('the slow variant is described as slow, not as quick', () {
      final slow = byId('ea_butt_kicks_slow');
      expect(slow.steps.join(' ').toLowerCase(), contains('slow'));
      expect(slow.steps.join(' ').toLowerCase(),
          isNot(contains('quick, continuous')),
          reason: 'the Slow variant told the user to move quickly');
      expect(slow.steps, isNot(equals(byId('ea_butt_kicks').steps)));
    });

    test('a travelling lunge travels; the on-the-spot one does not', () {
      final walking = byId('ea_barbell_lunges');
      final onSpot = byId('ea_barbell_lunges_on_the_spot');
      expect(walking.steps, isNot(equals(onSpot.steps)));
      expect(walking.steps.join(' ').toLowerCase(), contains('travel'));
      expect(onSpot.steps.join(' ').toLowerCase(),
          contains('return to the starting position'));
    });

    test('a muscle clean does not describe a power clean catch', () {
      // Different lifts: a muscle clean pulls through to the shoulder with no
      // re-bend under the bar; a power clean drops under it into a front rack.
      // Identical Steps meant one of the two was simply wrong.
      final muscle = byId('ea_barbell_muscle_clean');
      final power = byId('ea_barbell_power_clean');
      expect(muscle.steps, isNot(equals(power.steps)));
      expect(muscle.steps.join(' ').toLowerCase(),
          isNot(contains('rotate your elbows under the bar')));
      expect(power.steps.join(' ').toLowerCase(),
          contains('rotate your elbows under the bar'));
    });
  });

  group('safety wording the audit found missing', () {
    ExerciseItem byId(String id) => parsed.firstWhere((e) => e.id == id);

    test('an advanced arm balance names every joint it loads', () {
      // `contraindications` is what `filterContraindicated` reads to keep an
      // exercise away from an injured user. These two were the only `advanced`
      // poses in the catalog carrying no tag in any region, so the filter had
      // nothing to act on for either.
      //
      // Asserted as the EXACT set, not `contains('wrist')`: a weaker check
      // passes with the shoulder and lower-back tags deleted, which is most of
      // what this fix added. The tags are generated — `scripts/catalog/
      // tag_contraindications.py`, rules `wrist_weight_bearing`,
      // `shoulder_loaded_arm_balance` and `lumbar_extension` — so the order
      // here is the tagger's sorted output, and changing the rules without
      // regenerating turns this red alongside the Python outcome check.
      final crow = byId('ea_crow_pose');
      expect(crow.difficulty, ExerciseDifficulty.advanced);
      expect(crow.contraindications, ['shoulder', 'wrist']);

      // Wild Thing adds the lower back: it is a backbend, entered from a side
      // plank. Crow rounds rather than extends, which is why it is not here.
      final wild = byId('ea_wild_thing_pose');
      expect(wild.difficulty, ExerciseDifficulty.advanced);
      expect(wild.contraindications, ['lower_back', 'shoulder', 'wrist']);
    });

    test('a maximum-range cue is qualified by what the user can control', () {
      final e = byId('ea_alternate_leg_raise_from_reverse_plank_position');
      final text = e.steps.join(' ').toLowerCase();
      expect(text, isNot(contains('to your maximum range')));
      expect(text, contains('as high as you can control'));
    });

    test('swinging a hammer requires eye protection, not suggests it', () {
      // The first version of this fix said "wear eye protection IF AVAILABLE",
      // which reads as permission to swing a sledgehammer at a tyre without
      // any — on the same card that warns the head rebounds unpredictably.
      // Conditional framing is asserted against, not just the presence of the
      // words, because the weak version contained them too.
      final text = byId('ea_tyre_hammering').purpose!.toLowerCase();
      expect(text, contains('eye protection'));
      expect(text, contains('clear'));
      for (final hedge in ['if available', 'if possible', 'ideally', 'where possible']) {
        expect(text, isNot(contains(hedge)),
            reason: 'eye protection is hedged with "$hedge"');
      }
    });

    test('an equipmentId never ships without a label to show for it', () {
      // `exercise_reference.dart` renders `equipmentLabel ?? "Bodyweight"`,
      // and `filterByEquipmentAccess` drops a row whose label reads "none"
      // while its id names a machine. Either way the row is wrong in the UI.
      // Scoped to the one row this gate fixed; the remaining 77 are tracked
      // in core/DECISION_LOG.md as a separate, larger data-quality item.
      final e = byId('ea_diagonal_chop_cable');
      expect(e.equipmentId, 'cable_machine');
      expect(e.equipmentLabel, isNotNull);
      expect(e.equipmentLabel!.toLowerCase(), isNot(startsWith('none')));
    });
  });
}
