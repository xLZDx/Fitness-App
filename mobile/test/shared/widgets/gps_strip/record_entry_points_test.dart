// EP-G S04-24 AC-4/AC-6 and S04-25: the Record sheet GPS row, the Record
// shortcut and the other entry points (DT-24-12, DT-24-17, DT-24-18,
// DT-24-19). The REAL RecordSheet, openRecordSheet and AppShortcuts run.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/modes/widgets/record_sheet.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart'
    show scanAccessProvider;
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/session_digest_providers.dart';
import 'package:fitness_app/features/workouts/data/session_digest.dart';
import 'package:fitness_app/shared/widgets/app_shortcuts.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart' show HudSettingRow;
import 'package:fitness_app/shared/widgets/shell_dock.dart'
    show shellRecordSheetOpenerProvider;
import 'package:fitness_app/shared/widgets/window_size.dart';

import '../../../features/modes/mode_epic2_harness.dart'
    show FakeAuthRepository, FakeModeStore, fakeScanAccessProvider, kUserA;
import '../../../features/recording/pages/recorder_harness.dart' show Seams;
import '../../../support/s03_shell_harness.dart' show kTabPaths;

const ActiveSessionStatus kGpsRecording = ActiveSessionStatus(
  kind: ActiveSessionKind.gpsRecording,
  state: ActiveSessionState.recording,
  destination: kGpsRecordingDestination,
);
const ActiveSessionStatus kGpsUnfinished = ActiveSessionStatus(
  kind: ActiveSessionKind.gpsRecording,
  state: ActiveSessionState.unfinished,
  destination: kGpsRecordingDestination,
);
const ActiveSessionStatus kGym = ActiveSessionStatus(
  kind: ActiveSessionKind.gymWorkout,
  state: ActiveSessionState.running,
  destination: '/workout/9',
);

const SessionDigest _emptyDigest = SessionDigest(
    sessions: [], exerciseCount: 0, totalMinutes: 0, muscles: []);

final List<_Sheet> _opened = <_Sheet>[];

/// `openRecordSheet` keeps a process-wide "open" flag that is cleared only when
/// the sheet route completes, so every test closes the sheets it opened.
void sheetTest(String description, Future<void> Function(WidgetTester t) body) {
  testWidgets(description, (t) async {
    _opened.clear();
    try {
      await body(t);
    } finally {
      for (final s in _opened) {
        await s.close();
      }
    }
  });
}

