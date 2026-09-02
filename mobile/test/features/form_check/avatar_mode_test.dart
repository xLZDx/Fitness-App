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

import 'tracking_lost_test.dart' show nobody;
import 'unscorable_frame_test.dart' show oneSquat;

/// Drawing the user instead of showing the room.
///
/// The mode replaces the one thing on this page that cannot be wrong — the
/// camera image — with a drawing derived from a detector that can be. Every
/// test here is about that trade being honest: the figure appears only when
/// there is a live pose behind it, and disappears the moment there is not.

final _avatar = find.byKey(const Key('form_check.avatar'));
final _backdrop = find.byKey(const Key('form_check.backdrop'));

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

ProviderContainer _container(List<PoseFrame> frames) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(frames)),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget _page(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

void main() {
  testWidgets('on by default: the scene and the figure are what the user gets',
      (t) async {
    // Was the opposite until 2026-08-15, and the reason it flipped is a
    // decision rather than a discovery: the operator asked for this screen to
    // look like the reference animation and chose avatar mode as the main
    // view. The old default was protecting an unwatched feature; that argument
    // stops applying once someone states the preference.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(c.read(avatarModeProvider), isTrue);
    expect(_backdrop, findsOneWidget);
    expect(_avatar, findsOneWidget);
    expect(c.read(showSkeletonProvider), isFalse,
        reason: 'only the avatar moved; the diagnostic overlay stays off, and '
            'a default that switched on two things at once would be a second '
            'decision nobody made');
  });

  testWidgets('the camera is still one tap away', (t) async {
    // What the old default was protecting is now the toggle's job. If the
    // avatar is ever wrong about where the body is, this is the way out, so it
    // is pinned rather than left to the toggle test below.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();

    await t.tap(find.byTooltip('Show the camera again'));
    await t.pump(const Duration(seconds: 2));

    expect(c.read(avatarModeProvider), isFalse);
    expect(_backdrop, findsNothing);
    expect(_avatar, findsNothing);
  });

  testWidgets('switched on, the room is replaced and the body is drawn',
      (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(avatarModeProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(_backdrop, findsOneWidget);
    expect(_avatar, findsOneWidget);
    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'the avatar reads the same frame the skeleton does, so turning '
            'this on has to start publishing them even with the skeleton off');
    expect(c.read(showSkeletonProvider), isFalse,
        reason: 'the avatar must not need the diagnostic overlay switched on');
  });

  testWidgets('losing the person removes the figure but keeps the scene',
      (t) async {
    // The failure this mode would otherwise introduce. With the camera gone,
    // a figure left standing after the user walked away is indistinguishable
    // from one that is tracking.
    _phoneSized(t);
    final c = _container([...oneSquat(0), nobody(9000)]);
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(avatarModeProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(_avatar, findsNothing,
        reason: 'no live pose, no figure');
    expect(_backdrop, findsOneWidget,
        reason: 'the scene stays, so the screen reads as "nobody here" rather '
            'than as a crash');
  });

  testWidgets('a body it cannot place says so, instead of an empty scene',
      (t) async {
    // Not hypothetical. `SquatDepthClassifier.requiredLandmarks` is hips and
    // knees — no shoulder — so on a squat framed low the gate reports `ok` and
    // the rep counter counts, while the avatar has no shoulder to build a spine
    // from and nothing to draw. With the camera image gone, silence there is a
    // blank scene over a coach that is working perfectly.
    _phoneSized(t);
    // Repeated rather than a single frame. The mock replays its fixtures once,
    // 33 ms apart, and the mode is switched on after the first pump — a
    // one-frame fixture is already spent by then, so the provider would still
    // be null and the test would pass or fail for a reason that has nothing to
    // do with what it is about.
    final c = _container([
      for (var i = 0; i < 30; i++)
        PoseFrame(timestampMs: i * 100, landmarks: {
          LandmarkType.leftHip: const PoseLandmark(
              type: LandmarkType.leftHip, x: 0.45, y: 0.58, likelihood: 0.95),
          LandmarkType.rightHip: const PoseLandmark(
              type: LandmarkType.rightHip, x: 0.55, y: 0.58, likelihood: 0.95),
          LandmarkType.leftKnee: const PoseLandmark(
              type: LandmarkType.leftKnee, x: 0.45, y: 0.74, likelihood: 0.95),
          LandmarkType.rightKnee: const PoseLandmark(
              type: LandmarkType.rightKnee, x: 0.55, y: 0.74, likelihood: 0.95),
        }),
    ]);
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(avatarModeProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'positive control: a pose really did arrive');
    expect(_avatar, findsNothing);
    expect(find.byKey(const Key('form_check.avatar_no_torso')), findsOneWidget,
        reason: 'the screen has to account for the empty scene');
  });

  testWidgets('the toggle turns it off and back on', (t) async {
    // Same round trip as before the default flipped, walked from the other
    // end: the interesting assertion is the frame being dropped on the way OUT
    // of avatar mode, and that step is now the first tap rather than the
    // second.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump(const Duration(seconds: 2));
    expect(c.read(avatarModeProvider), isTrue,
        reason: 'positive control: it starts on, so the first tap really is '
            'the exit');

    await t.tap(find.byTooltip('Show the camera again'));
    await t.pump();
    expect(c.read(avatarModeProvider), isFalse);
    expect(_backdrop, findsNothing);
    // Held rather than dropped, since 2026-09-02: the target outline is now
    // placed on the tracked body and reads this frame over the raw camera too,
    // so leaving avatar mode no longer leaves nobody watching. The stale-pose
    // worry this line was written for is answered by the frame continuing to
    // arrive every 33ms rather than by clearing it — and the case where
    // genuinely nothing reads it is asserted directly in
    // `skeleton_overlay_test.dart`, on a movement with no authored outline.
    expect(c.read(latestPoseFrameProvider), isNotNull);

    await t.tap(find.byTooltip('Draw me as a figure'));
    await t.pump(const Duration(seconds: 2));
    expect(c.read(avatarModeProvider), isTrue);
    expect(_backdrop, findsOneWidget);
  });

  testWidgets('leaving the mode keeps the frame when the skeleton still wants it',
      (t) async {
    // The drop on exit must not steal the frame from the other reader. Two
    // switches over one provider is exactly where that kind of bug lives.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    c.read(avatarModeProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    await t.tap(find.byTooltip('Show the camera again'));
    await t.pump();

    expect(c.read(avatarModeProvider), isFalse);
    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'the skeleton is still on and still drawing from this frame');
  });

  testWidgets('and the reverse: turning the skeleton off does not blank the '
      'avatar', (t) async {
    // The direction the first version got wrong, and the reason the rule now
    // lives in one place. The avatar toggle checked its neighbour before
    // clearing the shared frame; the skeleton toggle cleared unconditionally.
    // With both on, turning the skeleton off took the avatar's figure with it
    // mid-set.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    c.read(avatarModeProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));
    expect(_avatar, findsOneWidget, reason: 'positive control');

    await t.tap(find.byTooltip('Show what the camera sees'));
    await t.pump();

    expect(c.read(showSkeletonProvider), isFalse);
    expect(c.read(avatarModeProvider), isTrue);
    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'the avatar is still on and still drawing from this frame');
    expect(_avatar, findsOneWidget);
  });
}
