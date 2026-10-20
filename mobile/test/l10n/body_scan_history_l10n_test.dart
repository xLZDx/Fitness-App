// C16 l10n tests: EN/RU parity of the history, edit-weight, delete-photos,
// compare and privacy keys, placeholder parity, ICU plural forms (RU uses
// one/few/many/other) and the rendered plural output (I18N-11, D-85).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _c16Prefixes = RegExp(
    r'^bodyScan(Compare|History|EditWeight|DeletePhotos|Privacy|Retention)');

Map<String, dynamic> _load(String name) =>
    json.decode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String message) {
  // Names that appear as {name} or {name, plural|select ...} at any depth.
  return {
    for (final m in RegExp(r'\{(\w+)(?=\s*[,}])').allMatches(message))
      m.group(1)!,
  }..removeAll({'one', 'few', 'many', 'other', 'zero', 'two'});
}

bool _isPlural(String m) => RegExp(r'\{\w+,\s*plural,').hasMatch(m);

Set<String> _pluralForms(String m) => {
      for (final x in RegExp(r'\b(zero|one|two|few|many|other)\{').allMatches(m))
        x.group(1)!,
    };

void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ru;
  late List<String> keys;

  setUpAll(() {
    en = _load('app_en.arb');
    ru = _load('app_ru.arb');
    keys = [
      for (final k in en.keys)
        if (!k.startsWith('@') && _c16Prefixes.hasMatch(k)) k,
    ]..sort();
  });

  test('the C16 key set is non-trivial and contains the named keys', () {
    expect(keys.length, greaterThan(50));
    for (final k in [
      'bodyScanCompareBaselineOnly',
      'bodyScanCompareTakeSecond',
      'bodyScanHistoryTitle',
      'bodyScanHistoryCount',
      'bodyScanEditWeightTitle',
      'bodyScanDeletePhotosTitle',
      'bodyScanPrivacyTitle',
      'bodyScanRetentionDays',
      'bodyScanRetentionHonest',
    ]) {
      expect(keys, contains(k));
    }
  });

  test('every C16 EN key exists in RU, non-empty, and vice versa', () {
    final ruKeys = [
      for (final k in ru.keys)
        if (!k.startsWith('@') && _c16Prefixes.hasMatch(k)) k,
    ]..sort();
    expect(ruKeys, keys, reason: 'EN and RU C16 key sets must be identical');
    for (final k in keys) {
      expect((en[k] as String).trim(), isNotEmpty, reason: 'EN $k');
      expect((ru[k] as String).trim(), isNotEmpty, reason: 'RU $k');
    }
  });

  test('RU is translated, not a copy of EN (Cyrillic present)', () {
    final cyr = RegExp(r'[Ѐ-ӿ]');
    for (final k in keys) {
      expect(cyr.hasMatch(ru[k] as String), isTrue,
          reason: 'RU $k looks untranslated: ${ru[k]}');
    }
  });

  test('placeholders are identical between EN and RU for every key', () {
    for (final k in keys) {
      expect(_placeholders(ru[k] as String), _placeholders(en[k] as String),
          reason: k);
    }
  });

  test('keys with placeholders carry @metadata in EN and RU is not '
      'missing the same placeholders', () {
    for (final k in keys) {
      if (_placeholders(en[k] as String).isEmpty) continue;
      final meta = en['@$k'];
      expect(meta, isA<Map>(), reason: 'EN @$k');
      final ph = (meta as Map)['placeholders'] as Map?;
      expect(ph, isNotNull, reason: 'EN @$k placeholders');
      expect(ph!.keys.toSet(), _placeholders(en[k] as String), reason: k);
    }
  });

  test('plural messages: EN has one+other, RU has one/few/many/other', () {
    final plurals = keys.where((k) => _isPlural(en[k] as String)).toList();
    expect(plurals, containsAll(['bodyScanHistoryCount', 'bodyScanRetentionDays']));
    for (final k in plurals) {
      expect(_isPlural(ru[k] as String), isTrue, reason: 'RU $k must be plural');
      expect(_pluralForms(en[k] as String), containsAll(['one', 'other']),
          reason: 'EN $k');
      expect(_pluralForms(ru[k] as String),
          containsAll(['one', 'few', 'many', 'other']),
          reason: 'RU $k needs every Russian plural category');
    }
  });

  test('the 48-hour promise is in both languages wherever EN makes it', () {
    final with48 = keys.where((k) => (en[k] as String).contains('48')).toList();
    expect(with48, isNotEmpty);
    expect(with48, contains('bodyScanRetentionHonest'));
    for (final k in with48) {
      expect(ru[k] as String, contains('48'), reason: 'RU $k lost the bound');
    }
    expect(en['bodyScanRetentionHonest'], contains('within 48 hours'));
  });

  test('RU weight uses the non-inflecting unit "кг"', () {
    expect(ru['bodyScanHistoryWeight'], '{value} кг');
  });

  group('rendered plurals', () {
    Future<AppLocalizations> load(String code) =>
        AppLocalizations.delegate.load(Locale(code));

    test('RU scan count follows the Russian categories', () async {
      final l = await load('ru');
      final expected = {
        0: 'сканов',
        1: 'скан',
        2: 'скана',
        4: 'скана',
        5: 'сканов',
        11: 'сканов',
        12: 'сканов',
        14: 'сканов',
        21: 'скан',
        22: 'скана',
        25: 'сканов',
        101: 'скан',
      };
      expected.forEach((n, word) {
        expect(l.bodyScanHistoryCount(n), '$n $word', reason: 'n=$n');
      });
    });

    test('RU retention days follow the Russian categories', () async {
      final l = await load('ru');
      final expected = {
        1: 'день',
        2: 'дня',
        5: 'дней',
        11: 'дней',
        21: 'день',
        30: 'дней',
        90: 'дней',
        365: 'дней',
      };
      expected.forEach((n, word) {
        expect(l.bodyScanRetentionDays(n), '$n $word', reason: 'n=$n');
      });
    });

    test('EN counts use one/other', () async {
      final l = await load('en');
      expect(l.bodyScanHistoryCount(1), '1 scan');
      expect(l.bodyScanHistoryCount(2), '2 scans');
      expect(l.bodyScanHistoryCount(0), '0 scans');
      expect(l.bodyScanRetentionDays(1), '1 day');
      expect(l.bodyScanRetentionDays(365), '365 days');
    });

    test('value placeholders render in both languages', () async {
      final en = await load('en');
      final ru = await load('ru');
      expect(en.bodyScanHistoryBodyFat('20.5'), 'Body fat 20.5%');
      expect(en.bodyScanHistoryWeight('80.5'), '80.5 kg');
      expect(ru.bodyScanHistoryBodyFat('20,5'), contains('20,5'));
      expect(ru.bodyScanHistoryWeight('80,5'), '80,5 кг');
    });
  });
}
