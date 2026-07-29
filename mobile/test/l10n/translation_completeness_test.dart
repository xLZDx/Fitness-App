import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards translation completeness.
///
/// The operator's complaint was a HALF-Russian interface: some screens
/// translated, most not. A key that exists in English but not in Russian is
/// exactly that bug, and `AppLocalizations` would silently fall back to English
/// rather than fail — so the suite has to be the thing that notices.
void main() {
  Map<String, String> load(String name) {
    final raw = File('lib/l10n/$name').readAsStringSync();
    final decoded = json.decode(raw) as Map<String, dynamic>;
    return {
      for (final e in decoded.entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };
  }

  late Map<String, String> en;
  late Map<String, String> ru;

  setUpAll(() {
    en = load('app_en.arb');
    ru = load('app_ru.arb');
  });

  test('every English key has a Russian translation', () {
    final missing = (en.keys.toSet()..removeAll(ru.keys)).toList()..sort();
    expect(missing, isEmpty,
        reason: 'these keys would silently render in English');
  });

  test('there are no orphan Russian keys', () {
    final orphans = (ru.keys.toSet()..removeAll(en.keys)).toList()..sort();
    expect(orphans, isEmpty,
        reason: 'a key with no English template is dead weight');
  });

  test('no translation is blank', () {
    final blank = ru.entries
        .where((e) => e.value.trim().isEmpty)
        .map((e) => e.key)
        .toList()
      ..sort();
    expect(blank, isEmpty);
  });

  // A Russian value identical to the English one is almost always a forgotten
  // string rather than a deliberate choice. Short tokens and brand names are
  // the legitimate exceptions.
  test('no prose was left untranslated', () {
    const allowedIdentical = <String>{
      // Brand name — the same in every language by design.
      'appTitle',
    };

    final untranslated = <String>[];
    for (final e in en.entries) {
      final rus = ru[e.key];
      if (rus == null) continue;
      if (allowedIdentical.contains(e.key)) continue;
      // Only flag real prose: anything with a space and some length.
      if (e.value.length < 8 || !e.value.contains(' ')) continue;
      if (rus == e.value) untranslated.add(e.key);
    }
    untranslated.sort();
    expect(untranslated, isEmpty,
        reason: 'identical to English — likely forgotten');
  });

  test('the catalogue is not trivially small', () {
    // Cheap tripwire: if a future edit truncates the ARB, this notices before
    // a user does.
    expect(en, hasLength(greaterThan(150)));
    expect(ru.length, en.length);
  });
}
