// T123 / I18N-03 / I18N-10 (C26, D-84, Y-F10): RU and EN plural forms for the
// new count strings, and the decimal rule (integers use ICU plurals, decimals
// use locale-formatted numbers with non-inflecting abbreviations).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

typedef _Call = String Function(AppLocalizations l, int n);

/// Russian cardinal category of a whole number.
String _ruForm(int n) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'few';
  return 'many';
}

class _Plural {
  const _Plural(this.key, this.call, this.ruFmt, this.ruWords, this.enFmt,
      this.enWords);
  final String key;
  final _Call call;

  /// Full expected RU string for a number and the word form.
  final String Function(int n, String word) ruFmt;

  /// RU words keyed by form (one / few / many).
  final Map<String, String> ruWords;
  final String Function(int n, String word) enFmt;

  /// EN words: one, other.
  final Map<String, String> enWords;
}

final _plurals = <_Plural>[
  _Plural(
    'bodyScanHistoryCount',
    (l, n) => l.bodyScanHistoryCount(n),
    (n, w) => '$n $w',
    const {'one': 'скан', 'few': 'скана', 'many': 'сканов'},
    (n, w) => '$n $w',
    const {'one': 'scan', 'other': 'scans'},
  ),
  _Plural(
    'bodyScanRetentionDays',
    (l, n) => l.bodyScanRetentionDays(n),
    (n, w) => '$n $w',
    const {'one': 'день', 'few': 'дня', 'many': 'дней'},
    (n, w) => '$n $w',
    const {'one': 'day', 'other': 'days'},
  ),
  _Plural(
    'nutritionStepsValue',
    (l, n) => l.nutritionStepsValue(n),
    (n, w) => '$n $w',
    const {'one': 'шаг', 'few': 'шага', 'many': 'шагов'},
    (n, w) => '$n $w',
    const {'one': 'step', 'other': 'steps'},
  ),
  _Plural(
    'bodyScanChecksCount',
    (l, n) => l.bodyScanChecksCount(n),
    (n, w) => '$n $w для проверки',
    const {'one': 'пункт', 'few': 'пункта', 'many': 'пунктов'},
    (n, w) => '$n $w to check',
    const {'one': 'item', 'other': 'items'},
  ),
  _Plural(
    'foodCheckCount',
    (l, n) => l.foodCheckCount(n),
    (n, w) => '$n $w для проверки',
    const {'one': 'пункт', 'few': 'пункта', 'many': 'пунктов'},
    (n, w) => '$n $w to check',
    const {'one': 'item', 'other': 'items'},
  ),
  _Plural(
    'bodyScanStrengthCount',
    (l, n) => l.bodyScanStrengthCount(n),
    (n, w) => '$n $w за последние 4 недели',
    const {'one': 'тренировка', 'few': 'тренировки', 'many': 'тренировок'},
    (n, w) => '$n $w in the last 4 weeks',
    const {'one': 'session', 'other': 'sessions'},
  ),
  _Plural(
    'bodyScanWeightBodyStale',
    (l, n) => l.bodyScanWeightBodyStale(n),
    (n, w) =>
        'Последней записи веса $n $w. Актуальный вес делает оценку надёжнее.',
    const {'one': 'день', 'few': 'дня', 'many': 'дней'},
    (n, w) =>
        'Your last weight is $n $w old. A current weight makes the estimate more reliable.',
    const {'one': 'day', 'other': 'days'},
  ),
  _Plural(
    'nutritionReviewBasis',
    (l, n) => l.nutritionReviewBasis(n),
    (n, w) => 'На основе $n $w',
    const {
      'one': 'записи веса',
      'few': 'записей веса',
      'many': 'записей веса'
    },
    (n, w) => 'Based on $n $w',
    const {'one': 'weigh-in', 'other': 'weigh-ins'},
  ),
  _Plural(
    'scanManualTimerStarted',
    (l, n) => l.scanManualTimerStarted(n),
    (n, w) => 'Фото через $n $w',
    const {'one': 'секунду', 'few': 'секунды', 'many': 'секунд'},
    (n, w) => 'Photo in $n $w',
    const {'one': 'second', 'other': 'seconds'},
  ),
  _Plural(
    'onbNutritionPaceMessage',
    (l, n) => l.onbNutritionPaceMessage('0,4', n),
    (n, w) =>
        'При безопасном темпе около 0,4 кг в неделю это займёт примерно $n $w.',
    const {'one': 'неделю', 'few': 'недели', 'many': 'недель'},
    (n, w) =>
        'At a safe pace of about 0,4 kg per week, this takes roughly $w.',
    // The EN branch is `one{1 week} other{{weeks} weeks}`.
    const {'one': '1 week', 'other': '{n} weeks'},
  ),
  _Plural(
    'bodyCheckInLast',
    (l, n) => l.bodyCheckInLast(n),
    (n, w) => 'Последняя проверка: $n $w назад',
    const {'one': 'день', 'few': 'дня', 'many': 'дней'},
    (n, w) => 'Last check-in: $n $w ago',
    const {'one': 'day', 'other': 'days'},
  ),
];

