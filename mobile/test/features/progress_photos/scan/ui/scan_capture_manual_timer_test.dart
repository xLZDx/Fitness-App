import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag, SemanticsNode;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_capture_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

/// Camera whose start() can be held open to observe the "starting" state.
class _SlowStartCamera extends FakeScanCamera {
  final Completer<void> gate = Completer<void>();
  @override
  Future<void> start() async {
    starts++;
    await gate.future;
  }
}

class _Rig {
  _Rig({FakeScanCamera? camera}) : camera = camera ?? FakeScanCamera();

  final FakeScanCamera camera;
  final speaker = FakeSpeaker();
  final haptics = FakeHaptics();
  final scans = FakeScanRepository();
  final photos = MockProgressPhotosRepository();
  // A realistic epoch-like clock: the live-region throttle compares against 0.
  int nowMs = 100000;
  Object? popped = 'unset';

  Future<void> pump(
    WidgetTester tester, {
    bool screenReader = false,
    bool reducedMotion = false,
    double textScale = 1.0,
    Locale locale = kTestLocale,
    int? timerSeconds,
    double? weightKg,
    bool pushed = false,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanCameraProvider.overrideWith((ref) => camera),
        scanSpeakerProvider.overrideWithValue(speaker),
        scanHapticsProvider.overrideWithValue(haptics),
        scanClockProvider.overrideWithValue(() => nowMs),
        scanRepositoryProvider.overrideWithValue(scans),
        progressPhotosRepositoryProvider.overrideWithValue(photos),
        if (timerSeconds != null)
          scanManualTimerSecondsProvider.overrideWith((_) => timerSeconds),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            accessibleNavigation: screenReader,
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: pushed
            ? Builder(
                builder: (ctx) => Scaffold(
                  body: TextButton(
                    key: const Key('test.open'),
                    onPressed: () async {
                      popped = await Navigator.of(ctx).push<Object?>(
                          MaterialPageRoute<Object?>(
                              builder: (_) =>
                                  ScanCaptureScreen(weightKg: weightKg)));
                    },
                    child: const Text('open'),
                  ),
                ),
              )
            : ScanCaptureScreen(weightKg: weightKg),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> frame(WidgetTester tester, PoseFrame f, {int stepMs = 250}) async {
    nowMs += stepMs;
    camera.ctrl.add(f);
    await tester.pump();
    await tester.pump();
  }

  /// Advances the real (fake-async) one-second manual timer by [seconds].
  Future<void> secs(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
  }

  Future<void> tapShutter(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('scan.shutter')));
    await tester.pump();
  }
}

final _countdown = find.byKey(const Key('scan.countdown'));
final _shutter = find.byKey(const Key('scan.shutter'));
final _cancel = find.byKey(const Key('scan.manualCancel'));


