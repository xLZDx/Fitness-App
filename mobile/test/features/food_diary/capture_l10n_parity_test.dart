// C24 capture_l10n_parity_test (I18N-05 for the capture story): the keys added
// by C24 (foodScan*, foodMeal*, foodBarcode*, foodLabel*, nutritionSources
// software keys) exist in BOTH ARB files, carry the same placeholders, and the
// Russian text is really translated (Cyrillic, not a copy of the English).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

final Map<String, dynamic> _en = _arb('en');
final Map<String, dynamic> _ru = _arb('ru');

Set<String> _keys(Map<String, dynamic> m) =>
    m.keys.where((k) => !k.startsWith('@')).toSet();

final RegExp _c24 = RegExp(
    r'^(foodScan|foodMeal|foodBarcode|foodLabel)\w*$|^nutritionSources(SoftwareTitle|Scanner|CalorieTracker|ReferenceOnly|FullList)$');

Set<String> _c24Keys() => _keys(_en).where(_c24.hasMatch).toSet();

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)').allMatches(s).map((m) => m.group(1)!).toSet();

bool _hasCyrillic(String s) => RegExp(r'[Ѐ-ӿ]').hasMatch(s);

void main() {
  test('the C24 key family is found (guard against a vacuous test)', () {
    final keys = _c24Keys();
    expect(keys.length, greaterThanOrEqualTo(45));
    for (final k in [
      'foodScanCancel',
      'foodMealScanTitle',
      'foodBarcodeInvalid',
      'foodLabelConfirm',
      'nutritionSourcesSoftwareTitle',
      'nutritionSourcesFullList',
    ]) {
      expect(keys, contains(k));
    }
  });

  test('every C24 key is in the Russian file', () {
    final missing = _c24Keys().difference(_keys(_ru));
    expect(missing, isEmpty, reason: 'missing in app_ru.arb: $missing');
  });

  test('no C24 key exists only in Russian', () {
    final ruOnly = _keys(_ru).where(_c24.hasMatch).toSet().difference(_keys(_en));
    expect(ruOnly, isEmpty);
  });

  test('every food* and nutritionSources* key has a Russian twin', () {
    bool family(String k) =>
        k.startsWith('food') || k.startsWith('nutritionSources');
    final missing = _keys(_en).where(family).toSet().difference(_keys(_ru));
    expect(missing, isEmpty, reason: 'missing in app_ru.arb: $missing');
  });

  test('values are non-empty strings in both languages', () {
    for (final k in _c24Keys()) {
      expect(_en[k], isA<String>(), reason: 'en $k');
      expect((_en[k] as String).trim(), isNotEmpty, reason: 'en $k');
      expect(_ru[k], isA<String>(), reason: 'ru $k');
      expect((_ru[k] as String).trim(), isNotEmpty, reason: 'ru $k');
    }
  });

  test('placeholders are identical between English and Russian', () {
    for (final k in _c24Keys()) {
      expect(_placeholders(_ru[k] as String), _placeholders(_en[k] as String),
          reason: k);
    }
  });

  test('placeholders are declared in @key metadata in both files', () {
    for (final k in _c24Keys()) {
      final ph = _placeholders(_en[k] as String);
      if (ph.isEmpty) continue;
      for (final arb in [_en, _ru]) {
        final meta = arb['@$k'] as Map<String, dynamic>?;
        expect(meta, isNotNull, reason: '@$k');
        final declared = ((meta!['placeholders'] ?? {}) as Map).keys.toSet();
        expect(declared, containsAll(ph), reason: '@$k');
      }
    }
  });

  test('the Russian text is translated: Cyrillic and not equal to English', () {
    // Technical tokens may legitimately stay Latin inside a Russian sentence,
    // but the sentence itself must contain Russian words.
    for (final k in _c24Keys()) {
      final ru = _ru[k] as String;
      expect(_hasCyrillic(ru), isTrue, reason: 'ru $k has no Cyrillic: $ru');
      expect(ru, isNot(_en[k]), reason: 'ru $k equals English');
    }
  });

  test('technical identifiers survive translation', () {
    const tokens = {
      'nutritionSourcesScanner': ['mobile_scanner', 'BSD-3-Clause'],
      'nutritionSourcesCalorieTracker': ['calorie-tracker', 'MIT'],
      'nutritionSourcesReferenceOnly': ['OpenNutriTracker', 'GPL-3.0', 'calorie-count'],
      'nutritionSourcesFullList': ['ATTRIBUTIONS_NUTRITION.md'],
    };
    for (final e in tokens.entries) {
      for (final t in e.value) {
        expect(_en[e.key] as String, contains(t), reason: 'en ${e.key}');
        expect(_ru[e.key] as String, contains(t), reason: 'ru ${e.key}');
      }
    }
  });

  test('C24 strings are plain sentences: no plural or select syntax', () {
    for (final k in _c24Keys()) {
      for (final arb in [_en, _ru]) {
        expect(arb[k] as String, isNot(contains('plural,')), reason: k);
        expect(arb[k] as String, isNot(contains('select,')), reason: k);
      }
    }
  });

  test('no raw server text or error codes in user-facing strings', () {
    for (final k in _c24Keys()) {
      for (final arb in [_en, _ru]) {
        final v = arb[k] as String;
        expect(v, isNot(contains('feature-disabled')), reason: k);
        expect(v, isNot(contains('Exception')), reason: k);
      }
    }
  });
}
