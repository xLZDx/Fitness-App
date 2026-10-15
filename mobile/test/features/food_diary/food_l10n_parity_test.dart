// C23 food_l10n_parity_test (I18N-01, I18N-07, ux wording): the `food*` keys
// exist in EN and RU with the same placeholders, no empty value, no
// untranslated copy, the plural has the RU one/few/many/other forms (checked
// through the generated localizations), and neither language uses
// budget-game wording.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String f) =>
    jsonDecode(File('lib/l10n/$f').readAsStringSync()) as Map<String, dynamic>;

/// Values that are proper names or units written identically in both languages.
const _sameInBoth = <String>{
  'foodSourceOff', // "Open Food Facts"
  'foodSourceUsda', // "USDA FoodData Central"
  'foodCheckChipLabel', // "{title}, {state}": placeholders only
};

final _placeholder = RegExp(r'\{(\w+)\}');

/// Placeholder names of a message; the plural header `{count, plural, ...}`
/// contributes only `count` and the inner `{count}` tokens.
Set<String> _names(String v) {
  final out = <String>{};
  for (final m in RegExp(r'\{(\w+)(?:,|\})').allMatches(v)) {
    out.add(m.group(1)!);
  }
  return out;
}

void main() {
  final en = _load('app_en.arb');
  final ru = _load('app_ru.arb');
  bool isFood(String k) => k.startsWith('food') && !k.startsWith('@');
  final enKeys = en.keys.where(isFood).toSet();
  final ruKeys = ru.keys.where(isFood).toSet();

  test('the food keys are a real set (guards against an empty scan)', () {
    expect(enKeys.length, greaterThan(150));
    for (final prefix in [
      'foodDiary', 'foodMacro', 'foodUnit', 'foodSource', 'foodAdd',
      'foodDescribe', 'foodQuick', 'foodSearch', 'foodDetail', 'foodCheck',
      'foodOil',
    ]) {
      expect(enKeys.any((k) => k.startsWith(prefix)), isTrue, reason: prefix);
    }
  });

  test('EN and RU have exactly the same food keys', () {
    expect(enKeys.difference(ruKeys), isEmpty, reason: 'missing in RU');
    expect(ruKeys.difference(enKeys), isEmpty, reason: 'missing in EN');
  });

  test('no empty value in either language', () {
    for (final k in enKeys) {
      expect((en[k] as String).trim(), isNotEmpty, reason: 'en $k');
      expect((ru[k] as String).trim(), isNotEmpty, reason: 'ru $k');
    }
  });

  test('placeholders match between EN and RU for every key', () {
    for (final k in enKeys) {
      expect(_names(ru[k] as String), _names(en[k] as String), reason: k);
    }
  });

  test('every placeholder is declared in the EN @metadata with a type', () {
    for (final k in enKeys) {
      final names = _names(en[k] as String);
      if (names.isEmpty) continue;
      final meta = en['@$k'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: '@$k missing');
      final ph = (meta!['placeholders'] as Map<String, dynamic>?) ?? {};
      for (final n in names) {
        expect(ph.containsKey(n), isTrue, reason: '$k placeholder $n');
      }
    }
  });

  test('RU is translated: Cyrillic, and not equal to EN, except names', () {
    final same = <String>[];
    for (final k in enKeys) {
      final r = ru[k] as String;
      if (r == en[k]) same.add(k);
    }
    expect(same.toSet().difference(_sameInBoth), isEmpty,
        reason: 'untranslated RU copy');
    final cyr = RegExp(r'[\u0400-\u04FF]');
    for (final k in enKeys) {
      if (_sameInBoth.contains(k)) continue;
      expect(cyr.hasMatch(ru[k] as String), isTrue, reason: 'ru $k has no Cyrillic');
    }
  });

  test('no budget-game wording in food copy (EN or RU)', () {
    final bad = RegExp(
        r'budget|cheat|points|score|burn|earn|бюджет|чит[- ]?мил|баллы|очки|заработ|сжеч',
        caseSensitive: false);
    for (final k in enKeys) {
      expect(bad.hasMatch(en[k] as String), isFalse, reason: 'en $k');
      expect(bad.hasMatch(ru[k] as String), isFalse, reason: 'ru $k');
    }
  });

  group('plural foodCheckCount', () {
    test('the ARB message carries the CLDR forms for each language', () {
      final e = en['foodCheckCount'] as String;
      final r = ru['foodCheckCount'] as String;
      for (final f in ['one{', 'other{']) {
        expect(e, contains(f));
      }
      for (final f in ['one{', 'few{', 'many{', 'other{']) {
        expect(r, contains(f), reason: 'RU must have $f');
      }
    });

    String word(AppLocalizations l, int n) =>
        l.foodCheckCount(n).replaceAll('$n', '').trim();

    test('RU forms follow 1 / 2-4 / 5-20 / 21 / 22-24 / 25', () {
      final l = lookupAppLocalizations(const Locale('ru'));
      final one = word(l, 1);
      final few = word(l, 2);
      final many = word(l, 5);
      expect({one, few, many}.length, 3, reason: 'three distinct RU forms');
      for (final n in [21, 31]) {
        expect(word(l, n), one, reason: '$n');
      }
      for (final n in [3, 4, 22, 23, 24]) {
        expect(word(l, n), few, reason: '$n');
      }
      for (final n in [0, 6, 8, 11, 12, 13, 14, 20, 25]) {
        expect(word(l, n), many, reason: '$n');
      }
      expect(l.foodCheckCount(2), startsWith('2 '));
    });

    test('EN forms: 1 singular, everything else plural', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.foodCheckCount(1), '1 item to check');
      expect(l.foodCheckCount(2), '2 items to check');
      expect(l.foodCheckCount(0), '0 items to check');
    });
  });

  test('the closed check codes each have a title and a help line in both '
      'languages', () {
    const codes = [
      'PortionUnclear', 'HiddenIngredients', 'LiquidUnknown', 'CookingMethod',
      'MultipleItems', 'BrandUnknown', 'FoodNotMatched', 'LowConfidenceItem',
      'LabelAmbiguous', 'DataInconsistent', 'ScaleMissing',
    ];
    for (final c in codes) {
      for (final k in ['foodCheck$c', 'foodCheckHelp$c']) {
        expect(en.containsKey(k), isTrue, reason: 'en $k');
        expect(ru.containsKey(k), isTrue, reason: 'ru $k');
      }
    }
  });

  test('units are non-inflecting: the value placeholder is inside the unit '
      'string', () {
    for (final k in ['foodUnitKcal', 'foodUnitGrams']) {
      expect(_placeholder.hasMatch(en[k] as String), isTrue);
      expect(_placeholder.hasMatch(ru[k] as String), isTrue);
      expect((ru[k] as String), isNot(contains('plural')),
          reason: '$k must not inflect (decimals would need a plural form)');
    }
  });
}
