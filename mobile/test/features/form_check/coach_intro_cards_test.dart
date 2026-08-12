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

/// R11h's two pre-camera cards.
///
/// `start_lifecycle_test.dart` covers what happens once the camera is opening.
/// This file covers the part before that, and in particular the claim the cards
/// themselves make: that the camera is not running while they are on screen.
/// That claim is why they could not be drawn as an overlay over a live preview,
/// so it is worth a test rather than a comment.

class _SilentService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();
  int startCount = 0;
  int permissionAsks = 0;

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async => permissionAsks++;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _frames.close();
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
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

void main() {
  testWidgets('the coach opens on the intro card, not on a camera',
      (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('coach.intro.start')), findsOneWidget);
    expect(find.byKey(const Key('coach.intro.privacy')), findsOneWidget,
        reason: 'the camera small print is readable BEFORE the prompt, which '
            'is the only point at which it can inform a decision');
    expect(container.read(coachSessionProvider).phase, CoachPhase.launch);
    expect(svc.startCount, 0);
    expect(svc.permissionAsks, 0);
  });

  testWidgets('"Start" moves to preparation and still opens nothing',
      (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.start')));
    await t.pumpAndSettle();

    expect(container.read(coachSessionProvider).phase, CoachPhase.preparation);
    expect(find.byKey(const Key('coach.prep.openCamera')), findsOneWidget);
    expect(find.byKey(const Key('coach.prep.angle')), findsOneWidget);
    expect(svc.startCount, 0,
        reason: 'the preparation card\'s own text promises exactly this');
  });

  testWidgets('back on the preparation card returns to the intro, not out of '
      'the screen', (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.start')));
    await t.pumpAndSettle();
    // Not `BackButtonIcon`: the card supplies its own leading control, because
    // "back" here means the previous card, not the previous route.
    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await t.pumpAndSettle();

    expect(container.read(coachSessionProvider).phase, CoachPhase.launch,
        reason: 'the flow has two steps, so back means the previous step');
    expect(find.byKey(const Key('coach.intro.start')), findsOneWidget);
  });

  testWidgets('the camera opens on the preparation card\'s button, and only '
      'then', (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.start')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.prep.openCamera')));
    // The button moves the phase; the build that follows schedules the open.
    await t.pump();
    await t.pump();

    expect(container.read(coachSessionProvider).phase,
        isNot(CoachPhase.preparation));
    expect(svc.permissionAsks, 1);
    expect(svc.startCount, 1);
  });

  testWidgets('backgrounding while still on the intro card does not open a '
      'camera on the way back', (t) async {
    // The lifecycle-resume path reopens the camera when it finds one stopped.
    // "Stopped" and "never asked for" look identical from `_started` alone, so
    // without a separate flag a user who glanced at a notification from the
    // intro card would have come back to a running camera they never
    // requested.
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();

    expect(svc.startCount, 0);
    expect(svc.permissionAsks, 0);
    expect(container.read(coachSessionProvider).phase, CoachPhase.launch);
  });
}
