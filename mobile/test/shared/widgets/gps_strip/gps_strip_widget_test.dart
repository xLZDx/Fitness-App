// EP-G S04-24 strip, rail slot, announcements and entry points (DT-24-7 to
// DT-24-12, DT-24-14, DT-24-19). The REAL MainShell, dock strip and rail slot
// run with the REAL RecorderController on scripted seams.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_flow.dart'
    show gpsRecordingPageOpenProvider;
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_codec.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/shared/widgets/dock_widgets.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/main_shell.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';

import '../../../features/recording/pages/recorder_harness.dart';
import '../../../support/s03_shell_harness.dart'
    show FakeSetTimer, TestClock, kTabPaths, kUserA, kUserB, setTimerState;

const Key _strip = ValueKey<String>('shell.dock.strip');
const Key _pill = ValueKey<String>('shell.dock.recordPill');
const Key _railRec = ValueKey<String>('shell.rail.record');

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

class _World {
  _World(this.t, this.seams, this.router, this.auth);
  final WidgetTester t;
  final Seams seams;
  final GoRouter router;
  final StreamController<AuthUser?> auth;

  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byType(MainShell)));
  String get top => router.routerDelegate.currentConfiguration.last.matchedLocation;

  Future<void> tick([Duration d = const Duration(milliseconds: 50)]) =>
      t.pump(d);

  Future<void> advance(Duration d) async {
    seams.env.now += d.inMilliseconds;
    await t.pump(d);
  }

  Future<void> startRecording() async {
    final ctl = c.read(recorderControllerProvider.notifier);
    unawaited(ctl.requestStart(sport: SportType.running));
    await t.pump();
    await t.pump();
    seams.emitFix();
    await t.pump();
    await advance(const Duration(seconds: 1));
    seams.emitFix();
    await t.pump();
  }

  Future<void> go(String p) async {
    router.go(p);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<_World> pump(
  WidgetTester t, {
  Size size = const Size(360, 800),
  Locale locale = const Locale('en'),
  String initial = '/home',
  AuthUser? user = kUserA,
  List<Override> extra = const <Override>[],
  bool gpsOn = true,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final seams = Seams();
  final auth = StreamController<AuthUser?>.broadcast();
  addTearDown(auth.close);
  final clock = TestClock();
  final router = GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      GoRoute(
          path: '/record/gps',
          builder: (_, __) => const Scaffold(body: Text('gps-page-stub'))),
      GoRoute(
          path: '/workout/:id',
          builder: (_, GoRouterState s) =>
              Scaffold(body: Text('workout-stub:${s.uri}'))),
      GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('settings-stub'))),
      ShellRoute(
        builder: (_, __, Widget child) => MainShell(child: child),
        routes: <RouteBase>[
          for (final String p in kTabPaths)
            GoRoute(
              path: p,
              pageBuilder: (_, GoRouterState s) => NoTransitionPage<void>(
                key: s.pageKey,
                child: HudScreenBody(children: <Widget>[
                  Text('stub-$p'),
                  for (int i = 0; i < 3; i++)
                    const SizedBox(height: 80, child: Text('row')),
                ]),
              ),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      restClockProvider.overrideWithValue(clock.call),
      authUserProvider.overrideWith((ref) async* {
        if (user != null) yield user;
        yield* auth.stream;
      }),
      modeStoreProvider.overrideWithValue(_MemModeStore()),
      if (gpsOn) gpsRecorderEnabledProvider.overrideWithValue(true),
      ...seams.overrides,
      ...extra,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (BuildContext ctx, Widget? child) =>
          WindowSizeScope(child: child ?? const SizedBox.shrink()),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return _World(t, seams, router, auth);
}

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));
Future<AppLocalizations> ru() =>
    AppLocalizations.delegate.load(const Locale('ru'));

/// Every node of the semantics tree, depth first.
Iterable<SemanticsNode> allNodes(WidgetTester t) sync* {
  final root = t.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return;
  final stack = <SemanticsNode>[root];
  while (stack.isNotEmpty) {
    final n = stack.removeLast();
    yield n;
    n.visitChildren((c) {
      stack.add(c);
      return true;
    });
  }
}

/// The strip node: the one that carries the open hint [hint].
SemanticsNode stripNode(WidgetTester t, String hint) =>
    allNodes(t).firstWhere((n) => n.hint == hint,
        orElse: () => fail('no semantics node with hint "$hint"'));

Finder skip(Key k) => find.byKey(k, skipOffstage: false);

void main() {
  group('DT-24-8 the GPS recording is visible on every tab', () {
    for (final p in kTabPaths) {
      testWidgets('/tab $p: strip with the GPS word, no Record pill',
          (t) async {
        final l10n = await en();
        final w = await pump(t, initial: p);
        expect(find.byKey(_strip), findsNothing, reason: 'idle: no strip');
        await w.startRecording();
        expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording);
        expect(find.byKey(_strip), findsOneWidget, reason: p);
        expect(find.byKey(_pill), findsNothing, reason: p);
        expect(find.text(l10n.gpsStripRecording), findsOneWidget);
      });
    }

    testWidgets('/gym-plus-gps shows GPS, not the gym word', (t) async {
      final l10n = await en();
      final w = await pump(t, extra: [
        setTimerProvider.overrideWith(
            () => FakeSetTimer(setTimerState(SetPhase.work))),
      ]);
      expect(find.text(l10n.stripWorkout), findsOneWidget,
          reason: 'gym alone shows the gym word');
      await w.startRecording();
      expect(find.text(l10n.gpsStripRecording), findsOneWidget);
      expect(find.text(l10n.stripWorkout), findsNothing);
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('acquiring shows the looking-for-GPS word and no time',
        (t) async {
      final l10n = await en();
      final w = await pump(t);
      final ctl = w.c.read(recorderControllerProvider.notifier);
      unawaited(ctl.requestStart(sport: SportType.running));
      await t.pump();
      await t.pump();
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.acquiring);
      expect(find.text(l10n.gpsStripAcquiring), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('flag off: the recorder is never mounted into the strip',
        (t) async {
      final w = await pump(t, gpsOn: false);
      expect(find.byKey(_strip), findsNothing);
      expect(find.byKey(_pill), findsOneWidget);
      expect(w.c.read(gpsRecorderEnabledProvider), isFalse);
    });
  });

  group('DT-24-9 label form and hint', () {
    final status = StateProvider<ActiveSessionStatus?>((ref) => null);

    ActiveSessionStatus gpsAt(int sec,
            {ActiveSessionState s = ActiveSessionState.recording}) =>
        ActiveSessionStatus(
          kind: ActiveSessionKind.gpsRecording,
          state: s,
          remaining: Duration(seconds: sec),
          countsUp: true,
          mode: '',
          destination: kGpsRecordingDestination,
          ownerUid: 'uidA',
        );

    testWidgets('/label-form: state, whole minutes, no seconds; hint '
        'gpsStripOpenHint; /stable-within-a-minute', (t) async {
      final h = t.ensureSemantics();
      final l10n = await en();
      final w = await pump(t, extra: [
        activeSessionStatusProvider.overrideWith((ref) => ref.watch(status)),
      ]);
      w.c.read(status.notifier).state = gpsAt(65);
      await t.pump();
      var node = stripNode(t, l10n.gpsStripOpenHint);
      expect(node.label, '${l10n.gpsStripRecording}, ${l10n.gpsUnitMinutes(1)}');
      expect(node.hint, l10n.gpsStripOpenHint);
      expect(RegExp(r'\d:\d\d').hasMatch(node.label), isFalse,
          reason: 'no m:ss clock in the spoken label');
      final first = node.label;
      w.c.read(status.notifier).state = gpsAt(95);
      await t.pump();
      node = stripNode(t, l10n.gpsStripOpenHint);
      expect(node.label, first, reason: 'unchanged within the same minute');
      w.c.read(status.notifier).state = gpsAt(125);
      await t.pump();
      node = stripNode(t, l10n.gpsStripOpenHint);
      expect(node.label, '${l10n.gpsStripRecording}, ${l10n.gpsUnitMinutes(2)}');
      h.dispose();
    });

    testWidgets('under one minute: only the state word is spoken', (t) async {
      final h = t.ensureSemantics();
      final l10n = await en();
      final w = await pump(t, extra: [
        activeSessionStatusProvider.overrideWith((ref) => ref.watch(status)),
      ]);
      w.c.read(status.notifier).state = gpsAt(30);
      await t.pump();
      expect(stripNode(t, l10n.gpsStripOpenHint).label, l10n.gpsStripRecording);
      h.dispose();
    });

    testWidgets('banner note becomes the third line and is spoken', (t) async {
      final h = t.ensureSemantics();
      final l10n = await en();
      final w = await pump(t, extra: [
        activeSessionStatusProvider.overrideWith((ref) => ref.watch(status)),
      ]);
      w.c.read(status.notifier).state = const ActiveSessionStatus(
          kind: ActiveSessionKind.gpsRecording,
          state: ActiveSessionState.recording,
          note: ActiveSessionNote.batteryCritical,
          destination: kGpsRecordingDestination);
      await t.pump();
      expect(find.text(l10n.gpsBannerShortBattery), findsOneWidget);
      expect(stripNode(t, l10n.gpsStripOpenHint).label,
          '${l10n.gpsStripRecording}, ${l10n.gpsBannerShortBattery}');
      w.c.read(status.notifier).state = const ActiveSessionStatus(
          kind: ActiveSessionKind.gpsRecording,
          state: ActiveSessionState.recording,
          note: ActiveSessionNote.storageWriteFailing,
          destination: kGpsRecordingDestination);
      await t.pump();
      expect(find.text(l10n.gpsBannerShortStorage), findsOneWidget);
      h.dispose();
    });

    testWidgets('a gym strip keeps its mode label and resume hint', (t) async {
      final h = t.ensureSemantics();
      final l10n = await en();
      await pump(t, gpsOn: false, extra: [
        setTimerProvider.overrideWith(
            () => FakeSetTimer(setTimerState(SetPhase.work))),
      ]);
      final node = stripNode(t, l10n.stripResumeHint);
      expect(node.hint, l10n.stripResumeHint);
      expect(node.label, contains(l10n.stripModeLabel('train')));
      h.dispose();
    });
  });

  group('DT-24-10 strip tap navigates, other shell actions change nothing', () {
    testWidgets('/strip-tap-navigates-no-modal', (t) async {
      final w = await pump(t);
      await w.startRecording();
      final callsBefore = List<String>.of(w.seams.journal.calls);
      await t.tap(find.byKey(_strip));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(w.top, '/record/gps');
      expect(find.text('gps-page-stub'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording);
      expect(w.seams.journal.calls, callsBefore,
          reason: 'navigating writes nothing');
    });

    testWidgets('/tab-change leaves the recording unchanged and writes nothing',
        (t) async {
      final w = await pump(t);
      await w.startRecording();
      final before = w.c.read(recorderControllerProvider);
      final callsBefore = List<String>.of(w.seams.journal.calls);
      for (final p in ['/workouts', '/progress', '/profile', '/home']) {
        await w.go(p);
        expect(find.byKey(_strip), findsOneWidget, reason: p);
      }
      final after = w.c.read(recorderControllerProvider);
      expect(after.phase, before.phase);
      expect(after.recordingId, before.recordingId);
      expect(w.seams.journal.calls, callsBefore);
      expect(w.seams.location.activeSubscriptions, 1);
      expect(w.seams.location.startCount, 1);
    });

    testWidgets('/mode-change leaves the recording and the strip unchanged',
        (t) async {
      final h = t.ensureSemantics();
      final w = await pump(t);
      await w.startRecording();
      final l10n = await en();
      final label = stripNode(t, l10n.gpsStripOpenHint).label;
      final callsBefore = List<String>.of(w.seams.journal.calls);
      await w.c.read(modeStateProvider.future);
      final r = await w.c
          .read(modeStateProvider.notifier)
          .selectMode(AppMode.body);
      expect(r, ModeSaveResult.saved, reason: 'the mode switch must happen');
      await t.pump();
      expect(find.byKey(_strip), findsOneWidget);
      expect(stripNode(t, l10n.gpsStripOpenHint).label, label);
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording);
      expect(w.seams.journal.calls, callsBefore);
      h.dispose();
    });

    testWidgets('/rotation leaves the recording unchanged', (t) async {
      final w = await pump(t);
      await w.startRecording();
      final id = w.c.read(recorderControllerProvider).recordingId;
      final l10n = await en();
      t.view.physicalSize = const Size(800, 360);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text(l10n.gpsRailRec), findsOneWidget,
          reason: 'landscape moves the recording into the rail slot');
      t.view.physicalSize = const Size(360, 800);
      await t.pump();
      expect(find.byKey(_strip), findsOneWidget);
      expect(w.c.read(recorderControllerProvider).recordingId, id);
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording);
      expect(t.takeException(), isNull);
    });
  });

  group('DT-24-7 and DT-24-11 every state renders in en and ru', () {
    String stripWord(AppLocalizations l, ActiveSessionState s) => switch (s) {
          ActiveSessionState.running => l.stripWorkout,
          ActiveSessionState.paused => l.stripPaused,
          ActiveSessionState.resting => l.stripResting,
          ActiveSessionState.restFinished => l.stripRestDone,
          ActiveSessionState.acquiring => l.gpsStripAcquiring,
          ActiveSessionState.recording => l.gpsStripRecording,
          ActiveSessionState.weakSignal => l.gpsStripWeak,
          ActiveSessionState.autoPaused => l.gpsStripPausedAuto,
          ActiveSessionState.unfinished => l.gpsStripUnfinished,
          ActiveSessionState.notRestored => l.gpsStripNotRestored,
          ActiveSessionState.revoked => l.gpsStripRevoked,
        };
    String railWord(AppLocalizations l, ActiveSessionState s) => switch (s) {
          ActiveSessionState.running => l.railStateRunning,
          ActiveSessionState.paused => l.railStatePaused,
          ActiveSessionState.resting => l.railStateResting,
          ActiveSessionState.restFinished => l.railStateRestDone,
          ActiveSessionState.acquiring => l.gpsRailSearch,
          ActiveSessionState.recording => l.gpsRailRec,
          ActiveSessionState.weakSignal => l.gpsRailWeak,
          ActiveSessionState.autoPaused => l.gpsRailAuto,
          ActiveSessionState.unfinished => l.gpsRailWaiting,
          ActiveSessionState.notRestored => l.gpsRailProblem,
          ActiveSessionState.revoked => l.gpsRailChoose,
        };

    test('the rail words are at most 8 characters in ru and en, non-empty', () async {
      for (final l in [await en(), await ru()]) {
        for (final s in ActiveSessionState.values) {
          final rail = railWord(l, s);
          expect(rail.trim(), isNotEmpty, reason: '$s');
          expect(stripWord(l, s).trim(), isNotEmpty, reason: '$s');
          if (l.localeName == 'ru') {
            expect(rail.runes.length, lessThanOrEqualTo(8),
                reason: 'ru rail word of $s: "$rail"');
          }
        }
      }
    });

    for (final loc in ['en', 'ru']) {
      for (final kind in ActiveSessionKind.values) {
        testWidgets('$loc/$kind: strip (360 dp) and rail slot (80 dp) '
            'render every state without overflow', (t) async {
          final l10n = loc == 'en' ? await en() : await ru();
          final current = StateProvider<ActiveSessionStatus?>((ref) => null);
          final w = await pump(t, locale: Locale(loc), extra: [
            activeSessionStatusProvider.overrideWith((ref) => ref.watch(current)),
          ]);
          for (final s in ActiveSessionState.values) {
            w.c.read(current.notifier).state = ActiveSessionStatus(
              kind: kind,
              state: s,
              remaining: const Duration(seconds: 125),
              countsUp: kind == ActiveSessionKind.gpsRecording,
              mode: 'train',
              destination: '/x',
            );
            await t.pump();
            expect(find.text(stripWord(l10n, s)), findsWidgets,
                reason: '$loc $kind strip word of $s');
            expect(t.takeException(), isNull, reason: '$loc $kind $s');
          }
        });
      }

      testWidgets('$loc: the compact rail slot shows each rail word without '
          'overflow (DT-24-11)', (t) async {
        final l10n = loc == 'en' ? await en() : await ru();
        for (final s in ActiveSessionState.values) {
          t.view.physicalSize = const Size(1100, 800);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(ProviderScope(
            key: UniqueKey(),
            overrides: [
              activeSessionStatusProvider.overrideWithValue(ActiveSessionStatus(
                kind: ActiveSessionKind.gpsRecording,
                state: s,
                remaining: const Duration(seconds: 125),
                countsUp: true,
                mode: '',
                destination: '/record/gps',
              )),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              locale: Locale(loc),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 80,
                    child: RailRecordSlot(onRecord: () {}, onOpenSession: (_) {}),
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          final rail = switch (s) {
            ActiveSessionState.running => l10n.railStateRunning,
            ActiveSessionState.paused => l10n.railStatePaused,
            ActiveSessionState.resting => l10n.railStateResting,
            ActiveSessionState.restFinished => l10n.railStateRestDone,
            ActiveSessionState.acquiring => l10n.gpsRailSearch,
            ActiveSessionState.recording => l10n.gpsRailRec,
            ActiveSessionState.weakSignal => l10n.gpsRailWeak,
            ActiveSessionState.autoPaused => l10n.gpsRailAuto,
            ActiveSessionState.unfinished => l10n.gpsRailWaiting,
            ActiveSessionState.notRestored => l10n.gpsRailProblem,
            ActiveSessionState.revoked => l10n.gpsRailChoose,
          };
          expect(find.text(rail), findsOneWidget, reason: '$loc $s');
          expect(t.takeException(), isNull, reason: 'overflow for $loc $s');
        }
      });
    }
  });

  group('DT-24-14 announcements: transitions once, nothing per second', () {
    testWidgets('/transitions-announce-once and /ticking-announces-nothing',
        (t) async {
      final l10n = await en();
      final announced = <String>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, (dynamic m) async {
        if (m is Map && m['type'] == 'announce') {
          announced.add((m['data'] as Map)['message'] as String);
        }
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
      final w = await pump(t);
      await w.startRecording();
      expect(announced.where((a) => a == l10n.gpsAnnStarted).length, 1);

      // 120 s of ordinary moving fixes: no announcement per second.
      final before = announced.length;
      for (var i = 0; i < 120; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix();
        await t.pump();
      }
      expect(announced.length, before, reason: 'ticking announces nothing');
      expect(find.byKey(_strip), findsOneWidget);

      // Stand still: auto-pause announces once.
      for (var i = 0; i < 14; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix(speed: 0);
        await t.pump();
      }
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.pausedAuto);
      expect(announced.where((a) => a == l10n.gpsAnnAutoPaused).length, 1);

      // Move again: auto-resume announces once.
      for (var i = 0; i < 6; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix(speed: 2.5);
        await t.pump();
      }
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording);
      expect(announced.where((a) => a == l10n.gpsAnnAutoResumed).length, 1);
      expect(announced.where((a) => a == l10n.gpsAnnAutoPaused).length, 1);
      expect(announced.where((a) => a == l10n.gpsAnnStarted).length, 1);
    });
  });

  group('U5 one announcer: the shell is silent while the page is open', () {
    testWidgets('start and auto-pause are not spoken by the shell',
        (t) async {
      final l10n = await en();
      final announced = <String>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, (dynamic m) async {
        if (m is Map && m['type'] == 'announce') {
          announced.add((m['data'] as Map)['message'] as String);
        }
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
      final w = await pump(t);
      w.c.read(gpsRecordingPageOpenProvider.notifier).state = true;
      await w.startRecording();
      for (var i = 0; i < 14; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix(speed: 0);
        await t.pump();
      }
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.pausedAuto);
      expect(announced.where((a) => a == l10n.gpsAnnStarted), isEmpty);
      expect(announced.where((a) => a == l10n.gpsAnnAutoPaused), isEmpty);
    });
  });

  group('DT-24-12 entry points with a foreign-account session', () {
    testWidgets('/dock-strip and /record-pill: foreign gym timer shows neither',
        (t) async {
      final w = await pump(t, extra: [
        setTimerProvider.overrideWith(
            () => FakeSetTimer(setTimerState(SetPhase.work))),
      ]);
      // The gym session belongs to the signed-in A (no owner captured yet).
      expect(find.byKey(_strip), findsOneWidget);
      w.c.read(activeSessionOwnerProvider.notifier)
          .capture(uid: 'uidB', destination: '/workout/1');
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(_strip), findsNothing, reason: 'foreign: strip hidden');
      expect(find.byKey(_pill), findsNothing, reason: 'foreign: pill hidden');
      expect(w.c.read(activeSessionForeignOwnerProvider), isTrue);
    });

    testWidgets('/dock-strip: own recording shows, B after a switch sees '
        'neither strip nor pill', (t) async {
      final w = await pump(t);
      await w.startRecording();
      expect(find.byKey(_strip), findsOneWidget);
      w.auth.add(kUserB);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(_strip), findsNothing);
      expect(find.byKey(_pill), findsNothing,
          reason: 'a foreign session exposes no Record entry either');
      expect(w.c.read(recorderPhaseProvider), RecorderPhase.recording,
          reason: 'the switch does not stop the recorder');
      w.auth.add(kUserA);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(_strip), findsOneWidget);
    });

    testWidgets('/rail-slot-compact: foreign session keeps the height, hides '
        'the control', (t) async {
      final w = await pump(t, size: const Size(900, 700));
      expect(skip(_railRec), findsWidgets);
      await w.startRecording();
      w.auth.add(kUserB);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final slot = skip(_railRec);
      expect(slot, findsWidgets);
      expect(find.byKey(_strip), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('DT-24-19 one strip slot', () {
    testWidgets('the strip shows exactly one session at a time', (t) async {
      final w = await pump(t, extra: [
        setTimerProvider.overrideWith(
            () => FakeSetTimer(setTimerState(SetPhase.work))),
      ]);
      await w.startRecording();
      expect(find.byKey(_strip), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shell.dock.strip')),
          findsOneWidget);
    });
  });
}
