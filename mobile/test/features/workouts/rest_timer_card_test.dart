import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/widgets/rest_timer.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart';

/// The card, as opposed to the state machine next door.
///
/// Two things are only checkable here: that the controls are wired to the
/// controller, and that the copy is localised — the card carried four
/// hardcoded English sentences into the Russian UI, which §34 lists as
/// forbidden outright.

class _Clock {
  DateTime now = DateTime.utc(2026, 8, 6, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Records the haptics the card asks for.
///
/// `HapticFeedback` goes out over `SystemChannels.platform`, which in a widget
/// test has no handler at all — the call silently succeeds and leaves no trace.
/// Without intercepting it, "an elapsed rest buzzes and a skipped one does not"
/// is unassertable.
List<String> _captureHaptics(WidgetTester t) {
  final seen = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        seen.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(() => t.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return seen;
}

Widget _app(ProviderContainer c, {Locale locale = const Locale('en')}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RestTimer()),
      ),
    );

({ProviderContainer c, _Clock clock}) _harness() {
  final clock = _Clock();
  final c = ProviderContainer(overrides: [
    restClockProvider.overrideWithValue(clock.call),
  ]);
  addTearDown(c.dispose);
  return (c: c, clock: clock);
}

void main() {
  testWidgets('it shows the time left', (t) async {
    final h = _harness();
    h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
    await t.pumpWidget(_app(h.c));

    expect(find.byKey(const Key('rest-timer.remaining')), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
  });

  testWidgets('skip ends the rest', (t) async {
    final h = _harness();
    h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
    await t.pumpWidget(_app(h.c));

    await t.tap(find.byKey(const Key('rest-timer.skip')));
    await t.pump();

    expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now),
        RestOutcome.skipped);
    // The controls go away with the rest: a Skip button on a finished rest is
    // an invitation to press something that does nothing.
    expect(find.byKey(const Key('rest-timer.skip')), findsNothing);
    expect(find.byKey(const Key('rest-timer.add')), findsNothing);
  });

  testWidgets('+30 s extends it', (t) async {
    final h = _harness();
    h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
    await t.pumpWidget(_app(h.c));
    expect(find.text('1:00'), findsOneWidget);

    await t.tap(find.byKey(const Key('rest-timer.add')));
    await t.pump();

    expect(find.text('1:30'), findsOneWidget);
  });

