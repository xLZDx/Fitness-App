import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/background/hud_sky.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show oneSquat;

/// FORM_COACH_HUD_ALIGNMENT's own DoD (`core/DECISION_LOG.md`,
/// "GPT-PM decision on findings #4 and #6") is background continuity across
/// all four Form Coach phases. The first pass wrapped only `launch`/
/// `preparation` (`coach_intro_cards.dart`) and missed `qualityCheck`..
/// `summary`, which render `FormCheckPage.build`'s own `FrostedScaffold`
/// directly -- a real GPT review round on the first patch caught exactly
/// this gap (evidence: `/form-check` is a root route outside `MainShell`,
/// so nothing upstream supplies a sky either). One test per phase, rather
/// than one shared helper asserting "the tree contains a HudSkyBackground
/// somewhere", so a future regression names which phase broke.

class _SilentService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _frames.close();
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// The launch/preparation cards mount their own `HudSkyBackground`
/// (`coach_intro_cards.dart`) rather than inheriting `FormCheckPage`'s, so
/// they are pumped with the plain page, no phase override.
ProviderContainer _introContainer() {
  final c = ProviderContainer(
    overrides: [poseDetectorServiceProvider.overrideWithValue(_SilentService())],
  );
  addTearDown(c.dispose);
  return c;
}

/// `qualityCheck`/`summary` need a running detector with real frames, same
/// fixture `coach_backdrop_test.dart` already uses for this exact reason.
ProviderContainer _liveContainer(CoachPhase phase) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(oneSquat(0))),
    coachInitialPhaseProvider.overrideWithValue(phase),
    coachBackdropRandomProvider.overrideWithValue(math.Random(7)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('launch: the sky is behind the intro card', (t) async {
    _phoneSized(t);
    await t.pumpWidget(_page(_introContainer()));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('coach.intro.start')), findsOneWidget);
    expect(find.byType(HudSkyBackground), findsOneWidget);
  });

  testWidgets('preparation: the sky is behind the readiness card', (t) async {
    _phoneSized(t);
    await t.pumpWidget(_page(_introContainer()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('coach.intro.start')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('coach.prep.openCamera')), findsOneWidget);
    expect(find.byType(HudSkyBackground), findsOneWidget);
  });

  testWidgets(
      'live (post-preparation): the sky is behind the exercise picker and '
      'set controls, not just the camera preview box', (t) async {
    _phoneSized(t);
    final c = _liveContainer(CoachPhase.qualityCheck);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    // A good pose auto-advances the phase machine past qualityCheck
    // (calibration, then ready) once frames start arriving -- the initial
    // override picks which branch of FormCheckPage.build is reached, not
    // where the session stays pinned. What matters here is that it landed
    // somewhere past preparation and short of summary, i.e. the "live"
    // branch this test targets.
    expect(
      c.read(coachSessionProvider).phase,
      isNot(anyOf(CoachPhase.launch, CoachPhase.preparation,
          CoachPhase.summary)),
    );
    expect(find.byType(HudSkyBackground), findsOneWidget,
        reason: 'FormCheckPage.build returns FrostedScaffold directly for '
            'every phase past preparation -- this is the branch the first '
            'HUD-alignment patch missed');
  });

  testWidgets('summary: the sky is behind the set-summary card', (t) async {
    _phoneSized(t);
    final c = _liveContainer(CoachPhase.summary);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(c.read(coachSessionProvider).phase, CoachPhase.summary);
    expect(find.byType(HudSkyBackground), findsOneWidget);
  });

  testWidgets(
      'an unsupported exercise chip is announced as a disabled control, not '
      'plain text', (t) async {
    // Same GPT review round that caught the missing background flagged this:
    // `HudChip(onTap: null)` alone drops out of the button role entirely for
    // a screen reader, rather than reading as a control the user cannot
    // currently take. `HudChip.enabled` (`hud_surface.dart`) exists to keep
    // it in the button role while marking it disabled -- this pins that the
    // exercise picker actually passes it, not just that the parameter exists.
    _phoneSized(t);
    final handle = t.ensureSemantics();
    final c = _liveContainer(CoachPhase.qualityCheck);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    final chip = find.byKey(Key('form_check.exercise.${FormExercise.pushup.name}'));
    expect(chip, findsOneWidget,
        reason: 'pushup is tagged but has no countable rep signal '
            '(form_coach_support_test.dart), so it always renders disabled');
    final semantics = t.getSemantics(chip);
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue,
        reason: 'still a control, not inert text');
    expect(semantics.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
    handle.dispose();
  });
}
