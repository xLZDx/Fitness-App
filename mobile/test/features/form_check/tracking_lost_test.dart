import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat;

/// Losing the person must be visible.
///
/// The detector used to `return` on a frame with no pose in it, which meant
/// nothing downstream was told anything at all: `latestPoseFrameProvider` kept
/// the last live pose and `poseGateVerdictProvider` kept the last verdict. The
/// overlay went on drawing a body that had walked away, over a gate verdict
/// describing a moment that had passed.
///
/// That was cosmetic only for as long as the camera image sat underneath —
/// the user could see an empty room and draw their own conclusion. The avatar
/// mode replaces that image with a still backdrop, at which point a frozen
/// figure and a tracking figure look exactly alike, and the screen is lying
/// rather than merely stale.
///
/// The detector now emits an EMPTY frame instead of returning, and the
/// controller publishes that as null. Asserted here through the real
/// controller and the real gate rather than against `gatePose` directly: the
/// reset is one expression in one controller, and nothing else in the app
/// would notice if a refactor dropped it.
///
/// [MlKitPoseDetectorService] itself cannot be exercised here — it constructs
/// its own `mlkit.PoseDetector` and needs a device. What is covered is the
/// contract it emits against: an empty frame means nobody, and every consumer
/// treats it that way.

/// The frame the detector now sends when it finds nobody.
PoseFrame nobody(int ts) => PoseFrame(timestampMs: ts, landmarks: const {});

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
    // Camera mode, stated rather than inherited — the default flipped on
    // 2026-08-15. This file asserts on the diagnostic skeleton being held and
    // dropped, and Gate A stopped drawing it in avatar mode.
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
  testWidgets('a body in frame is held, and drawn', (t) async {
    // The positive control. A test that asserts "the pose was cleared" passes
    // just as well when no pose ever arrived, which is how an absence gets
    // mistaken for a fix.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(c.read(latestPoseFrameProvider), isNotNull);
    expect(find.byKey(const Key('form_check.skeleton')), findsOneWidget);
  });

  testWidgets('losing the person clears the held pose', (t) async {
    _phoneSized(t);
    final c = _container([...oneSquat(0), nobody(9000)]);
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    await t.pump(const Duration(seconds: 2));

    expect(c.read(latestPoseFrameProvider), isNull,
        reason: 'the last pose from before the person left must not stay on '
            'screen as though the detector could still see them');
    expect(find.byKey(const Key('form_check.skeleton')), findsNothing);
  });

  testWidgets('and says so, instead of holding the previous verdict',
      (t) async {
    // Clearing the figure is half the fix. Without the verdict moving too, the
    // screen would go quiet and keep whatever it last said about a frame that
    // is no longer the situation.
    _phoneSized(t);
    final c = _container([...oneSquat(0), nobody(9000)]);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(c.read(poseGateVerdictProvider), PoseGateVerdict.missingJoints,
        reason: 'an empty frame reaches the gate, which reports it as joints '
            'it needed and did not get -- rendered as an instruction to step '
            'back into view');
  });
}
