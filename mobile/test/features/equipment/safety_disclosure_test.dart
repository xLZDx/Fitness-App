import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/state/safety_coverage_providers.dart';
import 'package:fitness_app/features/equipment/widgets/safety_disclosure.dart';

/// Nothing may claim to have screened exercises against a user's injuries
/// while the catalog carries no tags to screen with.
///
/// This is the test whose absence let `0c4bf24` through. The legacy catalog
/// held the only 144 tagged exercises in the product; deleting it took
/// contraindication coverage to 0 of 1,887 and every "filtered for your
/// injuries" claim in the app stayed on screen, because a filter that cannot
/// fire is not a bug in the filter and nothing in the code could notice.
Widget _host(Widget child, {required SafetyScreeningLevel level}) {
  return ProviderScope(
    overrides: [
      safetyScreeningLevelProvider.overrideWithValue(level),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('SafetyDisclosure', () {
    testWidgets('shows while the catalog cannot be screened', (tester) async {
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.none),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not screened these exercises'),
        findsOneWidget,
      );
    });

    testWidgets('says what to do instead, not only what is missing',
        (tester) async {
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.none),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Check with a professional'), findsOneWidget);
    });

    testWidgets('does NOT disappear merely because tagging landed',
        (tester) async {
      // This test used to assert the opposite, and the promise it encoded was
      // wrong. S3b's tags are deterministic rules over movement names and
      // primary muscles -- a real screen, and not a clinical one. Letting the
      // banner vanish at the first tagged exercise would put the app back to
      // claiming its lists were checked for you, sourced differently.
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.rulesOnly),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not by a clinician'), findsOneWidget);
    });

    testWidgets('says something weaker rather than something softer',
        (tester) async {
      // "Nothing was screened" and "screened by rules" describe different
      // products. The second is not a gentler wording of the first.
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.rulesOnly),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not screened these exercises'), findsNothing);
      expect(find.textContaining('hide exercises that load an area'),
          findsOneWidget);
    });

    testWidgets('disappears once a clinician has reviewed the tags',
        (tester) async {
      // Still self-removing, just at the honest threshold:
      // kSafetyTagsClinicallyReviewed, not "any tag exists".
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.clinical),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
    });

    test('the review flag is still false, and the app says so', () {
      expect(kSafetyTagsClinicallyReviewed, isFalse,
          reason: 'flip this only when a clinician has actually signed off on '
              'core/contraindications/*.csv; the weaker banner then removes '
              'itself');
    });

    testWidgets('announces itself rather than waiting to be found',
        (tester) async {
      // A dialog interrupts and is then invisible forever after one dismissal;
      // a per-item badge implies the un-badged rows were checked and cleared.
      // A live region is announced when it appears and stays put.
      await tester.pumpWidget(
        _host(const SafetyDisclosure(), level: SafetyScreeningLevel.none),
      );
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
        find.ancestor(
          of: find.textContaining('not screened'),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    });

    testWidgets('compact drops the detail but never the claim', (tester) async {
      await tester.pumpWidget(
        _host(const SafetyDisclosure(compact: true), level: SafetyScreeningLevel.none),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not screened these exercises'),
          findsOneWidget);
      expect(find.textContaining('Check with a professional'), findsNothing);
    });
  });

  group('the shipped copy', () {
    late Map<String, dynamic> en;

    setUpAll(() {
      en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
    });

    test('no string promises that exercises are screened', () {
      // The eight always-false affordances, as a rule rather than a list, so a
      // ninth cannot be added without this failing. Phrases are matched rather
      // than keys because the claim is the thing being banned, wherever it
      // moves to.
      const banned = [
        'screened against your logged conditions',
        'Safe with the injuries you listed',
        'past injuries',
        'respects the injury filter',
        'injury filtering,',
      ];
      final offenders = <String>[];
      for (final entry in en.entries) {
        if (entry.key.startsWith('@') || entry.value is! String) continue;
        for (final phrase in banned) {
          if ((entry.value as String).contains(phrase)) {
            offenders.add('${entry.key}: "$phrase"');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'these claim the injury filter is screening exercises, '
              'which it cannot do until the catalog is tagged:\n'
              '${offenders.join("\n")}');
    });

    test('the disclosure strings exist in both locales', () {
      final ru = jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())
          as Map<String, dynamic>;
      for (final key in [
        'safetyFilterNotYetScreened',
        'safetyFilterNotYetScreenedDetail',
        'safetyFilterCoverage',
      ]) {
        expect(en[key], isA<String>(), reason: '$key missing from app_en.arb');
        expect(ru[key], isA<String>(), reason: '$key missing from app_ru.arb');
      }
    });

    test('coverage is an ICU plural, not a Dart-side ternary', () {
      // The project's own l10n guard test provably misses ternary-wrapped
      // Text(), which is how two untranslated strings already slipped past it.
      // An ICU plural cannot slip the same way.
      expect(en['safetyFilterCoverage'] as String, contains('plural'));
    });
  });

  group('the celebration modal', () {
    test('is gone rather than reworded', () {
      // It celebrated the first use of a filter that has never removed
      // anything, and it had zero callers -- dead code making the product's
      // strongest claim. Rewording dead code would have kept the maintenance
      // and none of the value.
      expect(
        File('lib/features/moments/widgets/injury_filter_celebration_modal.dart')
            .existsSync(),
        isFalse,
      );
    });
  });
}
