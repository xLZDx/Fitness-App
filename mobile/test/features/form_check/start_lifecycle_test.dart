import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Opening the camera, and what the screen does while that is not going well.
///
/// Every case here rendered as the same thing before: a white spinner, turning,
/// with no text and no button. A camera held by another app, a permission
/// dialog that never resolved, a native call that simply never returned — all
/// of them produced a page that looked like it was still loading and never
/// would be.

/// A service whose `start()` finishes when the test says so, and not before.
class _ManualService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();
  final List<Completer<void>> starts = [];
  final List<Completer<void>> stops = [];

  /// How many times the screen asked for camera permission, and in what order
  /// relative to `start`. Recorded rather than counted so a test can prove the
  /// ask happens BEFORE the camera is opened, not merely that it happens.
  final List<String> calls = [];

  int get startCount => starts.length;
  int get permissionAsks => calls.where((c) => c == 'permission').length;

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async {
    calls.add('permission');
  }

  @override
  Future<void> start() {
    calls.add('start');
    final c = Completer<void>();
    starts.add(c);
    return c.future;
  }

  @override
  Future<void> stop() {
    final c = Completer<void>();
    stops.add(c);
    return c.future;
  }

  @override
  Future<void> dispose() async => _frames.close();
}

Widget _page(PoseDetectorService svc) => ProviderScope(
      overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

/// A phone-shaped viewport. The default 800x600 test surface is landscape, and
/// the page's camera panel is 9:16 — on the default surface the retry button
/// lands off the bottom, and scrolling it into view tucks it under the
/// translucent app bar. Neither says anything about the code under test.
/// Mounts the page and walks R11h's two cards, so the camera is open by the
/// time a test starts asserting about it.
///
/// Every case below used to begin `pumpWidget` + `pump` and have a camera. It
/// does not any more: arriving on the coach shows what it does and how to
/// stand, and the hardware is requested by that card's own button. The
/// cases themselves — a start that hangs, a stop that overtakes it, a retry —
/// are unchanged, and that is the point of routing them all through one helper
/// rather than editing nine preludes into nine slightly different shapes.
Future<void> _pumpToCamera(WidgetTester t, PoseDetectorService svc) async {
  await t.pumpWidget(_page(svc));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('coach.intro.openCamera')));
  // Two pumps, not one: the button only moves the phase, and the camera is
  // opened by the post-frame callback the resulting build schedules.
  await t.pump();
  await t.pump();
}

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a start that never returns stops being a spinner', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);

    expect(find.byType(CircularProgressIndicator), findsWidgets,
        reason: 'while the camera is genuinely opening, a spinner is right');
    expect(find.byKey(const Key('form-check-error')), findsNothing);

    // Past the timeout, with start() still hanging.
    await t.pump(const Duration(seconds: 16));
    await t.pump();

    expect(find.byKey(const Key('form-check-error')), findsOneWidget);
    expect(
        find.text('The camera did not open in time. Another app may still '
            'be holding it - close it and try again.'),
        findsOneWidget);
    expect(find.byKey(const Key('form-check-retry')), findsOneWidget,
        reason: 'a transient failure must not end the session');

    // The timeout message says everything the raw exception would.
    expect(find.byKey(const Key('form-check-error-detail')), findsNothing);

    svc.starts.first.complete();
    await t.pump();
  });

  testWidgets('retry actually tries again', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);
    await t.pump(const Duration(seconds: 16));
    await t.pump();

    expect(svc.startCount, 1);
    await t.tap(find.byKey(const Key('form-check-retry')));
    await t.pump();
    expect(svc.startCount, 2,
        reason: 'the button must call start(), not just '
            'clear the message');

    // And a start that succeeds this time clears the failure.
    svc.starts.last.complete();
    await t.pump();
    expect(find.byKey(const Key('form-check-error')), findsNothing);

    svc.starts.first.complete();
    await t.pump();
  });

  testWidgets('a real failure names itself and offers a retry', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);

    svc.starts.first.completeError(StateError('camera in use'));
    await t.pump();

    expect(find.byKey(const Key('form-check-error')), findsOneWidget);
    expect(find.text('The camera could not be opened.'), findsOneWidget);
    // The platform's own words, on their own line. They used to be spliced
    // into the middle of a Russian sentence, which read as a broken app in
    // one language and as nothing at all in the other.
    expect(find.byKey(const Key('form-check-error-detail')), findsOneWidget);
    expect(find.byKey(const Key('form-check-retry')), findsOneWidget);
  });

  testWidgets('a start overtaken by a stop does not report success', (t) async {
    // Background the app mid-start, then let the original start complete. It
    // belongs to a camera session that has already been torn down; believing
    // it leaves the page showing a live preview over a released camera.
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(svc.stops, hasLength(1), reason: 'pausing must release the camera');

    svc.starts.first.complete(); // the stale start lands late
    await t.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets,
        reason: 'the page must not claim a working preview');
    expect(find.byKey(const Key('form-check-error')), findsNothing,
        reason: 'nor invent a failure — the session was simply cancelled');

    svc.stops.first.complete();
    await t.pump();
  });

  testWidgets('a fresh visit does not show the last visit\'s verdict',
      (t) async {
    // The rep session outlives the page. Coming back showed the count and the
    // red or green banner from a set finished minutes earlier, sitting over a
    // camera that had not produced a single frame yet.
    _phoneSized(t);
    final svc = _ManualService();
    final container = ProviderContainer(
      overrides: [poseDetectorServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    // A previous set, left behind.
    container.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(repCount: 7, isArmed: true);
    container.read(poseMatchProvider.notifier).state = 0.91;

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    ));
    await t.pump();

    final session = container.read(repSessionControllerProvider);
    expect(session.repCount, 0, reason: 'a new visit is a new set');
    expect(session.lastRepCue, isNull);
    expect(session.lastReject, isNull);
    expect(container.read(poseMatchProvider), isNull);

    // No `starts.first.complete()` any more, and no tap-through to make one:
    // the reset happens in `initState`, so this case never needed a camera. It
    // only had one because arriving used to open it unconditionally.
    expect(svc.startCount, 0);
  });

  testWidgets('resuming waits for the teardown before reopening', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);
    svc.starts.first.complete();
    await t.pump();

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();

    expect(svc.startCount, 1,
        reason: 'start() must not run while stop() is still in flight — that '
            'is how the preview comes back permanently black');

    svc.stops.first.complete();
    await t.pump();
    expect(svc.startCount, 2, reason: 'and it must run once the stop lands');

    svc.starts.last.complete();
    await t.pump();
  });

  // Reported from a real device, 2026-08-08: opening the coach before ever
  // using the scanner showed
  // `CameraUnavailable(CameraUnavailableReason.permissionDenied)` and no
  // system dialog had appeared. `CameraSession.start` defaults to not
  // requesting -- correctly, so a resume cannot ambush the user -- and this
  // screen had no path that requested either. The camera was unreachable
  // unless some OTHER screen had already won the permission.
  testWidgets('nothing is asked for, and nothing opens, until the user says so',
      (t) async {
    _phoneSized(t);
    final svc = _ManualService();

    // R11h moved this. It used to read "a fresh arrival IS the user asking for
    // the camera", which was true when arriving was the only signal there was.
    // Now there is a card in front of it, ending on a button that says "open
    // the camera", so arriving is no longer an ask — and this half of the test
    // is the one that proves the card is not decoration over an
    // already-running preview.
    await t.pumpWidget(_page(svc));
    await t.pumpAndSettle();
    expect(svc.permissionAsks, 0, reason: 'the intro card asks for nothing');
    expect(svc.startCount, 0, reason: 'and opens nothing');

    await t.tap(find.byKey(const Key('coach.intro.openCamera')));
    await t.pump();
    await t.pump();

    expect(svc.permissionAsks, 1,
        reason: 'the button that says "open the camera" is the ask');
    expect(svc.calls.first, 'permission',
        reason: 'asking after opening the camera is asking too late — the '
            'open is what fails with permissionDenied');

    svc.starts.first.complete();
    await t.pump();
  });

  testWidgets('resuming from background does not put the dialog up again',
      (t) async {
    // The other half of the same rule, and the reason the default is `false`.
    // Someone who glanced at a notification did not ask for anything; a
    // permission dialog on the way back is an ambush, and on Android 13+ a
    // refusal collected that way is close to permanent.
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);
    svc.starts.first.complete();
    await t.pump();
    expect(svc.permissionAsks, 1);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    svc.stops.first.complete();
    await t.pump();

    expect(svc.startCount, 2, reason: 'the camera does reopen');
    expect(svc.permissionAsks, 1,
        reason: 'but nothing new was asked of the user');

    svc.starts.last.complete();
    await t.pump();
  });

  testWidgets('retry asks again — it is the clearest ask there is', (t) async {
    // Passing the `_startDetector` tear-off straight to onRetry type-checks in
    // Dart (optional named parameters are droppable) and silently takes the
    // `false` default, which would leave the retry button unable to fix the
    // one failure it is most often shown for.
    _phoneSized(t);
    final svc = _ManualService();
    await _pumpToCamera(t, svc);
    svc.starts.first.completeError(StateError('permission denied'));
    await t.pump();

    expect(svc.permissionAsks, 1);
    await t.tap(find.byKey(const Key('form-check-retry')));
    await t.pump();

    expect(svc.permissionAsks, 2,
        reason: 'the retry button must be able to raise the dialog');
    expect(svc.calls.last, 'start',
        reason: 'and still open the camera afterwards');

    svc.starts.last.complete();
    await t.pump();
  });
}