  testWidgets('pause and resume swap the button', (t) async {
    final h = _harness();
    h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
    await t.pumpWidget(_app(h.c));

    await t.tap(find.byKey(const Key('rest-timer.pause')));
    await t.pump();
    expect(h.c.read(restTimerProvider).isPaused, isTrue);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await t.tap(find.byKey(const Key('rest-timer.pause')));
    await t.pump();
    expect(h.c.read(restTimerProvider).isPaused, isFalse);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('it reports how the rest ended, once', (t) async {
    final outcomes = <RestOutcome>[];
    final h = _harness();
    h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));

    await t.pumpWidget(UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RestTimer(onFinished: outcomes.add)),
      ),
    ));

    await t.tap(find.byKey(const Key('rest-timer.skip')));
    await t.pump();
    await t.pump();
    // Repainting must not re-announce: the callback is a hand-off to the next
    // set, and firing it twice would advance twice.
    await t.pump();

    expect(outcomes, [RestOutcome.skipped]);
  });

  group('accessibility', () {
    // GPT-PM round 1 (2026-08-30 Session gate): swapping the stock
    // `CircularProgressIndicator` for `HudRing` dropped the automatic
    // progress-role semantic value the old widget supplied for free --
    // `HudRing` only wraps in `Semantics` when given a `semanticsLabel`,
    // and that path excludes its child's own semantics, which would have
    // silenced the countdown text instead. `rest_timer.dart` now wraps the
    // ring itself in one explicit `Semantics(label:, value:, excludeSemantics:
    // true)` node. This proves that node actually carries both pieces of
    // information, running and finished, rather than only removing the
    // regression from view.
    testWidgets('a running rest reports the title and the time left', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      final harness = _harness();
      harness.c.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
      await t.pumpWidget(_app(harness.c));

      expect(
        t.getSemantics(find.byType(HudRing)),
        matchesSemantics(label: 'Rest', value: '1:30'),
      );
      h.dispose();
    });

    testWidgets('a finished rest still reports a value, not silence', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      final harness = _harness();
      harness.c.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
      await t.pumpWidget(_app(harness.c));

      await t.tap(find.byKey(const Key('rest-timer.skip')));
      await t.pump();

      expect(
        t.getSemantics(find.byType(HudRing)),
        matchesSemantics(label: 'Rest', value: '0:00'),
      );
      h.dispose();
    });
  });

  group('the copy is localised', () {
    // It was not. `rest_timer.dart` shipped 'Rest timer', 'Rest complete —
    // next set', 'Tap to reset for the next round.' and 'Auto-stops your
    // phone — focus on the next set.' as literals, so a Russian user read
    // English in the middle of a set. §34: "hardcoded English in localised
    // UI" is on the forbidden list.

    testWidgets('Russian shows Russian', (t) async {
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(_app(h.c, locale: const Locale('ru')));

      expect(find.text('Отдых'), findsOneWidget);
      expect(find.text('Пропустить'), findsOneWidget);
      expect(find.text('+30 с'), findsOneWidget);
      expect(find.text('Rest'), findsNothing);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('English shows English', (t) async {
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(_app(h.c));

      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('a finished rest says so in the right language', (t) async {
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(_app(h.c, locale: const Locale('ru')));

      await t.tap(find.byKey(const Key('rest-timer.skip')));
      await t.pump();

      expect(find.text('Отдых пропущен'), findsOneWidget);
    });
  });

  group('a rest that simply runs out', () {
    // The most common real case, and it was untested: every finished-state test
    // reached "done" by pressing Skip, so the elapsed branch of the switch, the
    // ring colour and the haptic were never exercised. Found by the test-coverage
    // review, and it was right — the widget's own `Timer.periodic` never fired in
    // any test either, because every pump was `t.pump()` with no duration.

    testWidgets('the card finishes itself when the deadline passes', (t) async {
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(_app(h.c));
      expect(find.byKey(const Key('rest-timer.skip')), findsOneWidget);

      // The injected clock and the test binding's clock are separate: pumping a
      // duration fires the widget's ticker, advancing this one is what makes the
      // deadline actually past.
      h.clock.advance(const Duration(seconds: 61));
      await t.pump(const Duration(seconds: 1));

      expect(find.text('Rest complete'), findsOneWidget);
      expect(find.byKey(const Key('rest-timer.skip')), findsNothing);
      expect(find.byKey(const Key('rest-timer.add')), findsNothing);
      expect(find.byKey(const Key('rest-timer.pause')), findsNothing);
      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('an elapsed rest buzzes and a skipped one does not', (t) async {
      final haptics = _captureHaptics(t);
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(_app(h.c));
      expect(haptics, isEmpty);

      h.clock.advance(const Duration(seconds: 61));
      await t.pump(const Duration(seconds: 1));
      await t.pump();

      expect(haptics, ['HapticFeedbackType.heavyImpact']);

      // And a skip on a fresh rest stays silent.
      haptics.clear();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pump();
      await t.tap(find.byKey(const Key('rest-timer.skip')));
      await t.pump();
      await t.pump();

      expect(haptics, isEmpty);
    });

    testWidgets('it does not announce twice while it sits there', (t) async {
      final outcomes = <RestOutcome>[];
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 60));
      await t.pumpWidget(UncontrolledProviderScope(
        container: h.c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RestTimer(onFinished: outcomes.add)),
        ),
      ));

      h.clock.advance(const Duration(seconds: 61));
      // Five more ticks after it is already over.
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(seconds: 1));
      }

      expect(outcomes, [RestOutcome.elapsed]);
    });

    testWidgets('a rest that ended while the card was away shows as ended',
        (t) async {
      // The reviewers' BLOCKER, at the widget layer: the card is mounted for
      // the first time only AFTER the deadline has already passed. Nothing
      // observed the transition, and it still has to read as finished on the
      // very first frame — not for one second as a running timer at 0:00.
      final h = _harness();
      h.c.read(restTimerProvider.notifier).start(const Duration(seconds: 30));
      h.clock.advance(const Duration(minutes: 4));

      await t.pumpWidget(_app(h.c));

      expect(find.text('Rest complete'), findsOneWidget);
      expect(find.byKey(const Key('rest-timer.skip')), findsNothing);
    });
  });
}
