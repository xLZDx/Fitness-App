import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat;

/// Showing the user what the camera sees.
///
/// Every other readout on this page is a conclusion: a count, a verdict, a
/// match percentage. When a conclusion is wrong there are two very different
/// causes — the rule misjudged a real repetition, or the detector never found
/// the body — and they want opposite responses. Nothing on screen told them
/// apart, which is how "все повторения правильные даже если я неправильно
/// делаю" and "она меня не видит" become the same complaint.
///
/// It is OFF by default and stays off until asked for. The projection depends
/// on how the platform crops the preview and whether it has already mirrored
/// the front camera, and neither is settled until it has been seen on a real
/// phone. A skeleton drawn a few percent out reads as a broken detector, which
/// is worse than drawing nothing at all.

final _skeleton = find.byKey(const Key('form_check.skeleton'));

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
    // R11h: this file's subject is the camera UI, so it starts where
    // that UI lives instead of tapping through the two intro cards.
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    // Camera mode, stated rather than inherited from a default that flipped on
    // 2026-08-15. This file's subject is the diagnostic skeleton, which Gate A
    // stopped drawing in avatar mode — the avatar already draws lit bones, and
    // a second thinner set on top reads as a tracking failure. Both switches
    // also publish the same frame, so leaving avatar mode on would make "no
    // frame is kept while it is off" test the wrong switch entirely.
    avatarModeProvider.overrideWith((_) => false),
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
  testWidgets('nothing is drawn until it is asked for', (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    // Long enough for the mock to finish replaying its fixtures, so the
    // start timeout's timer is cancelled rather than left pending.
    await t.pump(const Duration(seconds: 2));

    expect(c.read(showSkeletonProvider), isFalse);
    expect(_skeleton, findsNothing);
  });

  testWidgets('and no frame is kept while nothing at all is drawn from it',
      (t) async {
    // The overlay being off must also stop the controller PUBLISHING frames:
    // otherwise a provider nobody reads is notified thirty times a second for
    // the whole set, next to a camera and a pose detector.
    //
    // **"Nobody reads it" grew a third reader on 2026-09-02**, and this test
    // asserted the old two. The target outline is now placed on the tracked
    // body, so it needs the frame exactly as the skeleton and the avatar do —
    // and over a raw camera with the skeleton off, which is one toggle from
    // the default, publishing nothing left the outline at its authored
    // coordinates and reproduced the whole defect that gate closed. Caught by
    // GPT-PM reviewing the fix, not by this suite.
    //
    // So the movement is switched to one with no authored target. That keeps
    // the assertion honest — it still says "no readers, no frames" — instead of
    // pinning a reader count that has changed once and may change again.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    c.read(selectedExerciseProvider.notifier).state = FormExercise.deadlift;
    await t.pumpWidget(_page(c));
    await t.pump();
    // Long enough for the mock to finish replaying its fixtures, so the
    // start timeout's timer is cancelled rather than left pending.
    await t.pump(const Duration(seconds: 2));

    expect(c.read(poseTargetProvider), isNull,
        reason: 'positive control: this movement really has no outline to '
            'place, so nothing is reading the frame');
    expect(c.read(latestPoseFrameProvider), isNull);
  });

  testWidgets('but a target outline is a reader, even with both toggles off',
      (t) async {
    // The other half, and the regression this pair exists for: the outline is
    // drawn over the raw camera too, and it cannot be placed on a body nobody
    // published.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(c.read(showSkeletonProvider), isFalse);
    expect(c.read(avatarModeProvider), isFalse);
    expect(c.read(poseTargetProvider), isNotNull);
    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'the outline has no body to sit on');
    expect(c.read(stabilisedBodyProvider), isNotNull,
        reason: 'and no stabilised body to be aligned against');
  });

  testWidgets('switched on, it draws the body the detector found', (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'switching it on has to start publishing frames');
    expect(_skeleton, findsOneWidget);
  });

  testWidgets('switched on before a frame arrives, it draws nothing yet',
      (t) async {
    // "On, but the camera has produced nothing" must not paint an empty
    // figure at the origin — a skeleton collapsed into the corner is exactly
    // the picture that says "this detector is broken".
    _phoneSized(t);
    final c = _container(const []);
    await t.pumpWidget(_page(c));
    c.read(showSkeletonProvider.notifier).state = true;
    await t.pump();
    await t.pump();

    expect(c.read(latestPoseFrameProvider), isNull);
    expect(_skeleton, findsNothing);
  });

  testWidgets('the toggle in the app bar turns it on and off', (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();

    await t.tap(find.byTooltip('Show what the camera sees'));
    await t.pump(const Duration(seconds: 2));
    expect(c.read(showSkeletonProvider), isTrue);
    expect(_skeleton, findsOneWidget);

    await t.tap(find.byTooltip('Show what the camera sees'));
    await t.pump();
    expect(c.read(showSkeletonProvider), isFalse);
    expect(_skeleton, findsNothing);
    // The frame STAYS, because the target outline is still reading it — see
    // the pair of tests above. The danger this line used to guard against was
    // a pose from a minute ago flashing over a live camera when the toggle
    // came back on; that cannot happen while the frame is being republished
    // every 33ms, and it is the publishing, not the dropping, that makes it
    // safe. With nothing reading it the frame is still dropped, which the
    // deadlift test above asserts directly.
    expect(c.read(latestPoseFrameProvider), isNotNull);
  });
}