const _wholeNumbers = [1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 20, 21, 22, 24, 25, 100, 101, 111, 112];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('RU integer plurals pick one / few / many', () {
    for (final p in _plurals) {
      test(p.key, () {
        for (final n in _wholeNumbers) {
          final form = _ruForm(n);
          expect(p.call(ru, n), p.ruFmt(n, p.ruWords[form]!),
              reason: '${p.key} n=$n expected form $form');
        }
      });
    }

    test('the 1/2/5/11/21/22/25 acceptance set maps to the right forms', () {
      expect([1, 2, 5, 11, 21, 22, 25].map(_ruForm).toList(),
          ['one', 'few', 'many', 'many', 'one', 'few', 'many']);
      // One representative key rendered end to end.
      final got = [1, 2, 5, 11, 21, 22, 25]
          .map((n) => ru.bodyScanHistoryCount(n))
          .toList();
      expect(got, [
        '1 скан',
        '2 скана',
        '5 сканов',
        '11 сканов',
        '21 скан',
        '22 скана',
        '25 сканов',
      ]);
    });

    test('zero uses the many form, except the today special case', () {
      expect(ru.bodyScanHistoryCount(0), '0 сканов');
      expect(ru.bodyCheckInLast(0), 'Последняя проверка: сегодня');
      expect(en.bodyCheckInLast(0), 'Last check-in: today');
    });
  });

  group('EN integer plurals: one vs other', () {
    for (final p in _plurals) {
      test(p.key, () {
        for (final n in [0, 1, 2, 5, 11, 21]) {
          if (p.key == 'bodyCheckInLast' && n == 0) continue;
          final word = n == 1 ? p.enWords['one']! : p.enWords['other']!;
          final expected = p.key == 'onbNutritionPaceMessage'
              ? 'At a safe pace of about 0,4 kg per week, this takes roughly ${word.replaceAll('{n}', '$n')}.'
              : p.enFmt(n, word);
          expect(p.call(en, n), expected, reason: '${p.key} n=$n');
        }
      });
    }
  });

  group('decimals never sit inside a plural (RU and EN)', () {
    const values = [0.4, 1.0, 1.5, 2.1, 5.0, 24.1];

    String fmt(String locale, double v) {
      final f = NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 1
        ..maximumFractionDigits = 1;
      return f.format(v);
    }

    test('RU numbers use the decimal comma, EN the decimal point', () {
      expect(values.map((v) => fmt('ru', v)).toList(),
          ['0,4', '1,0', '1,5', '2,1', '5,0', '24,1']);
      expect(values.map((v) => fmt('en', v)).toList(),
          ['0.4', '1.0', '1.5', '2.1', '5.0', '24.1']);
    });

    // key -> (RU message builder, EN message builder, RU tail after the
    // number, EN tail). The tail must be identical for every value: the
    // abbreviation does not inflect.
    final cases = <String, ({
      String Function(AppLocalizations, String) build,
      String ruMsg,
      String enMsg,
    })>{
      'bodyScanWeightTrendDown': (
        build: (l, n) => l.bodyScanWeightTrendDown(n),
        ruMsg: 'Снижение: # кг в неделю',
        enMsg: 'Down # kg per week',
      ),
      'nutritionReviewTrend': (
        build: (l, n) => l.nutritionReviewTrend(n),
        ruMsg: 'Динамика веса: # кг/нед.',
        enMsg: 'Weight trend: # kg/week',
      ),
      'onbNutritionTargetLine': (
        build: (l, n) => l.onbNutritionTargetLine(n),
        ruMsg: 'Целевой вес: # кг',
        enMsg: 'Target weight: # kg',
      ),
      'bodyScanChartSummaryDown(pts)': (
        build: (l, n) => l.bodyScanChartSummaryDown('20,0', n, '8'),
        ruMsg: 'Сглаженный тренд 20,0 процента, снижение на # п.п. за 8 нед.',
        enMsg: 'Smoothed trend 20,0 percent, down # points over 8 weeks.',
      ),
      'bodyScanChartSummaryDown(weeks)': (
        build: (l, n) => l.bodyScanChartSummaryDown('20,0', '2,0', n),
        ruMsg: 'Сглаженный тренд 20,0 процента, снижение на 2,0 п.п. за # нед.',
        enMsg: 'Smoothed trend 20,0 percent, down 2,0 points over # weeks.',
      ),
    };

    for (final e in cases.entries) {
      test('${e.key} keeps one fixed unit for every decimal', () {
        final ruOut = <String>[];
        for (final v in values) {
          final ruNum = fmt('ru', v);
          final enNum = fmt('en', v);
          final ruText = e.value.build(ru, ruNum);
          final enText = e.value.build(en, enNum);
          expect(ruText, e.value.ruMsg.replaceAll('#', ruNum),
              reason: 'RU $v');
          expect(enText, e.value.enMsg.replaceAll('#', enNum),
              reason: 'EN $v');
          ruOut.add(ruText.replaceAll(ruNum, '#'));
        }
        // Non-inflecting: removing the number leaves the same text for 0,4
        // and 1,0 and 2,1 and 5,0 and 24,1 alike.
        expect(ruOut.toSet(), {e.value.ruMsg});
      });
    }

    test('ETA range renders two decimals with the abbreviation "нед."', () {
      expect(ru.bodyScanEtaRange('29,9', '31,5'),
          'Примерно 29,9-31,5 нед., если темп сохранится');
      expect(en.bodyScanEtaRange('29.9', '31.5'),
          'About 29.9 to 31.5 weeks if the pace holds');
    });
  });

  group('ARB structure of the new plural keys', () {
    final enArb = _arb('app_en.arb');
    final ruArb = _arb('app_ru.arb');
    final keys = _plurals.map((p) => p.key).toList();

    test('every new RU plural defines one, few, many and other', () {
      for (final k in keys) {
        final v = ruArb[k] as String;
        for (final form in ['one', 'few', 'many', 'other']) {
          expect(RegExp('\\b$form\\{').hasMatch(v), isTrue,
              reason: '$k RU lacks "$form": $v');
        }
      }
    });

    test('every new EN plural defines one and other; =0 only where intended',
        () {
      for (final k in keys) {
        final v = enArb[k] as String;
        expect(RegExp(r'\bone\{').hasMatch(v), isTrue, reason: k);
        expect(RegExp(r'\bother\{').hasMatch(v), isTrue, reason: k);
      }
      expect((ruArb['bodyCheckInLast'] as String).contains('=0{'), isTrue);
      expect((enArb['bodyCheckInLast'] as String).contains('=0{'), isTrue);
    });

    test('plural variables match between EN and RU and are declared int', () {
      for (final k in keys) {
        final enVar =
            RegExp(r'\{\s*(\w+)\s*,\s*plural').firstMatch(enArb[k] as String)!;
        final ruVar =
            RegExp(r'\{\s*(\w+)\s*,\s*plural').firstMatch(ruArb[k] as String)!;
        expect(ruVar.group(1), enVar.group(1), reason: k);
        final ph = (enArb['@$k'] as Map)['placeholders'] as Map;
        expect((ph[enVar.group(1)] as Map)['type'], 'int',
            reason: '$k plural placeholder must be int');
      }
    });

    test('no plural anywhere in the ARB files has a decimal placeholder', () {
      for (final arb in [enArb, ruArb]) {
        for (final e in arb.entries) {
          if (e.key.startsWith('@') || e.value is! String) continue;
          for (final m in RegExp(r'\{\s*(\w+)\s*,\s*plural')
              .allMatches(e.value as String)) {
            final meta = enArb['@${e.key}'];
            Object? type;
            if (meta is Map) {
              final phs = meta['placeholders'];
              if (phs is Map) {
                final ph = phs[m.group(1)];
                if (ph is Map) type = ph['type'];
              }
            }
            expect(type == 'double' || type == 'num', isFalse,
                reason: '${e.key}: plural variable ${m.group(1)} is $type');
          }
        }
      }
    });
  });
}