class _Sheet {
  _Sheet(this.t, this.router, this.seams);
  final WidgetTester t;
  final GoRouter router;
  final Seams seams;
  String get top => router.routerDelegate.currentConfiguration.last.matchedLocation;
  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byKey(const Key('host.open'))));

  Future<void> close() async {
    for (var i = 0; i < 3; i++) {
      if (find.byKey(const Key('recordSheet')).evaluate().isEmpty) return;
      await t.tapAt(const Offset(4, 4));
      for (var j = 0; j < 4; j++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> open() async {
    _opened.add(this);
    await t.tap(find.byKey(const Key('host.open')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<_Sheet> pumpSheet(
  WidgetTester t, {
  bool gpsOn = true,
  ActiveSessionStatus? status,
  bool foreign = false,
  List<Override> extra = const [],
}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final store = FakeModeStore()..seed('uid-a', mode: AppMode.train);
  final auth = FakeAuthRepository(kUserA);
  addTearDown(auth.dispose);
  final seams = Seams();
  final router = GoRouter(
    initialLocation: '/home',
    routes: <RouteBase>[
      GoRoute(
        path: '/home',
        builder: (c, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('host.open'),
              onPressed: () => openRecordSheet(c),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      for (final p in [
        '/record/gps',
        '/workout/9',
        '/scan',
        '/workouts',
        '/form-check',
      ])
        GoRoute(
            path: p,
            builder: (_, __) => Scaffold(body: Text('stub:$p'))),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      authRepositoryProvider.overrideWith((ref) => auth),
      modeStoreProvider.overrideWithValue(store),
      modeFlagsProvider.overrideWithValue(const ModeFlags()),
      trainingContextPrefsProvider
          .overrideWith((ref) => Future<SharedPreferences>.value(prefs)),
      scanAccessProvider.overrideWith((ref) => ref.watch(fakeScanAccessProvider)),
      todayDigestProvider.overrideWithValue(_emptyDigest),
      if (gpsOn) gpsRecorderEnabledProvider.overrideWithValue(true),
      if (status != null) activeSessionStatusProvider.overrideWithValue(status),
      if (foreign) activeSessionForeignOwnerProvider.overrideWithValue(true),
      ...seams.overrides,
      ...extra,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  final result = _Sheet(t, router, seams);
  // The running app keeps the auth stream alive; so does the test.
  result.c.listen(authUserProvider, (_, __) {});
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return result;
}

Finder row(String id) => find.byKey(Key('recordSheet.row.$id'));
Finder get sheet => find.byKey(const Key('recordSheet'));

void main() {
  group('gpsRowModeFor and recordRowsFor (pure)', () {
    test('recorder off: no GPS row whatever runs', () {
      for (final s in [null, kGpsRecording, kGym]) {
        expect(gpsRowModeFor(recorderEnabled: false, status: s), GpsRowMode.none);
      }
      for (final m in AppMode.values) {
        final rows = recordRowsFor(m, gps: GpsRowMode.none);
        expect(rows.where((r) => r.id.startsWith('gps')), isEmpty);
      }
    });

    test('nothing running: start; GPS running or unfinished: open; gym: gymRunning',
        () {
      expect(gpsRowModeFor(recorderEnabled: true, status: null), GpsRowMode.start);
      expect(gpsRowModeFor(recorderEnabled: true, status: kGpsRecording),
          GpsRowMode.open);
      expect(gpsRowModeFor(recorderEnabled: true, status: kGpsUnfinished),
          GpsRowMode.open);
      expect(gpsRowModeFor(recorderEnabled: true, status: kGym),
          GpsRowMode.gymRunning);
    });

    test('rows: GPS last in Train and Body, first in Ride and Explore', () {
      for (final m in [AppMode.train, AppMode.body]) {
        final rows = recordRowsFor(m, gps: GpsRowMode.start);
        expect(rows.last.id, kRecordGpsStart, reason: '$m');
        expect(rows.last.enabled, isTrue);
        expect(rows.last.destination, kGpsRecordingDestination);
      }
      for (final m in [AppMode.ride, AppMode.explore]) {
        final rows = recordRowsFor(m, gps: GpsRowMode.start);
        expect(rows.first.id, kRecordGpsStart, reason: '$m');
      }
    });

    test('open row is enabled and never disabled; gym row is disabled with the '
        'gymRunning flag', () {
      final open = recordRowsFor(AppMode.train, gps: GpsRowMode.open).last;
      expect(open.id, kRecordGpsOpen);
      expect(open.enabled, isTrue);
      expect(open.gymRunning, isFalse);
      final gym = recordRowsFor(AppMode.train, gps: GpsRowMode.gymRunning).last;
      expect(gym.id, kRecordGpsStart);
      expect(gym.enabled, isFalse);
      expect(gym.gymRunning, isTrue);
    });

    test('the GPS row does not change the existing rows in order', () {
      for (final m in AppMode.values) {
        final base = recordRowsFor(m).map((r) => r.id).toList();
        final withGps = recordRowsFor(m, gps: GpsRowMode.start)
            .map((r) => r.id)
            .where((id) => id != kRecordGpsStart)
            .toList();
        expect(withGps, base, reason: '$m');
      }
    });
  });

  group('DT-24-17 the sheet opens during any source', () {
    sheetTest('idle: the enabled start row opens /record/gps', (t) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final s = await pumpSheet(t);
      await s.open();
      expect(sheet, findsOneWidget);
      expect(row(kRecordGpsStart), findsOneWidget);
      expect(find.text(l10n.gpsRowTitle), findsOneWidget);
      expect(t.widget<HudSettingRow>(row(kRecordGpsStart)).onTap, isNotNull);
      await t.tap(row(kRecordGpsStart));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(s.top, '/record/gps');
      expect(s.seams.location.startCount, 0,
          reason: 'opening the page starts nothing');
      expect(s.seams.perms.totalCalls, 0,
          reason: 'opening the sheet requests no permission');
    });

    sheetTest('/sheet-opens-with-gps-recording-and-row-reads-open-recording',
        (t) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final s = await pumpSheet(t, status: kGpsRecording);
      await s.open();
      expect(sheet, findsOneWidget, reason: 'not silently closed');
      expect(row(kRecordGpsOpen), findsOneWidget);
      expect(row(kRecordGpsStart), findsNothing,
          reason: 'no second recording can start');
      expect(find.text(l10n.gpsOpenRecording), findsOneWidget);
      expect(t.widget<HudSettingRow>(row(kRecordGpsOpen)).onTap, isNotNull);
      await t.tap(row(kRecordGpsOpen));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(s.top, '/record/gps');
      expect(s.seams.location.startCount, 0);
    });

    sheetTest('an unfinished recording also reads Open recording', (t) async {
      final s = await pumpSheet(t, status: kGpsUnfinished);
      await s.open();
      expect(sheet, findsOneWidget);
      expect(row(kRecordGpsOpen), findsOneWidget);
      expect(row(kRecordGpsStart), findsNothing);
    });

    sheetTest('/gym-timer-row-disabled-gpsRowGymRunning-with-open-workout',
        (t) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final s = await pumpSheet(t, status: kGym);
      await s.open();
      expect(sheet, findsOneWidget);
      expect(row(kRecordGpsStart), findsOneWidget);
      expect(t.widget<HudSettingRow>(row(kRecordGpsStart)).onTap, isNull,
          reason: 'the start row is disabled while a gym timer runs');
      expect(find.text(l10n.gpsRowGymRunning), findsWidgets);
      expect(find.byKey(const Key('recordSheet.gpsOpenWorkout')), findsOneWidget);
      await t.tap(find.byKey(const Key('recordSheet.gpsOpenWorkout')));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(s.top, '/workout/9');
      expect(s.seams.location.startCount, 0, reason: 'no recording started');
    });

    sheetTest('/no-second-recording-can-start: a refused row starts nothing',
        (t) async {
      final s = await pumpSheet(t, status: kGym);
      await s.open();
      await t.tap(row(kRecordGpsStart), warnIfMissed: false);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(s.top, '/home', reason: 'a disabled row navigates nowhere');
      expect(s.seams.location.startCount, 0);
      expect(s.seams.journal.calls, isEmpty);
    });

    sheetTest('flag off: S03 behaviour, the sheet does not open over a '
        'running gym timer and shows no GPS row when idle', (t) async {
      final s = await pumpSheet(t, gpsOn: false, status: kGym);
      await s.open();
      expect(sheet, findsNothing);
      final idle = await pumpSheet(t, gpsOn: false);
      await idle.open();
      expect(sheet, findsOneWidget);
      expect(row(kRecordGpsStart), findsNothing);
      expect(row(kRecordGpsOpen), findsNothing);
    });

    sheetTest('/record-sheet-opener: a foreign-account session never opens '
        'the sheet', (t) async {
      final s = await pumpSheet(t, foreign: true);
      await s.open();
      expect(sheet, findsNothing);
    });
  });

  group('DT-24-18 the pending decision and the recording stay reachable', () {
    sheetTest('/only-a-pending-revoked-decision-shows-the-normal-enabled-gps-'
        'start-row (real recorder, permission lost)', (t) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final s = await pumpSheet(t);
      s.seams.perms
        ..location = LocationPermissionStatus.grantedPrecise
        ..notification = NotificationPermissionStatus.granted;
      s.seams.env.ownerUid = 'uid-a';
      final c = s.c;
      unawaited(c.read(recorderControllerProvider.notifier).requestStart(
          sport: SportType.running));
      await t.pump();
      await t.pump();
      expect(c.read(recorderPhaseProvider), RecorderPhase.acquiring);
      // The permission is revoked in system settings: the watcher polls each second.
      s.seams.perms.location = LocationPermissionStatus.denied;
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(c.read(recorderPhaseProvider), RecorderPhase.permissionRevoked);
      expect(c.read(activeSessionStatusProvider), isNull,
          reason: 'a revoked recording has no strip');
      await s.open();
      expect(sheet, findsOneWidget);
      expect(row(kRecordGpsStart), findsOneWidget);
      expect(t.widget<HudSettingRow>(row(kRecordGpsStart)).onTap, isNotNull,
          reason: 'the normal enabled start row leads to the pending decision');
      expect(find.text(l10n.gpsRowTitle), findsOneWidget);
    });

    sheetTest('/recording-or-unfinished-shows-the-enabled-gpsOpen-row-never-'
        'disabled', (t) async {
      for (final st in [kGpsRecording, kGpsUnfinished]) {
        final s = await pumpSheet(t, status: st);
        await s.open();
        final w = t.widget<HudSettingRow>(row(kRecordGpsOpen));
        expect(w.onTap, isNotNull, reason: '${st.state}');
        await t.tapAt(const Offset(4, 4));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
    });
  });

  group('DT-24-12 the Record shortcut', () {
    const ctrl = LogicalKeyboardKey.controlLeft;
    const shift = LogicalKeyboardKey.shiftLeft;

    Future<(GoRouter, List<String>, WidgetTester)> pumpKeys(
      WidgetTester t, {
      ActiveSessionStatus? session,
      bool gpsOn = true,
      bool foreign = false,
    }) async {
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final calls = <String>[];
      final router = GoRouter(
        initialLocation: '/progress',
        routes: <RouteBase>[
          GoRoute(
              path: '/workout/:id',
              builder: (_, s) => Scaffold(body: Text('workout:${s.uri}'))),
          GoRoute(
              path: '/record/gps',
              builder: (_, __) => const Scaffold(body: Text('gps-stub'))),
          for (final p in kTabPaths)
            GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('page:$p'))),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(ProviderScope(
        overrides: <Override>[
          appRouterProvider.overrideWithValue(router),
          shellRecordSheetOpenerProvider.overrideWithValue(
              (BuildContext c, {GlobalKey? anchorKey}) => calls.add('record')),
          activeSessionStatusProvider.overrideWithValue(session),
          if (gpsOn) gpsRecorderEnabledProvider.overrideWithValue(true),
          if (foreign) activeSessionForeignOwnerProvider.overrideWithValue(true),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (c, child) => WindowSizeScope(
              child: AppShortcuts(child: child ?? const SizedBox.shrink())),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      return (router, calls, t);
    }

    Future<void> chord(WidgetTester t) async {
      await t.sendKeyDownEvent(ctrl);
      await t.sendKeyDownEvent(shift);
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await t.sendKeyUpEvent(shift);
      await t.sendKeyUpEvent(ctrl);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    String top(GoRouter r) => r.routerDelegate.currentConfiguration.last.matchedLocation;

    testWidgets('/record-shortcut with a GPS recording opens the SHEET (flag on)',
        (t) async {
      final (r, calls, _) = await pumpKeys(t, session: kGpsRecording);
      await chord(t);
      expect(calls, ['record'], reason: 'the sheet, whose row reads Open recording');
      expect(top(r), '/progress', reason: 'no second start surface');
    });

    testWidgets('gym timer + flag on also opens the sheet', (t) async {
      final (r, calls, _) = await pumpKeys(t, session: kGym);
      await chord(t);
      expect(calls, ['record']);
      expect(top(r), '/progress');
    });

    testWidgets('flag off keeps S03: a running session opens its destination',
        (t) async {
      final (r, calls, _) = await pumpKeys(t, session: kGym, gpsOn: false);
      await chord(t);
      expect(calls, isEmpty);
      expect(top(r), '/workout/9');
    });

    testWidgets('idle + flag on: the sheet opener runs once', (t) async {
      final (_, calls, _) = await pumpKeys(t);
      await chord(t);
      expect(calls, ['record']);
    });

    testWidgets('a foreign-account session blocks the shortcut in every case',
        (t) async {
      final (r, calls, _) = await pumpKeys(t, foreign: true);
      await chord(t);
      expect(calls, isEmpty);
      expect(top(r), '/progress');
      final (r2, calls2, _) = await pumpKeys(t, foreign: true, session: kGpsRecording);
      await chord(t);
      expect(calls2, isEmpty);
      expect(top(r2), '/progress');
    });
  });
}
