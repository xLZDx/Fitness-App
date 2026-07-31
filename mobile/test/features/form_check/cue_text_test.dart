import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:fitness_app/features/form_check/data/cue_text.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

/// The boundary where internal identifiers become words.
///
/// Loaded against the REAL localisations rather than a hand-written mock: the
/// generated class carries ~390 getters, so a mock drifts from the ARB the
/// moment anyone edits it — and a test that drifts is a test that passes while
/// the screen is wrong, which is exactly the failure this file guards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every classifier the app actually ships. The rule-name test walks this
  /// rather than a hardcoded list, so a new rule cannot be added without a
  /// name — which is how "Ошибки: squat.depth" reached a Russian screen.
  final shipped = <FormClassifier>[
    SquatDepthClassifier(),
    DeadliftHipHingeClassifier(),
    PushupAlignmentClassifier(),
  ];

  for (final locale in const ['en', 'ru']) {
    group('locale $locale', () {
      late AppLocalizations l10n;

      setUpAll(() async {
        l10n = await AppLocalizations.delegate.load(Locale(locale));
      });

      test('every cue key resolves to real text', () {
        for (final key in FormCueKey.values) {
          final text = formCueText(l10n, key);
          expect(text.trim(), isNotEmpty, reason: '$key has no text');
          expect(text, isNot(equals(key.name)),
              reason: '$key resolved to its own name');
        }
      });

      test('every shipped rule id has a human name', () {
        for (final c in shipped) {
          final name = formRuleName(l10n, c.rule);
          expect(name, isNot(equals(c.rule)),
              reason: '${c.rule} falls through to the raw identifier');
          expect(name.trim(), isNotEmpty);
        }
      });

      test('every unscorable verdict has an instruction', () {
        for (final v in PoseGateVerdict.values) {
          final hint = poseGateHint(l10n, v);
          if (v.isScorable) {
            expect(hint, isEmpty, reason: 'a scorable frame needs no hint');
          } else {
            expect(hint.trim(), isNotEmpty,
                reason: '$v leaves the user with no instruction');
          }
        }
      });

      test('every rep phase has a name', () {
        for (final phase in RepPhase.values) {
          expect(repPhaseText(l10n, phase).trim(), isNotEmpty);
        }
      });
    });
  }

  group('the Russian text is Russian', () {
    late AppLocalizations ru;

    setUpAll(() async {
      ru = await AppLocalizations.delegate.load(const Locale('ru'));
    });

    test('no cue, rule name, hint or phase is left in English', () {
      // Two consecutive Latin words is a sentence, not a unit or an
      // identifier. This is what "повторения — ready" and "Half-rep. Lighten
      // the bar and hit depth." both looked like on the operator's screen.
      final english = RegExp(r'[A-Za-z]{3,}\s+[A-Za-z]{3,}');
      final strings = <String>[
        for (final k in FormCueKey.values) formCueText(ru, k),
        for (final c in [
          'squat.depth',
          'deadlift.hip_hinge',
          'pushup.alignment',
        ])
          formRuleName(ru, c),
        for (final v in PoseGateVerdict.values) poseGateHint(ru, v),
        for (final p in RepPhase.values) repPhaseText(ru, p),
      ];
      final offenders = strings.where(english.hasMatch).toList();
      expect(offenders, isEmpty, reason: 'English on the Russian screen');
    });

    test('the coach addresses the user formally, like the rest of the app', () {
      // The app says "Отойдите", "Войдите", "Поставьте" everywhere else. Cues
      // shipped as "вставай"/"напряги" — the only informal strings in the
      // product, and jarring next to their own neighbours on the same screen.
      // Whole words only. Dart's \b is ASCII-based and does not fire between
      // Cyrillic letters, and a naive `contains` matches the formal form
      // inside itself — "подверните" contains "подверни". So the boundary is
      // spelled out as "not a Cyrillic letter".
      const informal = ['вставай', 'опустись', 'напряги', 'подверни', 'убавь',
          'держи', 'садись', 'опусти', 'поднимай'];
      for (final key in FormCueKey.values) {
        final text = formCueText(ru, key).toLowerCase();
        for (final word in informal) {
          final whole = RegExp('(^|[^а-яё])$word([^а-яё]|\$)');
          expect(whole.hasMatch(text), isFalse,
              reason: '$key uses the informal "$word": "$text"');
        }
      }
    });
  });
}
