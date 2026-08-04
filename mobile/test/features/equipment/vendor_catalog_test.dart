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
}
