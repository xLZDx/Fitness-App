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
class _ManualService implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();
  final List<Completer<void>> starts = [];
  final List<Completer<void>> stops = [];

  int get startCount => starts.length;

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> start() {
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
    await t.pumpWidget(_page(svc));
    await t.pump(); // let the post-frame callback run

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
    await t.pumpAndSettle();
  });

  testWidgets('retry actually tries again', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await t.pumpWidget(_page(svc));
    await t.pump();
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
    await t.pumpAndSettle();
  });

  testWidgets('a real failure names itself and offers a retry', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await t.pumpWidget(_page(svc));
    await t.pump();

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
    await t.pumpWidget(_page(svc));
    await t.pump();

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
    await t.pumpAndSettle();
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

    svc.starts.first.complete();
    await t.pumpAndSettle();
  });

  testWidgets('resuming waits for the teardown before reopening', (t) async {
    _phoneSized(t);
    final svc = _ManualService();
    await t.pumpWidget(_page(svc));
    await t.pump();
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
    await t.pumpAndSettle();
  });
}
