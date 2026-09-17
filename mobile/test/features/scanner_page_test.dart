import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/camera/camera_availability.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/state/recognition_history_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/live_recognition.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:fitness_app/features/scanner/widgets/scan_frame.dart';
import 'package:fitness_app/features/visual_equipment/widgets/live_equipment_preview.dart';
import 'package:fitness_app/shared/widgets/app_buttons.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

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

/// Never answers — models a recognition call that hangs rather than fails.
class _HangingService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) =>
      Completer<List<VisualMatch>>().future;
}

class _ThrowingService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      throw const VisualEquipmentException('model missing');
}

/// Answers with matches and reports having used the on-device fallback.
class _OfflineAnsweringService implements VisualEquipmentService,
    FallbackReportingRecogniser {
  @override
  bool lastAnsweredOffline = true;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      const [VisualMatch(equipmentId: 'leg_press', confidence: 0.9)];
}

/// Starts fine, then stops itself the way the frame-stall watchdog does.
class _SelfStoppingSession extends CameraSession {
  final ValueNotifier<CameraUnavailable?> _stopped =
      ValueNotifier<CameraUnavailable?>(null);

  @override
  ValueListenable<CameraUnavailable?> get selfStopped => _stopped;

  void stall() => _stopped.value =
      const CameraUnavailable(CameraUnavailableReason.initializationFailed);

  @override
  Future<void> start({bool requestPermission = false}) async {}

  @override
  Future<void> stop() async {}
}

/// A session whose low-light verdict a test can flip.
class _LightSession extends CameraSession {
  final ValueNotifier<bool> dark = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isLowLight => dark;

  @override
  Future<void> start({bool requestPermission = false}) async {}

  @override
  Future<void> stop() async {}
}

/// Answers the gallery pick without a platform channel.
///
/// The page's `_classify` — and with it `_lastScannedPath`, the remember rule
/// and the retry guard — has exactly two entry points, and both used to be out
/// of reach here. The camera one still is: it needs a real capture AND reads
/// the file back off disk to crop it. The gallery one only ever hands the
/// picked PATH to the controller ([ScannerPage] `_recogniseFromGallery`), so
/// with the picker faked there is nothing platform-bound left in it — the
/// mocked service is perfectly happy with a path that never existed.
///
/// This corrects a claim made while building R2: that the retry guard was
/// unreachable from a host test. That was true of the camera path, and was
/// generalised to both.
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker({this.path = '/tmp/picked.jpg'});

  /// null models the user backing out of the picker.
  final String? path;
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    return path == null ? null : XFile(path!);
  }
}

/// Installs [_FakeImagePicker] for one test and puts the real one back after.
///
/// `ImagePickerPlatform.instance` is process-global static state; leaving a
/// fake behind would silently change every test that runs later in this file.
_FakeImagePicker _useFakePicker({String? path = '/tmp/picked.jpg'}) {
  final previous = ImagePickerPlatform.instance;
  final fake = _FakeImagePicker(path: path);
  ImagePickerPlatform.instance = fake;
  addTearDown(() => ImagePickerPlatform.instance = previous);
  return fake;
}

/// Counts calls at the boundary that costs money.
///
/// `classifyFile` IS the paid cloud call. Asserting on rendered state instead
/// would not distinguish one recognition from two racing ones that happen to
/// agree — and the cost, the duplicate history row and the last-write-wins are
/// all on this side of the boundary.
class _CountingService implements VisualEquipmentService {
  _CountingService(this.results);

  final List<VisualMatch> results;
  int calls = 0;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    calls++;
    return rankTopK(results, limit: topK);
  }
}

/// Fails the first call, then hangs — the exact shape the retry card is for.
///
/// The hang is deliberate: it holds the retry in flight so a second tap in the
/// SAME frame meets the in-flight guard rather than a rebuilt, already-disabled
/// button. Those are two different defences and only one of them is the guard.
class _RetryProbeService implements VisualEquipmentService {
  int calls = 0;
  final Completer<List<VisualMatch>> _pending =
      Completer<List<VisualMatch>>();

  /// Lets the in-flight retry finish, so the controller's `.timeout()` Timer is
  /// cancelled and the test does not end with one pending.
  void finish() => _pending.complete(
      const [VisualMatch(equipmentId: 'leg_press', confidence: 0.95)]);

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    calls++;
    if (calls == 1) throw const VisualEquipmentException('model missing');
    return _pending.future;
  }
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

/// Feeds [equipmentExerciseIdsProvider] a fixed exercise-id set per
/// equipment, the same shape `last_session_card_test.dart` uses to prove
/// [LastSessionCard] against real providers rather than a mocked one.
class _FakeEquipmentRepository implements EquipmentRepository {
  _FakeEquipmentRepository(this.exerciseIds);
  final List<String> exerciseIds;

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => [
        for (final id in exerciseIds)
          ExerciseItem.fromJson({
            'id': id,
            'title': id,
            'equipmentId': equipmentId,
            'durationMinutes': 10,
            'difficulty': 'beginner',
            'muscles': const <String>[],
            'steps': const ['Step'],
          }),
      ];

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => const [];

  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;

  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
}

