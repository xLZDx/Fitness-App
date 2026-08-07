import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/camera/camera_availability.dart';
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
  Future<void> start({bool requestPermission = false}) async => starts++;

  @override
  Future<void> stop() async => stops++;
}

/// Fails [start] with a typed reason, then succeeds once [fixed] is set.
///
/// The second half is what makes the retry tests real: a session that always
/// throws cannot tell "the button did nothing" apart from "the button ran and
/// the camera is still refused".
class _FailingSession extends CameraSession {
  _FailingSession(this.reason);

  final CameraUnavailableReason reason;
  bool fixed = false;
  int starts = 0;
  int stops = 0;

  /// Records whether the caller asked for the system prompt, so a test can
  /// prove the automatic paths do NOT and the user-initiated one does.
  final List<bool> requestedPermission = [];

  @override
  Future<void> start({bool requestPermission = false}) async {
    starts++;
    requestedPermission.add(requestPermission);
    if (fixed) return;
    throw CameraUnavailable(reason);
  }

  @override
  Future<void> stop() async => stops++;
}

/// Answers the Settings call without a platform channel.
class _FakePermissionGate extends CameraPermissionGate {
  _FakePermissionGate({this.opens = true, this.throws = false});

  final bool opens;
  final bool throws;
  int openCalls = 0;

  @override
  Future<bool> openSettings() async {
    openCalls++;
    if (throws) throw Exception('platform refused');
    return opens;
  }
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

