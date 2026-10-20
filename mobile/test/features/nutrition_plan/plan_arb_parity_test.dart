// I18N-05 / I18N-07 for the C19 plan keys: EN/RU key parity, placeholder
// parity, ICU shape, one key per review reason, and the RU plural forms
// (one / few / many) resolved through the REAL generated localisations.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefixes = ['nutrition', 'reviewReason', 'planTone', 'weightLog'];

bool _isPlanKey(String k) =>
    !k.startsWith('@') && _prefixes.any((p) => k.startsWith(p));

Map<String, dynamic> _load(String name) => json.decode(
    File('lib/l10n/$name').readAsStringSync(encoding: utf8)) as Map<String, dynamic>;

Set<String> _placeholders(String message) =>
    RegExp(r'\{(\w+)\}').allMatches(message).map((m) => m.group(1)!).toSet()
      ..removeAll(
          {'plural', 'select', 'one', 'few', 'many', 'other', 'down', 'zero'});

void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ru;
  late List<String> keys;

  setUpAll(() {
    en = _load('app_en.arb');
    ru = _load('app_ru.arb');
    keys = en.keys.where(_isPlanKey).toList();
  });

  test('the plan key set is large enough to be the C19 set', () {
    // 143 keys were added by C19; later work may only add.
    expect(keys.length, greaterThanOrEqualTo(143));
  });

  test('every EN plan key exists in RU, non-empty, and vice versa', () {
    final ruKeys = ru.keys.where(_isPlanKey).toSet();
    expect(keys.toSet().difference(ruKeys), isEmpty,
        reason: 'missing in RU');
    expect(ruKeys.difference(keys.toSet()), isEmpty, reason: 'missing in EN');
    for (final k in keys) {
      expect((en[k] as String).trim(), isNotEmpty, reason: 'en $k');
      expect((ru[k] as String).trim(), isNotEmpty, reason: 'ru $k');
    }
  });

  test('RU values are translated (contain Cyrillic) and EN are not Cyrillic',
      () {
    final cyr = RegExp(r'[А-Яа-яЁё]');
    for (final k in keys) {
      expect(cyr.hasMatch(ru[k] as String), isTrue, reason: 'ru $k');
      expect(cyr.hasMatch(en[k] as String), isFalse, reason: 'en $k');
    }
  });

  test('both locales use exactly the same placeholders per key', () {
    for (final k in keys) {
      expect(_placeholders(ru[k] as String), _placeholders(en[k] as String),
          reason: k);
    }
  });

  test('every placeholder used by a message is declared in @key (EN)', () {
    for (final k in keys) {
      final used = _placeholders(en[k] as String);
      if (used.isEmpty) continue;
      final meta = en['@$k'];
      expect(meta, isA<Map>(), reason: '@$k missing');
      final declared = ((meta as Map)['placeholders'] as Map?)?.keys.toSet();
      expect(declared, isNotNull, reason: '@$k has no placeholders');
      expect(declared!.containsAll(used), isTrue, reason: k);
    }
  });

  test('no ICU "#" shorthand: gen-l10n would render it literally', () {
    for (final k in keys) {
      expect((en[k] as String).contains('#'), isFalse, reason: 'en $k');
      expect((ru[k] as String).contains('#'), isFalse, reason: 'ru $k');
    }
  });

  test('plural keys carry the right category set per language', () {
    for (final k in ['nutritionStepsValue', 'nutritionReviewBasis']) {
      final e = en[k] as String;
      final r = ru[k] as String;
      expect(e, contains('plural'));
      for (final c in ['one{', 'other{']) {
        expect(e, contains(c), reason: 'en $k $c');
      }
      for (final c in ['one{', 'few{', 'many{', 'other{']) {
        expect(r, contains(c), reason: 'ru $k $c');
      }
    }
  });

  test('select keys keep both branches in both languages', () {
    for (final k in [
      'nutritionReviewKcalApplied',
      'nutritionReviewKcalProposed',
      'nutritionReviewKcalInsight',
    ]) {
      for (final m in [en, ru]) {
        expect(m[k] as String, contains('down{'), reason: k);
        expect(m[k] as String, contains('other{'), reason: k);
      }
    }
  });

  test('every ReviewReason has its own reviewReason key in both languages',
      () {
    final seenEn = <String>{};
    for (final r in ReviewReason.values) {
      final key = 'reviewReason${r.name[0].toUpperCase()}${r.name.substring(1)}';
      expect(en.containsKey(key), isTrue, reason: 'en $key');
      expect(ru.containsKey(key), isTrue, reason: 'ru $key');
      expect(seenEn.add(en[key] as String), isTrue,
          reason: 'duplicate EN text for $key');
    }
    expect(ReviewReason.values.length, 14);
  });

  test('no promise or ETA wording in any EN plan text', () {
    for (final k in keys) {
      final v = (en[k] as String).toLowerCase();
      for (final w in ['guarantee', 'you will reach', 'will lose', 'eta:']) {
        expect(v.contains(w), isFalse, reason: '$k: $w');
      }
    }
  });

  group('RU plural forms through the generated localisations', () {
    final ruL = lookupAppLocalizations(const Locale('ru'));
    final enL = lookupAppLocalizations(const Locale('en'));

    test('steps value: one / few / many', () {
      const expected = {
        0: 'шагов',
        1: 'шаг',
        2: 'шага',
        3: 'шага',
        4: 'шага',
        5: 'шагов',
        11: 'шагов',
        12: 'шагов',
        14: 'шагов',
        21: 'шаг',
        22: 'шага',
        25: 'шагов',
        101: 'шаг',
        111: 'шагов',
      };
      for (final e in expected.entries) {
        expect(ruL.nutritionStepsValue(e.key), '${e.key} ${e.value}',
            reason: '${e.key}');
      }
    });

    test('weigh-in basis: forms follow the ARB wording', () {
      expect(ruL.nutritionReviewBasis(1), 'На основе 1 записи веса');
      expect(ruL.nutritionReviewBasis(2), 'На основе 2 записей веса');
      expect(ruL.nutritionReviewBasis(5), 'На основе 5 записей веса');
      expect(ruL.nutritionReviewBasis(21), 'На основе 21 записи веса');
      expect(ruL.nutritionReviewBasis(11), 'На основе 11 записей веса');
    });

    test('EN plural: 1 singular, else plural, number substituted', () {
      expect(enL.nutritionStepsValue(1), '1 step');
      expect(enL.nutritionStepsValue(0), '0 steps');
      expect(enL.nutritionStepsValue(8500), '8500 steps');
      expect(enL.nutritionReviewBasis(1), 'Based on 1 weigh-in');
      expect(enL.nutritionReviewBasis(3), 'Based on 3 weigh-ins');
    });

    test('decimal units do not inflect (kg, kcal)', () {
      expect(ruL.weightLogValue('79,5'), '79,5 кг');
      expect(ruL.nutritionKcalRangeValue('2 000', '2 200'), '2 000–2 200 ккал');
      expect(ruL.nutritionReviewTrend('-0,1'), 'Динамика веса: -0,1 кг/нед.');
    });
  });
}
