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
    base = (jsonDecode(await rootBundle.loadString('assets/data/exercises.json'))
            as List)
        .cast<Map<String, dynamic>>();
    ru = (jsonDecode(
            await rootBundle.loadString('assets/data/exercises.ru.json'))
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

    test('leaves no English words behind', () {
      // Catches a half-finished entry, which the Cyrillic check above would
      // pass as long as one word got translated.
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
      expect(leftovers, isEmpty);
    });
  });

  group('English base invariants the overlay format relies on', () {
    test('summary is always the first step', () {
      // The overlay stores only `title` + `steps` and derives the summary from
      // step one. If a catalog rebuild ever breaks this, the Russian summary
      // would silently diverge from the English one — so it fails here instead.
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

    test('the known blank step is filtered out of the parsed model', () {
      final raw = base.firstWhere(
          (e) => e['id'] == 'barbell_squat_to_a_bench')['steps'] as List;
      expect(raw.where((s) => (s as String).trim().isEmpty), isNotEmpty,
          reason: 'upstream data still has the blank step this guards');
      expect(ExerciseItem.parseSteps(raw).any((s) => s.trim().isEmpty), isFalse);
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
    ExerciseItem sample() => const ExerciseItem(
          id: 'squat',
          title: 'Barbell Squat',
          equipmentId: 'squat_rack',
          muscles: ['quads', 'glutes'],
          difficulty: ExerciseDifficulty.intermediate,
          durationMinutes: 12,
          summary: 'Step one.',
          steps: ['Step one.', 'Step two.'],
          frames: ['assets/exercises/squat_0.jpg'],
          primaryMuscles: ['quads'],
          contraindications: ['knee'],
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
        <String, Object>{'title': 'Ок', 'steps': <String>[]},
        <String, Object>{'title': 'Ок', 'steps': ['', '   ']},
        <String, Object>{'steps': ['Шаг.']},
      ]) {
        final out =
            AssetEquipmentRepository.applyTranslations([sample()], {'squat': bad});
        expect(out.single.title, 'Barbell Squat', reason: 'for $bad');
        expect(out.single.steps, ['Step one.', 'Step two.'], reason: 'for $bad');
      }
    });

    test('an empty overlay is a pass-through', () {
      final out = AssetEquipmentRepository.applyTranslations([sample()], {});
      expect(out.single.title, 'Barbell Squat');
    });
  });

  group('repository reads the bundled catalog in the requested language', () {
    test('English by default', () async {
      final repo = AssetEquipmentRepository();
      final all = await repo.exercisesFor('leg_press');
      expect(all.map((e) => e.title), contains('Leg Press'));
    });

    test('Russian when asked', () async {
      final repo = AssetEquipmentRepository(languageCode: 'ru');
      final all = await repo.exercisesFor('leg_press');
      expect(all.map((e) => e.title), contains('Жим ногами'));
      final legPress = all.firstWhere((e) => e.id == 'leg_press');
      expect(legPress.summary, legPress.steps.first);
      expect(legPress.primaryMuscles, contains('quads'),
          reason: 'translation must not disturb muscle tags');
    });

    test('falls back to English for a language with no overlay', () async {
      final repo = AssetEquipmentRepository(languageCode: 'de');
      final all = await repo.exercisesFor('leg_press');
      expect(all.map((e) => e.title), contains('Leg Press'));
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
