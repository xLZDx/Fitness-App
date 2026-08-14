import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/experimental_banner.dart';

/// A1 — the one item `ML_STRATEGY_2026-08-11.md:223-227` calls a gate before
/// release: the scanner, Form Coach and Posture must carry an explicit
/// experimental label.
///
/// The banner itself is nearly trivial. What is worth pinning is the part that
/// rots silently: the label word is rendered by the widget so three screens
/// cannot drift apart, and the disclosure has to survive the accessibility
/// text sizes where a fixed-height row would have clipped it — a disclosure
/// that is cut off is not a disclosure.

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ListView(children: [child])),
    );

void main() {
  testWidgets('shows the shared label word and the surface-specific sentence',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const ExperimentalBanner(message: 'Recognition can be wrong.'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Experimental'), findsOneWidget);
    expect(find.text('Recognition can be wrong.'), findsOneWidget);
    expect(find.byKey(const Key('experimental.banner')), findsOneWidget);
  });

  testWidgets('the label word follows the app language, the message does not',
      (tester) async {
    // The message is passed in already localized by the caller; the word is
    // this widget's own, which is what stops one screen saying "beta".
    await tester.pumpWidget(_wrap(
      const ExperimentalBanner(message: 'передан как есть'),
      locale: const Locale('ru'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Экспериментально'), findsOneWidget);
    expect(find.text('передан как есть'), findsOneWidget);
  });

  testWidgets('a long disclosure at 320dp and the largest text size is not '
      'clipped', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(_wrap(
      // The real Form Coach string, the longest of the three.
      const ExperimentalBanner(
        message: 'Rep counts and technique cues are approximate. They are not '
            'coaching, and they do not judge whether a movement is safe for you.',
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('experimental.banner')), findsOneWidget);
  });

  testWidgets('reads as ONE node, so a screen reader cannot deliver the '
      'warning without the text it qualifies', (tester) async {
    // This is the assertion that found the real defect: with
    // `Semantics(container: true)` the label word and the sentence were two
    // separate stops, and a user could swipe past having heard only
    // "Experimental".
    // Disposed inline, not via `addTearDown`: the framework verifies that no
    // semantics handle outlives the test body, and that check runs BEFORE
    // tear-downs, so the tidier-looking version fails on its own bookkeeping.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(
      const ExperimentalBanner(message: 'Not a medical assessment.'),
    ));
    await tester.pumpAndSettle();

    final semantics =
        tester.getSemantics(find.byKey(const Key('experimental.banner')));
    expect(semantics.label, contains('Experimental'));
    expect(semantics.label, contains('Not a medical assessment.'));
    handle.dispose();
  });
}
