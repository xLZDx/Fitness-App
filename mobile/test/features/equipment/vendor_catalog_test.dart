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

  /// Exactly the tags the muscle map draws, the chips filter on and
  /// `filterContraindicated` reads.
  const appMuscles = {
    'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
    'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
    'traps', 'triceps',
  };

  group('the vendor catalog', () {
    test('is the whole library and every entry can be played', () {
      expect(parsed, hasLength(1899));
      expect(withDemonstration(parsed), hasLength(1899),
          reason: 'a vendor entry with no clip has no reason to exist');
    });

    test('ids cannot collide with the catalog we already had', () {
      final legacy =
          (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>()
              .map((e) => e['id'] as String)
              .toSet();
      final vendor = parsed.map((e) => e.id).toSet();
      expect(vendor, hasLength(parsed.length), reason: 'ids are unique');
      expect(vendor.intersection(legacy), isEmpty,
          reason: 'the two lists are loaded together; a shared id would make '
              'one exercise silently replace another');
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

    test('only genuinely equipment-free exercises read as bodyweight', () {
      // Every vendor entry has `equipmentId == null` because the library knows
      // nothing of our 52 machines. The "at home" filter used to select on
      // exactly that, so it offered barbell squats as bodyweight work.
      final noEquipment = parsed.where((e) => !e.needsEquipment).toList();
      expect(noEquipment, isNotEmpty);
      expect(noEquipment.length, lessThan(parsed.length ~/ 2),
          reason: 'most of a gym library needs equipment');
      for (final e in noEquipment) {
        final label = e.equipmentLabel?.toLowerCase() ?? '';
        expect(
          label.isEmpty || label.startsWith('none') || label.contains('mat'),
          isTrue,
          reason: '${e.id} claims no equipment but needs "${e.equipmentLabel}"',
        );
      }
    });

    test('a mat does not count as equipment', () {
      // Nobody filtering for "at home" means to exclude yoga.
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
}
