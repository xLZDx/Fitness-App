import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:fitness_app/features/form_check/data/pose_silhouette.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/form_check/widgets/coach_demo.dart';
import 'package:fitness_app/features/form_check/widgets/coach_demo_clip.dart';

/// G17. The demonstration's two sources and the clip's lifecycle contract.
///
/// The contract (see `coach_demo_clip.dart`'s library doc) is what GPT-PM
/// required before approving a video decoder on this page: it plays only while
/// it is what the user is looking at, pauses in the background, never plays
/// under reduce-motion, and is disposed on unmount. Each clause is a test
/// below, against a controller that records what it was told without needing
/// a video platform underneath it.

/// A `VideoPlayerController` with no platform: records every call and moves
/// its own `value` the way the real one would, so `CoachDemoClip` cannot tell
/// the difference and neither can the widget that builds on `value.size`.
class _RecordingController extends VideoPlayerController {
  _RecordingController() : super.asset('assets/test_only/no_such_clip.mp4');

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
  Future<void> setLooping(bool looping) async => calls.add('loop:$looping');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  // `super.dispose()` is safe here: the real one only reaches the platform
  // once the real `initialize` has run, and this class never lets it.
  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await super.dispose();
  }
}

/// A controller whose decoder is broken, for the fail-soft poster case.
class _BrokenController extends _RecordingController {
  @override
  Future<void> initialize() async {
    calls.add('initialize');
    throw StateError('no decoder');
  }
}

/// A controller that opens but refuses to play.
class _WontPlayController extends _RecordingController {
  @override
  Future<void> play() async {
    calls.add('play');
    throw StateError('surface not ready');
  }
}

/// A controller that plays but refuses to pause — and stays playing.
class _WontPauseController extends _RecordingController {
  @override
  Future<void> pause() async {
    calls.add('pause');
    throw StateError('native pause rejected');
  }
}

/// A controller whose `initialize` waits for the test to let it finish, for
/// the unmount-while-opening race.
class _SlowController extends _RecordingController {
  final opened = Completer<void>();

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    await opened.future;
    // The real controller's event listener returns early once disposed
    // rather than touching a disposed notifier; so does this one.
    if (calls.contains('dispose')) return;
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 10),
      size: const Size(540, 960),
    );
  }
}

final _poster = find.byKey(const Key('form_check.demo_poster'));

/// The clip these tests drive is never opened — every controller here is a
/// fake — so this path only has to be a string.
const _fakeClip = 'assets/test_only/no_such_clip.mp4';

/// The poster, however, is a real `Image.asset`, so it has to be a bundled
/// one or the widget throws before any of the lifecycle clauses run.
///
/// It is deliberately NOT the squat's old poster. That asset stopped being
/// bundled with G1.2 (2026-09-09) — see `pubspec.yaml` — and a test for a
/// widget that outlives the clip should not depend on the clip's leftovers.
/// Any small bundled image does; this one is 5 KB.
const _realPoster = 'assets/posters/girl/3_4_sit_up.jpg';
final _video = find.byKey(const Key('form_check.demo_video'));

Widget _host(
  VideoPlayerController ctrl, {
  required bool active,
  bool reduceMotion = false,
}) =>
    ProviderScope(
      overrides: [
        coachDemoControllerFactoryProvider.overrideWithValue((_) => ctrl),
      ],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 270,
            height: 480,
            child: CoachDemoClip(
              asset: _fakeClip,
              poster: _realPoster,
              active: active,
            ),
          ),
        ),
      ),
    );

