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

import '../helpers/test_app.dart';
import '../support/golden_fonts.dart';

/// Visual regression coverage for the Form Coach screen, which had none.
///
/// This is the gap that made the redesign expensive. Three of the six defects
/// in gate G5 were found by the operator on a real phone, and two of those
/// passed the entire suite before and after the fix — a suite that measures
/// where an outline IS cannot tell whether anything inside it was drawn. Every
/// gate since has ended with "unverified on the device", and the device is
/// currently behind a PIN.
///
/// A golden is not a substitute for a phone: it renders in a host Skia with
/// bundled fonts, and it cannot tell you the picture is legible over a real
/// camera image. What it can do is fail when the layout moves, which is what
/// the redesign has been changing every gate, and it costs nothing to run.
///
/// **Avatar mode, deliberately.** The camera preview cannot render in a widget
/// test, and the point here is the HUD and the drawn body — both of which are
/// exactly what avatar mode shows.

/// A body standing at the top of a squat, frontal, every joint present.
///
/// Frontal rather than side-on so both sides of the figure are genuinely
/// observed: that is the state G5's geometry and G6's far-side latch are about,
/// and a profile fixture would hide half of what these gates changed.
PoseFrame _standing(int ts) {
  PoseLandmark p(LandmarkType t, double x, double y) =>
      PoseLandmark(type: t, x: x, y: y, likelihood: 0.92);
  return PoseFrame(
    timestampMs: ts,
    // A 9:16 portrait camera, which is what the app actually gets. The first
    // draft of this fixture left the default 1.0 and put x in [0.35, 0.65];
    // the golden it produced showed a figure bursting out of the preview, and
    // the figure was right — the FIXTURE was a square frame. `PoseLandmark.x`
    // ranges over [0, aspectRatio], not [0, 1] (see `pose_coordinate_space.
    // dart`), so those coordinates described a body wider than its own frame.
    // Worth recording rather than quietly fixing: it is the same class of
    // mistake as a test that passes for the wrong reason, and the golden is
    // what surfaced it within a minute.
    aspectRatio: 9 / 16,
    landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.22, 0.26),
      LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.34, 0.26),
      LandmarkType.leftElbow: p(LandmarkType.leftElbow, 0.19, 0.40),
      LandmarkType.rightElbow: p(LandmarkType.rightElbow, 0.37, 0.40),
      LandmarkType.leftWrist: p(LandmarkType.leftWrist, 0.17, 0.53),
      LandmarkType.rightWrist: p(LandmarkType.rightWrist, 0.39, 0.53),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.24, 0.54),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.32, 0.54),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.24, 0.74),
      LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.32, 0.74),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.24, 0.93),
      LandmarkType.rightAnkle: p(LandmarkType.rightAnkle, 0.32, 0.93),
    },
  );
}

void main() {
  setUpAll(loadHudGoldenFonts);

  /// **In the LIGHT theme, which is the one that broke.**
  ///
  /// This built `AppTheme.dark()` at first, as every widget test on this page
  /// does — and that is precisely how the HUD came to be unreadable on a real
  /// phone without a single test noticing. The coach's picture is dark whatever
  /// the app is, its readouts take their colour from `Theme.of(context)`, and
  /// in light mode that was navy text on a photograph. One configuration was
  /// broken and it was the one nothing rendered.
  ///
  /// So the reference image is now taken the way the operator's phone is
  /// actually set up: a light app, with a dark picture inside it.
  Widget page(ProviderContainer c) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.light,
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FormCheckPage(),
        ),
      );

  ProviderContainer container(CoachPhase phase) {
    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWithValue(
        // The same frame over and over: a still body, so the image is a
        // function of the code rather than of how many times the test pumped.
        MockPoseDetectorService([for (var i = 0; i < 40; i++) _standing(i * 33)]),
      ),
      coachInitialPhaseProvider.overrideWithValue(phase),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Pump the fixture through, then bring the frame source to rest.
  ///
  /// **Where in the demonstration this lands, since it matters.** The loop's
  /// controller runs 2000ms each way and repeats reversed, so 40 pumps of 33ms
  /// plus the 60ms settle put it about 0.69 of the way down, which
  /// `Curves.easeInOutCubic` carries to roughly 0.86 — genuinely mid-swing,
  /// not parked on an authored end where every interpolation agrees and the
  /// picture would say nothing about the geometry. Raised in review as an
  /// open question and settled by arithmetic rather than left as one. It is
  /// also self-correcting: change the controller's duration or this loop and
  /// the captured phase moves, which changes the image, which fails the
  /// golden — and somebody looks.
  ///
  /// `matchesGoldenFile` runs its comparison through `tester.runAsync`, which
  /// asserts no timers are pending — and `MockPoseDetectorService.start` awaits
  /// a 33ms delay between frames, so one is always in flight mid-stream.
  /// Stopping the service and pumping past that last delay lets its loop
  /// observe the stop and exit, which is also the honest state to photograph:
  /// a still body with no frame arriving, rather than one caught mid-stream.
  Future<void> settle(WidgetTester tester, ProviderContainer c) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await c.read(poseDetectorServiceProvider).stop();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('the live HUD over the drawn body', (tester) async {
    // Tall enough that the whole 9:16 preview fits above the fold. At 900 the
    // first version of this golden cut the body off at the knees, which makes
    // a poor reference image: half the thing under review was outside it.
    pinGoldenSurface(tester, size: const Size(400, 1400));
    final c = container(CoachPhase.qualityCheck);
    c.read(avatarModeProvider.notifier).state = true;
    await tester.pumpWidget(page(c));
    await settle(tester, c);

    await expectLater(
      find.byType(FormCheckPage),
      matchesGoldenFile('goldens/form_coach_live.png'),
    );
  });

  testWidgets('and the picker that comes before it', (tester) async {
    // The screen the redesign's first two gates rebuilt: one card carrying both
    // banners, the movement list, and the looping demonstration.
    pinGoldenSurface(tester, size: const Size(400, 1400));
    final c = container(CoachPhase.selection);
    await tester.pumpWidget(page(c));
    await settle(tester, c);

    await expectLater(
      find.byType(FormCheckPage),
      matchesGoldenFile('goldens/form_coach_selection.png'),
    );
  });
}
