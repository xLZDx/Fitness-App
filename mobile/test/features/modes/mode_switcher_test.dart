// S03-10 Mode switcher S-3 and Coming-later sheet (test plan 4.3). The real
// ModeSwitcherSheet is opened through the real `openModeSwitcher` from a test
// host (the Home chip belongs to step 4).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/home/widgets/home_lens.dart';
import 'package:fitness_app/shared/widgets/app_shortcuts.dart'
    show modeSwitcherOpenerProvider;
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/modes/widgets/mode_switcher_sheet.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart' show HudNavBar;
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart' show HudSettingRow;
import 'package:fitness_app/shared/widgets/main_shell.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mode_epic2_harness.dart';

const _openKey = Key('test.openSwitcher');
const _openTwiceKey = Key('test.openSwitcherTwice');

Widget _host(BuildContext c) => Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(
              key: _openKey,
              onPressed: () => openModeSwitcher(c),
              child: const Text('open')),
          ElevatedButton(
              key: _openTwiceKey,
              onPressed: () {
                openModeSwitcher(c);
                openModeSwitcher(c);
              },
              child: const Text('open2')),
        ]),
      ),
    );

FakeModeStore _store({AppMode mode = AppMode.train}) => FakeModeStore()
  ..seed('uid-a', mode: mode)
  ..seed('uid-b', mode: AppMode.body);

Future<Rig> _pump(WidgetTester t, FakeModeStore store,
    {Locale locale = const Locale('en')}) async {
  final rig = await pumpRig(t,
      store: store,
      locale: locale,
      initial: '/home',
      prefValues: {'training_context.v1.uid-a': 'gymMachines'},
      replace: {'/home': _host});
  return rig;
}


Future<void> _open(WidgetTester t) async {
  await t.tap(find.byKey(_openKey));
  await settleFrames(t, frames: 6);
  expect(byKeyS('modeSwitcher.sheet'), findsOneWidget);
}

Future<void> _closeAll(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    if (find.byKey(const Key('modeSwitcher.sheet')).evaluate().isEmpty &&
        find.byKey(const Key('comingLater.sheet')).evaluate().isEmpty) {
      break;
    }
    await t.tapAt(const Offset(4, 4));
    await settleFrames(t, frames: 4);
  }
}

