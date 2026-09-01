import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// The movement-picking screen, added 2026-09-01 between the intro card and the
/// camera.
///
/// The operator described it in one sentence: «на самом экране тренера оставить
/// только подогнать силует под вас и выбор упражнений и кнопку начать. Пока не
/// нажата кнопка начать камера не включется а показывается ролик... где
/// человеко подобный силует с свичащемся скилетом присидает.»
///
/// Three claims in that sentence are testable and all three are load-bearing,
/// so all three are below: the camera really is off, the demonstration really
/// is moving, and the screen really does carry only those controls.
///
/// NOTE for anyone adding a case here: never `pumpAndSettle` on this screen.
/// The demonstration loops for as long as it is displayed, so there is no
/// quiescent frame and `pumpAndSettle` times out rather than arriving.

class _SilentService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int permissionAsks = 0;

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async => permissionAsks++;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async => _frames.close();
}

/// Whose permission ask stays pending until the test releases it.
class _PendingPermissionService extends _SilentService {
  final asked = Completer<void>();

  @override
  Future<void> ensurePermission() {
    permissionAsks++;
    return asked.future;
  }
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

ProviderContainer _container(PoseDetectorService svc) {
  final c = ProviderContainer(
    overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
  );
  addTearDown(c.dispose);
  return c;
}

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// Mount, read the intro card, arrive at the picker. Two `pump`s, never
/// `pumpAndSettle` — see the note at the top of this file.
Future<void> _pumpToSelection(WidgetTester t, ProviderContainer c) async {
  await t.pumpWidget(_page(c));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('coach.intro.continue')));
  await t.pump();
  await t.pump();
}

/// The demonstration's painter for the frame currently on screen.
CustomPainter _demoPainter(WidgetTester t) =>
    t.widget<CustomPaint>(find.byKey(const Key('form_check.demo'))).painter!;

