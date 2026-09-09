import 'dart:math' as math;

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

import '../features/form_check/unscorable_frame_test.dart' show oneSquat;
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
///
/// One limit of that, so nobody reads more into these images than they hold.
/// The avatar's own body is filled near-black by design, for legibility
/// against a scene, so what survives in these pictures is the avatar's
/// SKELETON, not its body — the figure reads as bones here and as a filled
/// person on a phone (`reports/device-check-2026-09-02/`). The layout, the
/// readouts and the target silhouette are what these images pin.
///
/// The backdrop photograph itself used to resolve in some of these tests and
/// not others depending on which ran first — `Image.asset` decodes through a
/// real asset-bundle read that the first golden to touch a given file pays
/// for and every later one gets for free, so the same seeded scene rendered
/// differently depending on run order even though [deterministic] pinned
/// WHICH scene was picked. `precacheBackdrop` (below) forces that read onto
/// each container's own clock, so a given golden now shows the same picture
/// whether it runs alone or as part of the file — verified both ways with
/// `--plain-name` before these images were last re-recorded.

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

  /// The backdrop photograph is chosen at RANDOM, and until 2026-09-02 that
  /// did not show: `Image.asset` was not resolving in these tests, so every
  /// run photographed the same near-black layer underneath it and the choice
  /// could not matter. Once the photographs began resolving, two consecutive
  /// runs of the same unchanged test differed by 54% and then 94% — a golden
  /// that fails at random is worse than no golden, because the next person to
  /// see it red will re-record it without looking.
  ///
  /// A seeded `Random` makes the choice deterministic — **a FRESH one per
  /// container**, which the first version of this fix got wrong. A single
  /// `Random(7)` instance shared across all three containers is mutable
  /// state: each container's own `CoachBackdropController.build()` (and the
  /// reshuffle on selection-screen entry) calls `.nextInt()` on it and
  /// advances it, so which photograph a given test received depended on how
  /// many `.nextInt()` calls the OTHER containers had already made — a golden
  /// deterministic only for one fixed run order, and no more hermetic than
  /// the flake it replaced. GPT-PM, reviewing the first version of this gate.
  ///
  /// A function that builds a new `Random(7)` on every call gives each
  /// container its own sequence, starting from the same seed, so the first
  /// pick and the reshuffle are pinned independent of what any other
  /// container's provider tree has done.
  /// The sky phase needs the same treatment, and did not have it. A seeded
  /// `Random` pins which of the ten scenes is drawn, but `HudSkyPhase.forTime`
  /// picks the PHASE from the wall clock, and each phase draws a different
  /// photograph — so these goldens rendered one picture when recorded and
  /// another when checked a few hours later. That is the 54% difference that
  /// left all three excluded from verification rather than any layout change.
  ///
  /// 02:00 is not an arbitrary pick, and the measurement that chose it is
  /// worth keeping. Pinned to noon (`day`) these three goldens differ from
  /// their masters by 55.31 / 55.53 / 55.29 percent; pinned to 02:00 (`night`)
  /// the same three differ by 3.33 / 4.20 / 1.64. The masters were therefore
  /// recorded under `night`, and pinning any other phase would have meant
  /// re-recording all three wholesale — which would have swallowed that
  /// remaining few percent, the only part that is about the coach rather than
  /// the weather. 02:00 also sits well inside the band, which wraps midnight
  /// (`h < 5 || h >= 22`), so no rounding or timezone detail can push a run
  /// into `dawn`.
  ///
  /// Pinning ONE instant is the whole point: asserting that two DIFFERENT
  /// phases render alike would be asserting the six-phase behaviour away.
  /// `hud_sky_test.dart` still holds that boundary mapping honest, and the
  /// 55%-vs-3% split above is the evidence that this override is load-bearing
  /// rather than decorative — change the instant and the picture changes.
  List<Override> deterministic() => [
        coachBackdropRandomProvider.overrideWithValue(math.Random(7)),
        coachClockProvider.overrideWithValue(() => DateTime(2026, 8, 19, 2)),
      ];

  ProviderContainer container(CoachPhase phase) {
    final c = ProviderContainer(overrides: [
      ...deterministic(),
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

  /// Forces the container's chosen backdrop photo to be decoded before the
  /// golden is captured, so its presence in the picture is a function of the
  /// seeded [Random] this container got — not of whichever other goldens in
  /// this file happened to run first and warm `Image.asset`'s decode cache.
  ///
  /// GPT-PM, round 2: [deterministic] alone pins WHICH scene each container
  /// picks, and that was mistaken for pinning the picture. It does not —
  /// `Image.asset` resolves through a real asset-bundle read that the first
  /// golden to touch a given file pays for and every later one gets free,
  /// so the same seeded pick still rendered as a photograph in a full-file
  /// run and as the plain scrim when the same test ran alone. Caught by
  /// running each of the three tests with `--plain-name`: the picker golden
  /// alone was a 95.64% pixel diff against the one recorded inside the full
  /// file. `precacheImage` makes the read happen on this container's own
  /// clock, inside `tester.runAsync` the same way `matchesGoldenFile` itself
  /// already requires real asset I/O to be awaited in a widget test.
  Future<void> precacheBackdrop(WidgetTester tester, ProviderContainer c) async {
    final path = c.read(coachBackdropProvider);
    final element = tester.element(find.byType(FormCheckPage));
    await tester.runAsync(() => precacheImage(AssetImage(path), element));
    // The demonstration's poster used to be precached here too: a widget test
    // has no video platform, so the squat's clip always fell back to its
    // poster and that still image WAS the picture of the picker. G1.2
    // (2026-09-09) removed the clip, so there is no second image to decode —
    // the panel now holds a sentence, which needs no asset I/O.
    await tester.pump();
  }

  testWidgets('the live HUD over the drawn body', (tester) async {
    // Tall enough that the whole 9:16 preview fits above the fold. At 900 the
    // first version of this golden cut the body off at the knees, which makes
    // a poor reference image: half the thing under review was outside it.
    pinGoldenSurface(tester, size: const Size(400, 1400));
    final c = container(CoachPhase.qualityCheck);
    c.read(avatarModeProvider.notifier).state = true;
    await tester.pumpWidget(page(c));
    await precacheBackdrop(tester, c);
    await settle(tester, c);

    await expectLater(
      find.byType(FormCheckPage),
      matchesGoldenFile('goldens/form_coach_live.png'),
    );
  });

  testWidgets('a repetition the coach faulted, explained', (tester) async {
    // G7 and G8, which are the newest work on this page and the least looked
    // at: the cue on the picture, the ring on the joint the rule turns on, the
    // four counters with something in them for once, and the calm explanation
    // underneath. Every one of those is drawn only after a rep completes and
    // is faulted, which is why the two images above — a body standing still —
    // show none of them.
    //
    // `oneSquat` is the same fixture `fault_explanation_test.dart` asserts
    // against, so the pose that produces this picture is one another test has
    // already pinned as a completed, faulted repetition rather than something
    // arranged to look good here.
    pinGoldenSurface(tester, size: const Size(400, 1400));
    final c = ProviderContainer(overrides: [
      ...deterministic(),
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(oneSquat(0))),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    ]);
    addTearDown(c.dispose);
    c.read(avatarModeProvider.notifier).state = true;
    await tester.pumpWidget(page(c));
    await precacheBackdrop(tester, c);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    await c.read(poseDetectorServiceProvider).stop();
    await tester.pump(const Duration(milliseconds: 60));

    // Positive controls. A golden of a screen that never reached the state it
    // is named for is worse than no golden: it would lock in the empty version
    // and go green forever.
    final cue = c.read(repSessionControllerProvider).lastRepCue;
    expect(cue, isNotNull, reason: 'no repetition completed');
    expect(cue!.severity, greaterThan(0), reason: 'the repetition passed');
    expect(find.byKey(const Key('form_check.explain')), findsOneWidget);

    await expectLater(
      find.byType(FormCheckPage),
      matchesGoldenFile('goldens/form_coach_faulted.png'),
    );
  });

  testWidgets('and the picker that comes before it', (tester) async {
    // The screen the redesign's first two gates rebuilt: one card carrying both
    // banners, the movement list, and the looping demonstration.
    pinGoldenSurface(tester, size: const Size(400, 1400));
    final c = container(CoachPhase.selection);
    await tester.pumpWidget(page(c));
    await precacheBackdrop(tester, c);
    await settle(tester, c);

    await expectLater(
      find.byType(FormCheckPage),
      matchesGoldenFile('goldens/form_coach_selection.png'),
    );
  });
}