Finder _row(String m) => byKeyS('modeSwitcher.row.$m');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AC-SW-1 Home chip then Body row: two taps, Home follows the BODY lens',
      (tester) async {
    final store = _store();
    await pumpRig(tester,
        store: store,
        initial: '/home',
        overrides: [
          modeSwitcherOpenerProvider.overrideWithValue(openModeSwitcher),
        ],
        replace: {'/home': (c) => const HomePage()});
    await settleFrames(tester, frames: 15);
    List<String> sections() {
      final found = <String, double>{};
      for (final name in kHomeTrainSectionOrder) {
        final f = byKeyS('home.section.$name');
        if (f.evaluate().isNotEmpty) found[name] = tester.getTopLeft(f).dy;
      }
      return found.keys.toList()..sort((a, b) => found[a]!.compareTo(found[b]!));
    }

    var taps = 0;
    await tester.tap(byKeyS('home.modeChip'));
    taps++;
    await settleFrames(tester, frames: 6);
    await tester.tap(_row('body'));
    taps++;
    await settleFrames(tester, frames: 8);
    expect(taps, 2);
    expect(store.stored('uid-a')!.selectedMode, AppMode.body);
    final present = sections();
    final expected =
        homeSectionOrder(HomeLens.body).where(present.contains).toList();
    expect(present, expected,
        reason: 'visible order $present vs BODY order $expected');
  });

  testWidgets('RV-9b Coming-later Back from the switcher writes nothing and keeps the mode',
      (tester) async {
    final store = _store(mode: AppMode.body);
    final rig = await _pump(tester, store);
    await _open(tester);
    await tester.tap(_row('ride'));
    await settleFrames(tester, frames: 6);
    expect(byKeyS('comingLater.sheet'), findsOneWidget);
    await tester.tap(byKeyS('comingLater.back'));
    await settleFrames(tester, frames: 6);
    expect(byKeyS('comingLater.sheet'), findsNothing);
    expect(store.writes, isEmpty);
    expect(rig.container.read(selectedModeProvider), AppMode.body);
    await _closeAll(tester);
    expect(store.writes, isEmpty);
  });

  group('AC-SW-3', () {
    testWidgets('AC-SW-3/scrim dismiss: zero writes, zero events', (tester) async {
      final store = _store();
      final rig = await _pump(tester, store);
      final events = <ModeChanged>[];
      final sub = rig.container
          .read(modeChangeBusProvider)
          .stream
          .listen(events.add);
      addTearDown(sub.cancel);
      await _open(tester);
      await tester.tapAt(const Offset(4, 4));
      await settleFrames(tester);
      expect(byKeyS('modeSwitcher.sheet'), findsNothing);
      expect(store.writes, isEmpty);
      expect(events, isEmpty);
    });

    testWidgets('AC-SW-3/sameMode: re-selecting the current mode writes nothing',
        (tester) async {
      final store = _store();
      final rig = await _pump(tester, store);
      final events = <ModeChanged>[];
      final sub = rig.container.read(modeChangeBusProvider).stream.listen(events.add);
      addTearDown(sub.cancel);
      await _open(tester);
      await tester.tap(_row('train'));
      await settleFrames(tester);
      expect(byKeyS('modeSwitcher.sheet'), findsNothing);
      expect(store.writes, isEmpty);
      expect(events, isEmpty);
    });

    testWidgets('AC-SW-3/control: a real change writes once and emits once',
        (tester) async {
      final store = _store();
      final rig = await _pump(tester, store);
      final events = <ModeChanged>[];
      final sub = rig.container.read(modeChangeBusProvider).stream.listen(events.add);
      addTearDown(sub.cancel);
      await _open(tester);
      await tester.tap(_row('body'));
      await settleFrames(tester);
      expect(store.writes.length, 1);
      expect(store.stored('uid-a')!.selectedMode, AppMode.body);
      expect(events.length, 1);
      expect(events.single.to, AppMode.body);
    });
  });

  testWidgets('AC-SW-4 opening twice gives one sheet', (tester) async {
    await _pump(tester, _store());
    await tester.tap(find.byKey(_openTwiceKey));
    await settleFrames(tester, frames: 6);
    expect(byKeyS('modeSwitcher.sheet'), findsOneWidget);
    await _closeAll(tester);
  });

  for (final m in ['ride', 'explore']) {
    testWidgets('AC-SW-5/$m unavailable row opens Coming-later, no write',
        (tester) async {
      final store = _store();
      await _pump(tester, store);
      await _open(tester);
      await tester.tap(_row(m));
      await settleFrames(tester, frames: 6);
      expect(byKeyS('comingLater.sheet'), findsOneWidget);
      expect(tester.widget<Text>(byKeyS('comingLater.title')).data,
          l10nOf('en').modeComingLaterSheetTitle(m));
      expect(store.writes, isEmpty);
      await _closeAll(tester);
      expect(store.writes, isEmpty);
    });
  }

  testWidgets('DT-10-1 failed save: lens changes for the session, snackbar shown',
      (tester) async {
    final store = _store()..throwOnWrite = true;
    final rig = await _pump(tester, store);
    await _open(tester);
    await tester.tap(_row('body'));
    await settleFrames(tester);
    expect(rig.container.read(modeStateProvider).valueOrNull!.selectedMode,
        AppMode.body);
    expect(find.text(l10nOf('en').modeSwitchSaveError), findsOneWidget);
    expect(store.stored('uid-a')!.selectedMode, AppMode.train);
  });

  group('DT-10-2 plural of the unanswered-question link', () {
    for (final lang in ['ru', 'en']) {
      test('ARB forms /$lang', () {
        final l = l10nOf(lang);
        String f(int n) => l.modeSwitcherQuestions(n);
        if (lang == 'ru') {
          expect({f(1), f(2), f(5)}.length, 3,
              reason: 'ru one/few/many must differ: ${f(1)} | ${f(2)} | ${f(5)}');
          expect(f(21).replaceFirst('21', ''), f(1).replaceFirst('1', ''));
          expect(f(22).replaceFirst('22', ''), f(2).replaceFirst('2', ''));
        } else {
          expect(f(1).replaceFirst('1', ''), isNot(f(2).replaceFirst('2', '')));
          expect(f(5).replaceFirst('5', ''), f(2).replaceFirst('2', ''));
        }
      });
    }

    testWidgets('rendered row: one unanswered TRAIN question', (tester) async {
      final store = _store();
      SharedPreferences.setMockInitialValues({});
      final rig = await pumpRig(tester,
          store: store, initial: '/home', replace: {'/home': _host});
      expect(rig, isNotNull);
      await _open(tester);
      expect(tester.widget<Text>(find.descendant(
              of: byKeyS('modeSwitcher.questions.train'),
              matching: find.byType(Text))).data,
          l10nOf('en').modeSwitcherQuestions(1));
      await _closeAll(tester);
    });
  });

  testWidgets('DT-10-3 Coming-later action: Train, one write only if it changes',
      (tester) async {
    // Current = body: action switches to train with exactly one write.
    var store = _store(mode: AppMode.body);
    await _pump(tester, store);
    await _open(tester);
    await tester.tap(_row('explore'));
    await settleFrames(tester, frames: 6);
    await tester.tap(byKeyS('comingLater.chooseTrain'));
    await settleFrames(tester, frames: 6);
    expect(byKeyS('comingLater.sheet'), findsNothing);
    expect(byKeyS('modeSwitcher.sheet'), findsNothing);
    expect(store.stored('uid-a')!.selectedMode, AppMode.train);
    expect(store.writes.length, 1);
    // Current = train: no write at all.
    await tester.pumpWidget(const SizedBox());
    store = _store(mode: AppMode.train);
    await _pump(tester, store);
    await _open(tester);
    await tester.tap(_row('explore'));
    await settleFrames(tester, frames: 6);
    await tester.tap(byKeyS('comingLater.chooseTrain'));
    await settleFrames(tester, frames: 6);
    expect(store.writes, isEmpty);
  });

  testWidgets('DT-10-4 rows: exclusive group, only the current row selected',
      (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, _store(mode: AppMode.body));
    await _open(tester);
    final sel = <String>[
      for (final m in AppMode.values)
        if (isSelectedNode(tester.getSemantics(_row(m.name)))) m.name
    ];
    expect(sel, ['body']);
    final groups = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.inMutuallyExclusiveGroup == true)
        .length;
    expect(groups, greaterThanOrEqualTo(4));
    await _closeAll(tester);
    h.dispose();
  });

  testWidgets('DT-10-5 account switch while open: re-reads B, writes only under B',
      (tester) async {
    final store = _store(mode: AppMode.train);
    final rig = await _pump(tester, store);
    await _open(tester);
    rig.auth.emit(kUserB);
    await settleFrames(tester, frames: 12);
    expect(store.readUids, contains('uid-b'));
    expect(
        tester.widget<HudSettingRow>(_row('body')).selected, isTrue,
        reason: 'B is on body');
    expect(tester.widget<HudSettingRow>(_row('train')).selected, isFalse);
    await tester.tap(_row('train'));
    await settleFrames(tester, frames: 6);
    expect(store.writesFor('uid-a'), isEmpty);
    expect(store.writesFor('uid-b').length, 1);
    expect(store.writesFor('uid-b').single.state.selectedMode, AppMode.train);
  });

  group('shell integration', () {
    Future<(GoRouter, ProviderContainer, FakeModeStore, List<DateTime>)>
        pumpShell(WidgetTester tester, String initial) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = _store();
      final auth = FakeAuthRepository(kUserA);
      addTearDown(auth.dispose);
      final clock = <DateTime>[DateTime(2026, 1, 1, 12)];
      final router = GoRouter(initialLocation: initial, routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            for (final p in ['/home', '/scan', '/workouts', '/progress', '/profile'])
              GoRoute(path: p, builder: (c, s) => _host(c)),
          ],
        ),
      ]);
      addTearDown(router.dispose);
      late ProviderContainer container;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => auth),
          modeStoreProvider.overrideWithValue(store),
          trainingContextPrefsProvider
              .overrideWith((ref) => Future.value(prefs)),
          scanAccessProvider.overrideWith((ref) => ScanAccess.allowed),
          restClockProvider.overrideWithValue(() => clock.first),
          setCuesMutedProvider.overrideWith((ref) => true),
          setVoiceEnabledProvider.overrideWith((ref) => false),
        ],
        child: Builder(builder: (c) {
          container = ProviderScope.containerOf(c);
          return MaterialApp.router(
            theme: AppTheme.dark(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        }),
      ));
      await settleFrames(tester);
      return (router, container, store, clock);
    }

    testWidgets('AC-SH-4 a mode switch does not navigate', (tester) async {
      final (router, container, store, _) = await pumpShell(tester, '/progress');
      int idx() => tester.widget<HudNavBar>(find.byType(HudNavBar)).selectedIndex;
      final before = idx();
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      await _open(tester);
      await tester.tap(_row('body'));
      await settleFrames(tester);
      expect(store.stored('uid-a')!.selectedMode, AppMode.body);
      expect(router.routerDelegate.currentConfiguration.uri.path, loc);
      expect(loc, '/progress');
      expect(idx(), before);
      expect(container.read(modeStateProvider).valueOrNull!.selectedMode,
          AppMode.body);
    });

    testWidgets('AC-SW-2 a mode switch keeps timers, strip and ticking',
        (tester) async {
      final (router, container, store, clock) = await pumpShell(tester, '/home');
      // Real controllers, started with the injected clock.
      container.read(setTimerProvider.notifier).start(const SetPlan(
          sets: 3, workSeconds: 60, restSeconds: 20, readySeconds: 0));
      container.read(restTimerProvider.notifier).start(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      await settleFrames(tester, frames: 3);
      expect(byKeyS('shell.dock.strip'), findsOneWidget);
      String stripText() => tester
          .widgetList<Text>(find.descendant(
              of: byKeyS('shell.dock.strip'), matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .where((s) => !RegExp(r'\d').hasMatch(s))
          .join('|');
      final labelBefore = stripText();
      final setBefore = container.read(setTimerProvider);
      final restBefore = container.read(restTimerProvider);
      await _open(tester);
      await tester.tap(_row('body'));
      await settleFrames(tester, frames: 4);
      expect(store.stored('uid-a')!.selectedMode, AppMode.body);
      final setAfter = container.read(setTimerProvider);
      final restAfter = container.read(restTimerProvider);
      expect(setAfter.phase, setBefore.phase);
      expect(setAfter.setNumber, setBefore.setNumber);
      expect(setAfter.running, isTrue);
      expect(restAfter.endsAt, restBefore.endsAt);
      expect(restAfter.isIdle, isFalse);
      expect(stripText(), labelBefore);
      // The clock still ticks: 5 s later the set timer has moved and the rest
      // has 5 s less left.
      final secondsBefore = container.read(setTimerProvider).secondsLeft;
      clock[0] = clock.first.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(container.read(setTimerProvider).secondsLeft,
          lessThan(secondsBefore));
      expect(restAfter.endsAt!.difference(clock.first).inSeconds,
          restBefore.endsAt!.difference(clock.first).inSeconds);
      expect(byKeyS('shell.dock.strip'), findsOneWidget);
      expect(router, isNotNull);
      container.read(setTimerProvider.notifier).reset();
      container.read(restTimerProvider.notifier).clear();
      await settleFrames(tester, frames: 2);
    });
  });
}