void main() {
  testWidgets(
      'the picker carries the three controls it was asked for, and '
      'nothing that belongs to a running camera', (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final c = _container(svc);
    await _pumpToSelection(t, c);

    expect(c.read(coachSessionProvider).phase, CoachPhase.selection);
    expect(find.byKey(const Key('form_check.exercise.squat')), findsOneWidget);
    expect(find.byKey(const Key('coach.selection.start')), findsOneWidget);
    expect(find.text('Нажмите когда готовы'), findsOneWidget);
    expect(find.byKey(const Key('form_check.demo')), findsOneWidget);
    // A `CustomPaint` announces nothing on its own, so the screen's main
    // content would otherwise be a silent hole for a screen reader.
    expect(
        find.bySemanticsLabel('Показ выбранного движения: силуэт повторяет его'),
        findsOneWidget);

    // «оставить только». The banners moved to the intro card in the previous
    // gate and must not reappear here; the counters, the cue card and the
    // set controls belong to a set that has not started.
    expect(find.byKey(const Key('coach.intro.experimental')), findsNothing);
    expect(find.byKey(const Key('coach.intro.sustainer')), findsNothing);
    expect(find.byKey(const Key('form_check.start_set')), findsNothing);
    expect(find.byKey(const Key('form_check.match')), findsNothing);
    // Camera controls over a screen with no camera: flip, skeleton, avatar,
    // mute. Absent by the icons they are drawn with, because none of them
    // carries a key of its own.
    for (final icon in [
      Icons.cameraswitch,
      Icons.accessibility_outlined,
      Icons.person_outline,
      Icons.volume_up,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: 'no camera to control');
    }
  });

  testWidgets('no camera runs while the picker is on screen', (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final c = _container(svc);
    await _pumpToSelection(t, c);

    // Long enough for several cycles of the demonstration, so this covers
    // "never starts" rather than "has not started yet".
    await t.pump(const Duration(seconds: 6));
    expect(svc.startCount, 0);
    expect(svc.permissionAsks, 1,
        reason: 'the permission was asked once, on the card that explains it');
  });

  testWidgets('the demonstration moves', (t) async {
    // The claim the screen exists to make: a looping repetition to copy, not a
    // still picture of the bottom of one. Compared through `shouldRepaint`
    // because the painter is private to the page — and that is the same
    // comparison the framework itself uses to decide the animation is worth
    // redrawing, so a demonstration that passed here and stood still on a
    // phone would be a framework bug rather than a hole in this test.
    _phoneSized(t);
    final c = _container(_SilentService());
    await _pumpToSelection(t, c);

    final first = _demoPainter(t);
    await t.pump(const Duration(milliseconds: 500));
    final later = _demoPainter(t);

    expect(identical(first, later), isFalse);
    expect(first.shouldRepaint(later), isTrue,
        reason: 'the demonstrated pose is the same at both times');
  });

  testWidgets('the demonstration follows the chosen movement', (t) async {
    _phoneSized(t);
    final c = _container(_SilentService());
    await _pumpToSelection(t, c);

    expect(c.read(selectedExerciseProvider), FormExercise.squat);
    final squat = _demoPainter(t);

    await t.tap(find.byKey(const Key('form_check.exercise.curl')));
    await t.pump();
    expect(c.read(selectedExerciseProvider), FormExercise.curl);
    // Same animation clock, different movement: whatever the loop is doing,
    // the shape being drawn changed with the chip.
    expect(squat.shouldRepaint(_demoPainter(t)), isTrue);
  });

  testWidgets('the start button is what opens the camera', (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final c = _container(svc);
    await _pumpToSelection(t, c);

    await t.tap(find.byKey(const Key('coach.selection.start')));
    await t.pump();
    await t.pump();

    // The CONTROLLER's phase, not the derived one: `coachSessionProvider`
    // folds the live gate verdict on top, and the default verdict is `ok`, so
    // the screen is already at `ready` by the time this runs. Both are true;
    // this is the one the button is responsible for.
    expect(c.read(coachPhaseControllerProvider).phase, CoachPhase.qualityCheck);
    expect(svc.startCount, 1);
    expect(svc.permissionAsks, 1,
        reason: 'asked on the intro card, and NOT again here — a second ask '
            'after a refusal re-opens a dialog that is still "askable", and '
            'a second refusal on Android 13+ is close to permanent');
  });

  testWidgets(
      'back from the live screen returns to the picker with the '
      'camera released', (t) async {
    // Operator, point 3: «если нажать назад то поподешь на страницу выбора
    // упражнений с роликами». Back here does not leave the coach, so the page
    // is not unmounted and `dispose` never runs — releasing the camera is this
    // handler's own job, and that is the half worth a test.
    _phoneSized(t);
    final svc = _SilentService();
    final c = _container(svc);
    await _pumpToSelection(t, c);
    await t.tap(find.byKey(const Key('coach.selection.start')));
    await t.pump();
    await t.pump();
    expect(svc.startCount, 1);

    await t.tap(find.byKey(const Key('coach.live.back')));
    await t.pump();
    await t.pump();

    expect(c.read(coachSessionProvider).phase, CoachPhase.selection);
    expect(svc.stopCount, greaterThanOrEqualTo(1),
        reason: 'the camera is released, not left running behind the picker');
    expect(find.byKey(const Key('form_check.demo')), findsOneWidget,
        reason: 'and the demonstration is running again');

    // And the way forward still works: the flag that stops `build` opening a
    // second camera has to be cleared on the way back, or the start button
    // would move the phase and open nothing.
    await t.tap(find.byKey(const Key('coach.selection.start')));
    await t.pump();
    await t.pump();
    expect(svc.startCount, 2);
  });

  testWidgets('the camera waits for the permission ask that is still open',
      (t) async {
    // The transition to this screen deliberately does not wait for the
    // permission dialog — the user would be left staring at the card they just
    // dismissed. But the CAMERA has to, and the first version of this gate
    // fire-and-forgot the ask entirely. `CameraSession.start(requestPermission:
    // false)` READS the status and throws on a still-denied one rather than
    // waiting, so pressing start inside that window put a user who was in the
    // middle of granting permission onto the camera-failure card. GPT-PM's
    // review of this gate.
    _phoneSized(t);
    final svc = _PendingPermissionService();
    final c = _container(svc);
    await _pumpToSelection(t, c);

    expect(svc.permissionAsks, 1);
    expect(find.byKey(const Key('coach.selection.start')), findsOneWidget,
        reason: 'the screen is usable while the ask is still open');

    await t.tap(find.byKey(const Key('coach.selection.start')));
    await t.pump();
    await t.pump();
    expect(svc.startCount, 0,
        reason: 'the camera is not opened against an unanswered permission');

    svc.asked.complete();
    await t.pump();
    await t.pump();
    expect(svc.startCount, 1, reason: 'and it opens as soon as it is answered');
    expect(svc.permissionAsks, 1, reason: 'without asking a second time');
  });

  testWidgets('the screen holds together at 200% text scale', (t) async {
    // The new button's label is longer than the one it replaced, and the
    // review flagged that `AppPrimaryButton`'s icon-less branch renders a bare
    // `Text` with no ellipsis — so if anything constrained its height the
    // label would clip rather than wrap. Nothing does: `minimumSize` is a
    // minimum and the screen is a `ListView`. This pins that, and it is a real
    // assertion rather than a smoke test — a `RenderFlex` overflow raises an
    // exception the test framework fails on.
    _phoneSized(t);
    // Set on the dispatcher, not by wrapping the page in a `MediaQuery`:
    // `MaterialApp` only inserts its own when there is no ambient one, so a
    // wrapper built from a bare `MediaQueryData()` hands the whole tree a
    // `Size.zero` viewport and nothing lays out at all. (Tried; it "failed"
    // by finding no widgets, which says nothing about text scale.)
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

    final c = _container(_SilentService());
    await t.pumpWidget(_page(c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.continue')));
    await t.pump();
    await t.pump();

    expect(t.takeException(), isNull,
        reason: 'a RenderFlex overflow lands in the error reporter rather '
            'than throwing at the call site');

    // Scrolled to, not asserted where it sits: at this scale the panel above
    // it is taller than the viewport, so the button is below the fold and the
    // `ListView` has not built it yet. That is the screen working as intended
    // — it is a scrolling list — but it does mean a bare finder would report
    // the button missing and say nothing about the label.
    await t.scrollUntilVisible(
      find.byKey(const Key('coach.selection.start')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pump();

    expect(t.takeException(), isNull, reason: 'and none on the way down');
    expect(find.byKey(const Key('coach.selection.start')), findsOneWidget);
    expect(find.text('Нажмите когда готовы'), findsOneWidget,
        reason: 'the longer label wraps rather than clipping: '
            '`AppPrimaryButton` sizes from a MINIMUM, inside a ListView that '
            'does not cap its height');
  });

  testWidgets('the system back gesture goes to the same place as the arrow',
      (t) async {
    // `leading` alone would leave Android Back popping the route while the
    // arrow beside it returns to the picker — two controls, one meaning, two
    // destinations. This is the case that catches that.
    _phoneSized(t);
    final svc = _SilentService();
    final c = _container(svc);
    await _pumpToSelection(t, c);
    await t.tap(find.byKey(const Key('coach.selection.start')));
    await t.pump();
    await t.pump();

    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump();

    expect(c.read(coachSessionProvider).phase, CoachPhase.selection);
    expect(find.byKey(const Key('coach.selection.start')), findsOneWidget);
  });
}
