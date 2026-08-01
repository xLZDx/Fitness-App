import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Russian UI against English leaking back in.
///
/// The operator has now reported untranslated strings twice ("Any · cardio",
/// "8 min / beginner / core", "For you / Strength / Cardio / At Home",
/// "Offline downloads · Supporter+"). Every one was a hardcoded literal or a
/// raw catalog tag rendered straight to the screen, not a missing ARB entry —
/// so a test that only diffs the two ARB files would have passed while the
/// screen still read English. These check both.
void main() {
  final en = (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map).cast<String, dynamic>();
  final ru = (jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())
      as Map).cast<String, dynamic>();

  /// The app's own brand name is deliberately identical in both languages.
  const kBrandKeys = {'appTitle'};

  test('every English key has a Russian entry', () {
    final missing = en.keys
        .where((k) => !k.startsWith('@'))
        .where((k) => !ru.containsKey(k))
        .toList();
    expect(missing, isEmpty, reason: 'untranslated keys: $missing');
  });

  test('no Russian value is just the English one copied over', () {
    final copied = <String>[];
    for (final entry in ru.entries) {
      if (entry.key.startsWith('@')) continue;
      if (kBrandKeys.contains(entry.key)) continue;
      final value = entry.value;
      final english = en[entry.key];
      if (value is! String || english is! String) continue;
      // Four+ Latin letters in a row is the signal: "5 км" and "{arg0}%"
      // are legitimately identical across languages, "Offline downloads"
      // is not.
      //
      // Placeholder NAMES are stripped first. `'{date} · {time}'` is the same
      // string in both languages because it contains no words at all — only
      // two substitution points and a separator — but `date` and `time` are
      // four Latin letters each, so the raw check called it English left
      // behind. What is being asked is whether the TEXT was translated, and a
      // placeholder is not text.
      final words = value.replaceAll(RegExp(r'\{\w+\}'), '');
      if (value == english && RegExp(r'[A-Za-z]{4,}').hasMatch(words)) {
        copied.add('${entry.key}: $value');
      }
    }
    expect(copied, isEmpty, reason: 'English left in the Russian ARB: $copied');
  });

  test('no hardcoded English sentence is passed to a Text() widget', () {
    // Catches the class of bug the operator actually hit: a literal written
    // straight into the widget tree, which never reaches the ARB pipeline at
    // all.
    final offenders = <String>[];
    final textLiteral = RegExp(r"""Text\(\s*'([^']{4,90})'""");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in textLiteral.allMatches(src)) {
        final s = m.group(1)!;
        // Two consecutive words of 3+ Latin letters = a sentence, not an
        // identifier, a URL fragment or a unit.
        if (RegExp(r'[A-Za-z]{3,}\s+[A-Za-z]{3,}').hasMatch(s) &&
            !s.contains(r'$')) {
          offenders.add('${f.path}: "$s"');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'hardcoded English in the widget tree: $offenders');
  });

  test('no English month or weekday tables outside intl', () {
    // Two of these were shipping: the scheduling confirmation on the exercise
    // page and the date under a progress photo, each with its own hardcoded
    // ['Jan','Feb',...]. The widget-tree scan above cannot see them — the
    // literal is in a helper, not in a `Text(...)`.
    //
    // Russian dates decline, so even a translated array would be wrong: it is
    // "20 мая", never "мая 20". `DateFormat.MMMd(locale)` knows that for every
    // locale Flutter ships, which is why the rule is "no table at all" rather
    // than "translate the table".
    final offenders = <String>[];
    final table = RegExp(r"'(Jan|Mon)'\s*,\s*'(Feb|Tue)'");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (table.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'hardcoded date names — use DateFormat with the locale: '
            '$offenders');
  });

  test('user-facing enum labels go through the ARB, not a Dart switch', () {
    // `SubscriptionPeriod.displayLabel` returned 'Monthly' / 'Family · 2
    // seats' and was rendered straight into the Russian subscription page.
    // It is now `label(l10n)`, and the English version is renamed to
    // `debugLabel` so that reaching for it in a widget looks wrong.
    final src = File('lib/features/subscription/data/subscription_models.dart')
        .readAsStringSync();
    expect(src, contains('String label(AppLocalizations l10n)'));
    expect(src, isNot(contains('String get displayLabel')),
        reason: 'a getter named like a display string invites use in the UI');

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(f.readAsStringSync(), isNot(contains('.debugLabel')),
          reason: '${f.path} renders the English label');
    }
  });

  test('catalog vocabulary tags all have a localized label', () {
    // The muscle/difficulty/category tags are stored in English because they
    // drive filtering and the muscle map; CatalogLabels is what translates
    // them for display. A tag with no label there renders as a raw English
    // key — which is exactly how "core" and "beginner" reached the operator's
    // screen.
    final labels = File('lib/features/equipment/data/catalog_labels.dart')
        .readAsStringSync();
    const muscles = ['chest', 'back', 'lats', 'traps', 'lower_back', 'quads',
        'hamstrings', 'calves', 'glutes', 'adductors', 'shoulders', 'biceps',
        'triceps', 'forearms', 'core'];
    for (final m in muscles) {
      expect(labels, contains("case '$m':"), reason: '$m has no label');
    }
    for (final d in ['beginner', 'intermediate', 'advanced']) {
      expect(labels, contains('ExerciseDifficulty.$d'), reason: '$d unlabelled');
    }
    for (final c in ['strength', 'cardio', 'free_weights', 'functional']) {
      expect(labels, contains("case '$c':"), reason: '$c has no label');
    }
  });
}
