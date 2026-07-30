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

  test('placeholders match between languages', () {
    // A Russian string that drops `{arg0}` compiles and renders happily, minus
    // the error detail or number it was supposed to carry. Nothing else would
    // notice.
    Set<String> holes(String v) =>
        RegExp(r'\{(\w+)\}').allMatches(v).map((m) => m.group(1)!).toSet();

    final mismatched = <String>[];
    for (final e in en.entries) {
      final rus = ru[e.key];
      if (rus == null) continue;
      if (holes(e.value).difference(holes(rus)).isNotEmpty ||
          holes(rus).difference(holes(e.value)).isNotEmpty) {
        mismatched.add('${e.key}: en=${holes(e.value)} ru=${holes(rus)}');
      }
    }
    expect(mismatched, isEmpty);
  });

  test('every placeholder key declares its types in the template', () {
    // gen_l10n reads placeholder types from app_en.arb only. A value with
    // braces and no `@key` metadata generates a getter, not a method, and the
    // braces ship to the user as literal text.
    final raw = json.decode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final undeclared = <String>[];
    for (final e in en.entries) {
      if (!e.value.contains('{')) continue;
      final meta = raw['@${e.key}'];
      if (meta is! Map || meta['placeholders'] is! Map) {
        undeclared.add(e.key);
      }
    }
    undeclared.sort();
    expect(undeclared, isEmpty);
  });

  group('l10n pipeline guards', () {
    // These two mistakes were both made by scripts/l10n/apply_strings.py and
    // both broke the app rather than a screen, so they are pinned mechanically.

    /// Source with `//` comments removed.
    ///
    /// Needed because the comment in `main.dart` that documents this very rule
    /// names `AppLocalizations.of(context)`, and a naive substring search
    /// reported the warning as the violation.
    String code(String src) => src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    test('the widget that builds MaterialApp does not look up localizations',
        () {
      // It sits above the Localizations ancestor it installs, so the lookup
      // returns null and the non-nullable getter throws on the first frame —
      // the app does not boot. This has happened twice.
      final main = code(File('lib/main.dart').readAsStringSync());
      expect(main.contains('AppLocalizations.of(context)'), isFalse,
          reason: 'main.dart builds the MaterialApp; use onGenerateTitle if a '
              'translated title is ever wanted');
    });

    test('no file without a BuildContext looks up localizations', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = code(f.readAsStringSync());
        if (!src.contains('AppLocalizations.of(context)')) continue;
        if (!src.contains('BuildContext')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'these would not compile, or reference an undefined context');
    });
  });
}
