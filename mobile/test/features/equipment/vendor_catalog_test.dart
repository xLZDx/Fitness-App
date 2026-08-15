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

    test('the muscle clean stays tall; the power clean pulls under', () {
      // BOTH lifts finish with the bar racked on the front of the shoulders —
      // that is not the difference, and an earlier version of this fix got it
      // backwards by rewriting the muscle clean to stop at shoulder height with
      // no rack, which describes a high pull and is a different exercise again.
      // The actual distinction is the receive: a muscle clean turns the elbows
      // over while standing tall and never re-bends the knees, which is why it
      // is a technique/strength drill and caps the load; a power clean pulls
      // under the bar into a partial squat.
      final muscle = byId('ea_barbell_muscle_clean');
      final power = byId('ea_barbell_power_clean');
      final m = muscle.steps.join(' ').toLowerCase();
      final p = power.steps.join(' ').toLowerCase();

      expect(muscle.steps, isNot(equals(power.steps)));

      // Both rack it.
      expect(m, contains('front rack'));
      expect(p, contains('front rack'));

      // Only the muscle clean forbids the re-bend, and says so. Asserted in
      // BOTH directions: without the negative half, a later edit could add
      // "never re-bends the knees" to the power clean — a direct contradiction
      // of its own next clause — and the suite would stay green.
      expect(m, contains('never re-bends the knees'));
      expect(p, isNot(contains('never re-bends the knees')));

      // Only the power clean describes pulling under into one.
      expect(p, contains('pull yourself under'));
      expect(p, contains('partial squat'));
      expect(m, isNot(contains('pull yourself under')));
      expect(m, isNot(contains('partial squat')));

      // The Russian overlay is what a Russian-speaking user actually reads, and
      // the standing RU tests check coverage, step count and Cyrillic titles —
      // none of which notices the RU steps describing the wrong lift. Reverting
      // either RU correction alone left the whole suite green until this ran.
      final ru = (jsonDecode(
              File('assets/data/exercises_vendor.ru.json').readAsStringSync())
          as Map).cast<String, dynamic>();
      String ruSteps(String id) =>
          ((ru[id] as Map)['steps'] as List).join(' ').toLowerCase();
      final mRu = ruSteps('ea_barbell_muscle_clean');
      final pRu = ruSteps('ea_barbell_power_clean');

      // Matched on stems, not on whole words: Russian declines, so
      // `contains('фронтальную стойку')` passes only for the accusative that
      // happens to be written today and fails on a legitimate rewording in the
      // genitive. A mutation run proved that — reverting the RU muscle clean to
      // a power-clean description made this fail on the CASE of "стойка"
      // rather than on the missing distinction, which is the right verdict for
      // the wrong reason.
      expect(mRu, contains('фронтальн'));
      expect(pRu, contains('фронтальн'));
      expect(pRu, contains('полуприсед'));
      expect(mRu, isNot(contains('полуприсед')));

      // The muscle clean's defining cue is a NEGATION — "колени не сгибаются
      // повторно". A stem check for 'повторн' alone stays green if the "не" is
      // deleted, which inverts the cue into a description of the power clean
      // while the test still passes. Matched as one expression so the negation
      // cannot be dropped independently of the verb it negates. `\w` is ASCII
      // in Dart, so the verb ending is spelled out as a Cyrillic class.
      expect(mRu, matches(RegExp(r'не\s+сгиба[а-яё]*\s+повторн')));
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

    test('swinging a hammer requires eye protection, in the steps', () {
      // Two earlier versions of this fix were wrong in different ways. The
      // first said "wear eye protection IF AVAILABLE" — permission to swing a
      // sledgehammer without any, on the same card that warns the head
      // rebounds unpredictably. The second dropped the hedge but left the
      // instruction in `purpose`, which renders under the "Why this matters"
      // heading in de-emphasised `textSecondary` ABOVE the numbered steps
      // (`exercise_reference.dart`) — a benefit paragraph is the one place a
      // user mid-workout will not read as an instruction. It belongs in step 1,
      // before the stance cue, because putting on goggles is a pre-swing
      // action.
      final e = byId('ea_tyre_hammering');
      final first = e.steps.first.toLowerCase();
      expect(first, contains('eye protection'));
      expect(first, contains('nobody is standing near'));
      // `summary` is a byte-identical copy of `steps.first` catalog-wide.
      expect(e.summary, e.steps.first);
      // Asserted against, not just absent by luck: the hedged version
      // contained the words "eye protection" too and would pass a presence
      // check.
      for (final hedge in ['if available', 'if possible', 'ideally', 'where possible']) {
        expect(first, isNot(contains(hedge)),
            reason: 'eye protection is hedged with "$hedge"');
      }
      // And it is no longer duplicated back into the benefit paragraph.
      expect(e.purpose!.toLowerCase(), isNot(contains('eye protection')));

      // The same relocation was made in the Russian overlay, and nothing else
      // in the suite would notice it being reverted: the standing RU tests
      // check coverage, step counts and Cyrillic titles, none of which cares
      // WHICH step carries the PPE cue. Without this, a Russian-speaking user
      // could lose the eye-protection instruction with the suite still green.
      final ruTyre = ((jsonDecode(
                  File('assets/data/exercises_vendor.ru.json').readAsStringSync())
              as Map)['ea_tyre_hammering'] as Map)
          .cast<String, dynamic>();
      final ruFirst = (ruTyre['steps'] as List).first as String;
      expect(ruFirst.toLowerCase(), contains('защитные очки'));
      expect(ruFirst.toLowerCase(), contains('никого нет'));
      expect(ruTyre['summary'], ruFirst);
      expect((ruTyre['purpose'] as String).toLowerCase(),
          isNot(contains('защитные очки')));
      // The English half of this test has guarded against hedges since the
      // first version — "wear eye protection IF AVAILABLE" was the original
      // defect. The Russian half checked only WHERE the cue lives, so
      // "по возможности наденьте защитные очки" would have passed: the same
      // defect, reintroduced in the language the English guard cannot see.
      for (final hedge in [
        'по возможности',
        'при возможности',
        'если возможно',
        'если есть',
        'желательно'
      ]) {
        expect(ruFirst.toLowerCase(), isNot(contains(hedge)),
            reason: 'RU eye protection is hedged with "$hedge"');
      }
    });

    test('a benefit paragraph never contradicts the steps beneath it', () {
      // This log's own rule, written one gate earlier: a prose edit to this
      // catalog ships with an assertion that fails when the edit is reverted,
      // or it does not ship. Three prose fixes then shipped without one, which
      // is what this covers. All three were introduced BY a previous fix — the
      // failure mode here is not the vendor data, it is rewriting.
      final ru = (jsonDecode(
              File('assets/data/exercises_vendor.ru.json').readAsStringSync())
          as Map).cast<String, dynamic>();
      String ruPurpose(String id) =>
          ((ru[id] as Map)['purpose'] as String).toLowerCase();

      // 1. The wall forearm stretch. `purpose` said the intensity is set by
      // how far you "lean in" while step 4 says "Lean away" — opposite
      // directions on one card. Asserted as agreement between the two fields
      // rather than as a fixed string, so a legitimate rewording still passes
      // and only a contradiction fails.
      final fore = byId('ea_forearms_stretch_on_wall');
      final foreSteps = fore.steps.join(' ').toLowerCase();
      expect(foreSteps, contains('lean away'));
      expect(fore.purpose!.toLowerCase(), contains('lean away'));
      expect(fore.purpose!.toLowerCase(), isNot(contains('lean in')));
      expect(ruPurpose('ea_forearms_stretch_on_wall'),
          contains('отклоняетесь'));
      expect(ruPurpose('ea_forearms_stretch_on_wall'),
          isNot(contains('наклоняетесь')));

      // 2. The plate lateral lunge. EN loads the HIP MUSCLES of the bent leg;
      // the RU overlay said "hip JOINT", on a card carrying the `hip`
      // contraindication, and the fix for that then left "мышцы таза
      // согнутой" — an adjective with no noun. Both failures are asserted
      // against: no joint, and the noun present.
      final lungeRu = ruPurpose('ea_plate_lateral_lunge');
      expect(lungeRu, contains('мышцы'));
      expect(lungeRu, isNot(contains('сустав')));
      expect(lungeRu, contains('согнутой ноги'));

      // 3. The Nordic hamstring curl. Two opposite failures on one sentence:
      // an earlier "softening" edit BROADENED the medical claim from hamstring
      // injuries to injury risk generally, and the restored text then asserted
      // one settled tear mechanism. Both directions are pinned.
      final nordic = byId('ea_nordic_hamstring_curl_with_partner');
      final np = nordic.purpose!.toLowerCase();
      expect(np, contains('reducing hamstring injuries'));
      expect(np, isNot(contains('reducing injury risk')));
      expect(np, isNot(contains('exactly when')));
      final nordicRu = ruPurpose('ea_nordic_hamstring_curl_with_partner');
      expect(nordicRu, contains('задней поверхности бедра'));
      expect(nordicRu, isNot(contains('ровно тогда')));
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
