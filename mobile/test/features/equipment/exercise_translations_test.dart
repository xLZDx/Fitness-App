import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';

/// Guards the Russian exercise catalog.
///
/// The translation lives in a text-only overlay rather than a second copy of
/// the catalog, so the failure modes worth pinning are structural: an id that
/// loses its translation, a translation that quietly drops an instruction step,
/// and a language resolution that moves the interface but not the content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> base;
  late Map<String, dynamic> ru;

  setUpAll(() async {
    base = (jsonDecode(
            await rootBundle.loadString('assets/data/exercises_vendor.json'))
            as List)
        .cast<Map<String, dynamic>>();
    ru = (jsonDecode(
            await rootBundle.loadString('assets/data/exercises_vendor.ru.json'))
        as Map)
        .cast<String, dynamic>();
  });

  group('Russian overlay content', () {
    test('is packaged and non-trivial', () {
      expect(ru, isNotEmpty);
      expect(base, isNotEmpty);
    });

    test('covers every exercise and invents none', () {
      final baseIds = base.map((e) => e['id'] as String).toSet();
      expect(ru.keys.toSet(), equals(baseIds));
    });

    test('keeps the instruction step count of every exercise', () {
      // A translation that silently drops a step ships a materially different
      // — possibly less safe — set of instructions, and nothing about that is
      // visible at runtime. Compared post-filter so the one blank step in the
      // upstream data does not count against the translation.
      final mismatches = <String>[];
      for (final e in base) {
        final id = e['id'] as String;
        final en = ExerciseItem.parseSteps(e['steps']).length;
        final translated =
            ExerciseItem.parseSteps((ru[id] as Map)['steps']).length;
        if (en != translated) mismatches.add('$id: en=$en ru=$translated');
      }
      expect(mismatches, isEmpty);
    });

    test('is actually in Russian', () {
      final cyrillic = RegExp(r'[Ѐ-ӿ]');
      final untranslated = <String>[];
      ru.forEach((id, value) {
        final entry = value as Map;
        final strings = <String>[
          entry['title'] as String,
          ...(entry['steps'] as List).cast<String>(),
        ];
        if (strings.any((s) => !cyrillic.hasMatch(s))) untranslated.add(id);
      });
      expect(untranslated, isEmpty);
    });

    test('leaves no English words behind, beyond the ones a gym really says',
        () {
      // Catches a half-finished entry, which the Cyrillic check above would
      // pass as long as one word got translated.
      //
      // Zero was the right bar for the hand-written pre-purchase overlay. It
      // is the wrong bar for this one: 77 of 1,887 keep a Latin word on
      // purpose — brand names the equipment is sold under (Assault AirBike,
      // BOSU, Landmine, Silverback) and movement names a Russian lifter says
      // in English anyway (Good Morning, Renegade Row). Translating those
      // produces something nobody in a gym would recognise. A share, so a
      // genuinely half-translated rebuild still fails.
      final latinWord = RegExp(r'[a-zA-Z]{4,}');
      final leftovers = <String>[];
      ru.forEach((id, value) {
        final entry = value as Map;
        final strings = <String>[
          entry['title'] as String,
          ...(entry['steps'] as List).cast<String>(),
        ];
        if (strings.any(latinWord.hasMatch)) leftovers.add(id);
      });
      expect(leftovers.length, lessThan(ru.length ~/ 10),
          reason: '${leftovers.length} entries still read English: '
              '${leftovers.take(5)}');
    });
  });

  group('the summary invariant, in both languages', () {
    /// C2. This group used to check English only, and its own comment said the
    /// consequence out loud: "if a catalog rebuild ever breaks this, the Russian
    /// summary would silently diverge". It had already diverged — on **127** of
    /// 1,887 rows — and this file was green throughout, because nothing here
    /// looked at the Russian side.
    ///
    /// That is the more useful lesson than the 127 rows: a test that names the
    /// failure it is preventing, and then checks the other half of the pair, is
    /// indistinguishable from a passing test until someone measures. The
    /// English assertion was never wrong. It was just not the assertion the
    /// comment claimed it was.
    ///
    /// Both halves now run over all 1,887 rows.
    test('English: summary is always the first step', () {
      final broken = <String>[];
      for (final e in base) {
        final steps = ExerciseItem.parseSteps(e['steps']);
        if (steps.isEmpty) continue;
        if (e['summary'] != (e['steps'] as List).first) {
          broken.add(e['id'] as String);
        }
      }
      expect(broken, isEmpty);
    });

    test('Russian: summary is always the first step', () {
      // Repaired by `tools/catalog/repair_ru_summary.py`, deterministically:
      // every one of the 127 differed only in the phrasing of the same
      // instruction, with `steps[0]` carrying the newer wording. `steps[0]` is
      // canonical by construction — `merge_exercise_text.py` derives every
      // Russian summary from it and refuses to let a batch author one.
      final broken = <String>[];
      ru.forEach((id, entry) {
        final row = (entry as Map).cast<String, dynamic>();
        final steps = ExerciseItem.parseSteps(row['steps']);
        if (steps.isEmpty) return;
        if (row['summary'] != (row['steps'] as List).first) broken.add(id);
      });
      expect(broken, isEmpty,
          reason: '${broken.length} Russian rows break summary == steps[0]');
    });

    test('CONTROL: both sides were actually read', () {
      // Every assertion above passes over an empty collection. The catalogue is
      // 1,887 rows in both languages and each row has a summary to compare.
      expect(base, hasLength(1887));
      expect(ru, hasLength(1887));
      expect(base.where((e) => (e['summary'] as String?)?.isNotEmpty ?? false),
          hasLength(1887));
      expect(
        ru.values.where((e) =>
            ((e as Map)['summary'] as String?)?.isNotEmpty ?? false),
        hasLength(1887),
      );
    });

    test('a purpose written in one language is written in both (B3)', () {
      // `purpose` answers "what is this FOR", which `summary` structurally
      // cannot: the test above pins it to step one. A row that gained the field
      // in English only would show the heading to an English user and nothing
      // to a Russian one — the exact half-filled state B3 exists to remove.
      final enWithPurpose = {
        for (final e in base)
          if ((e['purpose'] as String? ?? '').trim().isNotEmpty) e['id'] as String
      };
      final ruWithPurpose = {
        for (final entry in ru.entries)
          if (((entry.value as Map)['purpose'] as String? ?? '').trim().isNotEmpty)
            entry.key
      };
      expect(enWithPurpose.difference(ruWithPurpose), isEmpty,
          reason: 'English purpose with no Russian one');
      expect(ruWithPurpose.difference(enWithPurpose), isEmpty,
          reason: 'Russian purpose with no English one');
    });

    test('a purpose is never just a copy of the first step (B3)', () {
      // The failure this catches is a batch author filling the new field by
      // pasting the instruction, which would put the same sentence on the card
      // twice under two different headings and teach nobody anything.
      final copies = <String>[];
      for (final e in base) {
        final purpose = (e['purpose'] as String? ?? '').trim();
        if (purpose.isEmpty) continue;
        final steps = (e['steps'] as List).cast<String>();
        if (steps.isNotEmpty && purpose == steps.first.trim()) {
          copies.add(e['id'] as String);
        }
      }
      expect(copies, isEmpty);
    });

    test('every row that has a purpose also has real steps (B3)', () {
      final orphans = [
        for (final e in base)
          if ((e['purpose'] as String? ?? '').trim().isNotEmpty &&
              (e['steps'] as List).isEmpty)
            e['id'] as String
      ];
      expect(orphans, isEmpty,
          reason: 'a purpose with no technique is half an answer');
    });

    test('no shipped entry carries a blank step', () {
      // This used to point at `barbell_squat_to_a_bench`, one row in the
      // pre-purchase catalog whose upstream source left an empty string in
      // the middle of its instructions, and assert that `parseSteps` filtered
      // it. That row went with its catalog on 2026-08-04 and the purchased
      // library has no blank step at all — so the assertion flips to the
      // stronger one, and the filtering behaviour itself stays covered by the
      // `ExerciseItem.parseSteps` fixtures below.
      final withBlank = base
          .where((e) => ((e['steps'] as List?) ?? const [])
              .any((s) => s is String && s.trim().isEmpty))
          .map((e) => e['id'] as String)
          .toList();
      expect(withBlank, isEmpty);
    });
  });

  group('ExerciseItem.parseSteps', () {
    test('drops blank and whitespace-only entries', () {
      expect(ExerciseItem.parseSteps(['a', '', '  ', 'b']), ['a', 'b']);
    });

    test('tolerates null and non-string entries', () {
      expect(ExerciseItem.parseSteps(null), isEmpty);
      expect(ExerciseItem.parseSteps(['ok', 7, null]), ['ok']);
    });
  });

  group('AssetEquipmentRepository.applyTranslations', () {
    ExerciseItem sample({String? purpose}) => ExerciseItem(
          id: 'squat',
          title: 'Barbell Squat',
          equipmentId: 'squat_rack',
          muscles: const ['quads', 'glutes'],
          difficulty: ExerciseDifficulty.intermediate,
          durationMinutes: 12,
          summary: 'Step one.',
          steps: const ['Step one.', 'Step two.'],
          purpose: purpose,
          frames: const ['assets/exercises/squat_0.jpg'],
          primaryMuscles: const ['quads'],
          contraindications: const ['knee'],
        );

    test('patches title, steps and summary from the overlay', () {
      final out = AssetEquipmentRepository.applyTranslations([sample()], {
        'squat': {
          'title': 'Приседания со штангой',
          'steps': ['Шаг один.', 'Шаг два.'],
        },
      });
      expect(out.single.title, 'Приседания со штангой');
      expect(out.single.steps, ['Шаг один.', 'Шаг два.']);
      expect(out.single.summary, 'Шаг один.');
    });

    test('never touches anything that drives behaviour', () {
      final out = AssetEquipmentRepository.applyTranslations([sample()], {
        'squat': {
          'title': 'Приседания',
          'steps': ['Шаг.'],
        },
      });
      final t = out.single;
      expect(t.id, 'squat');
      expect(t.equipmentId, 'squat_rack');
      expect(t.muscles, ['quads', 'glutes']);
      expect(t.primaryMuscles, ['quads']);
      expect(t.contraindications, ['knee']);
      expect(t.frames, ['assets/exercises/squat_0.jpg']);
      expect(t.difficulty, ExerciseDifficulty.intermediate);
      expect(t.durationMinutes, 12);
    });

    test('keeps English for an id the overlay is missing', () {
      final out =
          AssetEquipmentRepository.applyTranslations([sample()], {'other': {}});
      expect(out.single.title, 'Barbell Squat');
      expect(out, hasLength(1), reason: 'an untranslated exercise must not '
          'disappear from the catalog');
    });

    test('keeps English for a malformed entry rather than blanking the text',
        () {
      for (final bad in <Object>[
        'not a map',
        <String, Object>{'title': '', 'steps': ['x']},
        <String, Object>{'steps': ['Шаг.']},
      ]) {
        final out =
            AssetEquipmentRepository.applyTranslations([sample()], {'squat': bad});
        expect(out.single.title, 'Barbell Squat', reason: 'for $bad');
        expect(out.single.steps, ['Step one.', 'Step two.'], reason: 'for $bad');
      }
    });

    test('a title with no steps is still applied, and keeps the base steps',
        () {
      // Regression, 2026-08-04. This case used to be listed among the
      // malformed ones above: an overlay entry with an empty step list threw
      // the WHOLE translation away, title included.
      //
      // That was invisible while the pre-purchase catalog was the visible
      // half, because every one of its rows had instructions. The purchased
      // library ships 403 of 1,887 with a title and no steps, so removing
      // that catalog left a fifth of the app showing English titles under a
      // Russian UI — with the correct Russian sitting unused in the overlay.
      //
      // Both halves are asserted: the title must land, and steps the overlay
      // does not have must not be deleted from the base.
      for (final entry in <Object>[
        <String, Object>{'title': 'Присед со штангой', 'steps': <String>[]},
        <String, Object>{'title': 'Присед со штангой', 'steps': ['', '   ']},
        <String, Object>{'title': 'Присед со штангой'},
      ]) {
        final out = AssetEquipmentRepository
            .applyTranslations([sample()], {'squat': entry});
        expect(out.single.title, 'Присед со штангой', reason: 'for $entry');
        expect(out.single.steps, ['Step one.', 'Step two.'],
            reason: 'an overlay without steps must not delete them: $entry');
        expect(out.single.summary, sample().summary, reason: 'for $entry');
      }
    });

    test('an empty overlay is a pass-through', () {
      final out = AssetEquipmentRepository.applyTranslations([sample()], {});
      expect(out.single.title, 'Barbell Squat');
    });

    test('the overlay purpose replaces the base one', () {
      // Regression, 2026-08-13, caught at the Act gate. `purpose` was added
      // to the model, written into BOTH asset files, and covered by a data
      // ratchet asserting the two languages stay in step — and none of that
      // touched the render path. `withText` copied `purpose` from the base
      // row, so every Russian reader got the English paragraph under
      // "Зачем это нужно" while the correct Russian sat unused in the overlay.
      //
      // Exactly the failure the steps fallback above was written for, one
      // field later. The data being right is not evidence that the reader
      // sees it.
      final out = AssetEquipmentRepository.applyTranslations([
        sample(purpose: 'Builds the legs.'),
      ], {
        'squat': {
          'title': 'Приседания',
          'steps': ['Шаг один.'],
          'purpose': 'Развивает ноги.',
        },
      });
      expect(out.single.purpose, 'Развивает ноги.');
    });

    test('an overlay without a purpose keeps the base one rather than blanking',
        () {
      // Same reasoning as the steps fallback: a half-written overlay must
      // degrade to the wrong language, never to an empty section. The data
      // ratchet is what keeps this branch unreachable in the shipped files.
      for (final entry in <Map<String, Object>>[
        {'title': 'Приседания', 'steps': ['Шаг.']},
        {'title': 'Приседания', 'steps': ['Шаг.'], 'purpose': '   '},
        {'title': 'Приседания', 'steps': <String>[]},
      ]) {
        final out = AssetEquipmentRepository.applyTranslations([
          sample(purpose: 'Builds the legs.'),
        ], {
          'squat': entry,
        });
        expect(out.single.purpose, 'Builds the legs.', reason: 'for $entry');
      }
    });
  });

  group('repository reads the bundled catalog in the requested language', () {
    // `leg_press` still, but through a vendor exercise: the pre-purchase row
    // literally titled "Leg Press" was removed on 2026-08-04.
    test('English by default', () async {
      final repo = AssetEquipmentRepository();
      final all = await repo.exercisesFor('leg_press');
      expect(all.map((e) => e.title), contains('Horizontal Leg Press'));
    });

    test('Russian when asked', () async {
      final repo = AssetEquipmentRepository(languageCode: 'ru');
      final all = await repo.exercisesFor('leg_press');
      // A stepless entry: the one the 2026-08-04 overlay fix was about.
      expect(all.map((e) => e.title), contains('Жим ногами горизонтальный'));
      // And one with steps, which is where the tags can be disturbed.
      final legPress =
          all.firstWhere((e) => e.id == 'ea_leg_press_machine_close_stance');
      expect(legPress.title, 'Жим ногами в тренажёре с узкой постановкой стоп');
      expect(legPress.summary, legPress.steps.first);
      expect(legPress.primaryMuscles, contains('quads'),
          reason: 'translation must not disturb muscle tags');
    });

    test('falls back to English for a language with no overlay', () async {
      final repo = AssetEquipmentRepository(languageCode: 'de');
      final all = await repo.exercisesFor('leg_press');
      expect(all.map((e) => e.title), contains('Horizontal Leg Press'));
    });
  });

  group('AppLanguage.resolvedLocaleCode', () {
    test('an explicit choice wins over the device', () {
      expect(AppLanguage.ru.resolvedLocaleCode([const Locale('en')]), 'ru');
      expect(AppLanguage.en.resolvedLocaleCode([const Locale('ru')]), 'en');
    });

    test('system follows the device when the device is supported', () {
      expect(AppLanguage.system.resolvedLocaleCode([const Locale('en', 'US')]),
          'en');
      expect(AppLanguage.system.resolvedLocaleCode([const Locale('ru', 'MD')]),
          'ru');
    });

    test('system honours device preference order', () {
      expect(
        AppLanguage.system
            .resolvedLocaleCode([const Locale('de'), const Locale('en')]),
        'en',
      );
    });

    test('system on an unsupported device resolves to the fallback the '
        'interface will use', () {
      // The bug this pins: Flutter falls back to the first supported locale, so
      // the interface becomes Russian. Anything that answered "en" here would
      // ship Russian chrome around English exercise text.
      expect(AppLanguage.system.resolvedLocaleCode([const Locale('fr')]), 'ru');
      expect(AppLanguage.system.resolvedLocaleCode(const []), 'ru');
      expect(kSupportedLocaleCodes.first, 'ru');
    });
  });

  group('equipmentRepositoryProvider language wiring', () {
    ProviderContainer containerWith(AppSettings settings) {
      final c = ProviderContainer(overrides: [
        initialSettingsProvider.overrideWithValue(settings),
        deviceLocalesProvider.overrideWith((_) => [const Locale('en')]),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('resolves to the language the user reads', () {
      expect(
        containerWith(const AppSettings(language: AppLanguage.ru))
            .read(effectiveLanguageCodeProvider),
        'ru',
      );
      expect(
        containerWith(const AppSettings(language: AppLanguage.system))
            .read(effectiveLanguageCodeProvider),
        'en',
        reason: 'device is en and en is supported',
      );
    });

    test('is NOT rebuilt by an unrelated settings change', () async {
      // Regression guard for watching the whole AppSettings object: a theme tap
      // would rebuild the repository and force every derived FutureProvider to
      // re-read the bundled catalog.
      final c = containerWith(const AppSettings(language: AppLanguage.ru));
      final first = c.read(equipmentRepositoryProvider);
      await c
          .read(settingsControllerProvider.notifier)
          .setThemeMode(AppThemeMode.dark);
      await c
          .read(settingsControllerProvider.notifier)
          .setNotificationsEnabled(false);
      expect(c.read(equipmentRepositoryProvider), same(first));
    });

    test('IS rebuilt when the language changes', () async {
      final c = containerWith(const AppSettings(language: AppLanguage.ru));
      final first = c.read(equipmentRepositoryProvider);
      await c
          .read(settingsControllerProvider.notifier)
          .setLanguage(AppLanguage.en);
      final second = c.read(equipmentRepositoryProvider);
      expect(second, isNot(same(first)));
      expect((second as AssetEquipmentRepository).languageCode, 'en');
    });
  });
}
