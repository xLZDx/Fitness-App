import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/modes/data/mode_codec.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:fitness_app/shared/widgets/shell_dock.dart';

import '../../support/s03_shell_harness.dart';

const Key _pill = ValueKey<String>('shell.dock.recordPill');
const Key _strip = ValueKey<String>('shell.dock.strip');
const Key _dock = ValueKey<String>('shell.dock');
const Key _railRec = ValueKey<String>('shell.rail.record');
const Key _rail = ValueKey<String>('shell.rail');

class _MemModeStore implements ModeStore {
  final Set<String> wiped = <String>{};
  @override
  Future<ModeRead> read(String uid) async => const ModeReadMissing();
  @override
  Future<ModeWriteResult> write(String uid, ModeState state) async =>
      ModeWriteResult.written;
  @override
  void markUidWiped(String uid) => wiped.add(uid);
  @override
  bool isUidWiped(String uid) => wiped.contains(uid);
}

List<Override> _fakes(SetTimerState s, RestTimerState r) => <Override>[
      setTimerProvider.overrideWith(() => FakeSetTimer(s)),
      restTimerProvider.overrideWith(() => FakeRestTimer(r)),
    ];

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Finder _skip(Key k) => find.byKey(k, skipOffstage: false);

void _startReal(ShellFixture f, {bool rest = false}) {
  if (rest) {
    f.container.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
  } else {
    f.container.read(setTimerProvider.notifier).start(kTestSetPlan);
  }
}

