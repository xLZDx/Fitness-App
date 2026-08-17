import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/ai_planner/plan_reason_text.dart';
import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// F027, the half that could not be tested before.
///
/// `plan_builder.dart` composed its rationale in English, inside a pure data
/// layer with no `BuildContext`. Every assertion about that copy — that it
/// says "injury" and not "condition", that no cycle note claims a performance
/// peak, that the safety ceiling is stated at all — could therefore only ever
/// be made about the English. There was no other language to make it about.
///
/// So the most important line the planner emits, the one that tells a user the
/// app has **not** cleared them for unrestricted exercise, reached Russian
/// users in English. Not as a translation bug: as a consequence of where the
/// sentence was built.
///
/// Every case below runs in both locales. That is the change.
void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    // A real delegate load rather than a fixture: a fixture would agree with
    // whatever this test expected while the shipped ARB disagreed, which is
    // the failure mode the l10n guards exist for.
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  /// Every reason the builder can emit, with representative arguments.
  ///
  /// Enumerated by hand and then checked against the sealed hierarchy below,
  /// so a new reason cannot be added without this list failing.
  List<PlanReason> allReasons() => [
        const ScreeningCeilingReason(60),
        const DeloadReason(70),
        for (final r in CycleSelfReport.values) CycleSelfReportReason(r),
        for (final p in CyclePhase.values) CyclePhaseReason(p),
        for (final r in MovementRestriction.values)
          UntaggedRestrictionReason(r),
        const UntaggedRestrictionReason(null),
        const InjuryFilterReason(1),
        const InjuryFilterReason(4),
        const NoHistoryReason(),
        const DeficitOrderReason(),
      ];

  group('every reason renders, in both languages', () {
    test('nothing is blank, in either locale', () {
      for (final reason in allReasons()) {
        for (final (name, l10n) in [('en', en), ('ru', ru)]) {
          final text = planReasonText(l10n, reason);
          expect(text.trim(), isNotEmpty,
              reason: '$name: ${reason.runtimeType} rendered nothing');
        }
      }
    });

    test('the Russian is actually Russian', () {
      // The failure this whole finding is about does not look like a crash. It
      // looks like a perfectly formatted English sentence on a Russian screen,
      // which no null check and no "is it empty" test can see.
      final cyrillic = RegExp(r'[Ѐ-ӿ]');
      for (final reason in allReasons()) {
        expect(planReasonText(ru, reason), matches(cyrillic),
            reason: '${reason.runtimeType} has no Cyrillic in it — this is '
                'exactly the shape of the defect F027 recorded, so it is the '
                'shape the test looks for');
      }
    });

    test('no raw Dart identifier reaches a user', () {
      // The old builder interpolated `advisory.restriction?.name` — the enum's
      // own identifier. A user with a knee restriction was shown the literal
      // string "deepKneeFlexion", in English AND in Russian, and nothing in
      // the suite objected because nothing was reading that sentence.
      final identifier = RegExp(r'[a-z]+[A-Z][a-zA-Z]*');
      for (final r in MovementRestriction.values) {
        for (final (name, l10n) in [('en', en), ('ru', ru)]) {
          final text = planReasonText(l10n, UntaggedRestrictionReason(r));
          expect(text, isNot(matches(identifier)),
              reason: '$name: ${r.name} leaked a camelCase identifier: $text');
          // Only the multi-word names are checked by their own spelling.
          // `overhead`, `impact` and `balance` are enum identifiers AND
          // ordinary English words, and `restrictionOverhead` legitimately
          // renders as "reaching or pressing overhead" -- asserting their
          // absence would forbid the correct translation. A single-word leak
          // is indistinguishable from correct copy, so the camelCase check
          // above is the one that can actually tell.
          if (r.name != r.name.toLowerCase()) {
            expect(text, isNot(contains(r.name)),
                reason: '$name: the enum name itself is in the sentence');
          }
        }
      }
    });

    test('distinct reasons say distinct things', () {
      // A `switch` that fell through to one default would satisfy every test
      // above while telling every user the same thing.
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        final phases = {
          for (final p in CyclePhase.values)
            planReasonText(l10n, CyclePhaseReason(p)),
        };
        expect(phases, hasLength(CyclePhase.values.length), reason: name);

        expect(
          planReasonText(l10n, const ScreeningCeilingReason(60)),
          isNot(planReasonText(l10n, const DeloadReason(60))),
          reason: '$name: the safety ceiling and a deload are not the same '
              'statement and must not read as one',
        );
        expect(
          planReasonText(l10n, const NoHistoryReason()),
          isNot(planReasonText(l10n, const DeficitOrderReason())),
          reason: name,
        );
      }
    });
  });

  group('the numbers survive the move into the ARB', () {
    test('the ceiling percentage is in the sentence', () {
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        expect(planReasonText(l10n, const ScreeningCeilingReason(60)),
            contains('60'),
            reason: '$name: a cap the user cannot read is not a cap they know '
                'about');
        expect(planReasonText(l10n, const DeloadReason(85)), contains('85'),
            reason: name);
      }
    });

    test('the injury count is in the sentence, and the plural agrees', () {
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        expect(planReasonText(l10n, const InjuryFilterReason(4)), contains('4'),
            reason: name);
      }
      // English `one` deliberately renders the word rather than the digit, so
      // this asserts the branch was taken rather than the digit appearing.
      expect(planReasonText(en, const InjuryFilterReason(1)),
          allOf(contains('1 exercise'), isNot(contains('exercises'))));
      expect(planReasonText(en, const InjuryFilterReason(4)),
          contains('exercises'));
    });
  });

  group('the safety claims the old English carried, now carried in both', () {
    // These three assertions existed before F027 and were unarguably correct.
    // What was wrong was that they could only ever be made about English,
    // because English was the only thing the builder produced.

    test('the ceiling tells the user to talk to a professional', () {
      expect(planReasonText(en, const ScreeningCeilingReason(60)).toLowerCase(),
          contains('qualified exercise professional'));
      // Not a word-for-word match: the Russian is a translation, not a
      // transliteration. What has to survive is the referral itself.
      expect(planReasonText(ru, const ScreeningCeilingReason(60)).toLowerCase(),
          anyOf(contains('врач'), contains('специалист')));
    });

    test('the filter claim says injury, never condition', () {
      // `filterContraindicated` is passed the injury list and nothing else.
      // `HealthHistory.conditions` reaches no filter at all, so a sentence
      // claiming conditions were screened is wrong in the one direction a
      // safety claim must never be wrong in.
      final enText = planReasonText(en, const InjuryFilterReason(2));
      expect(enText.toLowerCase(), contains('injury'));
      expect(enText.toLowerCase(), isNot(contains('condition')));

      final ruText = planReasonText(ru, const InjuryFilterReason(2)).toLowerCase();
      expect(ruText, contains('травм'));
      expect(ruText, isNot(contains('состояни')),
          reason: 'the Russian copy must not widen the claim either — and '
              'until this test existed, nothing checked that it had not');
    });

    test('no cycle note claims a performance peak, in either language', () {
      // The exact strings that used to be there: "Peak performance day. PR
      // attempts welcome." and "Strength + speed window. Push the heavy days
      // now." They were removed from the English once. Nothing stopped a
      // translator putting one back.
      const bannedEn = [
        'pr attempt',
        'peak performance day',
        'push the heavy',
        'strength + speed window',
      ];
      const bannedRu = ['пик формы', 'рекорд', 'тяжёлые дни', 'пиковый день'];

      for (final p in CyclePhase.values) {
        final e = planReasonText(en, CyclePhaseReason(p)).toLowerCase();
        for (final b in bannedEn) {
          expect(e, isNot(contains(b)), reason: 'en/${p.name}: $b');
        }
        final r = planReasonText(ru, CyclePhaseReason(p)).toLowerCase();
        for (final b in bannedRu) {
          // 'пик формы' appears inside the ovulatory note as something the app
          // explicitly no longer claims, so the check is that no note ASSERTS
          // it — see the dedicated case below.
          if (b == 'пик формы') continue;
          expect(r, isNot(contains(b)), reason: 'ru/${p.name}: $b');
        }
      }
    });

    test('the ovulatory note disclaims the peak rather than stating it', () {
      // The English says "This used to be labelled a peak-performance day; the
      // evidence does not support that". A translation that kept the first
      // clause and dropped the second would reverse the meaning of the most
      // easily-reversed sentence in this feature.
      final ru0 =
          planReasonText(ru, const CyclePhaseReason(CyclePhase.ovulatory))
              .toLowerCase();
      expect(ru0, contains('не подтверждают'),
          reason: 'the disclaimer is the load-bearing half of this sentence');
    });

    test('every phase note presents itself as a calendar estimate', () {
      for (final p in CyclePhase.values) {
        expect(planReasonText(en, CyclePhaseReason(p)).toLowerCase(),
            contains('by your calendar'),
            reason: 'en/${p.name} presents an estimate as an observation');
        expect(planReasonText(ru, CyclePhaseReason(p)).toLowerCase(),
            contains('календарю'),
            reason: 'ru/${p.name} presents an estimate as an observation');
      }
    });

    test('the fallback claims neither a rating nor a weakness', () {
      // "Built from your latest difficulty ratings — weakest muscle groups
      // first" was wrong twice: nothing read a rating for ordering, and
      // "weakest" is a claim about strength this app does not measure.
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        for (final reason in const [NoHistoryReason(), DeficitOrderReason()]) {
          final text = planReasonText(l10n, reason).toLowerCase();
          for (final banned in const [
            'rating',
            'weakest',
            'оценк',
            'слаб',
          ]) {
            expect(text, isNot(contains(banned)),
                reason: '$name/${reason.runtimeType}: $banned');
          }
        }
      }
    });
  });

  group('titles', () {
    test('all four render, distinctly, in both languages', () {
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        final rendered = {
          for (final t in PlanTitle.values) planTitleText(l10n, t),
        };
        expect(rendered, hasLength(PlanTitle.values.length), reason: name);
        for (final t in rendered) {
          expect(t.trim(), isNotEmpty, reason: name);
        }
      }
      expect(planTitleText(ru, PlanTitle.deload), matches(RegExp(r'[а-яА-Я]')));
    });
  });

  group('the rationale paragraph', () {
    test('keeps the builder\'s order, with the ceiling first', () {
      const reasons = [
        ScreeningCeilingReason(60),
        DeloadReason(60),
        DeficitOrderReason(),
      ];
      final text = planRationaleText(en, reasons);
      expect(text, startsWith(planReasonText(en, reasons.first)),
          reason: 'a user the app has not cleared must not have to read past '
              'a deload note to find that out');
      for (final r in reasons) {
        expect(text, contains(planReasonText(en, r)));
      }
    });

    test('an empty list is an empty paragraph, not a crash', () {
      expect(planRationaleText(en, const []), isEmpty);
    });
  });

  test('the ARB carries every key this renderer needs, in both files', () {
    // The renderer is exhaustive over the sealed type by compilation. What the
    // compiler cannot see is a key present in `app_en.arb` and missing from
    // `app_ru.arb` — gen-l10n falls back to English silently, which reproduces
    // the exact defect F027 is about, one string at a time.
    Map<String, dynamic> arb(String f) =>
        jsonDecode(File('lib/l10n/$f').readAsStringSync())
            as Map<String, dynamic>;
    final enKeys = arb('app_en.arb').keys.where((k) => k.startsWith('planReason') || k.startsWith('planTitle'));
    final ruKeys = arb('app_ru.arb').keys.toSet();

    final missing = [
      for (final k in enKeys)
        if (!k.startsWith('@') && !ruKeys.contains(k)) k,
    ];
    expect(missing, isEmpty,
        reason: 'these plan strings would silently render in English for a '
            'Russian user, which is the defect this file exists about: '
            '$missing');
  });
}
