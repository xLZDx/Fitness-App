import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/features/workouts/widgets/set_timer_card.dart';

/// The card as a person meets it: the gate, the "I am ready" button, and the
/// repetition based set with its Done button.
class _SlowVoice extends MockVoiceCoach {
  _SlowVoice() : super(resolveText: (k) => k.name);
  final List<String> waited = <String>[];
  final List<Completer<void>> speeches = <Completer<void>>[];

  @override
  Future<void> sayAndWait(String text) {
    waited.add(text);
    final c = Completer<void>();
    speeches.add(c);
    return c.future;
  }
}

ExerciseItem _ex({
  String id = 'sq',
  String title = 'Goblet squat',
  String? equipmentId,
  List<String> steps = const ['Hold the weight at your chest. Sit back.'],
}) =>
    ExerciseItem(
      id: id,
      title: title,
      equipmentId: equipmentId,
      muscles: const ['legs'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: steps,
    );

const _plank = 'pl';

typedef _H = ({
  ProviderContainer c,
  SilentCuePlayer player,
  _SlowVoice voice,
});

Future<_H> _pump(
  WidgetTester t,
  ExerciseItem ex, {
  (double?, int?)? captured,
  bool voiceOn = true,
  Locale locale = const Locale('en'),
}) async {
  final player = SilentCuePlayer();
  final voice = _SlowVoice();
  final c = ProviderContainer(overrides: [
    cuePlayerProvider.overrideWithValue(player),
    voiceCoachProvider.overrideWithValue(voice),
  ]);
  addTearDown(c.dispose);
  _cur = c;
  if (captured != null) {
    c.read(setLoadProvider(ex.id).notifier).state =
        (weightKg: captured.$1, reps: captured.$2);
  }
  if (!voiceOn) c.read(setVoiceEnabledProvider.notifier).state = false;
  // Make sure no periodic timer outlives the test.
  addTearDown(() => c.read(setTimerProvider.notifier).reset());
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: SetTimerCard(exercise: ex)),
      ),
    ),
  ));
  return (c: c, player: player, voice: voice);
}

const _start = Key('workout.set_timer.primary');
const _ready = Key('workout.set_timer.ready');
const _done = Key('workout.set_timer.reps_done');
const _skip = Key('workout.set_timer.skip');
const _stop = Key('workout.set_timer.reset');
const _reps = Key('workout.set_timer.reps');
const _clock = Key('workout.set_timer.clock');

String _clockText(WidgetTester t) =>
    t.widget<Text>(find.byKey(_clock)).data ?? '';

Future<void> _tapStart(WidgetTester t) async {
  await t.tap(find.byKey(_start));
  await t.pump();
  await t.pump();
}

SetTimerState _st(_H h) => h.c.read(setTimerProvider);

ProviderContainer? _cur;

/// testWidgets that always stops the set timer and lets the intro's timeout
/// timer expire afterwards, so no periodic or timeout timer outlives the test.
void tw(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    _cur = null;
    await body(t);
    _cur?.read(setTimerProvider.notifier).reset();
    await t.pump(const Duration(seconds: 90));
  });
}

