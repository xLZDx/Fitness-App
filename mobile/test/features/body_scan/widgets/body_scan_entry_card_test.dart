// C17 part 3: the "Body check-in" entry card (D-73, D-74, D-76, D-78) and the
// user-facing title collision rule from the UX review (no duplicate titles
// among the tabs and the new pages).
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/state/scan_plan_context_provider.dart';
import 'package:fitness_app/features/body_scan/widgets/body_scan_entry_card.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';

class _Repo implements ScanRepository {
  _Repo(this.items);
  final List<ScanRecord> items;
  final List<String> deleted = [];
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((r) => r.id == id);
  }
}

class _Source extends ScanPlanContextSource {
  const _Source(this.mode);
  final ScanSurfaceMode mode;
  @override
  ScanPlanContext current() => ScanPlanContext(surfaceMode: mode);
}

ScanRecord _scan(String id, DateTime at, [JobStatus? status]) => ScanRecord(
      id: id,
      createdAt: at,
      shots: const {},
      analysis: status == null ? null : ScanAnalysis(status: status),
    );

DateTime _daysAgo(int d) => DateTime.now().subtract(Duration(days: d, hours: 1));

class _Rig {
  _Rig(this.repo, this.pushed);
  final _Repo repo;
  final List<String> pushed;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  List<ScanRecord> history = const [],
  ScanAccess access = ScanAccess.allowed,
  ScanSurfaceMode mode = ScanSurfaceMode.full,
  bool compact = false,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo([...history]);
  final pushed = <String>[];
  Widget page(String p) => Scaffold(body: Text('route:$p'));
  final router = GoRouter(
    initialLocation: '/',
    observers: [_Obs(pushed)],
    routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
                body: ListView(
                    children: [BodyScanEntryCard(compact: compact)]),
              )),
      for (final p in const [
        '/body-scan',
        '/body-scan/history',
        '/body-scan/privacy',
        '/subscription',
        '/profile',
      ])
        GoRoute(path: p, builder: (_, __) => page(p)),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      scanAccessProvider.overrideWithValue(access),
      scanRepositoryProvider.overrideWithValue(repo),
      scanPlanContextProvider.overrideWithValue(_Source(mode)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return _Rig(repo, pushed);
}

class _Obs extends NavigatorObserver {
  _Obs(this.pushed);
  final List<String> pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) {
    final n = route.settings.name;
    if (previous != null && n != null) pushed.add(n);
  }
}