void main() {
  announcementTests();
  testWidgets('AC-ST-1 idle: pill on Home, Workouts, Progress only', (t) async {
    for (final p in kTabPaths) {
      await pumpShell(t, initial: p, overrides: _fakes(SetTimerState.idle, RestTimerState.idle));
      final expectPill = ['/home', '/workouts', '/progress'].contains(p);
      expect(find.byKey(_pill), expectPill ? findsOneWidget : findsNothing, reason: p);
      expect(find.byKey(_strip), findsNothing, reason: p);
    }
  });

  testWidgets('AC-ST-2 running set timer: strip on all five tabs, no pill', (t) async {
    for (final p in kTabPaths) {
      await pumpShell(t,
          initial: p,
          overrides: _fakes(setTimerState(SetPhase.work), RestTimerState.idle));
      expect(find.byKey(_strip), findsOneWidget, reason: p);
      expect(find.byKey(_pill), findsNothing, reason: p);
    }
  });

  group('AC-ST-3 state words', () {
    final cases = <String, (SetTimerState, RestTimerState Function(DateTime), String?, bool)>{
      'a-setWorkRunning': (setTimerState(SetPhase.work), (n) => RestTimerState.idle, 'stripWorkout', true),
      'b-setWorkPaused': (setTimerState(SetPhase.work, running: false), (n) => RestTimerState.idle, 'stripPaused', true),
      'c-setRestRunning': (setTimerState(SetPhase.rest), (n) => RestTimerState.idle, 'stripWorkout', true),
      'd-setGettingReady': (setTimerState(SetPhase.gettingReady), (n) => RestTimerState.idle, 'stripWorkout', true),
      'e-restRunning': (SetTimerState.idle, (n) => RestTimerState(total: const Duration(seconds: 60), endsAt: n.add(const Duration(seconds: 60))), 'stripResting', true),
      'f-restPaused': (SetTimerState.idle, (n) => const RestTimerState(total: Duration(seconds: 60), pausedRemaining: Duration(seconds: 20)), 'stripPaused', true),
      'g-restFinished1min': (SetTimerState.idle, (n) => RestTimerState(total: const Duration(seconds: 30), endsAt: n.subtract(const Duration(minutes: 1))), 'stripRestDone', true),
      'h-restFinished11min': (SetTimerState.idle, (n) => RestTimerState(total: const Duration(seconds: 30), endsAt: n.subtract(const Duration(minutes: 11))), null, false),
      'i-restIdle': (SetTimerState.idle, (n) => RestTimerState.idle, null, false),
      'j-setDone': (setTimerState(SetPhase.done), (n) => RestTimerState.idle, null, false),
    };
    for (final e in cases.entries) {
      testWidgets('AC-ST-3/${e.key}', (t) async {
        final l10n = await _en();
        final clock = TestClock();
        final (set, restOf, key, strip) = e.value;
        await pumpShell(t,
            clock: clock, overrides: _fakes(set, restOf(clock.now)));
        final words = <String, String>{
          'stripWorkout': l10n.stripWorkout,
          'stripPaused': l10n.stripPaused,
          'stripResting': l10n.stripResting,
          'stripRestDone': l10n.stripRestDone,
        };
        expect(find.byKey(_strip), strip ? findsOneWidget : findsNothing);
        expect(find.byKey(_pill), strip ? findsNothing : findsOneWidget);
        if (key != null) {
          expect(find.text(words[key]!), findsOneWidget);
          for (final other in words.entries.where((w) => w.key != key)) {
            expect(find.text(other.value), findsNothing, reason: other.key);
          }
        }
        if (e.key == 'e-restRunning') expect(find.text('1:00'), findsOneWidget);
      });
    }
  });

  testWidgets('AC-ST-4 a mode switch does not touch the running timers', (t) async {
    final clock = TestClock();
    final h = t.ensureSemantics();
    final f = await pumpShell(t, clock: clock, overrides: [
      ...realTimerOverrides(clock),
      modeStoreProvider.overrideWithValue(_MemModeStore()),
    ]);
    _startReal(f);
    f.container.read(restTimerProvider.notifier).start(const Duration(seconds: 90));
    await t.pump(const Duration(seconds: 1));
    final setCtl = f.container.read(setTimerProvider.notifier);
    final restCtl = f.container.read(restTimerProvider.notifier);
    final label = t.getSemantics(find.byKey(_strip)).label;
    final setBefore = f.container.read(setTimerProvider);
    final restBefore = f.container.read(restTimerProvider);
    await f.container.read(modeStateProvider.future);
    final r = await f.container.read(modeStateProvider.notifier).selectMode(AppMode.body);
    expect(r, ModeSaveResult.saved, reason: 'the switch must really happen');
    await t.pump();
    expect(identical(f.container.read(setTimerProvider.notifier), setCtl), isTrue);
    expect(identical(f.container.read(restTimerProvider.notifier), restCtl), isTrue);
    expect(f.container.read(restTimerProvider).endsAt, restBefore.endsAt);
    expect(t.getSemantics(find.byKey(_strip)).label, label);
    clock.advance(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    final setAfter = f.container.read(setTimerProvider);
    expect(setAfter.phase != setBefore.phase || setAfter.secondsLeft != setBefore.secondsLeft, isTrue,
        reason: 'the set timer must still tick');
    h.dispose();
  });

  group('AC-ST-5 tap target', () {
    testWidgets('AC-ST-5/storedDestination', (t) async {
      final clock = TestClock();
      final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
      f.container.read(activeSessionOwnerProvider.notifier)
          .capture(uid: 'uidA', destination: '/workout/ex1?day=d1');
      _startReal(f);
      await t.pump();
      await t.tap(find.byKey(_strip));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('workout-stub:/workout/ex1?day=d1'), findsOneWidget);
    });
    testWidgets('AC-ST-5/emptyDestination goes to /workouts', (t) async {
      final clock = TestClock();
      final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
      _startReal(f);
      await t.pump();
      await t.tap(find.byKey(_strip));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(f.location, '/workouts');
    });
  });

  testWidgets('AC-ST-6 last list item stays above the strip', (t) async {
    await pumpShell(t,
        rows: 40, overrides: _fakes(setTimerState(SetPhase.work), RestTimerState.idle));
    final pos = t
        .state<ScrollableState>(find
            .ancestor(of: find.byKey(const Key('row.0')), matching: find.byType(Scrollable))
            .first)
        .position;
    for (int i = 0; i < 4; i++) {
      pos.jumpTo(pos.maxScrollExtent);
      await t.pump();
    }
    final last = t.getBottomLeft(find.byKey(const Key('row.39'))).dy;
    final stripTop = t.getTopLeft(find.byKey(_strip)).dy;
    expect(last, lessThanOrEqualTo(stripTop),
        reason: 'last row bottom $last under strip top $stripTop');
  });

  testWidgets('AC-ST-7 no dock on a pushed route', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t,
        initial: '/workout/x1', clock: clock, overrides: realTimerOverrides(clock));
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
        .read(setTimerProvider.notifier)
        .start(kTestSetPlan);
    await t.pump();
    expect(f.location, '/workout/x1');
    expect(_skip(_dock), findsNothing);
    expect(_skip(_strip), findsNothing);
    expect(_skip(_pill), findsNothing);
  });

  testWidgets('AC-ST-8 process death: a new scope has no strip and no recovery claim', (t) async {
    // Timers are memory-only: no persistence in the two providers (contract R-S5).
    final clock = TestClock();
    final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
    _startReal(f);
    await t.pump();
    expect(find.byKey(_strip), findsOneWidget);
    final f2 = await pumpShell(t, clock: TestClock(), overrides: realTimerOverrides(TestClock()));
    expect(f2.container.read(setTimerProvider).phase, SetPhase.idle);
    expect(find.byKey(_strip), findsNothing);
    expect(find.textContaining(RegExp('recover|restor|resum', caseSensitive: false)), findsNothing);
  });

  group('AC-ST-9 compaction at 360x480 scale 2.0', () {
    testWidgets('AC-ST-9/pill is the 48x48 icon variant', (t) async {
      final h = t.ensureSemantics();
      await pumpShell(t, size: const Size(360, 480), textScale: 2.0);
      final s = t.getSize(find.descendant(of: find.byKey(_pill), matching: find.byType(HudPanel).evaluate().isNotEmpty ? find.byType(HudPanel) : find.byType(HudButton)).first);
      expect(s, const Size(48, 48), reason: 'pill measured $s');
      expect(
          find.descendant(
              of: find.byKey(_pill),
              matching: find.byWidgetPredicate((w) =>
                  w is Semantics && (w.properties.label ?? '').isNotEmpty)),
          findsWidgets,
          reason: 'pill needs an accessible name');
      h.dispose();
    });
    testWidgets('AC-ST-9/strip is one line with a name', (t) async {
      final h = t.ensureSemantics();
      await pumpShell(t,
          size: const Size(360, 480),
          textScale: 2.0,
          overrides: _fakes(setTimerState(SetPhase.work), RestTimerState.idle));
      expect(find.text('Train'), findsNothing, reason: 'single line: no mode line');
      expect(
          find.descendant(
              of: find.byKey(_strip),
              matching: find.byWidgetPredicate((w) =>
                  w is Semantics && (w.properties.label ?? '').isNotEmpty)),
          findsWidgets,
          reason: 'strip needs an accessible name');
      h.dispose();
    });
  });

  testWidgets('AC-SH-5 pill and strip are never in one frame', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
    void check(String when) {
      final both = _skip(_pill).evaluate().isNotEmpty && _skip(_strip).evaluate().isNotEmpty;
      expect(both, isFalse, reason: 'both widgets in one frame: $when');
    }

    check('idle');
    _startReal(f);
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
      check('after start $i');
    }
    f.container.read(setTimerProvider.notifier).reset();
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
      check('after end $i');
    }
    expect(find.byKey(_pill), findsOneWidget);
  });

  group('rail Record slot', () {
    testWidgets('AC-WS-7a idle: Record slot on all five tabs, no dock', (t) async {
      for (final p in kTabPaths) {
        await pumpShell(t, size: const Size(1100, 800), initial: p);
        expect(find.byKey(_railRec), findsOneWidget, reason: p);
        expect(_skip(_dock), findsNothing, reason: p);
        final panel = t.widget<HudPanel>(find.descendant(of: find.byKey(_railRec), matching: find.byType(HudPanel)).first);
        expect(panel.onTap, isNotNull, reason: '$p: slot must be enabled');
      }
    });
    testWidgets('AC-WS-7b running: slot shows the session on all five tabs', (t) async {
      final l10n = await _en();
      for (final p in kTabPaths) {
        await pumpShell(t,
            size: const Size(1100, 800),
            initial: p,
            overrides: _fakes(setTimerState(SetPhase.work), RestTimerState.idle));
        final inSlot = find.descendant(
            of: find.byKey(_railRec),
            matching: find.byWidgetPredicate((w) =>
                w is Text &&
                (w.data == l10n.railStateRunning || w.data == l10n.stripWorkout)));
        expect(inSlot, findsOneWidget, reason: p);
      }
    });
    testWidgets('AC-WS-7c tapping the idle slot calls the Record sheet opener', (t) async {
      int calls = 0;
      GlobalKey? seen;
      await pumpShell(t, size: const Size(1100, 800), overrides: [
        shellRecordSheetOpenerProvider.overrideWithValue((ctx, {anchorKey}) {
          calls++;
          seen = anchorKey;
        }),
      ]);
      await t.tap(find.byKey(_railRec));
      await t.pump();
      expect(calls, 1);
      expect(seen, isNotNull, reason: 'the rail Record tap must pass its anchor key');
    });
    testWidgets('AC-WS-12 the Progress destination never moves', (t) async {
      for (final running in [false, true]) {
        Offset? first;
        for (final p in kTabPaths) {
          await pumpShell(t,
              size: const Size(1100, 800),
              initial: p,
              overrides: running
                  ? _fakes(setTimerState(SetPhase.work), RestTimerState.idle)
                  : const <Override>[]);
          final tile = find.descendant(
              of: find.byKey(_rail), matching: find.text('PROGRESS'));
          final top = t.getTopLeft(tile);
          first ??= top;
          expect(top, first, reason: '$p running=$running');
        }
      }
    });
    testWidgets('AC-WS-13 ru: state word and minutes in the slot', (t) async {
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      List<String> slotTexts() => find
          .descendant(of: find.byKey(_railRec), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .toList();
      await pumpShell(t, size: const Size(1100, 800), locale: const Locale('ru'));
      expect(slotTexts(), contains(ru.recordPill));
      await pumpShell(t,
          size: const Size(1100, 800),
          locale: const Locale('ru'),
          overrides: _fakes(setTimerState(SetPhase.work), RestTimerState.idle));
      final running = slotTexts();
      expect(t.takeException(), isNull);
      await pumpShell(t,
          size: const Size(1100, 800),
          locale: const Locale('ru'),
          overrides: _fakes(setTimerState(SetPhase.work, running: false), RestTimerState.idle));
      final paused = slotTexts();
      expect(t.takeException(), isNull);
      expect(running.any((s) => s.contains(':') || s.contains(ru.railMinutes(2))), isTrue,
          reason: 'minutes missing: $running');
      expect(running, isNot(equals(paused)), reason: 'running and paused must differ');
    });
  });

  testWidgets('DT-07-1 throwing providers hide the strip, never break the shell', (t) async {
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    late ShellFixture f;
    try {
      f = await pumpShell(t, overrides: [
        setTimerProvider.overrideWith(() => FakeSetTimer(SetTimerState.idle, throwOnBuild: true)),
        restTimerProvider.overrideWith(() => FakeRestTimer(RestTimerState.idle, throwOnBuild: true)),
      ]);
      expect(t.takeException(), isNull);
      expect(find.byKey(_strip), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      await f.go('/workouts');
      expect(f.location, '/workouts');
    } finally {
      debugPrint = old;
    }
    final joined = logs.join(' | ');
    expect(joined, contains('derive_failed'));
    expect(joined, isNot(contains('SECRET')));
  });

  testWidgets('DT-07-6 narrow-and-short window collapses the strip to one line', (t) async {
    final f = await pumpShell(t,
        overrides: _fakes(setTimerState(SetPhase.work, running: false), RestTimerState.idle));
    expect(find.text('Train'), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
    await resizeTo(t, const Size(580, 340));
    expect(t.takeException(), isNull);
    expect(find.text('Train'), findsNothing, reason: 'collapsed to one line');
    expect(find.text('2:05'), findsOneWidget, reason: 'timer text continuous');
    await resizeTo(t, const Size(360, 800));
    expect(find.text('Train'), findsOneWidget, reason: 'returns when tall again');
    expect(f.location, '/home');
  });

  testWidgets('DT-07-7 reduced motion: the strip is in the tree after one pump', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t,
        disableAnimations: true, clock: clock, overrides: realTimerOverrides(clock));
    expect(find.byKey(_strip), findsNothing);
    _startReal(f);
    await t.pump();
    expect(find.byKey(_strip), findsOneWidget);
  });

  testWidgets('DT-07-8 account B never sees account A running session', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
    f.container.read(activeSessionOwnerProvider.notifier)
        .capture(uid: 'uidA', destination: '/workout/ex1');
    _startReal(f);
    await t.pump();
    expect(find.byKey(_strip), findsOneWidget);
    f.auth.add(kUserB);
    await t.pump();
    await t.pump();
    for (final p in ['/home', '/workouts']) {
      await f.go(p);
      expect(find.byKey(_strip), findsNothing, reason: 'strip for B on $p');
      expect(find.byKey(_pill), findsNothing,
          reason: 'design F-11/RV-4: strip AND pill are hidden for another account ($p)');
    }
    expect(f.container.read(activeSessionForeignOwnerProvider), isTrue);
    expect(f.container.read(activeSessionOwnerProvider), isNotNull,
        reason: 'owner is kept while the timer runs (decision)');
    final s = f.container.read(setTimerProvider);
    expect(s.running, isTrue);
    await t.pump(const Duration(seconds: 5));
    expect(f.container.read(setTimerProvider).secondsLeft != s.secondsLeft ||
        f.container.read(setTimerProvider).phase != s.phase, isTrue);
  });

  testWidgets('DT-07-9 strip changes state at endsAt and goes after 10 minutes', (t) async {
    final l10n = await _en();
    final clock = TestClock();
    final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
    f.container.read(restTimerProvider.notifier).start(const Duration(seconds: 30));
    await t.pump();
    expect(find.text(l10n.stripResting), findsOneWidget);
    clock.advance(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 30));
    expect(find.text(l10n.stripRestDone), findsOneWidget,
        reason: 'no user action: the status must change by itself at endsAt');
    clock.advance(const Duration(minutes: 10));
    await t.pump(const Duration(minutes: 10));
    expect(find.byKey(_strip), findsNothing);
    expect(find.byKey(_pill), findsOneWidget);
  });

  testWidgets('DT-07-11 dock appearing grows the scroll clearance by the dock height', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t,
        initial: '/scan', rows: 40, clock: clock, overrides: realTimerOverrides(clock));
    final pos = t
        .state<ScrollableState>(find
            .ancestor(of: find.byKey(const Key('row.0')), matching: find.byType(Scrollable))
            .first)
        .position;
    for (int i = 0; i < 4; i++) {
      pos.jumpTo(pos.maxScrollExtent);
      await t.pump();
    }
    final extent0 = pos.maxScrollExtent;
    final y0 = t.getTopLeft(find.byKey(const Key('row.39'))).dy;
    _startReal(f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 90));
    final mid = pos.maxScrollExtent - extent0;
    expect(mid, greaterThan(0), reason: 'clearance should have started to grow');
    expect(mid, lessThan(68), reason: 'and still be animating (not a jump)');
    await t.pump(const Duration(milliseconds: 400));
    expect(pos.maxScrollExtent - extent0, closeTo(68, 1));
    expect((t.getTopLeft(find.byKey(const Key('row.39'))).dy - y0).abs(), lessThanOrEqualTo(68));
  });

  testWidgets('DT-07-13 timers survive tab visits and presentation swaps', (t) async {
    final clock = TestClock();
    final f = await pumpShell(t,
        initial: '/workouts', clock: clock, overrides: realTimerOverrides(clock));
    _startReal(f);
    final setCtl = f.container.read(setTimerProvider.notifier);
    final restCtl = f.container.read(restTimerProvider.notifier);
    int prev = f.container.read(setTimerProvider).secondsLeft;
    PhaseHolder.phase = f.container.read(setTimerProvider).phase;
    Future<void> step(String what) async {
      await t.pump(const Duration(seconds: 1));
      final s = f.container.read(setTimerProvider);
      expect(identical(f.container.read(setTimerProvider.notifier), setCtl), isTrue, reason: what);
      expect(identical(f.container.read(restTimerProvider.notifier), restCtl), isTrue, reason: what);
      expect(s.running, isTrue, reason: what);
      expect(s.secondsLeft != prev || s.phase != PhaseHolder.phase, isTrue,
          reason: 'still ticking after $what');
      prev = s.secondsLeft;
      PhaseHolder.phase = s.phase;
    }

    for (final p in kTabPaths) {
      await f.go(p);
      await step('visit $p');
    }
    await resizeTo(t, const Size(1100, 800));
    await step('rail');
    await resizeTo(t, const Size(360, 800));
    await step('bar');
  });
}