    testWidgets('says that recognising a machine sends the photo to the cloud',
        (tester) async {
      // The scanner tries Gemini FIRST and only falls back to the on-device
      // model, so every recognition uploads a photograph — one that, in a gym,
      // contains other people. Nothing on this screen said so, while the
      // form-check screen one tab away promised "no frames are uploaded".
      //
      // Asserted on the rendered text, not on the widget's existence: a strip
      // that renders an empty or unrelated string would satisfy a key-only
      // check while telling the user nothing.
      await pumpScan(tester);
      expect(find.byKey(const Key('scan-privacy-strip')), findsOneWidget);

      final strip = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('scan-privacy-strip')),
          matching: find.byType(Text),
          matchRoot: true,
        ),
      );
      final text = strip.data ?? '';
      expect(text, contains('Google'),
          reason: 'name who receives the photo, not "a third party"');
      expect(text.toLowerCase(), contains('on-device'),
          reason: 'the fallback is part of an honest description');
      expect(text.toLowerCase(), contains('other people'),
          reason: 'bystanders in a gym are the part users do not expect');
    });

    testWidgets('the viewfinder takes most of the screen', (tester) async {
      // Operator point 4 asked for a viewfinder big enough to fit a machine;
      // point 6, later, asked for the rest of it — "камера была почти во весь
      // экран" — after a screen recording showed a wide empty band above it.
      // So this no longer pins a 3:4 box, it pins the share of the screen.
      await pumpScan(tester);
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final preview = tester.getRect(find.byType(LiveEquipmentPreview));
      expect(preview.height / screen, greaterThan(0.6));

      final frame = tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(frame.widthFactor, 0.75);
      expect(frame.heightFactor, 0.75);
    });

    testWidgets('nothing separates the app bar from the viewfinder',
        (tester) async {
      // The band the operator circled: this page wrapped its list in a
      // SafeArea AND padded 88 from the top, but `FrostedScaffold` already
      // draws the body behind the bar — so the status-bar inset was counted
      // twice, about 128 logical points of empty purple.
      await pumpScan(tester);
      expect(
        find.ancestor(
          of: find.byType(LiveEquipmentPreview),
          matching: find.byType(SafeArea),
        ),
        findsNothing,
        reason: 'a SafeArea here double-counts the status bar',
      );
      // The viewfinder starts just under a 64pt bar plus the inset, not a
      // screen-eighth below it.
      final top = tester.getRect(find.byType(LiveEquipmentPreview)).top;
      expect(top, lessThan(110));
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

  /// R2.9 — the camera-off overlay must name the cause and offer the action
  /// that fixes THAT cause. Before this gate every failure rendered one title
  /// ("Camera unavailable"), the raw exception in the body, and no button.
  group('ScannerPage camera-unavailable states', () {
    Future<_FailingSession> pumpFailing(
      WidgetTester tester,
      CameraUnavailableReason reason, {
      CameraPermissionGate? gate,
    }) async {
      final session = _FailingSession(reason);
      await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(session),
        if (gate != null) cameraPermissionGateProvider.overrideWithValue(gate),
      ]);
      // Armed from a post-frame callback; the failure lands on the pump after.
      await tester.pump();
      await tester.pump();
      return session;
    }

    testWidgets('an ungranted permission explains before it asks',
        (tester) async {
      // `PermissionStatus.denied` means "never asked" AND "asked once,
      // refused" on Android — indistinguishable. Titling this card "access
      // denied" would be a false statement for every first-time user.
      await pumpFailing(tester, CameraUnavailableReason.permissionDenied);

      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-retry')), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-open-settings')), findsNothing);
    });

    testWidgets('arriving on the page never triggers the system prompt',
        (tester) async {
      // The page arms on arrival, on route change and on resume. Requesting
      // there would put the OS dialog in front of someone who never asked,
      // once per foreground event.
      final session =
          await pumpFailing(tester, CameraUnavailableReason.permissionDenied);

      expect(session.requestedPermission, isNotEmpty);
      expect(session.requestedPermission.every((asked) => !asked), isTrue,
          reason: 'automatic arming must not prompt');
    });

    testWidgets('tapping the permission button is what asks', (tester) async {
      final session =
          await pumpFailing(tester, CameraUnavailableReason.permissionDenied);

      await tester.tap(find.byKey(const Key('scan-camera-retry')));
      await tester.pump();
      await tester.pump();

      expect(session.requestedPermission.last, isTrue,
          reason: 'the user asking for the camera IS the contextual request');
    });

    testWidgets('a permanently-refused permission offers Settings, not retry',
        (tester) async {
      await pumpFailing(
          tester, CameraUnavailableReason.permissionPermanentlyDenied);

      expect(find.text('Camera access is blocked'), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-open-settings')), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-retry')), findsNothing);
    });

    testWidgets('no camera offers no action at all', (tester) async {
      // A retry button for hardware that does not exist would be a lie with a
      // button on it. The gallery path stays available below the viewfinder.
      await pumpFailing(tester, CameraUnavailableReason.noCamera);

      expect(find.text('No camera on this device'), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-retry')), findsNothing);
      expect(find.byKey(const Key('scan-camera-open-settings')), findsNothing);
    });

    testWidgets('a failed init offers a retry', (tester) async {
      await pumpFailing(tester, CameraUnavailableReason.initializationFailed);

      expect(find.text('Camera could not start'), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-retry')), findsOneWidget);
    });

    testWidgets('the four causes do not share one message', (tester) async {
      // The regression this gate exists for: one title for every cause.
      final titles = <String>{};
      for (final reason in CameraUnavailableReason.values) {
        await pumpFailing(tester, reason);
        final overlay = find.byKey(const Key('scan-camera-unavailable'));
        final texts = tester
            .widgetList<Text>(
                find.descendant(of: overlay, matching: find.byType(Text)))
            .map((t) => t.data)
            .whereType<String>();
        titles.add(texts.first);
      }
      expect(titles, hasLength(CameraUnavailableReason.values.length));
    });

    testWidgets('retry re-arms the camera and clears the overlay',
        (tester) async {
      final session =
          await pumpFailing(tester, CameraUnavailableReason.permissionDenied);
      final startsBeforeRetry = session.starts;

      // What the user does after granting access in the system dialog.
      session.fixed = true;
      await tester.tap(find.byKey(const Key('scan-camera-retry')));
      // Explicit pumps, not pumpAndSettle: a restored viewfinder renders the
      // preview's own warming spinner, which animates forever and never
      // settles.
      await tester.pump();
      await tester.pump();

      expect(session.starts, greaterThan(startsBeforeRetry));
      expect(find.byKey(const Key('scan-camera-unavailable')), findsNothing);
      expect(find.byType(LiveEquipmentPreview), findsOneWidget);
    });

    testWidgets('no raw exception text reaches the screen', (tester) async {
      // Never show internal exceptions to users. The old body interpolated the
      // caught object straight into the sentence.
      await pumpFailing(tester, CameraUnavailableReason.initializationFailed);

      expect(find.textContaining('CameraException'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('CameraUnavailableReason'), findsNothing);
    });

    testWidgets('a Settings screen that will not open says so', (tester) async {
      // Open Settings is the ONLY action for a permanently-refused
      // permission. A platform that declines the intent — some locked-down
      // Android builds do — used to leave the user tapping a dead button.
      final gate = _FakePermissionGate(opens: false);
      await pumpFailing(
          tester, CameraUnavailableReason.permissionPermanentlyDenied,
          gate: gate);

      await tester.tap(find.byKey(const Key('scan-camera-open-settings')));
      await tester.pump();

      expect(gate.openCalls, 1);
      expect(find.textContaining('Could not open Settings'), findsOneWidget);
    });

    testWidgets('a throwing Settings call is reported, not swallowed',
        (tester) async {
      final gate = _FakePermissionGate(throws: true);
      await pumpFailing(
          tester, CameraUnavailableReason.permissionPermanentlyDenied,
          gate: gate);

      await tester.tap(find.byKey(const Key('scan-camera-open-settings')));
      await tester.pump();

      expect(find.textContaining('Could not open Settings'), findsOneWidget);
    });

    testWidgets('a Settings screen that opens stays quiet', (tester) async {
      final gate = _FakePermissionGate();
      await pumpFailing(
          tester, CameraUnavailableReason.permissionPermanentlyDenied,
          gate: gate);

      await tester.tap(find.byKey(const Key('scan-camera-open-settings')));
      await tester.pump();

      expect(gate.openCalls, 1);
      expect(find.textContaining('Could not open Settings'), findsNothing);
    });
  });
}
