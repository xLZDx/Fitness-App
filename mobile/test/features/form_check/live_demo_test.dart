import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/form_check/widgets/coach_demo.dart';
import 'package:fitness_app/features/form_check/widgets/coach_demo_clip.dart';

import 'tracking_lost_test.dart' show nobody;
import 'unscorable_frame_test.dart' show oneSquat;

/// The live panel's hand-over: demonstration while nobody is tracked, the
/// user's own figure once somebody is, and back.
///
/// G17. This file was `silhouette_repaint_test.dart`, about the white target
/// outline's repaint rule; the outline is gone (`demo_silhouette_test.dart`
/// pins that) and what took its place has a contract of its own worth the
/// file: the demonstration fades out when a body is drawable, and its clip's
/// decoder is stopped ONLY after that fade has finished — not before, which
/// would freeze the last frame mid-fade, and not never, which would decode a
/// loop nobody can see underneath the avatar (GPT-PM, G17 plan review,
/// MAJOR). The recording controller is the only way to see the second half.

class _RecordingController extends VideoPlayerController {
  _RecordingController() : super.asset('assets/coach_demo/squat_side.mp4');

  final calls = <String>[];

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 10),
      size: const Size(540, 960),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await super.dispose();
  }
}

/// One fresh controller per clip mount, all of them kept: a test that expects
/// exactly one is also asserting the layer was never remounted — which it
/// was, before the panel's layers were keyed (see `form_check.layer.*`).
class _Factory {
  final created = <_RecordingController>[];
  VideoPlayerController call(String asset) {
    final c = _RecordingController();
    created.add(c);
    return c;
  }

  _RecordingController get only {
    expect(created, hasLength(1),
        reason: 'the clip must be mounted once, never re-inflated');
    return created.single;
  }
}

final _liveDemo = find.byKey(const Key('form_check.live_demo'));
final _demo = find.byKey(const Key('form_check.demo'));
final _avatar = find.byKey(const Key('form_check.avatar'));
final _target = find.byKey(const Key('form_check.silhouette'));

final _clip = find.byKey(const Key('form_check.demo_clip'));
final _skeleton = find.byKey(const Key('form_check.skeleton'));
final _figure = find.byKey(const Key('form_check.demo_figure'));

double _opacity(WidgetTester t) => t.widget<AnimatedOpacity>(_liveDemo).opacity;

PoseTarget _demoTarget(WidgetTester t) =>
    (t.widget<CustomPaint>(_figure).painter! as DemoFigurePainter).target;

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

ProviderContainer _container(
  List<PoseFrame> frames,
  _Factory factory, {
  bool avatar = true,
}) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(frames)),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    coachDemoControllerFactoryProvider.overrideWithValue(factory.call),
    avatarModeProvider.overrideWith((_) => avatar),
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

