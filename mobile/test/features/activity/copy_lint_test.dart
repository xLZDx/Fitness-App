// S02 test epic 3, U33: no external-source dedup promise (design 9, DQ-13).
//
// The only dedup S02 promises is the native-id rule. Copy that says duplicates
// are removed, or that a session was merged with the user's watch, is a claim
// this build cannot keep, so the localisation strings and the S02 screens are
// scanned for it. WEAK BY NATURE: it sees strings only, not behaviour; the
// native-id rule itself is proved by U10 / U11.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/s02_paths.dart';

/// Forbidden claims, English and the shipped Russian locale.
final List<RegExp> _forbidden = [
  for (final p in [
    r'dedup',
    r'de-dup',
    r'duplicate\s+removal',
    r'removes?\s+(all\s+)?duplicates',
    r'duplicates?\s+(are\s+|were\s+)?(removed|merged|detected|filtered)',
    r'merged\s+with\s+your\s+(watch|device|garmin|strava)',
    r'no\s+duplicates',
    r'without\s+duplicates',
    r'дедуп',
    r'дубликат',
    r'дублей',
    r'дубли\b',
    r'без\s+дублик',
    r'(объединен|объединён|слит)[а-яё]*\s+с\s+(ваш[а-яё]+\s+)?(часами|устройством|гармин|страва)',
  ])
    RegExp(p, caseSensitive: false, unicode: true),
];

List<String> claimsIn(String text) => [
      for (final r in _forbidden)
        if (r.hasMatch(text)) r.pattern,
    ];

/// All string literals of a Dart source (single or double quoted, one line).
Iterable<String> stringLiterals(String src) sync* {
  final dq = RegExp('"([^"\\n]*)"');
  final sq = RegExp("'([^'\\n]*)'");
  for (final r in [dq, sq]) {
    for (final m in r.allMatches(src)) {
      yield m.group(1) ?? '';
    }
  }
}

void main() {
  group('U33 copy lint scanner (positive controls)', () {
    test('flags the forbidden English and Russian claims', () {
      for (final bad in [
        'No duplicates in your history',
        'We remove duplicates for you',
        'Duplicates are removed automatically',
        'Merged with your watch',
        'Smart dedup',
        'Duplicate removal is on',
        'Без дублей',
        'Дубликаты удалены',
        'Объединено с вашими часами',
        'Дедупликация включена',
      ]) {
        expect(claimsIn(bad), isNotEmpty, reason: bad);
      }
    });

    test('a fixture string with `no duplicates` is flagged by the same scanner',
        () {
      const fixture = '{"a": "Sync keeps no duplicates"}';
      final flagged = [
        for (final v in (jsonDecode(fixture) as Map).values)
          if (claimsIn('$v').isNotEmpty) v,
      ];
      expect(flagged, ['Sync keeps no duplicates']);
      expect(stringLiterals("Text('no duplicates here')"), ['no duplicates here']);
    });

    test('ordinary activity copy is not flagged (negative controls)', () {
      for (final ok in [
        'Nothing is deleted: your data on this device stays as it is until you choose.',
        'Everything is in sync.',
        'Keep cloud',
        'Эти тренировки изменены на двух устройствах.',
        'Ничего не удаляется',
      ]) {
        expect(claimsIn(ok), isEmpty, reason: ok);
      }
    });
  });

  group('U33 the shipped copy makes no dedup promise', () {
    test('activity localisation strings, en and ru', () {
      var scanned = 0;
      for (final f in ['app_en.arb', 'app_ru.arb']) {
        final arb = (jsonDecode(repoFile('mobile/lib/l10n/$f').readAsStringSync())
                as Map)
            .cast<String, dynamic>();
        for (final e in arb.entries) {
          if (e.key.startsWith('@') || e.value is! String) continue;
          if (!e.key.startsWith('activity')) continue;
          scanned++;
          expect(claimsIn(e.value as String), isEmpty, reason: '$f ${e.key}');
        }
      }
      expect(scanned, greaterThan(60), reason: 'the scan must see the S02 strings');
    });

    test('string literals of the S02 widgets and state', () {
      var files = 0;
      var literals = 0;
      for (final dir in ['widgets', 'state']) {
        final d = Directory('${repoRoot().path}/mobile/lib/features/activity/$dir');
        for (final f in d.listSync().whereType<File>()) {
          if (!f.path.endsWith('.dart')) continue;
          files++;
          for (final s in stringLiterals(f.readAsStringSync())) {
            literals++;
            expect(claimsIn(s), isEmpty, reason: '${f.path}: $s');
          }
        }
      }
      expect(files, greaterThanOrEqualTo(3));
      expect(literals, greaterThan(10));
    });

    test('every activity key exists in both locales (nothing escapes the scan)',
        () {
      Set<String> keys(String f) => ((jsonDecode(
                  repoFile('mobile/lib/l10n/$f').readAsStringSync()) as Map)
              .keys
              .cast<String>())
          .where((k) => k.startsWith('activity') && !k.startsWith('@'))
          .toSet();
      expect(keys('app_ru.arb'), keys('app_en.arb'));
    });
  });
}
