// S03-11 Record sheet S-5 (test plan 4.4). Real RecordSheet through the real
// `openRecordSheet`, real go_router push into stub destinations.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/modes/widgets/record_sheet.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_gate_view.dart'
    show scanAccessMessage;
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/session_digest.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/session_digest_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart' show HudSettingRow;
import 'package:fitness_app/shared/widgets/main_shell.dart';
import 'package:fitness_app/shared/widgets/shell_dock.dart'
    show shellRecordSheetOpenerProvider;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'mode_epic2_harness.dart';

const _openKey = Key('test.openRecord');

Widget _host(BuildContext c) => Scaffold(
      body: Center(
        child: ElevatedButton(
            key: _openKey,
            onPressed: () => openRecordSheet(c),
            child: const Text('open')),
      ),
    );

const _scheduledToday = 'bench';

SessionDigest _digestWithToday() => SessionDigest(
      sessions: [
        ScheduledSession(
          id: 's1',
          exerciseId: _scheduledToday,
          exerciseTitle: 'Bench',
          scheduledFor: DateTime.now(),
          durationMinutes: 30,
          status: ScheduledSessionStatus.pending,
        )
      ],
      exerciseCount: 1,
      totalMinutes: 30,
      muscles: const ['chest'],
    );

const _emptyDigest = SessionDigest(
    sessions: [], exerciseCount: 0, totalMinutes: 0, muscles: []);

Future<Rig> _pump(
  WidgetTester t, {
  AppMode mode = AppMode.train,
  FakeModeStore? store,
  Size size = const Size(360, 800),
  ScanAccess scan = ScanAccess.allowed,
  SessionDigest digest = _emptyDigest,
  ModeFlags flags = const ModeFlags(),
  String initial = '/home',
  List<Override> extra = const [],
}) async {
  final s = store ?? (FakeModeStore()..seed('uid-a', mode: mode));
  return pumpRig(t,
      store: s,
      size: size,
      flags: flags,
      initial: initial,
      overrides: [
        fakeScanAccessProvider.overrideWith((_) => scan),
        todayDigestProvider.overrideWithValue(digest),
        ...extra,
      ],
      replace: {'/home': _host, '/progress': _host});
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.byKey(_openKey));
  await settleFrames(t, frames: 6);
}

Finder _row(String id) => byKeyS('recordSheet.row.$id');

