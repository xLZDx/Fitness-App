import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/state/recognition_history_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/live_recognition.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/widgets/live_equipment_preview.dart';

/// Records lifecycle calls without touching a camera.
class _SpySession extends CameraSession {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  /// Pumps ScannerPage under a real router.
  ///
  /// A router is now a hard requirement: the page listens to route changes to
  /// know when to release the camera, which is what replaced asking every
  /// navigation call site to remember to do it.
  ///
  /// MUST pump with the real app theme: it sets button minimumSize to
  /// Size.fromHeight(54) (minWidth == infinity), which crashed layout on a
  /// Row-placed button while a default-theme test stayed green.
  Future<ProviderContainer> pumpScan(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    // Phone-shaped surface. The viewfinder is now full-width 3:4, so on the
    // default 800x600 test window everything below it falls outside the
    // viewport and a lazy ListView never even builds it.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/scan',
      routes: [
        GoRoute(path: '/scan', builder: (_, __) => const ScannerPage()),
        GoRoute(
          path: '/equipment/:id',
          builder: (_, s) =>
              Scaffold(body: Text('equipment ${s.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ScannerPage)));
  }

  group('ScannerPage', () {
    testWidgets('photo recognition is the one and only path — no QR',
        (tester) async {
      // Operator point 7: QR is removed outright, photo recognition stays.
      await pumpScan(tester);
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('scan-recognise-camera')), findsOneWidget);
      expect(find.text('Recognise machine'), findsOneWidget);
      expect(find.byKey(const Key('scan-recognise-gallery')), findsOneWidget);
      expect(find.textContaining('QR'), findsNothing);
    });

    testWidgets('the viewfinder is full-width 3:4 with a proportional frame',
        (tester) async {
      // Operator point 4: the old fixed 300px strip with a 220x200 frame was
      // too small to fit a machine. The guide frame mirrors the 75% centre
      // crop the classifier receives.
      await pumpScan(tester);
      final ratio = tester.widget<AspectRatio>(find.ancestor(
        of: find.byType(LiveEquipmentPreview),
        matching: find.byType(AspectRatio),
      ));
      expect(ratio.aspectRatio, 3 / 4);
      final frame = tester.widget<FractionallySizedBox>(
          find.byType(FractionallySizedBox));
      expect(frame.widthFactor, 0.75);
      expect(frame.heightFactor, 0.75);
    });

    testWidgets('the viewfinder is present whether or not live mode is on',
        (tester) async {
      // The reported defect: "in live mode the camera window shows a black
      // square, you cannot see where to aim". The camera is no longer gated on
      // the Live switch at all — that switch controls the labeler.
      final container = await pumpScan(tester);
      expect(find.byType(LiveEquipmentPreview), findsOneWidget);

      container.read(liveModeEnabledProvider.notifier).state = true;
      await tester.pump();
      expect(find.byType(LiveEquipmentPreview), findsOneWidget);
    });

    testWidgets('opens the camera on arrival', (tester) async {
      final spy = _SpySession();
      await pumpScan(tester,
          overrides: [scanCameraSessionProvider.overrideWithValue(spy)]);
      // Armed from a post-frame callback, so it needs one more pump.
      await tester.pump();
      expect(spy.starts, greaterThan(0));
    });

    testWidgets('releases the camera when the route changes', (tester) async {
      // Structural release. /equipment/:id renders above the shell in the real
      // app, so this page is never disposed and autoDispose cannot fire; the
      // previous design asked each navigation call site to switch live mode off
      // first and one of them forgot, leaving the camera streaming behind the
      // page being read.
      final spy = _SpySession();
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(spy),
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]),
        ),
      ]);
      await tester.pump();
      final before = spy.stops;

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();
      await tester.scrollUntilVisible(find.text('leg press'), 120);
      await tester.tap(find.text('leg press'));
      await tester.pumpAndSettle();

      expect(find.text('equipment leg_press'), findsOneWidget);
      expect(spy.stops, greaterThan(before),
          reason: 'navigating away must release the camera');
    });

    testWidgets('renders classifier matches with confidence', (tester) async {
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
            VisualMatch(equipmentId: 'treadmill', confidence: 0.2),
          ]),
        ),
      ]);

      // Drive the controller directly: tapping the button would need a camera.
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(find.text('Best matches'), findsOneWidget);
      expect(find.text('leg press'), findsOneWidget);
      expect(find.text('80% confidence'), findsOneWidget);
      expect(find.text('treadmill'), findsOneWidget);
    });

    testWidgets('remembered machines surface as "My machines" chips',
        (tester) async {
      // Point 9: the history store was written on every recognition but no
      // screen ever read it. The chips route back to the machine's page.
      final repo = MockRecognitionHistoryRepository();
      addTearDown(repo.dispose);
      await repo.record(RecognitionEntry(
        equipmentId: 'leg_press',
        recognisedAt: DateTime.utc(2026, 7, 30, 12),
        confidence: 0.9,
        source: RecognitionSource.photo,
      ));
      await repo.record(RecognitionEntry(
        equipmentId: 'treadmill',
        recognisedAt: DateTime.utc(2026, 7, 30, 13),
        confidence: 0.8,
        source: RecognitionSource.live,
      ));

      await pumpScan(tester, overrides: [
        recognitionHistoryRepositoryProvider.overrideWithValue(repo),
      ]);
      await tester.pump();

      await tester.scrollUntilVisible(
          find.byKey(const Key('scan-history')), 200);
      expect(find.text('My machines'), findsOneWidget);
      expect(find.byKey(const Key('scan-history-treadmill')), findsOneWidget);
      expect(find.byKey(const Key('scan-history-leg_press')), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-history-treadmill')));
      await tester.pumpAndSettle();
      expect(find.text('equipment treadmill'), findsOneWidget,
          reason: 'a chip routes back to the machine page');
    });

    testWidgets('no history means no section at all', (tester) async {
      await pumpScan(tester);
      expect(find.byKey(const Key('scan-history')), findsNothing);
    });

    testWidgets('live mode is off by default and shows no live card',
        (tester) async {
      await pumpScan(tester);

      final toggle =
          tester.widget<Switch>(find.byKey(const Key('scan-live-toggle')));
      expect(toggle.value, isFalse);
      expect(find.byKey(const Key('scan-live-searching')), findsNothing);
      expect(find.byKey(const Key('scan-live-result')), findsNothing);
    });

    testWidgets('an unsettled vote shows the tentative leader, not a spinner',
        (tester) async {
      // The reported defect: live mode produced NOTHING but a spinner. While
      // the vote is below its bars the UI must still name the current leader
      // with its real score.
      final svc = MockLiveEquipmentService(
        smoother: RecognitionSmoother(window: 4, minConfidence: 0.5),
      );
      addTearDown(svc.dispose);

      await pumpScan(tester, overrides: [
        liveEquipmentServiceProvider.overrideWithValue(svc),
        liveModeEnabledProvider.overrideWith((_) => true),
      ]);

      // One weak frame: window not full, confidence bar unmet.
      svc.feed(const VisualMatch(equipmentId: 'leg_press', confidence: 0.2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('scan-live-tentative')), findsOneWidget);
      expect(find.byKey(const Key('scan-live-result')), findsNothing);
      expect(find.textContaining('leg press'), findsOneWidget);
      expect(find.textContaining('20'), findsWidgets,
          reason: 'the leader is shown with its real 20% score');
    });

    testWidgets('live mode shows searching, then the settled recognition',
        (tester) async {
      final svc = MockLiveEquipmentService(
        smoother: RecognitionSmoother(window: 2, minConfidence: 0.1),
      );
      addTearDown(svc.dispose);

      await pumpScan(tester, overrides: [
        liveEquipmentServiceProvider.overrideWithValue(svc),
        liveModeEnabledProvider.overrideWith((_) => true),
      ]);

      // Nothing settled yet.
      expect(find.byKey(const Key('scan-live-searching')), findsOneWidget);

      // Two agreeing frames fill the window and settle on one machine.
      svc.feed(
          const VisualMatch(equipmentId: 'rowing_machine', confidence: 0.8));
      svc.feed(
          const VisualMatch(equipmentId: 'rowing_machine', confidence: 0.6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('scan-live-result')), findsOneWidget);
      // Scoped to the card: the settled reading is also written to history,
      // so a "My machines" chip with the same name legitimately appears too.
      expect(
          find.descendant(
              of: find.byKey(const Key('scan-live-result')),
              matching: find.text('rowing machine')),
          findsOneWidget);
      expect(find.textContaining('100% of frames agree'), findsOneWidget);
    });
  });
}