/// Deliver every fixture frame, let the fade run to its end, and give the
/// host the rebuild in which it acts on the fade having ended.
Future<void> _settle(WidgetTester t) async {
  // The plain pump first, as `avatar_mode_test.dart` does: the page opens the
  // detector from a post-frame callback, and a timed pump elapses its clock
  // BEFORE drawing the frame that fires it — so without this the fixtures
  // would start streaming only after the two seconds meant to drain them.
  await t.pump();
  await t.pump(const Duration(seconds: 2));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('nobody tracked: the demonstration is on the panel, playing',
      (t) async {
    _phoneSized(t);
    final factory = _Factory();
    final c = _container([for (var i = 0; i < 30; i++) nobody(i * 100)], factory);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(_demo, findsOneWidget);
    expect(_opacity(t), 1);
    expect(factory.only.calls, contains('play'));
    expect(factory.only.calls, isNot(contains('pause')));
    expect(_avatar, findsNothing, reason: 'positive control: nobody to draw');
    expect(_target, findsNothing);
  });

  testWidgets('a tracked body fades it out, then stops the decoder',
      (t) async {
    _phoneSized(t);
    final factory = _Factory();
    final c = _container(oneSquat(0), factory);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(_avatar, findsOneWidget, reason: 'positive control: a body IS drawn');
    expect(_opacity(t), 0);
    expect(factory.only.calls.last, 'pause',
        reason: 'a hidden loop must not keep decoding under the avatar');
    expect(_target, findsNothing);
  });

  testWidgets('the decoder keeps running until the fade has finished',
      (t) async {
    // The clause the previous test cannot see: pausing at the START of the
    // fade would freeze the last frame mid-fade and still end in the same
    // settled state. Stop half-way through the 300 ms fade and look.
    _phoneSized(t);
    final factory = _Factory();
    final c = _container(oneSquat(0), factory);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    // The body is drawable; the fade has been started by this frame.
    expect(_opacity(t), 0, reason: 'positive control: the fade is under way');
    expect(factory.only.calls, contains('play'));

    await t.pump(const Duration(milliseconds: 150));
    expect(factory.only.calls, isNot(contains('pause')),
        reason: 'mid-fade the clip must still be decoding');

    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    expect(factory.only.calls.last, 'pause',
        reason: 'and stop once the fade has ended');
  });

  testWidgets('losing the body brings the demonstration back', (t) async {
    _phoneSized(t);
    final factory = _Factory();
    final c = _container([...oneSquat(0), nobody(9000)], factory);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(_avatar, findsNothing);
    expect(_opacity(t), 1);
    expect(factory.only.calls.last, 'play');
  });

  testWidgets('camera mode hands over on the same body', (t) async {
    // Off the tracked body rather than off the avatar's figure, since there
    // is no avatar in this mode — `coachBodyDrawableProvider` is the one
    // answer for both.
    _phoneSized(t);
    final factory = _Factory();
    final c = _container(oneSquat(0), factory, avatar: false);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(_avatar, findsNothing, reason: 'camera mode draws no avatar');
    expect(_opacity(t), 0);
    expect(factory.only.calls.last, 'pause');
    expect(_target, findsNothing);
  });

  testWidgets('under reduce motion the hand-over still completes and the '
      'clip never plays', (t) async {
    // The fade is zero-length here (`hudMotionDuration`), and `onEnd` is
    // what returns the clip to inactive — if it did not fire for a
    // zero-length animation, `active` would stay true for good. Observable
    // on the clip widget itself.
    _phoneSized(t);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final factory = _Factory();
    final c = _container(oneSquat(0), factory);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(_avatar, findsOneWidget, reason: 'positive control');
    expect(_opacity(t), 0);
    expect(factory.only.calls, isNot(contains('play')));
    expect(t.widget<CoachDemoClip>(_clip).active, isFalse);
  });

  testWidgets('the drawn demonstration moves on the live screen while nobody '
      'is tracked', (t) async {
    // The curl has no clip, so its demonstration is the drawn figure driven
    // by the page's own clock — which the live screen used to stop
    // unconditionally ("the live screen never demonstrates"). Two frames
    // half a second apart must not be the same pose.
    _phoneSized(t);
    final factory = _Factory();
    final c = _container([for (var i = 0; i < 40; i++) nobody(i * 100)], factory);
    c.read(selectedExerciseProvider.notifier).state = FormExercise.curl;
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    await t.pump();

    expect(factory.created, isEmpty, reason: 'positive control: no clip');
    final first = _demoTarget(t);
    await t.pump(const Duration(milliseconds: 500));
    final second = _demoTarget(t);
    expect(second.joints, isNot(equals(first.joints)),
        reason: 'the demonstration clock must run on the live screen while '
            'the demonstration is what is shown');
  });

  testWidgets('camera mode, skeleton on: a frame the stabiliser rejects draws '
      'no skeleton over the demonstration; an accepted body swaps them',
      (t) async {
    // One figure on the panel. The skeleton must wait for the same acceptance
    // that hands the panel over, or a partial pose from the room draws glowing
    // fragments over the clip (seen on the S23 with the toggle on).
    _phoneSized(t);
    final factory = _Factory();
    final partial = [
      for (var i = 0; i < 20; i++)
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
    ];
    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(partial)),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
      coachDemoControllerFactoryProvider.overrideWithValue(factory.call),
      avatarModeProvider.overrideWith((_) => false),
      showSkeletonProvider.overrideWith((_) => true),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'positive control: a frame did arrive');
    expect(c.read(stabilisedBodyProvider), isNull,
        reason: 'positive control: and the stabiliser rejected it');
    expect(_opacity(t), 1);
    expect(_skeleton, findsNothing);
  });

  testWidgets('camera mode, skeleton on: an accepted body fades the '
      'demonstration and draws the skeleton', (t) async {
    _phoneSized(t);
    final factory = _Factory();
    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(oneSquat(0))),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
      coachDemoControllerFactoryProvider.overrideWithValue(factory.call),
      avatarModeProvider.overrideWith((_) => false),
      showSkeletonProvider.overrideWith((_) => true),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(stabilisedBodyProvider), isNotNull, reason: 'positive control');
    expect(_opacity(t), 0);
    expect(_skeleton, findsOneWidget);
  });

  testWidgets('a body the avatar cannot place keeps the demonstration up',
      (t) async {
    // Hips and knees only: the gate scores it, the avatar cannot build a
    // spine from it. The status band says so; the panel keeps demonstrating
    // rather than going blank.
    _phoneSized(t);
    final factory = _Factory();
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
    ], factory);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(avatarCannotPlaceBodyProvider), isTrue,
        reason: 'positive control');
    expect(_opacity(t), 1);
    expect(factory.only.calls, isNot(contains('pause')));
  });
}
