import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Which screen shows the movement, and which shows the shape to hit.
///
/// Operator, after the first silhouette build: *"лучше добавить анимацию как
/// правильно надо делать и юзер должен попытаться попадать в силуэт на экране
/// хотя бы на 80%"*. Both halves of that, and they cannot be on screen at the
/// same time: an outline that keeps moving is not one you can be 80% inside.
///
/// **The split is now BY SCREEN, not by moment within one screen.** These
/// tests used to assert that the live screen demonstrated until the first
/// repetition and then handed over. It no longer demonstrates at all: the
/// picker owns the demonstration, the live screen owns the target. Decided by
/// GPT-PM on 2026-09-02 (`VERDICT: MAJOR`) against the redesign's own point 2
/// and point 4, superseding the 2026-08-31 instruction that had put the loop
/// on the live screen — ending the loop at the first rep would have left the
/// same defect running for the first rep of every set.
///
/// The interpolation itself is pinned in `pose_target_test.dart`. What is
/// checked here is that each screen shows its own one thing, and that neither
/// is painted over a camera that is not running.

final _demo = find.byKey(const Key('form_check.demo'));
final _target = find.byKey(const Key('form_check.silhouette'));

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

ProviderContainer _container({CoachPhase phase = CoachPhase.qualityCheck}) {
  // An empty fixture list: start() completes at once and no frame ever
  // arrives, which is precisely the state the demonstration is for.
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(const [])),
    // R11h: this file's subject is the camera UI, so it starts where
    // that UI lives instead of tapping through the two intro cards.
    coachInitialPhaseProvider.overrideWithValue(phase),
    // And camera mode specifically, since 2026-08-15 flipped the default. The
    // demonstration and the target outline are both fitted to the PANEL; the
    // avatar is placed where the body is, and Gate A stopped the two being
    // drawn together. This file is about the panel-fitted pair.
    avatarModeProvider.overrideWith((_) => false),
  ]);
  addTearDown(c.dispose);
  return c;
}

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the picker is where the movement is demonstrated', (t) async {
    // The positive control for every "no demo" assertion below. Without it,
    // deleting the demonstration from the app entirely would pass this file.
    _phoneSized(t);
    final c = _container(phase: CoachPhase.selection);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(find.byKey(const Key('coach.selection.demo')), findsOneWidget);
    expect(_demo, findsOneWidget, reason: 'the loop itself, not just its host');
    expect(_target, findsNothing,
        reason: 'nothing to aim at yet — the camera has not started');
  });

  testWidgets('the live screen shows the target from the very first frame',
      (t) async {
    // Before any repetition, which is exactly the window the old behaviour
    // filled with an animation. A user who has just pressed «Нажмите когда
    // готовы» needs the shape to arrive at, not a preview of it.
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsNothing,
        reason: 'an outline that keeps moving is not one you can be 80% '
            'inside; the picker already demonstrated it');
    expect(_target, findsOneWidget);
  });

  testWidgets('and still shows it once repetitions are being counted',
      (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    // The page clears the session on mount, so this has to land after.
    c.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(repCount: 1, isArmed: true);
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsOneWidget);
  });

  testWidgets('and mid-descent, when the user most needs something to hit',
      (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    c.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(phase: RepPhase.descending, isArmed: true);
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsOneWidget);
  });

  testWidgets('a movement with no authored demonstration shows the target',
      (t) async {
    // The deadlift has a rep signal but no target pair. Neither outline is
    // drawn rather than half of one.
    _phoneSized(t);
    final c = _container();
    c.read(selectedExerciseProvider.notifier).state = FormExercise.deadlift;
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsNothing, reason: 'the deadlift has no target either');
  });

  testWidgets('nothing is demonstrated over a camera that is not running',
      (t) async {
    _phoneSized(t);
    final c = _container();
    c.read(poseErrorProvider.notifier).state = 'detector died';
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsNothing);
    expect(find.byKey(const Key('form-check-error')), findsOneWidget);
  });
}