void main() {
  group('Progress (full) form', () {
    testWidgets('title, provisional label, never-scanned line, actions',
        (tester) async {
      await _pump(tester);
      expect(find.text('Body check-in'), findsOneWidget);
      expect(find.text('Rough estimate from height, weight and age'),
          findsOneWidget);
      expect(find.text('No check-ins yet.'), findsOneWidget);
      expect(find.text('Start check-in'), findsOneWidget);
      expect(find.text('Scan history'), findsOneWidget);
      expect(find.text('Photo privacy'), findsOneWidget);
      expect(find.byKey(const Key('bodyCheckIn.card.progress')), findsOneWidget);
      // The old jargon title never reappears on the card.
      expect(find.textContaining('Guided body scan'), findsNothing);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
    });

    testWidgets('the title is a semantics header', (tester) async {
      await _pump(tester);
      expect(
          find.ancestor(
              of: find.text('Body check-in'),
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.header == true)),
          findsOneWidget);
    });

    testWidgets('start opens /body-scan', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('bodyCheckIn.start')));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan'), findsOneWidget);
    });

    testWidgets('history and privacy links open their routes', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('bodyCheckIn.history')));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan/history'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyCheckIn.privacy')));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan/privacy'), findsOneWidget);
    });

    testWidgets('start, history and privacy are at least 48 dp', (tester) async {
      await _pump(tester);
      for (final k in const [
        'bodyCheckIn.start',
        'bodyCheckIn.history',
        'bodyCheckIn.privacy'
      ]) {
        final s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(48), reason: k);
        expect(s.width, greaterThanOrEqualTo(48), reason: k);
      }
    });

    testWidgets('signed out renders nothing', (tester) async {
      await _pump(tester, access: ScanAccess.signedOut);
      expect(find.text('Body check-in'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('last check-in line', () {
    testWidgets('today, 1 day, many days; newest record wins', (tester) async {
      await _pump(tester, history: [_scan('a', DateTime.now())]);
      expect(find.text('Last check-in: today'), findsOneWidget);
      expect(find.text('No check-ins yet.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, history: [_scan('a', _daysAgo(1))]);
      expect(find.text('Last check-in: 1 day ago'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, history: [
        _scan('old', _daysAgo(40)),
        _scan('new', _daysAgo(12)),
        _scan('mid', _daysAgo(30)),
      ]);
      expect(find.text('Last check-in: 12 days ago'), findsOneWidget);
    });

    testWidgets('a future-dated record never shows a negative count',
        (tester) async {
      await _pump(tester, history: [
        _scan('f', DateTime.now().add(const Duration(days: 3)))
      ]);
      expect(find.text('Last check-in: today'), findsOneWidget);
      expect(find.textContaining(RegExp(r'-\d')), findsNothing);
    });

    testWidgets('RU plural forms: 1, 2, 5, 21 days', (tester) async {
      const want = {
        1: 'Последняя проверка: 1 день назад',
        2: 'Последняя проверка: 2 дня назад',
        5: 'Последняя проверка: 5 дней назад',
        21: 'Последняя проверка: 21 день назад',
      };
      for (final e in want.entries) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester, history: [_scan('a', _daysAgo(e.key))], locale: 'ru');
        expect(find.text(e.value), findsOneWidget, reason: '${e.key} days');
      }
      expect(find.text('Проверка тела'), findsOneWidget);
      expect(find.text('Body check-in'), findsNothing);
    });
  });

  group('measurement-only (D-74)', () {
    testWidgets('shows the neutral note and no goal figures', (tester) async {
      await _pump(tester,
          mode: ScanSurfaceMode.measurementOnly,
          history: [_scan('a', _daysAgo(3), JobStatus.done)]);
      expect(find.text('Photos and history only. Goal figures are not shown here.'),
          findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('to go'), findsNothing);
      expect(find.textContaining('ETA'), findsNothing);
      // The only number on the card is the day count of the last check-in.
      final digits = RegExp(r'\d+');
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where(digits.hasMatch)
          .toList();
      expect(texts, ['Last check-in: 3 days ago']);
    });

    testWidgets('the full surface does not show the measurement-only note',
        (tester) async {
      await _pump(tester, mode: ScanSurfaceMode.full);
      expect(find.textContaining('Goal figures are not shown'), findsNothing);
    });

    testWidgets('the compact Home card carries the note too', (tester) async {
      await _pump(tester, mode: ScanSurfaceMode.measurementOnly, compact: true);
      expect(find.textContaining('Goal figures are not shown'), findsOneWidget);
    });

    testWidgets('the default scan plan context is measurement-only',
        (tester) async {
      // No override of the plan context: the safe default must apply.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          scanAccessProvider.overrideWithValue(ScanAccess.allowed),
          scanRepositoryProvider.overrideWithValue(_Repo([])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BodyScanEntryCard()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Goal figures are not shown'), findsOneWidget);
    });
  });

  group('resume and failure card (D-78)', () {
    for (final s in [JobStatus.queued, JobStatus.uploading, JobStatus.analysing]) {
      testWidgets('a ${s.name} scan shows Finish your scan; Resume opens the flow',
          (tester) async {
        await _pump(tester, history: [_scan('p', _daysAgo(0), s)]);
        expect(find.byKey(const Key('bodyScan.resumeCard')), findsOneWidget);
        expect(find.text('Finish your scan'), findsOneWidget);
        expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
        await tester.tap(find.text('Resume'));
        await tester.pumpAndSettle();
        expect(find.text('route:/body-scan'), findsOneWidget);
      });
    }

    testWidgets('done, cancelled and legacy (no analysis) records show no card',
        (tester) async {
      await _pump(tester, history: [
        _scan('d', _daysAgo(1), JobStatus.done),
        _scan('c', _daysAgo(2), JobStatus.cancelled),
        _scan('legacy', _daysAgo(3)),
      ]);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
    });

    testWidgets('Cancel deletes the pending local record and removes the card',
        (tester) async {
      final rig = await _pump(tester, history: [_scan('p', _daysAgo(0), JobStatus.queued)]);
      await tester.tap(find.byKey(const Key('bodyScan.resume.cancel')));
      await tester.pumpAndSettle();
      expect(rig.repo.deleted, ['p']);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
      expect(find.text('No check-ins yet.'), findsOneWidget);
    });

    testWidgets('only the NEWEST unfinished scan is offered', (tester) async {
      final rig = await _pump(tester, history: [
        _scan('older', _daysAgo(5), JobStatus.queued),
        _scan('newer', _daysAgo(1), JobStatus.analysing),
      ]);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bodyScan.resume.cancel')));
      await tester.pumpAndSettle();
      expect(rig.repo.deleted, ['newer']);
    });

    testWidgets('a failed scan shows the failure card with Retry / Keep / Delete',
        (tester) async {
      await _pump(tester, history: [_scan('f', _daysAgo(0), JobStatus.failed)]);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
      expect(find.text('The scan could not be completed'), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.failed.retry')), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.failed.keep')), findsOneWidget);
    });

    testWidgets('failed: Retry opens the flow', (tester) async {
      await _pump(tester, history: [_scan('f', _daysAgo(0), JobStatus.failed)]);
      await tester.tap(find.byKey(const Key('bodyScan.failed.retry')));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan'), findsOneWidget);
    });

    testWidgets('failed: Keep hides the card but keeps the record', (tester) async {
      final rig = await _pump(tester, history: [_scan('f', _daysAgo(0), JobStatus.failed)]);
      await tester.tap(find.byKey(const Key('bodyScan.failed.keep')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
      expect(rig.repo.deleted, isEmpty);
      expect(rig.repo.items, hasLength(1));
    });

    testWidgets('failed: Delete removes the local record', (tester) async {
      final rig = await _pump(tester, history: [_scan('f', _daysAgo(0), JobStatus.failed)]);
      await tester.tap(find.text('Delete scan'));
      await tester.pumpAndSettle();
      expect(rig.repo.deleted, ['f']);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
    });

    testWidgets('the compact Home card never shows the resume card',
        (tester) async {
      await _pump(tester,
          compact: true, history: [_scan('p', _daysAgo(0), JobStatus.queued)]);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
    });

    testWidgets('a gated user (not allowed) does not get the resume card',
        (tester) async {
      await _pump(tester,
          access: ScanAccess.needsSupporter,
          history: [_scan('p', _daysAgo(0), JobStatus.queued)]);
      expect(find.byKey(const Key('bodyScan.resumeCard')), findsNothing);
    });
  });

  group('compact Home form', () {
    testWidgets('title, label, last check-in and one action only', (tester) async {
      await _pump(tester, compact: true, history: [_scan('a', _daysAgo(2))]);
      expect(find.byKey(const Key('bodyCheckIn.card.home')), findsOneWidget);
      expect(find.text('Body check-in'), findsOneWidget);
      expect(find.text('Rough estimate from height, weight and age'),
          findsOneWidget);
      expect(find.text('Last check-in: 2 days ago'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Start check-in'), findsNothing);
      expect(find.byKey(const Key('bodyCheckIn.history')), findsNothing);
      expect(find.byKey(const Key('bodyCheckIn.privacy')), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('the button and the whole card open /body-scan', (tester) async {
      await _pump(tester, compact: true);
      await tester.tap(find.byKey(const Key('bodyCheckIn.start')));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Body check-in'));
      await tester.pumpAndSettle();
      expect(find.text('route:/body-scan'), findsOneWidget);
    });
  });

  group('access states', () {
    testWidgets('needs Supporter: message, subscription route, no scan links',
        (tester) async {
      await _pump(tester, access: ScanAccess.needsSupporter);
      expect(find.text('The guided scan is a Supporter benefit.'), findsOneWidget);
      expect(find.text('Rough estimate from height, weight and age'), findsNothing);
      expect(find.byKey(const Key('bodyCheckIn.history')), findsNothing);
      await tester.tap(find.byKey(const Key('bodyCheckIn.start')));
      await tester.pumpAndSettle();
      expect(find.text('route:/subscription'), findsOneWidget);
    });

    testWidgets('age unknown: message and profile route', (tester) async {
      await _pump(tester, access: ScanAccess.ageUnknown);
      expect(find.textContaining('Complete your profile'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bodyCheckIn.start')));
      await tester.pumpAndSettle();
      expect(find.text('route:/profile'), findsOneWidget);
    });

    testWidgets('underage: message only, no action at all', (tester) async {
      await _pump(tester, access: ScanAccess.underage);
      expect(find.textContaining('only available from age 18'), findsOneWidget);
      expect(find.byKey(const Key('bodyCheckIn.start')), findsNothing);
      expect(find.byKey(const Key('bodyCheckIn.history')), findsNothing);
    });

    testWidgets('needs consent: start is offered (it opens the consent first)',
        (tester) async {
      await _pump(tester, access: ScanAccess.needsConsent);
      expect(find.byKey(const Key('bodyCheckIn.start')), findsOneWidget);
      expect(find.text('Rough estimate from height, weight and age'),
          findsOneWidget);
      expect(find.byKey(const Key('bodyCheckIn.history')), findsNothing);
    });

    testWidgets('underage on the compact card: no action, tap goes nowhere',
        (tester) async {
      await _pump(tester, access: ScanAccess.underage, compact: true);
      expect(find.byKey(const Key('bodyCheckIn.start')), findsNothing);
      await tester.tap(find.text('Body check-in'));
      await tester.pumpAndSettle();
      expect(find.textContaining('route:'), findsNothing);
    });
  });

  group('user-facing titles are unique (UX review item 9)', () {
    for (final code in ['en', 'ru']) {
      test('no two tabs / new pages share a title in $code', () async {
        final l = await AppLocalizations.delegate.load(Locale(code));
        final titles = <String, String>{
          // Bottom tabs.
          'tab.home': l.homeHome,
          'tab.workouts': l.navWorkouts,
          'tab.scan': l.navScan,
          'tab.progress': l.progressProgress,
          'tab.profile': l.profileProfile,
          // New / entry surfaces.
          'card.bodyCheckIn': l.bodyCheckInTitle,
          'page.bodyScanFlow': l.bodyScanTitle,
          'page.bodyScanHistory': l.bodyScanHistoryTitle,
          'page.bodyScanPrivacy': l.bodyScanPrivacyTitle,
          'page.bodyScanResult': l.bodyScanResultTitle,
          'page.nutritionPlan': l.nutritionPlanTitle,
          'page.weightLog': l.weightLogTitle,
          'page.nutritionSources': l.nutritionSourcesTitle,
          'page.nutritionExplainer': l.nutritionExplainerTitle,
          'page.foodDiary': l.foodDiaryTitle,
          'legacy.guidedScan': l.scanEntryTitle,
        };
        final seen = <String, String>{};
        for (final e in titles.entries) {
          final k = e.value.trim().toLowerCase();
          expect(k, isNotEmpty, reason: e.key);
          expect(seen.containsKey(k), isFalse,
              reason: '"${e.value}" used by both ${seen[k]} and ${e.key}');
          seen[k] = e.key;
        }
      });
    }

    test('the card title is "Body check-in", not a scan/estimate promise', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(l.bodyCheckInTitle, 'Body check-in');
      expect(l.bodyCheckInTitle.toLowerCase(), isNot(contains('body fat')));
    });
  });
}
