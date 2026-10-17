// S03-18 epic 5C (DT-18-2 style): the S03 ARB keys exist in en and ru with the
// same placeholders; ru strings are real translations, not copies of en.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _s03 = RegExp(
    r'^(mode|home|progress|activity|source|sources|strip|rail|record|signOut|sportGroup|syncChip|nav)[A-Z0-9_.]');

Map<String, dynamic> _load(String lang) => json.decode(
        File('lib/l10n/app_$lang.arb').readAsStringSync())
    as Map<String, dynamic>;

Set<String> _ph(Map<String, dynamic> m, String key) {
  final dynamic meta = m['@$key'];
  if (meta is Map && meta['placeholders'] is Map) {
    return (meta['placeholders'] as Map).keys.cast<String>().toSet();
  }
  return <String>{};
}

void main() {
  final Map<String, dynamic> en = _load('en');
  final Map<String, dynamic> ru = _load('ru');
  final List<String> keys = en.keys
      .where((String k) => !k.startsWith('@') && _s03.hasMatch(k))
      .toList();

  test('the S03 key set is not empty (the filter matches real keys)', () {
    expect(keys.length, greaterThan(100));
  });

  test('every S03 en key has an ru key', () {
    final List<String> missing =
        keys.where((String k) => !ru.containsKey(k)).toList();
    expect(missing, isEmpty);
  });

  test('an ru @metadata block, where present, lists no placeholder en lacks',
      () {
    final List<String> bad = <String>[
      for (final String k in keys)
        if (ru.containsKey('@$k') && _ph(ru, k).difference(_ph(en, k)).isNotEmpty)
          k
    ];
    expect(bad, isEmpty);
  });

  test('ru placeholders used in the string text match the en ones', () {
    final RegExp p = RegExp(r'\{([a-z][A-Za-z0-9]*)[,}]');
    final List<String> bad = <String>[
      for (final String k in keys)
        if (ru[k] is String &&
            en[k] is String &&
            p.allMatches(en[k] as String).map((m) => m.group(1)).toSet().difference(
                    p.allMatches(ru[k] as String).map((m) => m.group(1)).toSet()).isNotEmpty)
          k
    ];
    expect(bad, isEmpty);
  });

  test('ru plural keys carry one, few, many and other', () {
    final List<String> bad = <String>[
      for (final String k in keys)
        if (ru[k] is String &&
            (ru[k] as String).contains(', plural,') &&
            !RegExp(r'one\{').hasMatch(ru[k] as String) ||
            (ru[k] is String &&
                (ru[k] as String).contains(', plural,') &&
                !(RegExp(r'few\{').hasMatch(ru[k] as String) &&
                    RegExp(r'many\{').hasMatch(ru[k] as String) &&
                    RegExp(r'other\{').hasMatch(ru[k] as String))))
          k
    ];
    expect(bad, isEmpty);
  });

  test('no S03 ru string is empty or still an exact english copy of a sentence',
      () {
    final List<String> bad = <String>[
      for (final String k in keys)
        if (ru[k] is String &&
            ((ru[k] as String).trim().isEmpty ||
                (ru[k] == en[k] && k != 'sourceHealthConnect' && k != 'sourceHealthConnect' &&
                    RegExp(r'[A-Za-z]{4,} [A-Za-z]{3,}')
                        .hasMatch(en[k] as String))))
          k
    ];
    expect(bad, isEmpty);
  });
}