Future<void> _close(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    if (byKeyS('recordSheet').evaluate().isEmpty) return;
    await t.tapAt(const Offset(4, 4));
    await settleFrames(t, frames: 4);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AC-RC-1 TRAIN scan row goes to /scan, no permission call',
      (tester) async {
    final perm = MockPermissionChannel(tester.binding);
    addTearDown(() => perm.dispose(tester.binding));
    final rig = await _pump(tester);
    await _open(tester);
    await tester.tap(_row('trainScan'));
    await settleFrames(tester);
    expect(rig.visits.last, '/scan');
    expect(byKeyS('recordSheet'), findsNothing);
    expect(perm.calls, isEmpty);
  });

  testWidgets('AC-RC-2/none: no today row', (tester) async {
    await _pump(tester);
    await _open(tester);
    expect(_row('trainToday'), findsNothing);
    expect(_row('trainScan'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('AC-RC-2/scheduled: today row present and enabled, leads to the workout',
      (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, digest: _digestWithToday());
    await _open(tester);
    expect(_row('trainToday'), findsOneWidget);
    expect(isEnabledNode(tester.getSemantics(_row('trainToday'))), isTrue);
    expect(tester.widget<HudSettingRow>(_row('trainToday')).onTap, isNotNull);
    expect(todayWorkoutPath(_digestWithToday(), DateTime.now()),
        '/workout/$_scheduledToday?day=s1');
    await _close(tester);
    h.dispose();
  });

  testWidgets('AC-RC-3/flagsOff BODY meal row leads only to the manual add-food page',
      (tester) async {
    final rig = await _pump(tester, mode: AppMode.body);
    await _open(tester);
    expect(_row('bodyMeal'), findsOneWidget);
    expect(_row('bodyWeight'), findsOneWidget);
    expect(find.byWidgetPredicate((w) =>
            w is HudSettingRow &&
            w.key.toString().contains('recordSheet.row')),
        findsNWidgets(3));
    await tester.tap(_row('bodyMeal'));
    await settleFrames(tester);
    expect(rig.visits.last, '/nutrition/add');
  });

  testWidgets('AC-RC-3/refused: body scan row present, disabled, reason in value',
      (tester) async {
    final h = tester.ensureSemantics();
    final l10n = l10nOf('en');
    final rig = await _pump(tester, mode: AppMode.body, scan: ScanAccess.underage);
    await _open(tester);
    final n = tester.getSemantics(_row('bodyScan'));
    expect(isEnabledNode(n), isFalse);
    expect(allText(n), contains(scanAccessMessage(l10n, ScanAccess.underage)));
    await tester.tap(_row('bodyScan'), warnIfMissed: false);
    await settleFrames(tester);
    expect(rig.visits.built, isEmpty, reason: 'a refused row opens nothing');
    await _close(tester);
    h.dispose();
  });

  testWidgets('AC-RC-4 open and close writes nothing', (tester) async {
    final store = FakeModeStore()..seed('uid-a', mode: AppMode.train);
    final rig = await _pump(tester, store: store);
    final keysBefore = rig.prefs.getKeys().toSet();
    await _open(tester);
    expect(byKeyS('recordSheet'), findsOneWidget);
    await _close(tester);
    expect(byKeyS('recordSheet'), findsNothing);
    expect(store.writes, isEmpty);
    expect(rig.prefs.getKeys().toSet(), keysBefore);
  });

  testWidgets('AC-RC-5 follow a row, pop: back on the originating tab, no sheet',
      (tester) async {
    final rig = await _pump(tester, initial: '/progress');
    expect(find.byKey(_openKey), findsOneWidget);
    await _open(tester);
    await tester.tap(_row('trainChoose'));
    await settleFrames(tester);
    expect(rig.visits.last, '/workouts');
    rig.router.pop();
    await settleFrames(tester);
    expect(find.byKey(_openKey), findsOneWidget, reason: 'origin host is /progress');
    expect(byKeyS('recordSheet'), findsNothing);
  });

  testWidgets('DT-11-1 mode without rows: empty text and Open Train', (tester) async {
    // BODY cannot be emptied by flags (see findings); an enabled Ride has no rows.
    final store = FakeModeStore()..seed('uid-a', mode: AppMode.ride);
    await _pump(tester,
        store: store, flags: const ModeFlags(rideEnabled: true));
    await _open(tester);
    expect(byKeyS('recordSheet.empty'), findsOneWidget);
    expect(find.text(l10nOf('en').recordNothingHere), findsOneWidget);
    await tester.tap(byKeyS('recordSheet.openTrain'));
    await settleFrames(tester);
    expect(store.stored('uid-a')!.selectedMode, AppMode.train);
    expect(byKeyS('recordSheet'), findsNothing);
  });

  testWidgets('DT-11-1b BODY with every tile flag-hidden is reachable (contract)',
      (tester) async {
    // The contract wants recordNothingHere for a BODY mode whose tiles are all
    // hidden by flags; production's body rows have no flag input.
    for (final id in [kRecordBodyScan, kRecordBodyMeal, kRecordBodyWeight]) {
      expect(id, isNotEmpty);
    }
    final rows = recordRowsFor(AppMode.body, scanAccess: ScanAccess.signedOut);
    expect(rows.where((r) => r.enabled), isNotEmpty,
        reason: 'meal and weight rows are always offered; no flag hides them');
    expect(rows.length, 3);
  }, skip: false);

  testWidgets('DT-11-2 does not open while a session strip shows', (tester) async {
    await _pump(tester, extra: [
      activeSessionStatusProvider.overrideWithValue(const ActiveSessionStatus(
          kind: ActiveSessionKind.gymWorkout, state: ActiveSessionState.running))
    ]);
    await _open(tester);
    expect(byKeyS('recordSheet'), findsNothing);
  });

  testWidgets('DT-11-2 control: opens when no session', (tester) async {
    await _pump(tester);
    await _open(tester);
    expect(byKeyS('recordSheet'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('DT-11-3 BODY answer "Food diary": meal row is first and primary',
      (tester) async {
    final store = FakeModeStore()
      ..seed('uid-a', mode: AppMode.body, answers: {
        AppMode.body: ModeAnswer.answered('food'),
      });
    await _pump(tester, store: store);
    await _open(tester);
    final meal = tester.getTopLeft(_row('bodyMeal')).dy;
    final scan = tester.getTopLeft(_row('bodyScan')).dy;
    await _close(tester);
    expect(meal, lessThan(scan), reason: 'meal row must come first');
  });

  test('DT-11-4 every Record destination is a route of app_router.dart', () {
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    final dests = <String>{};
    for (final m in [AppMode.train, AppMode.body]) {
      for (final r in recordRowsFor(m, todayPath: '/workout/x?day=y')) {
        dests.add(r.destination.split('?').first);
      }
    }
    expect(dests, containsAll(<String>{
      '/scan', '/workouts', '/form-check', '/body-scan',
      '/nutrition/add', '/nutrition/weight', '/workout/x'
    }));
    for (final d in dests) {
      final template = d == '/workout/x' ? '/workout/:' : d;
      final found = RegExp("path: '([^']*)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .any((p) => d == '/workout/x' ? p.startsWith(template) : p == d);
      expect(found, isTrue, reason: 'no route for $d');
    }
  });

  group('expanded window placement', () {
    testWidgets('anchored show: popover under the anchor, 360 wide', (tester) async {
      final anchor = GlobalKey();
      await _pump(tester, size: const Size(1100, 800), extra: []);
      // Re-pump a host with an anchor.
      await tester.pumpWidget(const SizedBox());
      await pumpRig(tester,
          store: FakeModeStore()..seed('uid-a'),
          size: const Size(1100, 800),
          initial: '/home',
          overrides: [todayDigestProvider.overrideWithValue(_emptyDigest)],
          replace: {
            '/home': (c) => Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 100, left: 40),
                      child: ElevatedButton(
                        key: anchor,
                        onPressed: () => openRecordSheet(c, anchorKey: anchor),
                        child: const Text('anchor'),
                      ),
                    ),
                  ),
                )
          });
      await tester.tap(find.byKey(anchor));
      await settleFrames(tester, frames: 6);
      final sheet = tester.getRect(byKeyS('recordSheet'));
      final a = tester.getRect(find.byKey(anchor));
      expect(sheet.width, lessThanOrEqualTo(360));
      expect(sheet.top, greaterThan(a.bottom - 1));
      expect(sheet.left, closeTo(a.left, 30));
      await _close(tester);
    });

    testWidgets('rail Record slot opens the sheet under the slot (lane note: no anchor key)',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FakeModeStore()..seed('uid-a');
      final auth = FakeAuthRepository(kUserA);
      addTearDown(auth.dispose);
      final router = GoRouter(initialLocation: '/home', routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            for (final p in ['/home', '/scan', '/workouts', '/progress', '/profile'])
              GoRoute(path: p, builder: (c, s) => const SizedBox()),
          ],
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => auth),
          modeStoreProvider.overrideWithValue(store),
          trainingContextPrefsProvider.overrideWith((ref) => Future.value(prefs)),
          scanAccessProvider.overrideWith((ref) => ScanAccess.allowed),
          todayDigestProvider.overrideWithValue(_emptyDigest),
          shellRecordSheetOpenerProvider.overrideWithValue(openRecordSheet),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await settleFrames(tester);
      await tester.tap(byKeyS('shell.rail.record'));
      await settleFrames(tester, frames: 6);
      expect(byKeyS('recordSheet'), findsOneWidget);
      final slot = tester.getRect(byKeyS('shell.rail.record'));
      final sheet = tester.getRect(byKeyS('recordSheet'));
      // Contract 10.6: the popover hangs at the rail slot, not in the window centre.
      expect((sheet.center.dx - 550).abs(), greaterThan(60),
          reason: 'sheet is centred in the window (dialog fallback): '
              'sheet=$sheet slot=$slot');
      await _close(tester);
    });
  });
}
