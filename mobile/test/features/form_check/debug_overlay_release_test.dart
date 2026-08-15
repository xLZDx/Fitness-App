import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_coordinate_space.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_unit_probe.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// The release screen must carry no developer copy.
///
/// `pose[pixels] n=807 x -0.466..1.968 ...` shipped to users on purpose: the
/// measurement it exists to produce could only be taken on a real phone with a
/// real body in frame, so hiding it behind `kDebugMode` would have meant nobody
/// ever read it. The number has since been taken (R0 audit §7.5) and the design
/// spec quotes the string verbatim as a defect, so the exposure ends here.
///
/// This is the test the master prompt §18.5 asks for by name: "Add a test that
/// release and production presentation contain no debug copy." It has to
/// override the flag rather than read `kDebugMode`, because a test runs in
/// debug — asserting on the ambient constant would check the build the user
/// never sees.

final _probeLine = find.byKey(const Key('form-check-unit-probe'));

/// A report with real content, so an absent line proves the gate closed rather
/// than proving there was nothing to draw.
/// `all` and `aspectRatio` are the operator's own, read off the phone that
/// produced the screenshots, and are kept verbatim.
///
/// `trusted` is INVENTED — a body sitting comfortably inside the frame. Nobody
/// has measured the real trusted extent yet; that is what Gate B is for. It is
/// stated rather than left to look measured, because this file's job is to
/// prove the probe line is absent in release, and any content at all serves
/// that. Do not quote these four numbers as evidence of anything.
const _report = PoseUnitReport(
  frames: 807,
  all: PoseExtent(
    minX: -0.466,
    maxX: 1.968,
    minY: -2.173,
    maxY: 3.015,
    landmarks: 26631,
  ),
  trusted: PoseExtent(
    minX: 0.071,
    maxX: 0.598,
    minY: 0.104,
    maxY: 0.943,
    landmarks: 19442,
  ),
  minLikelihood: 0.7,
  spaces: {PoseCoordinateSpace.pixels},
  aspectRatio: 0.667,
);

/// One frame carrying two usable coordinates — enough for the probe to fold in,
/// which is what the measurement tests below need it to be.
const _frame = PoseFrame(
  timestampMs: 1,
  landmarks: {
    LandmarkType.leftHip: PoseLandmark(
      type: LandmarkType.leftHip,
      x: 0.4,
      y: 0.5,
      likelihood: 0.9,
    ),
    LandmarkType.rightHip: PoseLandmark(
      type: LandmarkType.rightHip,
      x: 0.6,
      y: 0.5,
      likelihood: 0.9,
    ),
  },
);

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

ProviderContainer _container({
  required bool debugOverlay,
  PoseDetectorService? service,
}) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(service ?? MockPoseDetectorService(const [])),
    poseDebugOverlayProvider.overrideWithValue(debugOverlay),
    // R11h: this file's subject is the camera UI, so it starts where
    // that UI lives instead of tapping through the two intro cards.
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Tall enough that the diagnostic's slot is inside the viewport: `ListView`
/// builds only the children it can show, so a short view would report the line
/// missing for the wrong reason and the test would pass while the bug shipped.
void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(400, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the release build shows no coordinate diagnostic', (t) async {
    _tall(t);
    final c = _container(debugOverlay: false);
    c.read(poseUnitReportProvider.notifier).state = _report;

    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_probeLine, findsNothing);
    expect(
      find.textContaining('pose['),
      findsNothing,
      reason: 'the design spec quotes this string verbatim as a defect',
    );
  });

  testWidgets('a debug build still shows it', (t) async {
    // The positive control. Without it the test above would keep passing if the
    // diagnostic were deleted outright, or if the whole page stopped building,
    // and would say nothing about whether the flag works.
    _tall(t);
    final c = _container(debugOverlay: true);
    c.read(poseUnitReportProvider.notifier).state = _report;

    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_probeLine, findsOneWidget);
  });

  test('the release build does not even measure', () async {
    // Gating only the render would leave the probe folding every landmark of
    // every frame into extents nobody will read, and writing a provider on each
    // one. Cheap, but paid thirty times a second for nothing.
    final svc = MockPoseDetectorService(const [_frame]);
    final c = _container(debugOverlay: false, service: svc);
    addTearDown(svc.dispose);

    c.read(formFeedbackControllerProvider);
    await svc.start();
    await pumpEventQueue();

    expect(c.read(poseUnitReportProvider).isEmpty, isTrue);
  });

  test('a debug build does measure', () async {
    // The control for the one above: it must fail for the flag's sake, not
    // because the fixture never reached the probe.
    final svc = MockPoseDetectorService(const [_frame]);
    final c = _container(debugOverlay: true, service: svc);
    addTearDown(svc.dispose);

    c.read(formFeedbackControllerProvider);
    await svc.start();
    await pumpEventQueue();

    expect(c.read(poseUnitReportProvider).isEmpty, isFalse);
  });
}
