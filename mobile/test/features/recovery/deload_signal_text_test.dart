import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/recovery/deload_signal_text.dart';

/// F027, third site.
///
/// `deload_detector.dart` composed its reasons in English and
/// `deload_banner.dart` rendered `reasons.first` straight into a `Text`, so a
/// Russian user was told in English that their body was asking for a break.
///
/// Worth recording how it survived: the banner's own fallback was written with
/// double quotes, and the l10n guard's literal regex matched only `'...'`.
/// The string was not hidden behind anything clever. It was hidden behind a
/// quotation mark, and the guard reported a clean tree for as long as that was
/// true.
void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  const signals = <DeloadSignal>[
    HardSessionsSignal(1),
    HardSessionsSignal(7),
    MissedSessionsSignal(3, 8),
    HrvBelowBaselineSignal(12),
  ];

  test('every signal renders in both languages', () {
    for (final s in signals) {
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        expect(deloadSignalText(l10n, s).trim(), isNotEmpty,
            reason: '$name: ${s.runtimeType}');
      }
    }
  });

  test('the Russian is actually Russian', () {
    final cyrillic = RegExp(r'[Ѐ-ӿ]');
    for (final s in signals) {
      expect(deloadSignalText(ru, s), matches(cyrillic),
          reason: '${s.runtimeType} rendered without Cyrillic — the exact '
              'shape of the defect this file exists about');
    }
  });

  test('the numbers reach the sentence', () {
    for (final (name, l10n) in [('en', en), ('ru', ru)]) {
      expect(deloadSignalText(l10n, const MissedSessionsSignal(3, 8)),
          allOf(contains('3'), contains('8')),
          reason: '$name: "you missed some of some" is not a signal');
      expect(deloadSignalText(l10n, const HrvBelowBaselineSignal(12)),
          contains('12'),
          reason: name);
      expect(deloadSignalText(l10n, const HardSessionsSignal(7)), contains('7'),
          reason: name);
    }
  });

  test('the singular reads as a sentence, not as a template', () {
    // English `one` deliberately says "Your last workout" with no digit —
    // "Your last 1 workouts" was what the old composed string produced, and it
    // is the sort of thing nobody notices in review and everybody notices in a
    // screenshot.
    final one = deloadSignalText(en, const HardSessionsSignal(1));
    expect(one, isNot(contains('1 workout')));
    expect(one, contains('last workout'));
    expect(deloadSignalText(en, const HardSessionsSignal(7)),
        contains('7 workouts'));
  });

  test('distinct signals say distinct things', () {
    for (final (name, l10n) in [('en', en), ('ru', ru)]) {
      final rendered = {for (final s in signals) deloadSignalText(l10n, s)};
      expect(rendered, hasLength(signals.length), reason: name);
    }
  });

  test('the generic fallback exists in both languages', () {
    // The banner shows this when a deload is recommended and no individual
    // signal is available to name. It is the string that was double-quoted.
    expect(en.recoveryDeloadGenericSignal.trim(), isNotEmpty);
    expect(ru.recoveryDeloadGenericSignal, matches(RegExp(r'[Ѐ-ӿ]')));
    expect(ru.recoveryDeloadGenericSignal,
        isNot(en.recoveryDeloadGenericSignal));
  });
}