void main() {
  group('coachDemoFor', () {
    // I4a. Both halves matter and they fail for different reasons. The squat
    // must be the STATED absence, not the clip (which G1.2 proved unusable)
    // and not null (which renders nothing and is reserved for a movement the
    // coach does not teach) and above all not the drawn figure — the squat has
    // an authored `poseTargetsFor` pair, so a missing branch here would fall
    // through to it silently and ship the stand-in the 2026-09-09 ruling
    // rejected.
    test('the squat is an explicit absence, not a clip and not a figure', () {
      final source = coachDemoFor(FormExercise.squat);
      expect(source, isA<CoachDemoUnavailableSource>());
      expect(source, isNot(isA<CoachDemoClipSource>()));
      expect(source, isNot(isA<CoachDemoFigureSource>()));
      expect(source, isNotNull,
          reason: 'an absence the coach states, not one it renders as nothing');
      expect(poseTargetsFor(FormExercise.squat), isNotNull,
          reason: 'the fall-through this branch exists to prevent is real');
    });

    test('every other authored movement is the drawn figure, from the same '
        'pair the scoring reads', () {
      for (final e in FormExercise.values) {
        if (e == FormExercise.squat) continue;
        final pair = poseTargetsFor(e);
        final source = coachDemoFor(e);
        if (pair == null) {
          expect(source, isNull, reason: '$e has nothing authored');
          continue;
        }
        expect(source, isA<CoachDemoFigureSource>(), reason: '$e');
        source as CoachDemoFigureSource;
        expect(source.from, same(pair.$1));
        expect(source.to, same(pair.$2));
      }
    });

    test('a movement without targets has no demonstration at all', () {
      // The deadlift has a rep signal but no target pair — the same case
      // `demo_silhouette_test.dart` has pinned since the picker existed.
      expect(poseTargetsFor(FormExercise.deadlift), isNull,
          reason: 'positive control for the case below');
      expect(coachDemoFor(FormExercise.deadlift), isNull);
    });
  });

  group('CoachDemoClip lifecycle', () {
    testWidgets('active: looping, muted, initialised, playing', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();

      expect(ctrl.calls, ['loop:true', 'volume:0.0', 'initialize', 'play']);
      expect(_poster, findsOneWidget, reason: 'stays underneath, always');
      expect(_video, findsOneWidget);
    });

    testWidgets('inactive: initialised but never played; active later plays; '
        'inactive again pauses', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: false));
      await t.pump();
      await t.pump();
      expect(ctrl.calls, isNot(contains('play')));

      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      expect(ctrl.calls.last, 'play');

      await t.pumpWidget(_host(ctrl, active: false));
      await t.pump();
      expect(ctrl.calls.last, 'pause');
    });

    testWidgets('leaving the foreground pauses; coming back resumes only '
        'while still active', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();
      expect(ctrl.calls.last, 'play', reason: 'positive control');

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(ctrl.calls.last, 'pause');

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(ctrl.calls.last, 'play');

      // Backgrounded while inactive: nothing to resume.
      await t.pumpWidget(_host(ctrl, active: false));
      await t.pump();
      expect(ctrl.calls.last, 'pause');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(ctrl.calls.last, 'pause',
          reason: 'a resume must not restart a clip nobody is looking at');
      // Restore the binding's state for the tests that follow.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('reduce motion: the poster is the demonstration, the decoder '
        'never runs', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: true, reduceMotion: true));
      await t.pump();
      await t.pump();

      expect(ctrl.calls, isNot(contains('play')));
      expect(_poster, findsOneWidget);
      expect(_video, findsNothing);
    });

    testWidgets('a decoder that fails leaves the poster and reports it',
        (t) async {
      final ctrl = _BrokenController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();

      expect(ctrl.calls, isNot(contains('play')));
      expect(_poster, findsOneWidget);
      expect(_video, findsNothing);
    });

    testWidgets('a decoder that opens but will not play falls back to the '
        'poster', (t) async {
      final ctrl = _WontPlayController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();

      expect(ctrl.calls, contains('play'), reason: 'positive control');
      expect(_video, findsNothing,
          reason: 'a platform view over a decoder that refused is a black '
              'frame where a demonstration was promised');
      expect(_poster, findsOneWidget);
    });

    testWidgets('a decoder that drops the clip mid-loop falls back to the '
        'poster', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();
      expect(_video, findsOneWidget, reason: 'positive control');

      ctrl.value = ctrl.value.copyWith(errorDescription: 'codec dropped');
      await t.pump();

      expect(_video, findsNothing);
      expect(_poster, findsOneWidget);
      // And the fallback is final: nothing tries to play a broken decoder.
      await t.pumpWidget(_host(ctrl, active: false));
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      expect(ctrl.calls.where((c) => c == 'play'), hasLength(1));
    });

    testWidgets('a decoder that refuses to pause is shut down, not hidden',
        (t) async {
      // Hiding alone would leave a still-playing decoder behind the poster
      // for as long as the panel is mounted — beside the camera and the pose
      // detector. Failure has to end in exactly one dispose.
      final ctrl = _WontPauseController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();
      expect(ctrl.calls.last, 'play', reason: 'positive control');

      await t.pumpWidget(_host(ctrl, active: false));
      await t.pump();
      await t.pump();
      expect(ctrl.calls, contains('pause'));
      expect(ctrl.calls.where((c) => c == 'dispose'), hasLength(1),
          reason: 'a decoder that will not stop on request is disposed');
      expect(_video, findsNothing);
      expect(_poster, findsOneWidget);

      // Neither a later activation nor the unmount touches it again.
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pumpWidget(const SizedBox.shrink());
      expect(ctrl.calls.where((c) => c == 'play'), hasLength(1));
      expect(ctrl.calls.where((c) => c == 'dispose'), hasLength(1));
    });

    testWidgets('unmounting while the decoder is still opening disposes it '
        'exactly once', (t) async {
      final ctrl = _SlowController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      expect(ctrl.calls.last, 'initialize', reason: 'positive control');

      await t.pumpWidget(const SizedBox.shrink());
      ctrl.opened.complete();
      await t.pump();
      await t.pump();

      expect(ctrl.calls.where((c) => c == 'dispose'), hasLength(1));
      expect(ctrl.calls, isNot(contains('play')));
    });

    testWidgets('unmounting disposes the controller', (t) async {
      final ctrl = _RecordingController();
      await t.pumpWidget(_host(ctrl, active: true));
      await t.pump();
      await t.pump();
      expect(ctrl.calls, isNot(contains('dispose')));

      await t.pumpWidget(const SizedBox.shrink());
      expect(ctrl.calls.last, 'dispose');
    });
  });

  group('DemoFigurePainter', () {
    // The demonstration is a new pose every frame under the SAME target id, so
    // the painter has to compare content or the loop renders one frozen frame.
    // Moved here from `silhouette_repaint_test.dart`'s subject when the white
    // outline it tested was removed.
    final pair = poseTargetsFor(FormExercise.curl)!;
    final bounds = Rect.fromLTWH(0, 0, 1, 1);

    test('a different interpolation repaints', () {
      final a = DemoFigurePainter(
          target: lerpPoseTarget(pair.$1, pair.$2, 0.2),
          build: BodyBuild.unknown,
          fitBounds: bounds);
      final b = DemoFigurePainter(
          target: lerpPoseTarget(pair.$1, pair.$2, 0.6),
          build: BodyBuild.unknown,
          fitBounds: bounds);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('the same pose does not', () {
      final a = DemoFigurePainter(
          target: lerpPoseTarget(pair.$1, pair.$2, 0.4),
          build: BodyBuild.unknown,
          fitBounds: bounds);
      final b = DemoFigurePainter(
          target: lerpPoseTarget(pair.$1, pair.$2, 0.4),
          build: BodyBuild.unknown,
          fitBounds: bounds);
      expect(a.shouldRepaint(b), isFalse);
    });
  });
}