class PhaseHolder {
  static SetPhase phase = SetPhase.idle;
}

List<String> _captureAnnouncements() {
  final out = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
    if (m is Map && m['type'] == 'announce') {
      out.add((m['data'] as Map)['message'] as String);
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return out;
}

void announcementTests() {
  group('AC-A11Y-4 session announcements', () {
    testWidgets('started, paused, resumed, ended for the signed-in owner', (t) async {
      final l10n = await _en();
      final said = _captureAnnouncements();
      final clock = TestClock();
      final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
      f.container.read(activeSessionOwnerProvider.notifier)
          .capture(uid: 'uidA', destination: '/workout/ex1');
      final ctl = f.container.read(setTimerProvider.notifier);
      ctl.start(kTestSetPlan);
      await t.pump();
      expect(said, [l10n.stripSessionStarted]);
      ctl.pause();
      await t.pump();
      expect(said.last, l10n.stripPaused);
      ctl.start(kTestSetPlan);
      await t.pump();
      expect(said.last, l10n.stripSessionResumed);
      await t.pump(const Duration(seconds: 30));
      final n = said.length;
      await t.pump(const Duration(seconds: 30));
      expect(said.length, n, reason: 'the tick must never announce');
      ctl.reset();
      await t.pump();
      expect(said.last, l10n.stripSessionEnded);
      expect(said.length, n + 1);
    });

    testWidgets('a rest-only status announces neither started nor ended, but pause and resume', (t) async {
      final l10n = await _en();
      final said = _captureAnnouncements();
      final clock = TestClock();
      final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
      final rest = f.container.read(restTimerProvider.notifier);
      rest.start(const Duration(seconds: 60));
      await t.pump();
      expect(find.byKey(_strip), findsOneWidget);
      expect(said, isEmpty, reason: 'resting must not announce "started": $said');
      rest.pause();
      await t.pump();
      expect(said, [l10n.stripPaused]);
      rest.resume();
      await t.pump();
      expect(said.last, l10n.stripSessionResumed);
      final n = said.length;
      clock.advance(const Duration(seconds: 61));
      await t.pump(const Duration(seconds: 61));
      expect(find.text(l10n.stripRestDone), findsOneWidget);
      clock.advance(const Duration(minutes: 11));
      await t.pump(const Duration(minutes: 11));
      expect(find.byKey(_strip), findsNothing);
      expect(said.length, n, reason: 'rest finished/ended must not announce: $said');
    });

    testWidgets('an account switch announces nothing', (t) async {
      final said = _captureAnnouncements();
      final clock = TestClock();
      final f = await pumpShell(t, clock: clock, overrides: realTimerOverrides(clock));
      f.container.read(activeSessionOwnerProvider.notifier)
          .capture(uid: 'uidA', destination: '/workout/ex1');
      f.container.read(setTimerProvider.notifier).start(kTestSetPlan);
      await t.pump();
      expect(said.length, 1);
      f.auth.add(kUserB);
      await t.pump();
      await t.pump();
      expect(find.byKey(_strip), findsNothing);
      expect(said.length, 1, reason: 'status turning null for B must stay silent: $said');
    });
  });
}