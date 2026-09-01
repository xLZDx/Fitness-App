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
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

/// R11h's pre-camera card.
///
/// `start_lifecycle_test.dart` covers what happens once the camera is opening.
/// This file covers the part before that, and in particular the claim the card
/// itself makes: that the camera is not running while it is on screen. That
/// claim is why it could not be drawn as an overlay over a live preview, so it
/// is worth a test rather than a comment.
///
/// It was two cards until 2026-09-01. The tests that walked between them are
/// gone; what they were actually protecting -- nothing opens until the button,
/// and the small print is readable before the prompt -- is kept below.

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

    expect(find.byKey(const Key('coach.intro.openCamera')), findsOneWidget);
    expect(find.byKey(const Key('coach.intro.privacy')), findsOneWidget,
        reason: 'the camera small print is readable BEFORE the prompt, which '
            'is the only point at which it can inform a decision');
    expect(container.read(coachSessionProvider).phase, CoachPhase.launch);
    expect(svc.startCount, 0);
    expect(svc.permissionAsks, 0);
  });

  testWidgets('one card carries every block both used to', (t) async {
    // The merge is only safe if nothing was dropped on the way, so this lists
    // the blocks EXHAUSTIVELY rather than sampling four of them. The first
    // version checked four keys while the decision log claimed it checked
    // everything -- a preservation test that does not cover what it says it
    // covers is worse than none, because the claim is what gets believed.
    // Caught in review of this gate.
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();

    for (final key in [
      // From the old launch card.
      'coach.intro.experimental',
      'coach.intro.body',
      'coach.intro.feature.reps',
      'coach.intro.feature.cues',
      'coach.intro.feature.summary',
      // From the old preparation card.
      'coach.prep.angle',
      'coach.prep.distance',
      'coach.prep.mount',
      'coach.prep.light',
      'coach.prep.clothing',
      // On both, and it must survive on the merged one.
      'coach.intro.privacy',
      // The controls.
      'coach.intro.openCamera',
      'coach.intro.later',
      // `coach.intro.sustainer` is deliberately NOT here: it is conditional, so
      // its absence in this loop would be indistinguishable from it being
      // correctly hidden. It has its own test below, covering both answers.
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key went missing');
    }
    expect(svc.startCount, 0);
  });

  testWidgets('the moved sustainer pitch appears for the user it is for, and '
      'only for them', (t) async {
    // The block the exhaustive loop above CANNOT cover, because it is
    // conditional: absence there would be indistinguishable from "correctly
    // hidden". Without this, the card could be deleted outright and every
    // other test in this file would stay green -- the gate would silently
    // regress to "the pitch never precedes the camera", which is the one thing
    // moving it was for. Caught in review of this gate.
    _phoneSized(t);
    final svc = _SilentService();

    // Resolved and free: with no signed-in user the stream yields null at once.
    final free = _container(svc);
    await t.pumpWidget(_page(free));
    await t.pumpAndSettle();
    expect(free.read(entitlementResolvedProvider), isTrue);
    expect(find.byKey(const Key('coach.intro.sustainer')), findsOneWidget,
        reason: 'this is the user the pitch is addressed to');
    expect(svc.permissionAsks, 0,
        reason: 'and they see it before anything is asked of them');

    // Resolved and paying: no pitch, and the camera is still reachable.
    final paid = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWithValue(_SilentService()),
      effectiveTierProvider
          .overrideWithValue(SubscriptionTier.celebrityTrainer),
    ]);
    addTearDown(paid.dispose);
    await t.pumpWidget(_page(paid));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('coach.intro.sustainer')), findsNothing,
        reason: 'selling a subscription to a subscriber');
    expect(find.byKey(const Key('coach.intro.openCamera')), findsOneWidget);
  });

  testWidgets('a subscription stream that has not answered yet still lets the '
      'user open the camera, and still warns them', (t) async {
    // The gate's review argued the button should be BLOCKED until entitlement
    // resolves, so the sustainer pitch cannot be missed. Refused, and this is
    // the test that records the decision rather than leaving it in a comment:
    // `subscription_providers.dart:95-98` makes exactly the opposite choice for
    // exactly this provider, and gating a camera on a network round-trip is a
    // worse failure than a late pitch.
    //
    // What must NOT be missed is the warning, and it is unconditional. The
    // pitch is an upsell; showing it to somebody who already pays -- which is
    // what an unresolved stream would cause -- is the harm the provider exists
    // to prevent.
    //
    // The first version of this test asserted the pitch was absent by default
    // and failed: with no signed-in user the stream yields null immediately and
    // entitlement IS resolved. The loading state has to be constructed.
    _phoneSized(t);
    final svc = _SilentService();
    final container = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWithValue(svc),
      currentSubscriptionProvider.overrideWith((_) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();

    expect(container.read(entitlementResolvedProvider), isFalse,
        reason: 'a stream that never yields leaves entitlement resolving');
    expect(find.byKey(const Key('coach.intro.experimental')), findsOneWidget,
        reason: 'the safety warning does not wait for a network answer');
    expect(find.byKey(const Key('coach.intro.sustainer')), findsNothing,
        reason: 'the upsell does, deliberately');

    await t.tap(find.byKey(const Key('coach.intro.openCamera')));
    await t.pump();
    await t.pump();
    expect(svc.startCount, 1,
        reason: 'the camera is not held hostage by the subscription stream');
  });

  testWidgets('the custom card-to-card back control is gone', (t) async {
    // The old cards supplied their own leading arrow because "back" meant the
    // previous card. That step no longer exists, so the control does not
    // either. The navigator's OWN back button is a different thing and is
    // allowed to stay: it means "leave the coach", same as "Позже".
    _phoneSized(t);
    final container = _container(_SilentService());

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    expect(find.byKey(const Key('coach.intro.later')), findsOneWidget,
        reason: 'leaving the feature entirely is still offered');
  });

  testWidgets('the camera opens on the button of that card, and only then',
      (t) async {
    _phoneSized(t);
    final svc = _SilentService();
    final container = _container(svc);

    await t.pumpWidget(_page(container));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.openCamera')));
    // The button moves the phase; the build that follows schedules the open.
    await t.pump();
    await t.pump();

    expect(container.read(coachSessionProvider).phase, isNot(CoachPhase.launch));
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
