import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/body_scan_flow_page.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_flow_machine.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/scan_flow_controller.dart';
import 'package:fitness_app/features/body_scan/state/scan_plan_context_provider.dart';
import 'package:fitness_app/features/body_scan/widgets/analysis_progress_view.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';

import 'support/driver_harness.dart';

class _Rig {
  late GoRouter router;
  late ProviderContainer container;
  final FakeRunner runner = FakeRunner();
  final InMemoryBodyScanSettingsStore store = InMemoryBodyScanSettingsStore();
}

Future<_Rig> _pump(
  WidgetTester tester, {
  ScanAccess access = ScanAccess.allowed,
  BodyScanFlags flags = const BodyScanFlags(),
  BodyScanSettings settings = const BodyScanSettings(),
  List<WeightEntry>? weights,
  ScanPlanContextSource? plan,
}) async {
  final rig = _Rig();
  rig.router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(
          path: '/body-scan', builder: (_, __) => const BodyScanFlowPage()),
      GoRoute(
        path: '/photos/scan',
        builder: (ctx, __) => Scaffold(
          body: Column(children: [
            const Text('capture'),
            ElevatedButton(
                key: const Key('capture.done'),
                onPressed: () => ctx.pop('scan-1'),
                child: const Text('return id')),
            ElevatedButton(
                key: const Key('capture.back'),
                onPressed: () => ctx.pop(),
                child: const Text('return null')),
          ]),
        ),
      ),
      GoRoute(
          path: '/body-scan/result/:id',
          builder: (_, s) => Scaffold(body: Text('result ${s.pathParameters['id']}'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...driverOverrides(
        runner: rig.runner,
        flags: flags,
        settings: settings,
        weights: weights ??
            [WeightEntry(at: kDriverNow.subtract(const Duration(hours: 2)), kg: 80)],
      ),
      scanAccessProvider.overrideWithValue(access),
      bodyScanSettingsStoreProvider.overrideWithValue(rig.store),
      if (plan != null) scanPlanContextProvider.overrideWithValue(plan),
    ],
    child: Builder(builder: (ctx) {
      rig.container = ProviderScope.containerOf(ctx);
      return MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: rig.router,
      );
    }),
  ));
  await tester.pumpAndSettle();
  rig.router.push('/body-scan');
  await tester.pumpAndSettle();
  return rig;
}

FlowStage _stage(_Rig r) => r.container.read(scanFlowControllerProvider).state.stage;

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('bodyScan.intro.start')));
  await tester.pumpAndSettle();
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _returnScan(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key("capture.done")));
  await _frames(tester);
}

