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
    //
    // F027 widened this. The old version matched only a literal IMMEDIATELY
    // after `Text(`, so anything wrapped in a ternary was invisible to it --
    // a blind spot this file's own ARB notes had already recorded
    // ("does not see ternary-wrapped Text()") without closing. Two strings
    // were living in it: the injury-filter count on the equipment page and
    // the Sustainer pitch on the team feed. Both were user-facing English on
    // a Russian screen, and one of them was safety copy.
    //
    // It now reads the whole FIRST POSITIONAL argument of every `Text(` call,
    // with comments stripped first. Both details are load-bearing: named
    // arguments (`key:`, `style:`) carry identifiers that are not display
    // copy, and a comment containing a comma otherwise ends the argument
    // early -- which is the precise reason the team-feed string survived a
    // first attempt at this widening.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final s in _textArguments(_stripComments(f.readAsStringSync()))) {
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

  test('the widened scan still sees a ternary-wrapped literal', () {
    // The guard needs its own guard. A scan that silently stopped matching
    // would report a clean tree forever, which is exactly the failure mode
    // F027 came from -- so this pins the widening itself rather than trusting
    // that an empty offender list means what it looks like it means.
    const sample = '''
      Text(
        // a comment, with commas, that used to end the argument early
        flag
            ? l10n.somethingTranslated
            : 'Become a Sustainer to read what your coach is sharing.',
        style: theme.textTheme.bodyMedium,
      )
    ''';
    expect(_textArguments(_stripComments(sample)),
        contains('Become a Sustainer to read what your coach is sharing.'));
  });

  test('the scan sees a double-quoted literal, and one split across lines', () {
    // The second blind spot, found by scanning data layers for prose and then
    // asking why the guard had not already objected. The answer was not
    // subtle: the literal regex was `'([^'\\\n]{4,120})'` — single quotes
    // only — and Dart treats `"..."` as exactly the same literal.
    //
    // `deload_banner.dart` was living in that gap, showing Russian users
    // *"Recovery signals are pointing toward a lighter week."* while this
    // suite reported a clean widget tree. It was hidden behind a quotation
    // mark, which is why the self-test matters more than the scan: a guard
    // that cannot fail is indistinguishable from a codebase that is clean.
    const sample = '''
      Text(
        flag
            ? "Recovery signals are pointing toward a "
                "lighter week."
            : other,
        style: theme.textTheme.bodyMedium,
      )
    ''';
    final found = _textArguments(_stripComments(sample));
    expect(found, contains('Recovery signals are pointing toward a '));
    expect(found, contains('lighter week.'),
        reason: 'adjacent concatenation is two literals to Dart, and the '
            'wrap that splits a sentence must not also hide it');
  });

  test('the widened scan ignores what is not display copy', () {
    // Named arguments and compared-against literals are not user-facing, and
    // a scan that flagged them would be turned off rather than obeyed.
    const sample = '''
      Text(
        e.toString().contains('no longer has')
            ? l10n.keyMissing
            : l10n.blobMissing,
        key: const Key('some identifier here'),
      )
    ''';
    expect(_textArguments(_stripComments(sample)), isEmpty);
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

/// Every `Text(...)` call's first positional argument, as string literals.
///
/// Deliberately not a regular expression over the whole call: Dart arguments
/// nest, and the thing being looked for is display copy, which is only ever
/// the first positional one.
List<String> _textArguments(String src) {
  final out = <String>[];
  // Both quote styles. The first version of this matched only `'...'`, and
  // Dart treats `"..."` as exactly the same literal — so a double-quoted
  // sentence in a widget tree was invisible to a guard whose entire job is to
  // find sentences in widget trees. One was living in that gap:
  // `deload_banner.dart` rendered *"Recovery signals are pointing toward a
  // lighter week."* to Russian users, and this suite reported a clean tree.
  //
  // Adjacent concatenation is handled by matching each chunk separately
  // rather than the whole expression: `'a ' 'b'` is two literals to Dart and
  // two matches here, and a sentence long enough to be worth catching survives
  // being cut in half by the line wrap that split it.
  final literal = RegExp("'([^'\\\\\\n]{4,120})'|\"([^\"\\\\\\n]{4,120})\"");
  final predicate =
      RegExp(r'(contains|startsWith|endsWith|indexOf|split)\($|==\s*$');
  for (final call in RegExp(r'\bText\(').allMatches(src)) {
    var i = call.end;
    var depth = 1;
    int? firstComma;
    while (i < src.length && depth > 0) {
      final c = src[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ',' && depth == 1 && firstComma == null) {
        firstComma = i;
      }
      i++;
    }
    final span = src.substring(call.end, firstComma ?? i - 1);
    for (final m in literal.allMatches(span)) {
      if (predicate.hasMatch(span.substring(0, m.start).trimRight())) continue;
      out.add(m.group(1) ?? m.group(2)!);
    }
  }
  return out;
}

/// [src] with comments blanked out, preserving offsets.
///
/// A comment's own commas and quotation marks are indistinguishable from code
/// to any scan that does not do this, and both appear in this repository's
/// comments constantly.
String _stripComments(String src) {
  final out = src.split('');
  var i = 0;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    if (quote != null) {
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out[i] = ' ';
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        if (src[i] != '\n') out[i] = ' ';
        i++;
      }
      if (i < src.length) out[i] = ' ';
      if (i + 1 < src.length) out[i + 1] = ' ';
      i += 2;
      continue;
    }
    i++;
  }
  return out.join();
}
