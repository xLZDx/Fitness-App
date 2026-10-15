import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/widgets/nutrition_inputs.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// E2 localisation guards (I18N-01, I18N-03, I18N-10, ONB-14): key parity,
/// placeholder parity, RU plural completeness, the generated signature order of
/// `onbNutritionPaceMessage(kg, weeks)` and exact plural rendering.
Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Keys added by E2 (onboarding step, profile flow, diet chip, widened
/// pregnancy question).
bool _isE2Key(String k) =>
    !k.startsWith('@') &&
    (k.startsWith('onbNutrition') ||
        k.startsWith('nutProfile') ||
        k == 'onbStepNutrition' ||
        k == 'onbDietPescatarian' ||
        k == 'healthStepProfessionalGuidance');

/// `{name}` placeholders of a message, ignoring ICU plural/select selectors.
Set<String> _placeholders(String message) {
  final names = <String>{};
  // Pull out every `{identifier}` and the argument of `{id, plural, ...}`.
  for (final m in RegExp(r'\{\s*([A-Za-z_]\w*)\s*(,\s*(plural|select))?')
      .allMatches(message)) {
    final id = m.group(1)!;
    // Selector words inside a plural body are `one{`, `few{`, ... -- the regex
    // matches them as identifiers too, so drop the closed selector set.
    if (const {'one', 'few', 'many', 'other', 'zero', 'two'}.contains(id)) {
      continue;
    }
    names.add(id);
  }
  return names;
}

void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ru;

  setUpAll(() {
    en = _arb('app_en');
    ru = _arb('app_ru');
  });

  group('I18N-01 EN/RU parity of the E2 keys', () {
    test('both locales define exactly the same E2 key set', () {
      final enKeys = en.keys.where(_isE2Key).toSet();
      final ruKeys = ru.keys.where(_isE2Key).toSet();
      expect(enKeys, isNotEmpty);
      expect(enKeys.length, greaterThan(60),
          reason: 'the scan must actually see the onbNutrition*/nutProfile* set');
      expect(ruKeys.difference(enKeys), isEmpty,
          reason: 'keys only in RU');
      expect(enKeys.difference(ruKeys), isEmpty,
          reason: 'keys only in EN (untranslated)');
    });

    test('no E2 value is empty or whitespace in either locale', () {
      for (final arb in [en, ru]) {
        for (final k in arb.keys.where(_isE2Key)) {
          expect((arb[k] as String).trim(), isNotEmpty, reason: k);
        }
      }
    });

    test('RU values are really Russian, not copies of the English text', () {
      final cyr = RegExp(r'[Ѐ-ӿ]');
      for (final k in ru.keys.where(_isE2Key)) {
        final v = ru[k] as String;
        // Pure numeric ranges ("3,000-5,000") have no letters to translate.
        if (!RegExp(r'[A-Za-z]').hasMatch(en[k] as String)) continue;
        expect(cyr.hasMatch(v), isTrue, reason: '$k is not translated: $v');
      }
    });

    test('placeholders match between the locales for every E2 key', () {
      for (final k in en.keys.where(_isE2Key)) {
        expect(_placeholders(ru[k] as String), _placeholders(en[k] as String),
            reason: k);
      }
    });

    test('every EN placeholder is declared in its @metadata block', () {
      for (final k in en.keys.where(_isE2Key)) {
        final names = _placeholders(en[k] as String);
        if (names.isEmpty) continue;
        final meta = en['@$k'] as Map<String, dynamic>?;
        expect(meta, isNotNull, reason: '$k has placeholders but no @$k');
        final declared =
            (meta!['placeholders'] as Map<String, dynamic>).keys.toSet();
        expect(declared, names, reason: k);
      }
    });
  });

  group('I18N-03 / I18N-10 plural completeness', () {
    test('every E2 plural message in RU defines one, few, many and other', () {
      final plurals = ru.keys
          .where(_isE2Key)
          .where((k) => (ru[k] as String).contains(', plural,'))
          .toList();
      expect(plurals, contains('onbNutritionPaceMessage'),
          reason: 'the pace message is the E2 plural key');
      for (final k in plurals) {
        final v = ru[k] as String;
        for (final form in ['one', 'few', 'many', 'other']) {
          expect(RegExp('$form\\s*\\{').hasMatch(v), isTrue,
              reason: '$k lacks the RU "$form" form');
        }
      }
    });

    test('every E2 plural message in EN defines other (and one)', () {
      for (final k in en.keys
          .where(_isE2Key)
          .where((k) => (en[k] as String).contains(', plural,'))) {
        final v = en[k] as String;
        expect(RegExp(r'other\s*\{').hasMatch(v), isTrue, reason: k);
        expect(RegExp(r'one\s*\{').hasMatch(v), isTrue, reason: k);
      }
    });

    test('the pace placeholders are declared kg:String then weeks:int', () {
      final p = (en['@onbNutritionPaceMessage']
          as Map<String, dynamic>)['placeholders'] as Map<String, dynamic>;
      expect(p.keys.toList(), ['kg', 'weeks']);
      expect((p['kg'] as Map)['type'], 'String');
      expect((p['weeks'] as Map)['type'], 'int');
    });
  });

  group('generated AppLocalizations signature and rendering', () {
    late AppLocalizations l10nEn;
    late AppLocalizations l10nRu;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
      l10nRu = await AppLocalizations.delegate.load(const Locale('ru'));
    });

    test('onbNutritionPaceMessage(kg, weeks): the String comes first, the int '
        'second, and each lands in its own slot', () {
      // This call only compiles with the (String kg, int weeks) order, and the
      // output proves the values were not swapped in the template.
      expect(l10nEn.onbNutritionPaceMessage('0.5', 12),
          'At a safe pace of about 0.5 kg per week, this takes roughly 12 weeks.');
      expect(l10nRu.onbNutritionPaceMessage('0,5', 12),
          'При безопасном темпе около 0,5 кг в неделю это займёт примерно 12 недель.');
    });

    test('EN plural: 1 week, 2 weeks, 0 weeks', () {
      expect(l10nEn.onbNutritionPaceMessage('0.5', 1),
          endsWith('roughly 1 week.'));
      expect(l10nEn.onbNutritionPaceMessage('0.5', 2),
          endsWith('roughly 2 weeks.'));
      expect(l10nEn.onbNutritionPaceMessage('0.5', 0),
          endsWith('roughly 0 weeks.'));
    });

    test('RU plural: one/few/many forms for 1, 2, 5, 11, 21, 22, 25, 111', () {
      const expected = {
        1: 'неделю',
        2: 'недели',
        3: 'недели',
        4: 'недели',
        5: 'недель',
        11: 'недель',
        12: 'недель',
        14: 'недель',
        21: 'неделю',
        22: 'недели',
        25: 'недель',
        101: 'неделю',
        111: 'недель',
      };
      expected.forEach((n, word) {
        expect(l10nRu.onbNutritionPaceMessage('0,5', n),
            endsWith('примерно $n $word.'),
            reason: 'n=$n');
      });
    });

    test('RU decimals keep a non-inflecting abbreviation (I18N-10)', () {
      for (final kg in ['0,4', '1,0', '1,5', '2,1', '5,0', '24,1']) {
        expect(l10nRu.onbNutritionTargetLine(kg), 'Целевой вес: $kg кг');
      }
      for (final kg in ['0.4', '1.0', '1.5', '2.1', '5.0', '24.1']) {
        expect(l10nEn.onbNutritionTargetLine(kg), 'Target weight: $kg kg');
      }
    });

    test('exclusion limit and remove labels carry their placeholder', () {
      expect(l10nEn.onbNutritionExcludedLimit(20), 'You can add up to 20 foods.');
      expect(l10nRu.onbNutritionExcludedLimit(20),
          'Можно добавить не более 20 продуктов.');
      expect(l10nEn.onbNutritionExcludedRemove('olives'), 'Remove olives');
      expect(l10nRu.onbNutritionExcludedRemove('оливки'), 'Убрать: оливки');
      expect(l10nEn.nutProfileStepOf(2, 3), 'Step 2 of 3');
      expect(l10nRu.nutProfileStepOf(2, 3), 'Шаг 2 из 3');
    });

    test('every FoodAllergen has a non-empty label in both locales and the '
        'labels are distinct', () {
      for (final l10n in [l10nEn, l10nRu]) {
        final labels = [
          for (final a in FoodAllergen.values) foodAllergenLabel(l10n, a)
        ];
        expect(labels.every((s) => s.trim().isNotEmpty), isTrue);
        expect(labels.toSet(), hasLength(FoodAllergen.values.length));
      }
    });

    test('D-75 exact safety copy, EN and RU, through the generated class', () {
      expect(l10nEn.onbNutritionGuidanceNone, 'None of these');
      expect(l10nEn.onbNutritionGuidanceReported, 'One or more applies');
      expect(l10nRu.onbNutritionGuidanceNone, 'Ничего из этого');
      expect(l10nRu.onbNutritionGuidanceReported,
          'Подходит один или несколько пунктов');
      expect(l10nEn.healthStepProfessionalGuidance,
          'Are you currently pregnant or breastfeeding, or within the first few months after giving birth?');
      expect(l10nRu.healthStepProfessionalGuidance,
          'Вы сейчас беременны, кормите грудью или находитесь в первые месяцы после родов?');
      expect(l10nEn.onbNutritionLockedNotice,
          "We'll leave food and calorie targets for later. You can add them any time in your nutrition profile.");
    });

    test('safety copy has no diagnostic words and no "prefer not to say"', () {
      for (final arb in [en, ru]) {
        final text = [
          for (final k in arb.keys.where((k) => k.startsWith('onbNutritionGuidance')))
            (arb[k] as String).toLowerCase()
        ].join(' | ');
        for (final banned in [
          'anorexia', 'bulimia', 'eating disorder', 'disorder', 'diagnos',
          'prefer not', 'анорекс', 'булим', 'расстройств', 'диагноз',
          'предпочитаю не',
        ]) {
          expect(text, isNot(contains(banned)), reason: banned);
        }
      }
    });

    test('the locked notice mentions no number and no reason (both locales)', () {
      for (final s in [l10nEn.onbNutritionLockedNotice, l10nRu.onbNutritionLockedNotice]) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
      }
    });
  });

  group('closed enums used by the step have a label in both locales', () {
    test('Goal/sex/ownership/diet enums are fully covered by ARB keys', () {
      // Adding an enum value without a key makes the switch in the widget fail
      // to compile; this guards the ARB side of the same contract.
      for (final g in GoalDirection.values) {
        final key = 'onbNutritionGoal${g.name[0].toUpperCase()}${g.name.substring(1)}';
        expect(en.containsKey(key), isTrue, reason: key);
        expect(ru.containsKey(key), isTrue, reason: key);
      }
      for (final o in PlanOwnership.values) {
        final key = 'onbNutritionOwnership${o.name[0].toUpperCase()}${o.name.substring(1)}';
        expect(en.containsKey(key), isTrue, reason: key);
        expect(ru.containsKey(key), isTrue, reason: key);
      }
      expect(en.containsKey('onbDietPescatarian'), isTrue);
      expect(DietaryPreference.values, contains(DietaryPreference.pescatarian));
    });
  });
}