WorkoutSession _scanTestSession({
  required String id,
  required String exerciseId,
  required DateTime completedAt,
  double? weightKg,
  int? reps,
}) =>
    WorkoutSession(
      id: id,
      title: exerciseId,
      status: WorkoutSessionStatus.completed,
      startedAt: completedAt.subtract(const Duration(minutes: 20)),
      completedAt: completedAt,
      durationMinutes: 20,
      exercises: [
        WorkoutSessionExercise(
          exerciseId: exerciseId,
          exerciseTitle: exerciseId,
          sets: [(weightKg: weightKg, reps: reps)],
        ),
      ],
    );

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
        // Under a Scaffold, as `MainShell` hosts it in the app: the page's
        // SnackBars need a Scaffold to land on, and since SCAN-G1 the page
        // no longer brings its own (`FrostedScaffold` is gone).
        GoRoute(
          path: '/scan',
          builder: (_, __) => const Scaffold(
            backgroundColor: Colors.transparent,
            body: ScannerPage(),
          ),
        ),
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

  /// Runs the REAL gallery path: scrolls the button in, taps it, and lets the
  /// picked path travel through the page's own `_classify`.
  ///
  /// Requires [_useFakePicker] to have been called. Two pumps rather than
  /// `pumpAndSettle`: the viewfinder's warming spinner animates for as long as
  /// the fake session publishes no surface, so settling never arrives.
  Future<void> tapGallery(WidgetTester tester) async {
    final gallery = find.byKey(const Key('scan-recognise-gallery'));
    await tester.scrollUntilVisible(gallery, 120);
    await tester.tap(gallery);
    await tester.pump();
    await tester.pump();
  }

  group('ScannerPage', () {
    testWidgets('photo recognition is the one and only path — no QR',
        (tester) async {
      // Operator point 7: QR is removed outright, photo recognition stays.
      await pumpScan(tester);
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('scan-recognise-camera')), findsOneWidget);
      expect(find.text('Recognise'), findsOneWidget);
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

    // SCAN-G1 (core/SCAN_G1_SCOPE.md). The screen is the reference's Scan
    // screen: a 230px viewfinder card with 16px gutters under the title, the
    // one primary button under it, and no sheet. The four tests that pinned
    // the previous full-bleed-camera-plus-sheet layout are replaced by these;
    // the pixel-level contract is `scan_reference_geometry_test.dart` and
    // `tools/design/scan_fidelity_check.py`, this is the structural one.
    testWidgets('the viewfinder is the reference card: 230px tall, 16px in',
        (tester) async {
      await pumpScan(tester);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final preview = tester.getRect(find.byType(LiveEquipmentPreview));
      expect(preview.height, closeTo(230, 0.5),
          reason: '`height:230px` (Sunset.dc.html:186)');
      expect(preview.left, closeTo(16, 0.5), reason: '`margin:0 16px`');
      expect(preview.width, closeTo(width - 32, 0.5));
      expect(find.byType(ScanFrame), findsOneWidget);
      expect(find.byKey(const Key('scan-hint')), findsOneWidget);
      expect(find.text('ALIGN THE MACHINE IN FRAME'), findsOneWidget);
    });

    testWidgets('the card sits under the title at the reference spacing',
        (tester) async {
      // Reference: title top 52, card top 116.1 with a 46px status bar --
      // 64.1px apart. The test harness has no status bar, so only the
      // distance is pinned here; the absolute position is the geometry
      // test's job.
      await pumpScan(tester);
      final title = tester.getTopLeft(find.text('Scan'));
      final card = tester.getRect(find.byType(LiveEquipmentPreview));
      expect(card.top - title.dy, closeTo(64.1, 3));
      expect(
        find.ancestor(
          of: find.byType(LiveEquipmentPreview),
          matching: find.byType(SafeArea),
        ),
        findsNothing,
        reason: 'HudScreenBody already pads the status bar; a SafeArea here '
            'would count it twice',
      );
    });

    testWidgets('no sheet: one list, controls visible without a drag',
        (tester) async {
      await pumpScan(tester);
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      final primary = tester.getRect(find.byKey(const Key('scan-recognise-camera')));
      final card = tester.getRect(find.byType(LiveEquipmentPreview));
      expect(primary.top - card.bottom, closeTo(14, 0.5),
          reason: '`margin:14px 16px 18px` (Sunset.dc.html:221)');
      expect(primary.height, closeTo(52, 1),
          reason: 'padding 16 + 20px glyph line');
      expect(primary.bottom, lessThan(screen));
      expect(find.byKey(const Key('scan-recognise-gallery')), findsOneWidget);
    });

    testWidgets('the live toggle sits in the controls row and still works',
        (tester) async {
      final container = await pumpScan(tester);
      expect(container.read(liveModeEnabledProvider), isFalse);

      await tester.tap(find.byKey(const Key('scan-live-toggle')));
      await tester.pump();

      expect(container.read(liveModeEnabledProvider), isTrue,
          reason: 'the control moved under the button, not out of the app');
    });

    testWidgets('Scan again returns to the aiming state', (tester) async {
      // SCAN-G1 R4. After a locked match the primary button reads "Scan
      // again"; tapping it forgets the answer -- the match card leaves, the
      // hint returns to "align", the button reads "Recognise" -- without
      // touching the camera.
      //
      // FITAPP-EQUIP-ACC-2026-09-17: a cloud classifier match no longer
      // settles as confident, so this locks the match through the
      // printed-text anchor instead (the only remaining reachable path to
      // ScanOutcome.confident) -- "leg press" is in machine_text_anchor.dart's
      // own phrase table at confidence 0.92, which is also why the ring
      // assertion below is unchanged.
      final spy = _SpySession();
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(spy),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);
      await container.read(equipmentListProvider.future);
      await tester.pump();
      final stopsBefore = spy.stops;
      _useFakePicker();
      await tapGallery(tester);

      expect(find.byKey(const Key('scan-match-card')), findsOneWidget);
      expect(find.text('MACHINE LOCKED'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      expect(find.text('Recognise'), findsNothing);
      expect(find.text('92'), findsOneWidget, reason: 'the ring value');

      await tester.tap(find.byKey(const Key('scan-recognise-camera')));
      await tester.pump();

      expect(find.byKey(const Key('scan-match-card')), findsNothing);
      expect(find.text('ALIGN THE MACHINE IN FRAME'), findsOneWidget);
      expect(find.text('Recognise'), findsOneWidget);
      expect(container.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.noEquipment);
      expect(spy.stops, stopsBefore, reason: 'the camera never stopped');
    });

    testWidgets('the hint says RECOGNISING while a capture is classified',
        (tester) async {
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        // A short timeout so the hanging call settles before the test ends
        // (a pending 30s Timer fails the binding's teardown).
        recogniseTimeoutProvider
            .overrideWithValue(const Duration(milliseconds: 30)),
        visualEquipmentServiceProvider.overrideWithValue(_HangingService()),
      ]);
      final scan = container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/hangs.jpg');
      await tester.pump();

      expect(find.text('RECOGNISING…'), findsOneWidget);
      final button = tester.widget<HudButton>(
          find.byKey(const Key('scan-recognise-camera')));
      expect(button.enabled, isFalse,
          reason: 'no second capture while one is in flight');

      await tester.pump(const Duration(milliseconds: 50));
      await scan;
      await tester.pump();
      expect(find.text('RECOGNISING…'), findsNothing);
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
      // FITAPP-EQUIP-ACC-2026-09-17: locked through the printed-text anchor
      // -- the only remaining reachable path to ScanOutcome.confident -- same
      // as the test above.
      final spy = _SpySession();
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(spy),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);
      await container.read(equipmentListProvider.future);
      await tester.pump();
      final before = spy.stops;

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();
      // The match card's CTA (the reference's "Open exercises"); the name
      // itself is not the tap target and also appears on the history chip.
      final cta = find.byKey(const Key('scan-open-exercises'));
      await tester.scrollUntilVisible(cta, 120);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('equipment leg_press'), findsOneWidget);
      expect(spy.stops, greaterThan(before),
          reason: 'navigating away must release the camera');
    });

    testWidgets(
        'a cloud match, however confident, renders as alternatives, not a locked card',
        (tester) async {
      // FITAPP-EQUIP-ACC-2026-09-17: measurement (48.5% live top-1 on 33 real
      // gym photos) showed neither "one candidate" nor "a wide top1/top2
      // margin" separates a correct cloud answer from a confident-sounding
      // wrong one, so every cloud match -- including a single one at 0.8 with
      // nothing to compare against -- now settles as alternatives instead of
      // locking a match card. This replaces the old
      // "renders classifier matches with confidence" test, which asserted the
      // exact `confident`-plus-runner-up rendering this fix removes.
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
            VisualMatch(equipmentId: 'treadmill', confidence: 0.2),
          ]),
        ),
      ]);

      // Drives the controller directly, which is enough for a rendering
      // assertion. (The gallery button IS tappable here — see _useFakePicker —
      // but this test is about what the matches list renders, not about how
      // the result got there.)
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(
          container.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.alternatives);
      // No locked card -- both candidates are plain rows in the "not sure"
      // list, each with its own confidence figure.
      expect(find.byKey(const Key('scan-match-card')), findsNothing);
      expect(find.text('MACHINE LOCKED'), findsNothing);
      expect(find.text('Not sure — closest matches'), findsOneWidget);
      expect(find.text('leg press'), findsOneWidget);
      expect(find.text('80% confidence'), findsOneWidget);
      expect(find.text('treadmill'), findsOneWidget);
      expect(find.text('20% confidence'), findsOneWidget);
      // The classifier fills labelHint too, with its own internal label. That
      // must never be captioned as something read off the machine.
      expect(find.textContaining('Read on the machine'), findsNothing);
    });

    // SCAN-G1 review (MAJOR): the printed-text honesty note used to render
    // INSIDE ScanMatchCard, so a reachable production state grew the
    // canonical card past what R6's fidelity gate measures (whose fixture
    // never exercises this branch). Proves both halves of the fix: the note
    // still reaches the user, and the card it describes stays exactly the
    // shape the reference defines.
    testWidgets(
        'a printed-text match keeps its honesty note out of the canonical card',
        (tester) async {
      // FITAPP-EQUIP-ACC-2026-09-17: a cloud classifier can no longer settle
      // as confident at all (even with a `MatchSource.printedText` tag
      // fabricated directly on its output, as this test used to do), so this
      // now goes through the REAL printed-text anchor -- the only remaining
      // path to ScanOutcome.confident. "Falcon Incline" is deliberately not
      // in machine_text_anchor.dart's phrase table, so the match comes from
      // the catalogue-name fallback (`_matchByCatalogueName`), which is what
      // sets `labelHint` to the exact printed phrase. `normaliseText` strips
      // everything but letters, and `_matchByCatalogueName` only considers
      // MULTI-word catalogue names -- a digit-bearing single "word" like
      // "Cybertron 9000" silently drops to one word and is skipped, which is
      // what the first version of this fixture got wrong.
      final container = await pumpScan(tester, overrides: [
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('FALCON INCLINE')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Falcon Incline',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);
      await container.read(equipmentListProvider.future);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      final noteFinder = find.textContaining('FALCON INCLINE');
      expect(noteFinder, findsOneWidget,
          reason: 'the honesty note must still reach the user');
      expect(
        find.descendant(
            of: find.byKey(const Key('scan-match-card')),
            matching: noteFinder),
        findsNothing,
        reason: 'R4: the canonical match card ends at its CTA -- the note '
            'is a production extra below the one button, not inside it',
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('scan-match-card')),
            matching: find.byKey(const Key('scan-open-exercises'))),
        findsOneWidget,
        reason: 'the card itself is still the reference card, CTA and all',
      );
    });

    // Gate D -> Scanner wiring: the same Level-1 equipment-type memory the
    // equipment detail page shows now also appears under a confident scan
    // result. These prove the WIRING (real equipment id reaches
    // LastSessionCard, and it stays honest when there is nothing to say) --
    // the arithmetic itself is `equipment_type_history_test.dart`'s job.
    testWidgets(
        'a confident match with real logged history shows Level-1 memory',
        (tester) async {
      // FITAPP-EQUIP-ACC-2026-09-17: locked through the printed-text anchor.
      // `_FakeEquipmentRepository.listEquipment()` returns an empty list, but
      // that is enough -- "leg press" is matched from
      // machine_text_anchor.dart's own phrase table, not from the catalogue
      // content; the catalogue only needs to have resolved (non-null) for the
      // anchor to run at all.
      final when = DateTime.now().subtract(const Duration(days: 3));
      final container = await pumpScan(tester, overrides: [
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentRepositoryProvider
            .overrideWithValue(_FakeEquipmentRepository(['leg_press_row'])),
        workoutSessionsProvider.overrideWith((_) => Stream.value([
              _scanTestSession(
                id: 's1',
                exerciseId: 'leg_press_row',
                completedAt: when,
                weightKg: 70,
                reps: 8,
              ),
            ])),
        workoutSessionTotalsProvider.overrideWith(
            (_) async => WorkoutLogTotals(total: 1, longestStreakDays: 1)),
      ]);
      await container.read(equipmentListProvider.future);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      // LastSessionCard reads three independently-async providers
      // (exercise ids, the session stream, the totals future) before it has
      // anything to render; settle all three before asserting, the same
      // reasoning `session_digest_providers_test.dart` documents for its own
      // multi-provider `settle()` helper.
      await container.read(equipmentExerciseIdsProvider('leg_press').future);
      await container.read(workoutSessionsProvider.future);
      await container.read(workoutSessionTotalsProvider.future);
      await tester.pump();

      expect(find.text('Your last session with this equipment'),
          findsOneWidget);
      expect(find.text('70 kg × 8 reps'), findsOneWidget);
    });

    testWidgets(
        'a confident match with no logged history shows no fake memory',
        (tester) async {
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
          ]),
        ),
        equipmentRepositoryProvider
            .overrideWithValue(_FakeEquipmentRepository(['leg_press_row'])),
        // An empty (not never-emitting) stream: a real snapshot that says
        // "checked, zero sessions" -- `Stream.empty()` never emits at all,
        // which would leave `workoutSessionsProvider.future` hanging forever
        // and prove nothing about the CONFIRMED-no-history path this test
        // names.
        workoutSessionsProvider
            .overrideWith((_) => Stream.value(const <WorkoutSession>[])),
        workoutSessionTotalsProvider
            .overrideWith((_) async => WorkoutLogTotals.zero),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await container.read(equipmentExerciseIdsProvider('leg_press').future);
      await container.read(workoutSessionsProvider.future);
      await container.read(workoutSessionTotalsProvider.future);
      await tester.pump();

      // A confirmed empty history earns no card at all -- never a fabricated
      // "0 kg" or "never used" line (see LastSessionCard's own doc comment).
      expect(
          find.text('Your last session with this equipment'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets(
        "history logged on a DIFFERENT equipment type is excluded from this match's memory",
        (tester) async {
      final when = DateTime.now().subtract(const Duration(days: 1));
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
          ]),
        ),
        // The fake repository only ever maps exercise ids for the equipment
        // id it is asked about, so a session logged against an exercise
        // that belongs to a DIFFERENT equipment type's id set never matches.
        equipmentRepositoryProvider
            .overrideWithValue(_FakeEquipmentRepository(['leg_press_row'])),
        workoutSessionsProvider.overrideWith((_) => Stream.value([
              _scanTestSession(
                id: 's1',
                exerciseId: 'lat_pulldown_row',
                completedAt: when,
                weightKg: 40,
                reps: 10,
              ),
            ])),
        workoutSessionTotalsProvider.overrideWith(
            (_) async => WorkoutLogTotals(total: 1, longestStreakDays: 1)),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await container.read(equipmentExerciseIdsProvider('leg_press').future);
      await container.read(workoutSessionsProvider.future);
      await container.read(workoutSessionTotalsProvider.future);
      await tester.pump();

      // This is the confirmed-no-history case for `leg_press` -- the one
      // logged session belongs to a different equipment type -- so the whole
      // card is absent, not just the number.
      expect(
          find.text('Your last session with this equipment'), findsNothing);
      expect(find.text('40 kg × 10 reps'), findsNothing);
    });

    testWidgets('undecided (alternatives) matches attach no memory at all',
        (tester) async {
      // Below the honesty threshold (`_Matches._unsureBelow`), so neither
      // candidate headlines -- and neither should carry a memory card, since
      // the app has not actually resolved which equipment the user is
      // looking at.
      final when = DateTime.now().subtract(const Duration(days: 1));
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.3),
            VisualMatch(equipmentId: 'treadmill', confidence: 0.25),
          ]),
        ),
        equipmentRepositoryProvider
            .overrideWithValue(_FakeEquipmentRepository(['leg_press_row'])),
        workoutSessionsProvider.overrideWith((_) => Stream.value([
              _scanTestSession(
                id: 's1',
                exerciseId: 'leg_press_row',
                completedAt: when,
                weightKg: 70,
                reps: 8,
              ),
            ])),
        workoutSessionTotalsProvider.overrideWith(
            (_) async => WorkoutLogTotals(total: 1, longestStreakDays: 1)),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();
      await tester.pump();

      expect(find.text('Not sure — closest matches'), findsOneWidget);
      expect(
          find.text('Your last session with this equipment'), findsNothing);
    });

    testWidgets('a match read off the machine says so, and shows the phrase',
        (tester) async {
      // B5b. The whole value of the text anchor to a USER is that the
      // identification is checkable: they can look at the shroud and see the
      // same words. Without this the anchor is just a silently better guess.
      final container = await pumpScan(tester, overrides: [
        // The classifier would say `treadmill` for this machine — that is what
        // v1 actually did to the operator's abduction machine, at 0.892.
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'treadmill', confidence: 0.89),
          ]),
        ),
        machineTextRecogniserProvider.overrideWithValue(
          FakeMachineTextRecogniser(
              'NAUTILUS\nINSPIRATION\nABDUCTION / ADDUCTION'),
        ),
        // The anchor reads the catalogue and SKIPS itself while that is
        // unresolved -- deliberately, so a slow catalogue cannot block a scan.
        // Proven, not assumed: without a resolved catalogue the screen renders
        // `treadmill | 89% confidence`, i.e. the classifier answered because
        // the anchor stood down.
        //
        // OVERRIDDEN, not awaited. `await
        // container.read(equipmentListProvider.future)` HUNG this test for 6.5
        // minutes (log frozen 22:32:44 -> 22:39:14 with flutter_tester.exe
        // alive): the real repository reads the catalogue off the asset bundle
        // and that never completes here. A widget test that hangs is worse
        // than one that fails -- it looks like it is still working.
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'hip_abductor_adductor',
                name: 'Hip abductor / adductor',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);

      // BOTH are needed, and each for a different reason:
      //   - the override, so the catalogue resolves at all (awaiting the real
      //     asset-backed one hung this test for 6.5 minutes);
      //   - the await, because a FutureProvider is still async even when its
      //     body returns immediately, so the first `read(...).valueOrNull`
      //     inside the anchor is null without it -- and the anchor then stands
      //     down, the classifier answers, and this test fails claiming the
      //     rendering is broken when it is the setup that is.
      await container.read(equipmentListProvider.future);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(find.text('Read on the machine: ABDUCTION ADDUCTION'),
          findsOneWidget);
      // And the classifier's answer is not on screen at all: a decisive
      // reading short-circuits it.
      expect(find.text('treadmill'), findsNothing);
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

    testWidgets('an empty history explains itself instead of vanishing',
        (tester) async {
      // Reverses the previous behaviour, which hid the section entirely when
      // empty. R2.6 requires an empty history to have a useful state, and the
      // old one meant a user could not learn the feature existed until they
      // had already used it — the one moment the explanation is worthless.
      await pumpScan(tester);
      await tester.scrollUntilVisible(
          find.byKey(const Key('scan-history-empty')), 120);

      expect(find.byKey(const Key('scan-history-empty')), findsOneWidget);
      expect(find.byKey(const Key('scan-history')), findsNothing,
          reason: 'no chips without entries');
      expect(find.text('My machines'), findsOneWidget);
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

    testWidgets('a recognition timeout renders a retry, not a spinner',
        (tester) async {
      // R2.2 state 11. The call used to be unbounded: a request that hung left
      // the spinner up forever, with no retry and no way out but leaving.
      final container = await pumpScan(tester, overrides: [
        // A working camera, so the page has exactly one Scrollable. Without
        // it the real session hits the permission channel, fails, and the
        // camera-unavailable overlay adds its own scroll view — which
        // scrollUntilVisible then drives instead of the page's list.
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        recogniseTimeoutProvider
            .overrideWithValue(const Duration(milliseconds: 30)),
        visualEquipmentServiceProvider.overrideWithValue(_HangingService()),
      ]);

      // Started, not awaited: the timeout is a Timer, and inside testWidgets
      // timers only fire when the test clock is pumped. Awaiting first would
      // deadlock — the future is waiting on a timer the await prevents from
      // ever running.
      final scan = container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/hangs.jpg');
      await tester.pump(const Duration(milliseconds: 50));
      await scan;
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const Key('scan-timeout')), 120);

      expect(find.byKey(const Key('scan-timeout')), findsOneWidget);
      expect(find.byKey(const Key('scan-retry-recognition')), findsOneWidget);
      // The recognition itself has settled. Asserted on the state rather than
      // on "no CircularProgressIndicator anywhere": the viewfinder shows its
      // own warming spinner while the fake session publishes no surface, and
      // that one is not the spinner this rule is about.
      expect(container.read(visualEquipmentControllerProvider).isLoading,
          isFalse);
    });

    testWidgets('a dark viewfinder says so, without covering the camera',
        (tester) async {
      // R2.2 state 9. The guidance is "add light" — a user who cannot see what
      // the camera sees cannot tell whether they followed it, so the banner
      // sits over the preview rather than replacing it.
      final session = _LightSession();
      await pumpScan(tester,
          overrides: [scanCameraSessionProvider.overrideWithValue(session)]);
      await tester.pump();

      expect(find.byKey(const Key('scan-low-light')), findsNothing);

      session.dark.value = true;
      await tester.pump();

      expect(find.byKey(const Key('scan-low-light')), findsOneWidget);
      expect(find.byType(LiveEquipmentPreview), findsOneWidget,
          reason: 'the viewfinder must stay visible under the banner');

      session.dark.value = false;
      await tester.pump();
      expect(find.byKey(const Key('scan-low-light')), findsNothing);
    });

    testWidgets(
        'the low-light banner stays inside the viewfinder card, under the status bar',
        (tester) async {
      // MVP1.G2 regression guard, carried over the SCAN-G1 layout change. The
      // banner used to be a second overlay over a full-bleed camera and twice
      // ended up in the wrong place (under the status bar; colliding with
      // the top strip) while this suite, with its zero inset, saw nothing.
      // It now lives INSIDE the card, so the only geometry that matters is
      // that it is within the card -- and the card is below the padded top.
      tester.view.padding = const FakeViewPadding(top: 94);
      addTearDown(tester.view.resetPadding);

      final session = _LightSession()..dark.value = true;
      await pumpScan(tester,
          overrides: [scanCameraSessionProvider.overrideWithValue(session)]);
      await tester.pump();

      final card = tester.getRect(find.byType(LiveEquipmentPreview));
      final banner = tester.getRect(find.byKey(const Key('scan-low-light')));

      expect(card.top, greaterThanOrEqualTo(94),
          reason: 'the whole card clears the simulated status bar inset');
      expect(banner.top, greaterThanOrEqualTo(card.top));
      expect(banner.bottom, lessThanOrEqualTo(card.bottom));
      expect(banner.left, greaterThanOrEqualTo(card.left));
      expect(banner.right, lessThanOrEqualTo(card.right));
    });

    testWidgets('an offline answer says it came from the device',
        (tester) async {
      // R2.2 state 12. The fallback used to be invisible: the user got the
      // weaker answer and was never told the cloud was unreachable, so a poor
      // result read as the app being bad rather than the network being absent.
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        visualEquipmentServiceProvider
            .overrideWithValue(_OfflineAnsweringService()),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const Key('scan-offline-answer')), 120);

      expect(find.byKey(const Key('scan-offline-answer')), findsOneWidget);
      expect(container.read(visualEquipmentControllerProvider).requireValue
          .answeredOffline, isTrue);
    });

    testWidgets('a cloud answer carries no offline note', (tester) async {
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]),
        ),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();

      expect(find.byKey(const Key('scan-offline-answer')), findsNothing);
    });

    testWidgets('a camera that stops itself surfaces a retry, not a spinner',
        (tester) async {
      // The frame-stall watchdog calls stop() and throws nothing — nobody is
      // awaiting it. The page only learned about failures thrown by start(),
      // so this left the preview on its warming spinner forever, with none of
      // the reason-and-retry UI.
      final session = _SelfStoppingSession();
      await pumpScan(tester,
          overrides: [scanCameraSessionProvider.overrideWithValue(session)]);
      await tester.pump();

      expect(find.byKey(const Key('scan-camera-unavailable')), findsNothing);

      session.stall();
      await tester.pump();

      expect(find.byKey(const Key('scan-camera-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('scan-camera-retry')), findsOneWidget);
    });

    testWidgets('a confident result offers the AI Coach', (tester) async {
      // R2.8: reuse the existing sheet at the moment the user is standing in
      // front of the machine, rather than only one screen later.
      //
      // FITAPP-EQUIP-ACC-2026-09-17: locked through the printed-text anchor
      // -- the only remaining reachable path to ScanOutcome.confident.
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);
      await container.read(equipmentListProvider.future);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const Key('scan-ai-coach')), 120);

      expect(find.byKey(const Key('scan-ai-coach')), findsOneWidget);
    });

    testWidgets(
        'N04: a user refused all training is offered no AI Coach here either',
        (tester) async {
      // The coach's answer IS a sets-and-reps prescription. `exercise_page`
      // withholds it structurally for a refused user; this route reached
      // `AiCoachSheet` directly and did not, so someone the app refuses all
      // training could still ask for and receive one.
      //
      // Blocked by a STATED answer -- chest pain during exertion -- not by an
      // unfinished questionnaire, which is the distinction
      // `SafetyContext.blockedByAStatedAnswer` exists to draw and which the
      // test above ('a confident result offers the AI Coach', an un-onboarded
      // user) is the control for.
      // FITAPP-EQUIP-ACC-2026-09-17: locked through the printed-text anchor,
      // so `scan-ai-coach`'s absence proves the safety block, not merely that
      // `alternatives` never renders it (which is what a cloud-classifier
      // fixture would now prove instead, uselessly, since it never reaches
      // `locked` at all).
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({
                for (final q in ParQQuestion.values)
                  q: q == ParQQuestion.chestPain,
              }),
            )),
      ]);
      await container.read(equipmentListProvider.future);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('scan-ai-coach')), findsNothing);
    });

    testWidgets(
        'R-07/F014: a stated health answer withholds the AI Coach here too',
        (tester) async {
      // The second direct route to `AiCoachSheet`, and the reason it gets its
      // own case rather than trusting the equipment page's. Both read
      // `blockedByAStatedAnswer`, but "both call the same getter" is a claim
      // about the source; this measures the scanner.
      //
      // The questionnaire is fully CLEARED, so nothing in the screening can be
      // doing the blocking -- only F014's professional-guidance answer can.
      // The control is 'a confident result offers the AI Coach' above, which
      // runs the same recognition with no safety override at all.
      // FITAPP-EQUIP-ACC-2026-09-17: locked through the printed-text anchor,
      // for the same reason as N04 above.
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({
                for (final q in ParQQuestion.values) q: false,
              }),
              health: const HealthFlags(
                professionalGuidance: ProfessionalGuidanceNeed.reported,
              ),
            )),
      ]);
      await container.read(equipmentListProvider.future);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('scan-ai-coach')), findsNothing);
    });

    testWidgets('an undecided result offers no AI Coach', (tester) async {
      // The coach needs ONE subject. Offering it against a list the app just
      // said it could not choose between would pick one silently — exactly
      // what the alternatives list exists to avoid.
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.45),
            VisualMatch(equipmentId: 'hack_squat', confidence: 0.40),
          ]),
        ),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/close.jpg');
      await tester.pump();

      expect(find.byKey(const Key('scan-ai-coach')), findsNothing);
    });

    testWidgets('a failed recognition shows no raw exception', (tester) async {
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        visualEquipmentServiceProvider.overrideWithValue(_ThrowingService()),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const Key('scan-failed')), 120);

      expect(find.byKey(const Key('scan-failed')), findsOneWidget);
      expect(find.textContaining('model missing'), findsNothing,
          reason: 'internal exceptions must never reach the user');
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

    testWidgets('a confident gallery scan is remembered', (tester) async {
      // The positive control for the test below it. Without one, "an undecided
      // scan writes nothing" passes exactly as happily when NOTHING on the path
      // can write at all — which is how the earlier version of that test
      // passed while never reaching `_remember`.
      //
      // FITAPP-EQUIP-ACC-2026-09-17: a cloud classifier match can no longer
      // settle as confident, so this control now goes through the
      // printed-text anchor instead -- the only remaining reachable path to
      // ScanOutcome.confident and its auto-remember-on-recognise behaviour.
      // `_CountingService`/`service.calls` is dropped: the anchor answers
      // first and the classifier is never reached, same as every other
      // confident-via-anchor test in this file.
      final picker = _useFakePicker();
      final history = MockRecognitionHistoryRepository();
      addTearDown(history.dispose);

      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        recognitionHistoryRepositoryProvider.overrideWithValue(history),
        machineTextRecogniserProvider
            .overrideWithValue(FakeMachineTextRecogniser('leg press')),
        equipmentListProvider.overrideWith((_) async => const [
              EquipmentItem(
                id: 'leg_press',
                name: 'Leg press',
                manufacturer: 'Any',
                category: 'strength',
                description: '',
              ),
            ]),
      ]);
      await container.read(equipmentListProvider.future);
      await tapGallery(tester);

      expect(picker.calls, 1, reason: 'the button opened the picker');
      expect((await history.list()).map((e) => e.equipmentId), ['leg_press'],
          reason: 'a confident scan IS a machine the user identified');
    });

    testWidgets(
        'a cloud alternatives scan is remembered only after the user picks one',
        (tester) async {
      // FITAPP-EQUIP-ACC-2026-09-17, GPT-PM review round 2 (MAJOR): after
      // Option C, a cloud match is never auto-remembered (it is always
      // `alternatives`, and `isWorthRemembering` is false for it) -- so the
      // ONLY way a cloud identification still reaches "My machines" is the
      // user's own tap in this list, which must now write the TAPPED
      // candidate before navigating. Proves both halves: nothing is written
      // before the tap, and exactly the tapped equipment is written after.
      final history = MockRecognitionHistoryRepository();
      addTearDown(history.dispose);

      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        recognitionHistoryRepositoryProvider.overrideWithValue(history),
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
            VisualMatch(equipmentId: 'treadmill', confidence: 0.1),
          ]),
        ),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/machine.jpg');
      await tester.pump();

      expect(
          container.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.alternatives);
      expect(await history.list(), isEmpty,
          reason: 'nothing is written before the user picks one');

      final cta = find.text('treadmill');
      await tester.scrollUntilVisible(cta, 120);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text('equipment treadmill'), findsOneWidget,
          reason: 'the tap still navigates to the picked equipment');
      final written = await history.list();
      expect(written.map((e) => e.equipmentId), ['treadmill'],
          reason: 'exactly the machine the user tapped -- not the top '
              'candidate the model happened to rank first (0.9, leg_press)');
      expect(written.single.confidence, 0.1,
          reason: 'the tapped candidate\'s own confidence, not the top one\'s');
      expect(written.single.source, RecognitionSource.photo);
    });

    testWidgets('an undecided gallery scan is not remembered', (tester) async {
      // `alternatives` is the app saying "I am not sure, you pick". Recording
      // its top candidate would file, as a machine the user identified, one
      // they were never asked about.
      //
      // Restored from R2d, where it was deleted for passing on a technicality:
      // it drove the controller directly, one layer BELOW `_remember`, so the
      // history was empty no matter what the outcome had been. It now goes
      // through the button, and the test above proves this same path does
      // write when the result warrants it.
      final picker = _useFakePicker();
      final history = MockRecognitionHistoryRepository();
      addTearDown(history.dispose);
      final service = _CountingService(const [
        VisualMatch(equipmentId: 'leg_press', confidence: 0.45),
        VisualMatch(equipmentId: 'hack_squat', confidence: 0.40),
      ]);

      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        recognitionHistoryRepositoryProvider.overrideWithValue(history),
        visualEquipmentServiceProvider.overrideWithValue(service),
      ]);
      await tapGallery(tester);

      expect(picker.calls, 1);
      expect(service.calls, 1);
      expect(
          container.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.alternatives,
          reason: 'two close matches are an undecided result');
      expect(await history.list(), isEmpty,
          reason: 'an undecided scan must not become a remembered machine');
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      // `if (picked == null) return;` — a real production branch that only
      // became reachable from a host test with the picker faked. Leaving it
      // uncovered would mean the fake carries a null mode nothing exercises.
      final history = MockRecognitionHistoryRepository();
      addTearDown(history.dispose);
      final service = _CountingService(const [
        VisualMatch(equipmentId: 'leg_press', confidence: 0.95),
      ]);

      final picker = _useFakePicker(path: null);
      final container = await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        recognitionHistoryRepositoryProvider.overrideWithValue(history),
        visualEquipmentServiceProvider.overrideWithValue(service),
      ]);
      await tapGallery(tester);

      expect(picker.calls, 1, reason: 'the picker did open');
      expect(service.calls, 0, reason: 'no image, no paid recognition');
      expect(await history.list(), isEmpty);
      expect(container.read(visualEquipmentControllerProvider).hasError, isFalse,
          reason: 'cancelling is not an error to report');
      // The assertion that actually discriminates. Without the early return,
      // `picked.path` throws on null, the catch turns it into a "could not
      // capture" SnackBar, and every OTHER assertion here still holds —
      // recognition is not reached either way. Deciding to say nothing to a
      // user who chose to back out is the whole behaviour under test.
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a deliberate cancel is not a failure to report');
    });

    testWidgets('a double-tapped retry runs recognition once', (tester) async {
      // Driven through the "Recognition failed" card — a thrown recogniser,
      // not a timeout. Both problem cards carry the same retry button and the
      // same invitation to tap it again. Unguarded, a double tap fired two
      // concurrent recognitions racing on the controller state, the machine
      // card and the history write: two PAID cloud calls, two history rows,
      // last-write-wins on screen.
      //
      // Asserted at `classifyFile` — the paid boundary itself. Asserting on
      // what the screen shows could not tell one recognition from two racing
      // ones that happen to agree.
      _useFakePicker();
      final service = _RetryProbeService();
      await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(_SpySession()),
        visualEquipmentServiceProvider.overrideWithValue(service),
      ]);
      await tapGallery(tester);

      // Scroll to the BUTTON, not to the card that contains it: the page's
      // list is lazy, and a finder resolved against the card leaves the button
      // itself outside the built range.
      final retry = find.byKey(const Key('scan-retry-recognition'));
      await tester.scrollUntilVisible(retry, 120);
      expect(find.byKey(const Key('scan-failed')), findsOneWidget,
          reason: 'a thrown recognition is the failed outcome, not a timeout');
      expect(service.calls, 1, reason: 'the scan that failed');

      // Fire the button's OWN callback twice without a frame in between.
      //
      // Two `tester.tap`s cannot express this: dispatching the first pointer
      // event flushes the rebuild, `classifyFilePath` has already set the state
      // to loading, and the failed card — button and all — is gone before the
      // second tap is delivered. That disappearance is itself a real defence,
      // asserted below; it is simply not the one this half is about. Invoking
      // `onPressed` twice is what a same-frame double arrival (two fingers, a
      // synthesised repeat) actually looks like inside the widget, and it is
      // the only route that reaches the in-flight guard in `_retryLastScan`.
      final onPressed = tester.widget<AppSecondaryButton>(retry).onPressed;
      expect(onPressed, isNotNull, reason: 'the retry button starts enabled');
      onPressed!();
      onPressed();
      await tester.pump();

      expect(service.calls, 2,
          reason: 'one failed scan + exactly one retry; a concurrent second '
              'retry would be a second paid cloud call');

      // The second defence, one layer out: once the frame HAS been rebuilt,
      // the retry control is not offered at all while recognition is in
      // flight, so no further tap can reach the callback.
      expect(retry, findsNothing,
          reason: 'an in-flight retry withdraws the button');

      // Let the retry finish so the controller's timeout Timer is cancelled
      // and the test does not end with one pending.
      service.finish();
      await tester.pump();
      await tester.pump();
    });

    testWidgets(
        'a denied camera hides the Live card instead of spinning forever',
        (tester) async {
      // Before this fix, `_LiveSection` rendered whenever the Live toggle was
      // on regardless of `_cameraFailure` -- with no camera, no frame was
      // ever going to arrive to settle `_LiveCard`'s "searching" spinner, so
      // it spun with no explanation next to the unavailable-camera card.
      await pumpScan(tester, overrides: [
        scanCameraSessionProvider.overrideWithValue(
            _FailingSession(CameraUnavailableReason.permissionDenied)),
        liveModeEnabledProvider.overrideWith((_) => true),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('Camera access needed'), findsOneWidget,
          reason: 'the failure card is still shown');
      expect(find.byKey(const Key('scan-live-searching')), findsNothing,
          reason: 'the Live card must not render over a dead camera');
      expect(find.byKey(const Key('scan-live-result')), findsNothing);
      expect(find.byKey(const Key('scan-live-tentative')), findsNothing);
    });
  });
}