/// Labels of every live-region semantics node currently in the tree.
List<String> _live(WidgetTester tester) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    if (n.hasFlag(SemanticsFlag.isLiveRegion)) out.add(n.label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

/// The digit currently shown by the countdown.
String? _digit(WidgetTester tester) =>
    tester.widgetList<Text>(_countdown).isEmpty
        ? null
        : tester.widget<Text>(_countdown).data;

void main() {
  group('manual shutter timer: start, tick, fire', () {
    testWidgets('tap starts a visible, announced, haptic timer and takes no photo yet',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);

      expect(r.camera.stills, 0, reason: 'no instant photo any more');
      expect(_digit(tester), '5');
      expect(r.speaker.said, ['Photo in 5 seconds']);
      expect(r.haptics.ticks, 1);
      expect(tester.widget<FilledButton>(_shutter).onPressed, isNull,
          reason: 'a second tap on the shutter must not stack timers');
      expect(_cancel, findsOneWidget);
    });

    testWidgets('each second ticks once (digit, speech, haptic) and it fires at zero',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);

      await r.secs(tester, 1);
      expect(_digit(tester), '4');
      await r.secs(tester, 1);
      expect(_digit(tester), '3');
      await r.secs(tester, 1);
      await r.secs(tester, 1);
      expect(_digit(tester), '1');
      expect(r.camera.stills, 0);
      expect(r.speaker.said, ['Photo in 5 seconds', '4', '3', '2', '1']);
      expect(r.haptics.ticks, 5);

      await r.secs(tester, 1);
      expect(r.camera.stills, 1);
      expect(r.haptics.shutters, greaterThanOrEqualTo(1));
      expect(_countdown, findsNothing);
      expect(find.descendant(
              of: find.byKey(const Key('scan.pose')), matching: find.text('Side')),
          findsOneWidget,
          reason: 'the next pose follows the capture');
      expect(r.speaker.said, contains('Next pose: Side'));
    });

    testWidgets('timer length follows the provider (3 s)', (tester) async {
      final r = _Rig();
      await r.pump(tester, timerSeconds: 3);
      await r.tapShutter(tester);
      expect(r.speaker.said.single, 'Photo in 3 seconds');
      await r.secs(tester, 2);
      expect(r.camera.stills, 0);
      await r.secs(tester, 1);
      expect(r.camera.stills, 1);
    });

    testWidgets('a provider value outside 3/5/10 falls back to 5 s',
        (tester) async {
      final r = _Rig();
      await r.pump(tester, timerSeconds: 7);
      await r.tapShutter(tester);
      expect(r.speaker.said.single, 'Photo in 5 seconds');
      await r.secs(tester, 4);
      expect(r.camera.stills, 0);
      await r.secs(tester, 1);
      expect(r.camera.stills, 1);
    });

    testWidgets('the auto machine is not fed while the manual timer runs',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.frame(tester, frontFrame());
      await r.tapShutter(tester);
      // Ready frames for 4.5 s: an auto countdown would have shot by ~3.5 s.
      for (var i = 0; i < 4; i++) {
        await r.secs(tester, 1);
        await r.frame(tester, frontFrame());
        await r.frame(tester, frontFrame());
      }
      expect(r.camera.stills, 0,
          reason: 'only the manual timer may take the photo');
      expect(_digit(tester), '1');
      await r.secs(tester, 1);
      expect(r.camera.stills, 1, reason: 'exactly one photo');
    });
  });

  group('manual shutter timer: cancel', () {
    testWidgets('Cancel aborts: nothing captured, warn haptic, speech stopped',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);
      await r.secs(tester, 2);
      final stopsBefore = r.speaker.stops;

      await tester.tap(_cancel);
      await tester.pump();
      expect(_countdown, findsNothing);
      expect(_cancel, findsNothing);
      expect(r.haptics.warns, 1);
      expect(r.speaker.stops, greaterThan(stopsBefore));
      expect(tester.widget<FilledButton>(_shutter).onPressed, isNotNull);

      await r.secs(tester, 10);
      expect(r.camera.stills, 0, reason: 'a cancelled timer must never fire');
    });

    testWidgets('after Cancel a new timer starts from the full length',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);
      await r.secs(tester, 3);
      await tester.tap(_cancel);
      await tester.pump();
      await r.tapShutter(tester);
      expect(_digit(tester), '5');
      await r.secs(tester, 4);
      expect(r.camera.stills, 0);
      await r.secs(tester, 1);
      expect(r.camera.stills, 1);
    });

    testWidgets('leaving the app cancels the timer (nobody is posing)',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);
      await r.secs(tester, 1);
      expect(_digit(tester), '4');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // Frames are disabled while paused, so the proof is: no photo is taken
      // while away and the timer is gone when the app returns.
      await r.secs(tester, 10);
      expect(r.camera.stills, 0, reason: 'a timer must not fire in the background');
      expect(r.haptics.warns, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(_countdown, findsNothing);
      expect(_cancel, findsNothing);
      expect(tester.widget<FilledButton>(_shutter).onPressed, isNotNull);
      await r.secs(tester, 10);
      expect(r.camera.stills, 0);
    });

    testWidgets('flipping the camera cancels the timer', (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.tapShutter(tester);
      await tester.tap(find.byKey(const Key('scan.flip')));
      await tester.pump();
      expect(_countdown, findsNothing);
      expect(r.camera.flips, 1);
      await r.secs(tester, 10);
      expect(r.camera.stills, 0);
    });
  });

  group('manualOverride only when readiness is not green at fire time', () {
    testWidgets('front not ready, side ready, back ready at tap but lost at fire',
        (tester) async {
      final r = _Rig();
      await r.pump(tester, weightKg: 82.5);

      // FRONT: no frame was ever evaluated -> not ready when the timer fires.
      await r.tapShutter(tester);
      await r.secs(tester, 5);
      expect(r.camera.stills, 1);

      // SIDE: green readiness the whole time.
      await r.frame(tester, sideFrame());
      await r.frame(tester, sideFrame());
      await r.tapShutter(tester);
      for (var i = 0; i < 4; i++) {
        await r.secs(tester, 1);
        await r.frame(tester, sideFrame());
      }
      await r.secs(tester, 1);
      expect(r.camera.stills, 2);

      // BACK: ready at the tap, readiness lost before the timer ends.
      await tester.tap(find.byKey(const Key('scan.facingAway')));
      await tester.pump();
      await r.frame(tester, backFrame());
      await r.frame(tester, backFrame());
      await r.tapShutter(tester);
      await r.secs(tester, 2);
      await r.frame(tester, emptyFrame());
      await r.secs(tester, 3);
      expect(r.camera.stills, 3);

      await tester.tap(find.byKey(const Key('scan.save')));
      await tester.pump();
      await tester.pump();
      final rec = r.scans.saved.single;
      expect(rec.manualOverride, {ScanPose.front: true, ScanPose.back: true},
          reason: 'side was ready when it fired, so it carries no override');
      expect(rec.anyManualOverride, isTrue);
      expect(rec.analysis!.status, JobStatus.queued);
      expect(rec.weightKg, 82.5);
      expect(rec.isLegacy, isFalse);
    });

    testWidgets('a fully ready manual capture records no override at all',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      for (final f in [frontFrame(), sideFrame()]) {
        await r.frame(tester, f);
        await r.frame(tester, f);
        await r.tapShutter(tester);
        for (var i = 0; i < 4; i++) {
          await r.secs(tester, 1);
          await r.frame(tester, f);
        }
        await r.secs(tester, 1);
      }
      await tester.tap(find.byKey(const Key('scan.facingAway')));
      await tester.pump();
      await r.frame(tester, backFrame());
      await r.frame(tester, backFrame());
      await r.tapShutter(tester);
      for (var i = 0; i < 4; i++) {
        await r.secs(tester, 1);
        await r.frame(tester, backFrame());
      }
      await r.secs(tester, 1);
      expect(r.camera.stills, 3);
      await tester.tap(find.byKey(const Key('scan.save')));
      await tester.pump();
      await tester.pump();
      expect(r.scans.saved.single.manualOverride, isEmpty);
      expect(r.scans.saved.single.anyManualOverride, isFalse);
    });

    testWidgets('a retaken pose forgets its override', (tester) async {
      final r = _Rig();
      await r.pump(tester);
      for (var pose = 0; pose < 3; pose++) {
        await r.tapShutter(tester);
        await r.secs(tester, 5);
      }
      expect(r.camera.stills, 3);
      // Retake front with a ready body: the stale override must be gone.
      await tester.tap(find.byKey(const Key('scan.retake.front')));
      await tester.pump();
      await tester.pump();
      await r.frame(tester, frontFrame());
      await r.frame(tester, frontFrame());
      await r.tapShutter(tester);
      for (var i = 0; i < 4; i++) {
        await r.secs(tester, 1);
        await r.frame(tester, frontFrame());
      }
      await r.secs(tester, 1);
      expect(r.camera.stills, 4);
      await tester.tap(find.byKey(const Key('scan.save')));
      await tester.pump();
      await tester.pump();
      expect(r.scans.saved.single.manualOverride,
          {ScanPose.side: true, ScanPose.back: true});
    });

    testWidgets('the screen pops with the new scan id', (tester) async {
      final r = _Rig();
      await r.pump(tester, pushed: true);
      await tester.tap(find.byKey(const Key('test.open')));
      await tester.pumpAndSettle();
      for (var pose = 0; pose < 3; pose++) {
        await r.tapShutter(tester);
        await r.secs(tester, 5);
      }
      await tester.tap(find.byKey(const Key('scan.save')));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(r.scans.saved, hasLength(1));
      expect(r.popped, r.scans.saved.single.id);
    });
  });

  group('one announcement channel per tick', () {
    testWidgets('screen reader: countdown is a live region and speech stays silent',
        (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      await r.pump(tester, screenReader: true);
      await r.tapShutter(tester);
      await r.secs(tester, 1);
      await r.secs(tester, 1);

      expect(r.speaker.said, isEmpty,
          reason: 'the live region is the only channel');
      expect(r.haptics.ticks, 3, reason: 'haptic ticks stay');
      expect(_live(tester), contains('Photo in 3'));
      handle.dispose();
    });

    testWidgets('screen reader: auto countdown does not speak digits either',
        (tester) async {
      final r = _Rig();
      await r.pump(tester, screenReader: true);
      await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
      expect(r.camera.stills, 1);
      expect(r.speaker.said.where((s) => RegExp(r'^\d$').hasMatch(s)), isEmpty);
      expect(r.haptics.ticks, greaterThan(0));
    });

    testWidgets('no screen reader: speech carries it, one utterance per tick',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
      final digits =
          r.speaker.said.where((s) => RegExp(r'^\d$').hasMatch(s)).toList();
      expect(digits, ['3', '2', '1'], reason: 'each digit spoken exactly once');
    });
  });

  group('hint live region and cues', () {
    testWidgets('the polite live region changes at most once per 2 s',
        (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      await r.pump(tester);
      final small = body(h: 0.45, top: 0.25); // step closer
      final big = body(h: 0.98, top: 0.005); // step back

      await r.frame(tester, small);
      expect(_live(tester), contains('Step a little closer.'));

      // 500 ms later the hint flips; the visible text follows, the live
      // region keeps the previous cue.
      await r.frame(tester, big);
      await r.frame(tester, big);
      expect(find.text('Step back a little.'), findsWidgets);
      expect(_live(tester), contains('Step a little closer.'));
      expect(_live(tester), isNot(contains('Step back a little.')));

      // After the 2 s gap the next change goes through.
      await r.frame(tester, small);
      await r.frame(tester, big);
      await r.frame(tester, big);
      await r.frame(tester, big);
      await r.frame(tester, big);
      await r.frame(tester, big);
      expect(_live(tester), contains('Step back a little.'));
      handle.dispose();
    });

    testWidgets('speech failure is swallowed and the hint stays on the live region',
        (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      r.speaker.result = false;
      await r.pump(tester);
      await r.frame(tester, body(h: 0.45, top: 0.25));
      await tester.pump();
      expect(r.speaker.said, contains('Step a little closer.'));
      expect(tester.takeException(), isNull);
      expect(_live(tester), contains('Step a little closer.'));
      handle.dispose();
    });

    testWidgets('named haptic patterns: one per failing check class, ready, lost',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);

      await r.frame(tester, body(h: 0.45, top: 0.25)); // distance
      await r.frame(tester, body(h: 0.45, top: 0.25)); // same: no repeat
      expect(r.haptics.patterns, [ScanHapticPattern.distance]);

      r.camera.lum = 0.05; // lighting too dark
      await r.frame(tester, frontFrame());
      expect(r.haptics.patterns.last, ScanHapticPattern.lighting);

      r.camera.lum = null;
      await r.frame(tester, body(cx: 0.1)); // off centre
      expect(r.haptics.patterns.last, ScanHapticPattern.position);

      await r.frame(tester, sideFrame()); // wrong pose for the front step
      expect(r.haptics.patterns.last, ScanHapticPattern.pose);

      await r.frame(tester, frontFrame());
      expect(r.haptics.patterns.last, ScanHapticPattern.ready);

      await r.frame(tester, emptyFrame());
      expect(r.haptics.patterns.contains(ScanHapticPattern.lost), isTrue);
      expect(r.haptics.patterns.where((p) => p == ScanHapticPattern.ready),
          hasLength(1));
      // Every class produced a distinct pattern.
      expect(r.haptics.patterns.toSet(), containsAll({
        ScanHapticPattern.distance,
        ScanHapticPattern.lighting,
        ScanHapticPattern.position,
        ScanHapticPattern.pose,
        ScanHapticPattern.ready,
        ScanHapticPattern.lost,
      }));
    });

    testWidgets('over-exposure from the real luminance blocks the countdown',
        (tester) async {
      final r = _Rig();
      r.camera.lum = 0.99;
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => false, limitMs: 3000);
      expect(_countdown, findsNothing);
      expect(r.camera.stills, 0);
      expect(find.text('It is too bright. Reduce the glare.'), findsWidgets);
    });

    testWidgets('a camera that cannot measure falls back to the low-light verdict',
        (tester) async {
      final r = _Rig();
      r.camera.low.value = true;
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => false, limitMs: 3000);
      expect(_countdown, findsNothing);
      expect(find.text('It is too dark. Add more light.'), findsWidgets);
    });

    testWidgets('a camera without luminance and without low light proceeds',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
      expect(r.camera.stills, 1);
    });

    testWidgets('all-checks-OK cue is announced once on the live region',
        (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      await r.pump(tester);
      await r.frame(tester, frontFrame());
      expect(_live(tester), contains('All four checks OK, hold still'));
      expect(
          r.speaker.said.where((s) => s == 'All four checks OK, hold still'),
          hasLength(1));
      handle.dispose();
    });
  });

  group('accessibility and layout', () {
    testWidgets('text scale 2.0 at 360x640 in Russian: no overflow, shutter >= 48 dp, reachable',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final r = _Rig();
      await r.pump(tester, textScale: 2.0, locale: const Locale('ru'));
      await r.frame(tester, body(h: 0.45, top: 0.25));
      expect(tester.takeException(), isNull);

      final rect = tester.getRect(_shutter);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));

      final scroll = tester.getRect(find.byKey(const Key('scan.panelScroll')));
      expect(scroll.height, lessThanOrEqualTo(320),
          reason: 'the status area is capped at half the screen');

      await tester.tap(_shutter);
      await tester.pump();
      expect(r.speaker.said.last, 'Фото через 5 секунд');
      expect(tester.takeException(), isNull);
      final cancel = tester.getRect(_cancel);
      expect(cancel.height, greaterThanOrEqualTo(48));
      expect(cancel.bottom, lessThanOrEqualTo(640));
      expect(find.text('Отменить таймер'), findsOneWidget);
    });

    testWidgets('text scale 2.0 on the back step keeps the facing-away control in the scroll area',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final r = _Rig();
      await r.pump(tester, textScale: 2.0, locale: const Locale('ru'));
      for (var i = 0; i < 2; i++) {
        await r.tapShutter(tester);
        await r.secs(tester, 5);
      }
      expect(find.byKey(const Key('scan.facingAway')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_shutter).bottom, lessThanOrEqualTo(640));
      expect(tester.getRect(_shutter).height, greaterThanOrEqualTo(48));
    });

    testWidgets('shutter is labelled and focusable for assistive tech',
        (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      await r.pump(tester);
      final node = tester.getSemantics(_shutter);
      expect(node.label, 'Take photo now');
      expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      handle.dispose();
    });

    testWidgets('reduced motion replaces the spinner with static text',
        (tester) async {
      final cam = _SlowStartCamera();
      final r = _Rig(camera: cam);
      await r.pump(tester, reducedMotion: true);
      expect(find.text('Starting the camera'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final cam2 = _SlowStartCamera();
      final r2 = _Rig(camera: cam2);
      await r2.pump(tester);
      expect(find.text('Starting the camera'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      cam.gate.complete();
      cam2.gate.complete();
      await tester.pump();
    });

    testWidgets('the manual shutter is disabled until the camera is running',
        (tester) async {
      final cam = _SlowStartCamera();
      final r = _Rig(camera: cam);
      await r.pump(tester);
      expect(tester.widget<FilledButton>(_shutter).onPressed, isNull);
      cam.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<FilledButton>(_shutter).onPressed, isNotNull);
    });

    testWidgets('camera error is announced as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      final r = _Rig();
      r.camera.startError = StateError('denied');
      await r.pump(tester);
      final node = tester.getSemantics(find.byKey(const Key('scan.cameraError')));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
      handle.dispose();
    });
  });
}

extension on _Rig {
  Future<void> drive(WidgetTester tester, PoseFrame f,
      {required bool Function() until, int limitMs = 20000}) async {
    final end = nowMs + limitMs;
    while (!until() && nowMs < end) {
      await frame(tester, f);
    }
  }
}
