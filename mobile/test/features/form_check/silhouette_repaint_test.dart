import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// The outline follows the body, and the painter has to be asked to redraw it.
///
/// `alignTargetToFrame` is covered directly in `pose_alignment_test.dart`, and
/// the picture it produces is covered by the goldens. Between the two sat the
/// part that decides whether any of it reaches the screen: `_SilhouettePainter
/// .shouldRepaint`, which used to compare only the target, the mode and
/// whether the match had crossed the pass mark — none of which change while a
/// user moves through a repetition.
///
/// A golden cannot see this. It photographs one settled frame; a stale outline
/// that never repaints looks identical in a still.

PoseFrame _bodyAt(double dx, {int ts = 0}) {
  PoseLandmark p(LandmarkType t, double x, double y) =>
      PoseLandmark(type: t, x: x + dx, y: y, likelihood: 0.92);
  return PoseFrame(
    timestampMs: ts,
    aspectRatio: 9 / 16,
    landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.22, 0.26),
      LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.30, 0.26),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.23, 0.54),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.29, 0.54),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.24, 0.74),
      LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.28, 0.74),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.24, 0.93),
      LandmarkType.rightAnkle: p(LandmarkType.rightAnkle, 0.28, 0.93),
    },
  );
}

void main() {
  Widget page(ProviderContainer c) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FormCheckPage(),
        ),
      );

  CustomPainter painterOf(WidgetTester t) => t
      .widget<CustomPaint>(find.byKey(const Key('form_check.silhouette')))
      .painter!;

  testWidgets('a body that moved repaints the outline; a still one does not',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(const [])),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    ]);
    addTearDown(c.dispose);

    c.read(latestPoseFrameProvider.notifier).state = _bodyAt(0);
    await tester.pumpWidget(page(c));
    await tester.pump();
    final first = painterOf(tester);

    // The identical body again. A painter that reports "repaint" here would
    // redraw the whole outline on every camera frame of a held position, which
    // is the cost the coarse match comparison next to it exists to avoid.
    c.read(latestPoseFrameProvider.notifier).state = _bodyAt(0, ts: 33);
    await tester.pump();
    expect(painterOf(tester).shouldRepaint(first), isFalse,
        reason: 'nothing about the body changed');

    // A step to one side. Same pose, same size, different place — invisible to
    // every other field `shouldRepaint` compares.
    c.read(latestPoseFrameProvider.notifier).state = _bodyAt(0.09, ts: 66);
    await tester.pump();
    expect(painterOf(tester).shouldRepaint(first), isTrue,
        reason: 'the outline follows the body, so it has to be redrawn when '
            'the body moves — and a step sideways changes nothing else this '
            'painter looks at');
  });

  testWidgets('a one-frame far-side dropout does not jump the outline',
      (tester) async {
    // The avatar holds a far side the detector loses for up to 200ms
    // (`AvatarFarSideLatch`), because losing it moves the drawn trunk by more
    // than 15% — that is measured, and it is why the latch exists. The target
    // outline is now placed on the same body, so it has to be placed on the
    // same STABILISED body: aligning to raw landmarks would snap the anchor
    // from the hip midpoint to the near hip on a blink, sliding the outline
    // half a hip-width off a figure that deliberately did not move. Raised by
    // GPT-PM, 2026-09-02, against the first version of this gate.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(const [])),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    ]);
    addTearDown(c.dispose);

    c.read(latestPoseFrameProvider.notifier).state = _bodyAt(0);
    await tester.pumpWidget(page(c));
    await tester.pump();
    final both = c.read(stabilisedBodyProvider);
    expect(both, isNotNull);
    final anchored = alignTargetToBody(both!.joints, squatBottomTarget)!;

    // The same body, one frame later, with the far side below the detector's
    // confidence threshold — a blink, not a turn.
    final blink = PoseFrame(
      timestampMs: 33,
      aspectRatio: 9 / 16,
      landmarks: {
        for (final e in _bodyAt(0).landmarks.entries)
          e.key: e.key.name.startsWith('right')
              ? PoseLandmark(
                  type: e.key, x: e.value.x, y: e.value.y, likelihood: 0.2)
              : e.value,
      },
    );
    c.read(latestPoseFrameProvider.notifier).state = blink;
    await tester.pump();
    final held = c.read(stabilisedBodyProvider);
    expect(held, isNotNull, reason: 'the near side alone still carries a torso');
    final afterBlink = alignTargetToBody(held!.joints, squatBottomTarget)!;

    expect(afterBlink.bodyCentre.$1, closeTo(anchored.bodyCentre.$1, 1e-9),
        reason: 'the outline moved sideways on a body that did not');
    expect(afterBlink.bodyCentre.$2, closeTo(anchored.bodyCentre.$2, 1e-9));
    expect(afterBlink.scale, closeTo(anchored.scale, 1e-9));
  });
}
