import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/widgets/rest_timer.dart';

/// The card, as opposed to the state machine next door.
///
/// Two things are only checkable here: that the controls are wired to the
/// controller, and that the copy is localised — the card carried four
/// hardcoded English sentences into the Russian UI, which §34 lists as
/// forbidden outright.

class _Clock {
  DateTime now = DateTime.utc(2026, 8, 6, 12);
  DateTime call() => now;
}

Widget _app(ProviderContainer c, {Locale locale = const Locale('en')}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
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

    expect(h.c.read(restTimerProvider).outcome, RestOutcome.skipped);
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
}