void main() {
  group('timed exercise (unchanged surface)', () {
    tw('idle shows the clock and the timed summary, no reps line',
        (t) async {
      final h = await _pump(t, _ex(id: _plank, title: 'Plank'));
      expect(find.byKey(_reps), findsNothing);
      expect(find.text('0:30'), findsOneWidget);
      expect(find.textContaining('s work'), findsOneWidget);
      expect(h.c.read(setPlanProvider(_ex(id: _plank, title: 'Plank')))
          .isRepBased, isFalse);
    });

    tw('timed work shows skip and no Done button', (t) async {
      final h = await _pump(t, _ex(id: _plank, title: 'Plank'), voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_ready));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);
      expect(find.byKey(_done), findsNothing);
      expect(find.byKey(_skip), findsOneWidget);
      expect(find.byKey(_reps), findsNothing);
      expect(_clockText(t), '0:30');
      await t.pump(const Duration(seconds: 1));
      expect(_clockText(t), '0:29');
    });

    tw('spoken intro uses the seconds wording', (t) async {
      final h = await _pump(t, _ex(id: _plank, title: 'Plank'));
      await _tapStart(t);
      expect(h.voice.waited.single, contains('seconds'));
      expect(h.voice.waited.single, isNot(contains('repetitions')));
    });
  });

  group('the briefing gate', () {
    tw('Start enters the gate: ready button hidden while speaking',
        (t) async {
      final h = await _pump(t, _ex());
      expect(find.byKey(_ready), findsNothing);
      await _tapStart(t);

      expect(_st(h).phase, SetPhase.briefing);
      expect(_st(h).introSpeaking, isTrue);
      expect(find.byKey(_ready), findsNothing);
      expect(find.text('LISTEN'), findsOneWidget);
      expect(h.voice.waited.single, contains('Goblet squat'));
      expect(h.voice.waited.single, contains('10 repetitions'),
          reason: 'rep based intro');
      expect(h.voice.waited.single, contains('Hold the weight at your chest.'),
          reason: 'first sentence of the first step is appended');
      expect(h.voice.waited.single, isNot(contains('Sit back.')),
          reason: 'only the first sentence');
    });

    tw('the ready button appears when the speech ends', (t) async {
      final h = await _pump(t, _ex());
      await _tapStart(t);
      h.voice.speeches.single.complete();
      await t.pump();
      await t.pump();
      expect(find.byKey(_ready), findsOneWidget);
      expect(find.text('I am ready'), findsOneWidget);
      expect(find.text('GET READY'), findsOneWidget);
    });

    tw('no clock runs in the gate and nothing sounds', (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      final before = _clockText(t);
      await t.pump(const Duration(minutes: 5));
      expect(_clockText(t), before);
      expect(h.player.played, isEmpty);
      expect(_st(h).phase, SetPhase.briefing);
      expect(find.byKey(_ready), findsOneWidget);
    });

    tw('voice off: the ready button is there at once', (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      expect(h.voice.waited, isEmpty);
      expect(find.byKey(_ready), findsOneWidget);
    });

    tw('tapping ready starts the countdown, ready disappears',
        (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_ready));
      await t.pump();
      expect(_st(h).phase, SetPhase.gettingReady);
      expect(_st(h).secondsLeft, 3);
      expect(find.byKey(_ready), findsNothing);
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);
      expect(h.player.played,
          [SetCue.tick, SetCue.tick, SetCue.startGong]);
    });

    tw('pause in the gate shows Resume and keeps the ready button',
        (t) async {
      final h = await _pump(t, _ex());
      await _tapStart(t);
      expect(find.text('Pause'), findsOneWidget);
      await t.tap(find.byKey(_start)); // Pause
      await t.pump();

      expect(_st(h).running, isFalse);
      expect(_st(h).phase, SetPhase.briefing);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.byKey(_ready), findsOneWidget,
          reason: 'the speech was cancelled, so the gate is shown');
      expect(h.voice.stopCalls, 1);
    });

    tw('resume does not repeat the intro', (t) async {
      final h = await _pump(t, _ex());
      await _tapStart(t);
      await t.tap(find.byKey(_start)); // pause
      await t.pump();
      await t.tap(find.byKey(_start)); // resume
      await t.pump();
      await t.pump();
      expect(h.voice.waited.length, 1);
      expect(_st(h).phase, SetPhase.briefing);
      expect(_st(h).running, isTrue);
    });

    tw('the ready button works while paused', (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_start)); // pause
      await t.pump();
      await t.tap(find.byKey(_ready));
      await t.pump();
      expect(_st(h).phase, SetPhase.gettingReady);
      expect(_st(h).running, isTrue);
    });

    tw('skip in the gate is ready', (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_skip));
      await t.pump();
      expect(_st(h).phase, SetPhase.gettingReady);
      expect(_st(h).setNumber, 0);
    });

    tw('stop in the gate resets to the idle card', (t) async {
      final h = await _pump(t, _ex());
      await _tapStart(t);
      await t.tap(find.byKey(_stop));
      await t.pump();
      expect(_st(h).isIdle, isTrue);
      expect(find.byKey(_ready), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(h.voice.stopCalls, 1);
    });
  });

  group('repetition based set', () {
    tw('idle: ring shows target reps, summary is in reps', (t) async {
      await _pump(t, _ex());
      expect(_clockText(t), '10');
      expect(find.text('10 reps'), findsOneWidget);
      expect(find.textContaining('10 reps'), findsWidgets);
      expect(find.textContaining('s work'), findsNothing);
    });

    tw('load known: "N reps · at X kg"', (t) async {
      await _pump(t, _ex(equipmentId: 'dumbbell'), captured: (40, 8));
      expect(_clockText(t), '8');
      expect(find.text('8 reps · at 40 kg'), findsOneWidget);
    });

    tw('fractional load keeps its decimals', (t) async {
      await _pump(t, _ex(equipmentId: 'barbell'), captured: (62.5, 5));
      expect(find.text('5 reps · at 62.5 kg'), findsOneWidget);
    });

    tw('the reps line is also shown in the gate', (t) async {
      await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      expect(find.byKey(_reps), findsOneWidget);
      expect(_clockText(t), '10');
    });

    Future<_H> toWork(WidgetTester t,
        {(double?, int?)? captured, ExerciseItem? ex}) async {
      final h = await _pump(t, ex ?? _ex(),
          captured: captured, voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_ready));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);
      return h;
    }

    tw('work: no clock, Done visible, skip hidden', (t) async {
      final h = await toWork(t);
      expect(find.byKey(_done), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(_skip), findsNothing);
      expect(find.byKey(_reps), findsOneWidget);
      expect(_clockText(t), '10');
      await t.pump(const Duration(minutes: 3));
      expect(_st(h).phase, SetPhase.work);
      expect(_clockText(t), '10');
    });

    tw('Done writes load and reps, then rest begins', (t) async {
      final h = await toWork(t, captured: (40, 8), ex: _ex(equipmentId: 'dumbbell'));
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(h.c.read(setLoadProvider('sq')), (weightKg: 40.0, reps: 8));
      expect(_st(h).phase, SetPhase.rest);
      expect(_st(h).secondsLeft, greaterThan(0));
      expect(find.byKey(_done), findsNothing);
      expect(find.byKey(_reps), findsNothing);
      expect(find.byKey(_skip), findsOneWidget);
      expect(h.player.played.last, SetCue.endGong);
    });

    tw('Done on a bodyweight move writes reps and a null load',
        (t) async {
      final h = await toWork(t);
      expect(h.c.read(setLoadProvider('sq')), isNull);
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(h.c.read(setLoadProvider('sq')), (weightKg: null, reps: 10));
    });

    tw('rest counts down and the next set is rep work again',
        (t) async {
      final h = await toWork(t);
      await t.tap(find.byKey(_done));
      await t.pump();
      final rest = _st(h).secondsLeft;
      await t.pump(Duration(seconds: rest));
      expect(_st(h).phase, SetPhase.work);
      expect(_st(h).setNumber, 2);
      expect(find.byKey(_done), findsOneWidget);
    });

    tw('Done on the last set ends the session', (t) async {
      final h = await toWork(t);
      final total = _st(h).totalSets;
      for (var i = 1; i <= total; i++) {
        expect(_st(h).setNumber, i);
        await t.tap(find.byKey(_done));
        await t.pump();
        if (i < total) {
          await t.pump(Duration(seconds: _st(h).secondsLeft));
        }
      }
      expect(_st(h).isDone, isTrue);
      expect(find.byKey(_done), findsNothing);
      expect(find.text('Again'), findsOneWidget);
      expect(h.player.played.last, SetCue.finished);
    });

    tw('the capture written by Done pre-fills the next plan',
        (t) async {
      final h = await toWork(t);
      await t.tap(find.byKey(_done));
      await t.pump();
      final plan = h.c.read(setPlanProvider(_ex()));
      expect(plan.prescription.targetReps, 10);
    });

    tw('Done pressed while paused moves to rest and the rest clock runs',
        (t) async {
      final h = await toWork(t);
      await t.tap(find.byKey(_start)); // Pause
      await t.pump();
      expect(_st(h).running, isFalse);
      expect(find.byKey(_done), findsOneWidget);
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(_st(h).phase, SetPhase.rest);
      expect(_st(h).running, isTrue);
      final left = _st(h).secondsLeft;
      await t.pump(const Duration(seconds: 1));
      expect(_st(h).secondsLeft, left - 1);
      expect(h.c.read(setLoadProvider('sq')), (weightKg: null, reps: 10),
          reason: 'bodyweight keeps the reps-only capture');
    });

    tw('last-set Done stops the clock immediately', (t) async {
      final h = await toWork(t);
      final total = _st(h).totalSets;
      for (var i = 1; i <= total; i++) {
        await t.tap(find.byKey(_done));
        await t.pump();
        if (i < total) await t.pump(Duration(seconds: _st(h).secondsLeft));
      }
      expect(_st(h).isDone, isTrue);
      final played = h.player.played.length;
      await t.pump(const Duration(seconds: 5));
      expect(h.player.played.length, played);
    });

    tw('loaded move with no weight writes no capture, so the question stays',
        (t) async {
      final ex = _ex(equipmentId: 'dumbbell');
      final h = await _pump(t, ex, voiceOn: false);
      await t.tap(find.byKey(_start));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      // Dismiss the weight sheet without answering.
      await t.tapAt(const Offset(5, 5));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(_st(h).phase, SetPhase.briefing);
      await t.tap(find.byKey(_ready));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(_st(h).phase, SetPhase.rest);
      expect(h.c.read(setLoadProvider('sq')), isNull,
          reason: 'a reps-only record would stop the weight question');
    });

    tw('loaded move with a known weight still records weight and reps',
        (t) async {
      final h = await toWork(t,
          captured: (40, 8), ex: _ex(equipmentId: 'dumbbell'));
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(h.c.read(setLoadProvider('sq')), (weightKg: 40.0, reps: 8));
    });
  });

  group('another exercise page and the rest header', () {
    tw('A running: the page for B shows idle, the dock state still shows A',
        (t) async {
      final h = await _pump(t, _ex(id: 'B'), voiceOn: false);
      final plan = h.c.read(setPlanProvider(_ex(id: 'B')));
      final ctl = h.c.read(setTimerProvider.notifier);
      ctl.start(plan, exerciseId: 'A');
      ctl.confirmReady();
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);

      expect(find.text('Start'), findsOneWidget);
      expect(find.byKey(_done), findsNothing);
      expect(find.byKey(_ready), findsNothing);
      expect(find.byKey(_stop), findsNothing);

      final raw = _st(h);
      expect(raw.exerciseId, 'A');
      expect(raw.running, isTrue);
      expect(raw.phase, SetPhase.work);
      final status = deriveActiveSessionStatus(
          setTimer: raw, rest: RestTimerState.idle, now: DateTime.utc(2026));
      expect(status, isNotNull);
      expect(status!.state, ActiveSessionState.running);
    });

    tw('Start on B replaces A, including when the plans are equal', (t) async {
      final h = await _pump(t, _ex(id: 'B'), voiceOn: false);
      final plan = h.c.read(setPlanProvider(_ex(id: 'B')));
      final ctl = h.c.read(setTimerProvider.notifier);
      ctl.start(plan, exerciseId: 'A');
      ctl.confirmReady();
      await t.pump(const Duration(seconds: 3));
      expect(_st(h).phase, SetPhase.work);

      await _tapStart(t);
      expect(_st(h).exerciseId, 'B');
      expect(_st(h).phase, SetPhase.briefing);
      expect(find.byKey(_ready), findsOneWidget);
    });

    tw('the page of the running exercise shows its own session', (t) async {
      final h = await _pump(t, _ex(id: 'B'), voiceOn: false);
      await _tapStart(t);
      expect(_st(h).exerciseId, 'B', reason: 'the card always passes its id');
      expect(find.byKey(_ready), findsOneWidget);
    });

    tw('header shows the NEXT set number during rest', (t) async {
      final h = await _pump(t, _ex(), voiceOn: false);
      await _tapStart(t);
      await t.tap(find.byKey(_ready));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(find.text('Set 1 of 3'), findsOneWidget, reason: 'during work');
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(_st(h).phase, SetPhase.rest);
      expect(find.text('Set 2 of 3'), findsOneWidget);
      expect(find.text('Set 1 of 3'), findsNothing);
    });

    tw('Russian header during rest is "Подход 2 из 3"', (t) async {
      await _pump(t, _ex(), voiceOn: false, locale: const Locale('ru'));
      await _tapStart(t);
      await t.tap(find.byKey(_ready));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.byKey(_done));
      await t.pump();
      expect(find.text('Подход 2 из 3'), findsOneWidget);
    });

    tw('the Russian skip label stays on one line at a narrow width',
        (t) async {
      t.view.physicalSize = const Size(360, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await _pump(t, _ex(), voiceOn: false, locale: const Locale('ru'));
      await _tapStart(t);
      final label = find.text('Пропустить');
      expect(label, findsOneWidget);
      expect(find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsOneWidget);
      final style = t.widget<Text>(label).style;
      final twoLines = (style?.fontSize ?? 14) * 2;
      expect(t.getSize(label).height, lessThan(twoLines),
          reason: 'a wrapped label would be at least two lines tall');
      expect(t.takeException(), isNull);
    });
  });

  group('Russian copy', () {
    tw('the gate and Done are localised', (t) async {
      final h = await _pump(t, _ex(), locale: const Locale('ru'));
      await _tapStart(t);
      expect(find.text('СЛУШАЙТЕ'), findsOneWidget);
      h.voice.speeches.single.complete();
      await t.pump();
      await t.pump();
      expect(find.text('Готов'), findsOneWidget);
    });
  });
}
