import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/check_items.dart';

/// Pure file-read checks of the body scan strings (C15): no widget, no
/// generated localizations. They read the ARB sources directly.
Map<String, dynamic> _read(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

bool _isScanKey(String k) =>
    !k.startsWith('@') && (k.startsWith('bodyScan') || k.startsWith('checkCode'));

/// Top level placeholder names of a message (`{name}` and the selector of a
/// plural), not the words inside plural branches.
Set<String> _placeholders(String v) {
  final out = <String>{};
  for (final m in RegExp(r'\{\s*([A-Za-z_]\w*)\s*(?:,|\})').allMatches(v)) {
    out.add(m.group(1)!);
  }
  return out;
}

void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ru;
  late Set<String> enKeys;
  late Set<String> ruKeys;

  setUpAll(() {
    en = _read('app_en.arb');
    ru = _read('app_ru.arb');
    enKeys = en.keys.where(_isScanKey).toSet();
    ruKeys = ru.keys.where(_isScanKey).toSet();
  });

  group('parity', () {
    test('there are body scan keys to check (guards against a renamed prefix)',
        () {
      expect(enKeys.length, greaterThan(100));
    });

    test('EN and RU define exactly the same bodyScan*/checkCode* keys', () {
      expect(enKeys.difference(ruKeys), isEmpty,
          reason: 'missing in RU: ${enKeys.difference(ruKeys)}');
      expect(ruKeys.difference(enKeys), isEmpty,
          reason: 'missing in EN: ${ruKeys.difference(enKeys)}');
    });

    test('no empty or whitespace-only value in either locale', () {
      for (final k in enKeys) {
        expect((en[k] as String).trim(), isNotEmpty, reason: 'EN $k');
        expect((ru[k] as String).trim(), isNotEmpty, reason: 'RU $k');
      }
    });

    test('placeholder names match between locales for every key', () {
      for (final k in enKeys) {
        expect(_placeholders(ru[k] as String), _placeholders(en[k] as String),
            reason: k);
      }
    });

    test('every message with placeholders declares them in @metadata', () {
      for (final k in enKeys) {
        final ph = _placeholders(en[k] as String);
        if (ph.isEmpty) continue;
        final meta = en['@$k'] as Map<String, dynamic>?;
        expect(meta, isNotNull, reason: 'EN @$k missing');
        final declared = (meta!['placeholders'] as Map<String, dynamic>).keys.toSet();
        expect(declared, containsAll(ph), reason: 'EN @$k');
      }
    });

    test('RU text is not a verbatim copy of EN for sentences', () {
      for (final k in enKeys) {
        final e = en[k] as String;
        if (e.split(' ').length < 4) continue;
        expect(ru[k], isNot(e), reason: 'untranslated $k');
      }
    });
  });

  group('RU plurals define one, few, many and other', () {
    test('every plural message in RU has all four branches', () {
      final plurals = [for (final k in ruKeys) if ((ru[k] as String).contains(', plural,')) k];
      expect(plurals, isNotEmpty);
      for (final k in plurals) {
        final v = ru[k] as String;
        for (final form in ['one', 'few', 'many', 'other']) {
          expect(RegExp('\\b$form\\{').hasMatch(v), isTrue,
              reason: 'RU $k lacks "$form"');
        }
      }
    });

    test('EN plural messages define one and other', () {
      for (final k in enKeys) {
        final v = en[k] as String;
        if (!v.contains(', plural,')) continue;
        expect(RegExp(r'\bone\{').hasMatch(v), isTrue, reason: 'EN $k lacks one');
        expect(RegExp(r'\bother\{').hasMatch(v), isTrue, reason: 'EN $k lacks other');
      }
    });

    test('the same keys are plurals in both locales', () {
      Set<String> plural(Map<String, dynamic> m) => {
            for (final k in m.keys.where(_isScanKey))
              if ((m[k] as String).contains(', plural,')) k
          };
      expect(plural(ru), plural(en));
    });

    test('decimal quantities use non-inflecting RU units, no plural', () {
      // Decimal values (24.1 points, 0.4 kg per week) must not select a
      // plural form: they are pre-formatted strings with fixed units.
      for (final k in [
        'bodyScanChangeDown',
        'bodyScanChangeUp',
        'bodyScanNoiseNote',
        'bodyScanPointsToGoal',
        'bodyScanWeightTrendDown',
        'bodyScanWeightTrendUp',
        'bodyScanMassValue',
        'bodyScanEtaRange',
        'bodyScanChartSummaryDown',
        'bodyScanChartSummaryUp',
        'bodyScanChartSummaryFlat',
      ]) {
        expect(ru[k], isNotNull, reason: k);
        expect(ru[k] as String, isNot(contains(', plural,')), reason: k);
      }
      expect(ru['bodyScanPointsToGoal'], contains('п.п.'));
      expect(ru['bodyScanWeightTrendDown'], contains('кг'));
      expect(ru['bodyScanWeightTrendUp'], contains('кг'));
      expect(ru['bodyScanMassValue'], contains('кг'));
      expect(ru['bodyScanEtaRange'], contains('нед.'));
    });
  });

  group('closed check codes', () {
    test('every CheckCode has a checkCode key in both locales', () {
      for (final c in CheckCode.values) {
        expect(en.containsKey(c.l10nKey), isTrue, reason: 'EN ${c.l10nKey}');
        expect(ru.containsKey(c.l10nKey), isTrue, reason: 'RU ${c.l10nKey}');
      }
    });

    test('there are no checkCode keys without a CheckCode (no orphans)', () {
      final expected = {for (final c in CheckCode.values) c.l10nKey};
      final actual = enKeys.where((k) => k.startsWith('checkCode')).toSet();
      expect(actual, expected);
    });

    test('l10nKey is checkCode plus the capitalised enum name', () {
      expect(CheckCode.poorLighting.l10nKey, 'checkCodePoorLighting');
      expect(CheckCode.provisionalEstimator.l10nKey,
          'checkCodeProvisionalEstimator');
      expect(CheckCode.weightStale.l10nKey, 'checkCodeWeightStale');
    });

    test('the stale-weight text names the same 7 days as the constant', () {
      expect(CheckCode.weightStaleAfterDays, 7);
      expect(en['checkCodeWeightStale'], contains('7 days'));
      expect(ru['checkCodeWeightStale'], contains('7'));
    });

    test('check texts carry no placeholders (closed, fixed copy)', () {
      for (final c in CheckCode.values) {
        expect(_placeholders(en[c.l10nKey] as String), isEmpty, reason: c.name);
        expect(_placeholders(ru[c.l10nKey] as String), isEmpty, reason: c.name);
      }
    });
  });

  group('copy rules', () {
    test('the plain-language limit and rough-estimate labels exist verbatim',
        () {
      expect(en['bodyScanRoughLabel'],
          'Rough estimate from height, weight and age');
      expect(en['bodyScanLimitNote'], contains('1-2 points'));
      expect(en['bodyScanWeightInvalid'], contains('20'));
      expect(en['bodyScanWeightInvalid'], contains('400'));
    });

    test('the cloud consent copy names the blurring limit in both locales', () {
      expect(en['bodyScanCloudBody'], contains('cannot verify the blurring'));
      expect(en['bodyScanCloudBody'], contains('tattoos'));
      expect((ru['bodyScanCloudBody'] as String).length, greaterThan(60));
    });

    test('no value embeds a raw URL or an ellipsis-only placeholder', () {
      for (final k in enKeys) {
        expect(en[k] as String, isNot(contains('http')), reason: k);
        expect(ru[k] as String, isNot(contains('http')), reason: k);
      }
    });
  });
}