void main() {
  group('analysisStageFor', () {
    test('maps every flow stage to a progress stage', () {
      expect(analysisStageFor(FlowStage.savingLocal), AnalysisStage.photos);
      expect(analysisStageFor(FlowStage.queued), AnalysisStage.photos);
      expect(analysisStageFor(FlowStage.uploading), AnalysisStage.photos);
      expect(analysisStageFor(FlowStage.analysing), AnalysisStage.composition);
      expect(analysisStageFor(FlowStage.verifying), AnalysisStage.plausibility);
      expect(analysisStageFor(FlowStage.done), AnalysisStage.saved);
      expect(analysisStageFor(FlowStage.failed), AnalysisStage.photos);
    });
  });

  group('access gate', () {
    testWidgets('a blocked account sees the gate message and no intro',
        (tester) async {
      await _pump(tester, access: ScanAccess.needsSupporter);
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).last));
      expect(find.text(l10n.scanEntrySupporter), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.intro.start')), findsNothing);
    });
  });

  group('intro', () {
    testWidgets('opens the flow and shows the provisional intro',
        (tester) async {
      final r = await _pump(tester);
      expect(_stage(r), FlowStage.intro);
      expect(find.byKey(const Key('bodyScan.intro.roughLabel')), findsOneWidget);
      expect(find.text('Body scan'), findsOneWidget); // app bar
    });

    testWidgets('the default plan context is measurement only (note shown)',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('bodyScan.intro.measurementOnly')),
          findsOneWidget);
    });

    testWidgets('a full plan context hides the measurement-only note',
        (tester) async {
      await _pump(tester,
          plan: _FullSource());
      expect(find.byKey(const Key('bodyScan.intro.measurementOnly')),
          findsNothing);
    });

    testWidgets('Close pops back to the previous page', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('bodyScan.intro.close')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('weight prompt routing', () {
    testWidgets('a fresh weight skips the sheet and opens the capture',
        (tester) async {
      await _pump(tester);
      await _start(tester);
      expect(find.text('capture'), findsOneWidget);
      expect(find.text('Log your weight first'), findsNothing);
    });

    testWidgets('no weight on file opens the sheet before the capture',
        (tester) async {
      final r = await _pump(tester, weights: const []);
      await _start(tester);
      expect(find.text('Log your weight first'), findsOneWidget);
      expect(find.text('capture'), findsNothing);
      expect(_stage(r), FlowStage.weightPrompt);
    });

    testWidgets('Skip continues to the capture', (tester) async {
      await _pump(tester, weights: const []);
      await _start(tester);
      await tester.tap(find.byKey(const Key('bodyScan.weight.skip')));
      await tester.pumpAndSettle();
      expect(find.text('capture'), findsOneWidget);
    });

    testWidgets('Save continues to the capture', (tester) async {
      final r = await _pump(tester, weights: const []);
      await _start(tester);
      await tester.enterText(find.byKey(const Key('bodyScan.weight.field')), '80');
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pumpAndSettle();
      expect(find.text('capture'), findsOneWidget);
      expect(_stage(r), FlowStage.capturing);
    });

    testWidgets('dismissing the sheet is treated as skip, never a dead end',
        (tester) async {
      await _pump(tester, weights: const []);
      await _start(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('capture'), findsOneWidget);
    });
  });

  group('capture and analysis', () {
    testWidgets('capture returning an id shows the analysis progress',
        (tester) async {
      final r = await _pump(tester);
      await _start(tester);
      await _returnScan(tester);
      expect(r.container.read(bodyScanActiveScanIdProvider), 'scan-1');
      expect(_stage(r), FlowStage.verifying);
      expect(find.byType(AnalysisProgressView), findsOneWidget);
      expect(find.text('Step 3 of 5: Plausibility check'), findsWidgets);
      expect(r.runner.calls, ['resume']);
      // Cancel is the first focus target (progress view contract).
      expect(find.byKey(const Key('bodyScan.progress.cancel')), findsOneWidget);
    });

    testWidgets('provisional progress says photos are kept on this device',
        (tester) async {
      await _pump(tester);
      await _start(tester);
      await _returnScan(tester);
      expect(find.text('Photos kept on this device'), findsWidgets);
    });

    testWidgets('leaving the capture without saving cancels and goes back',
        (tester) async {
      final r = await _pump(tester);
      await _start(tester);
      await tester.tap(find.byKey(const Key('capture.back')));
      await tester.pumpAndSettle();
      expect(find.text("home"), findsOneWidget);
      expect(r.runner.calls, isEmpty);
    });

    testWidgets('a done record opens the result route for that scan',
        (tester) async {
      final r = await _pump(tester);
      await _start(tester);
      await _returnScan(tester);
      r.container.read(fakeScanRecordsProvider.notifier).state = [
        recordWith('scan-1', JobStatus.done)
      ];
      await tester.pump();
      await _frames(tester);
      expect(find.text('result scan-1'), findsOneWidget);
    });

    testWidgets('Cancel on the progress screen cancels the runner and pops',
        (tester) async {
      final r = await _pump(tester);
      await _start(tester);
      await _returnScan(tester);
      r.runner.calls.clear();
      await tester.tap(find.byKey(const Key('bodyScan.progress.cancel')));
      await _frames(tester);
      expect(r.runner.calls, ['cancel:scan-1']);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('terminal failure card (D-78)', () {
    Future<_Rig> toFailed(WidgetTester tester) async {
      final r = await _pump(tester);
      await _start(tester);
      await _returnScan(tester);
      r.container.read(fakeScanRecordsProvider.notifier).state = [
        recordWith('scan-1', JobStatus.failed, lastError: 'internal')
      ];
      await tester.pump();
      await _frames(tester);
      return r;
    }

    testWidgets('shows Retry, Keep and Delete instead of the progress',
        (tester) async {
      final r = await toFailed(tester);
      expect(_stage(r), FlowStage.failed);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsOneWidget);
      expect(find.byType(AnalysisProgressView), findsNothing);
    });

    testWidgets('Retry requeues the same scan on the runner', (tester) async {
      final r = await toFailed(tester);
      r.runner.calls.clear();
      await tester.tap(find.byKey(const Key('bodyScan.failed.retry')));
      await _frames(tester);
      expect(_stage(r), FlowStage.queued);
      expect(r.runner.calls, ['retry:scan-1']);
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing);
    });

    testWidgets('Keep on this device leaves the page, the scan is untouched',
        (tester) async {
      final r = await toFailed(tester);
      r.runner.calls.clear();
      await tester.tap(find.byKey(const Key('bodyScan.failed.keep')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(r.runner.calls, isEmpty);
    });

    testWidgets('Delete scan deletes through the runner and leaves the card',
        (tester) async {
      final r = await toFailed(tester);
      r.runner.calls.clear();
      await tester.tap(find.byKey(const Key('bodyScan.failed.delete')));
      await tester.pumpAndSettle();
      expect(r.runner.calls, ['cancel:scan-1'],
          reason: 'Delete must reach the runner');
      expect(find.byKey(const Key('bodyScan.failedCard')), findsNothing,
          reason: 'the failed card must not stay as a dead end');
    });
  });

  group('cloud consent trigger (D-5)', () {
    testWidgets('flag off: no consent sheet, straight to the capture',
        (tester) async {
      await _pump(tester);
      await _start(tester);
      expect(find.text('Send photos for analysis?'), findsNothing);
      expect(find.text('capture'), findsOneWidget);
    });

    testWidgets('flag on without consent: sheet first, Agree stores consent',
        (tester) async {
      final r = await _pump(tester, flags: const BodyScanFlags(cloudPhotos: true));
      await tester.tap(find.byKey(const Key('bodyScan.intro.start')));
      await tester.pumpAndSettle();
      expect(find.text('Send photos for analysis?'), findsOneWidget);
      expect(find.text('capture'), findsNothing);
      await tester.tap(find.byKey(const Key('bodyScan.cloud.agree')));
      await tester.pumpAndSettle();
      final saved = await r.store.watch().first;
      expect(saved.cloudConsentVersion, kBodyScanCloudConsentVersion);
      expect(find.text('capture'), findsOneWidget);
    });

    testWidgets('flag on, Not now: no consent stored, scan stays on device',
        (tester) async {
      final r = await _pump(tester, flags: const BodyScanFlags(cloudPhotos: true));
      await tester.tap(find.byKey(const Key('bodyScan.intro.start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyScan.cloud.decline')));
      await tester.pumpAndSettle();
      final saved = await r.store.watch().first;
      expect(saved.cloudConsentVersion, isNull);
      expect(find.text('capture'), findsOneWidget);
    });

    testWidgets('flag on with current consent: no sheet', (tester) async {
      await _pump(tester,
          flags: const BodyScanFlags(cloudPhotos: true),
          settings: const BodyScanSettings(
              cloudConsentVersion: kBodyScanCloudConsentVersion));
      await _start(tester);
      expect(find.text('Send photos for analysis?'), findsNothing);
      expect(find.text('capture'), findsOneWidget);
    });
  });
}

class _FullSource extends ScanPlanContextSource {
  const _FullSource();
  @override
  ScanPlanContext current() =>
      const ScanPlanContext(surfaceMode: ScanSurfaceMode.full);
}
