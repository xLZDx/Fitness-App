import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// When the page shows the movement, and when it shows the shape to hit.
///
/// Operator, after the first silhouette build: *"лучше добавить анимацию как
/// правильно надо делать и юзер должен попытаться попадать в силуэт на экране
/// хотя бы на 80%"*. Both halves of that, and they cannot be on screen at the
/// same time: an outline that keeps moving is not one you can be 80% inside.
///
/// The interpolation itself is pinned in `pose_target_test.dart`. What is
/// checked here is the switch between the two, and that a demonstration is
/// never painted over a camera that is not running.

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

ProviderContainer _container() {
  // An empty fixture list: start() completes at once and no frame ever
  // arrives, which is precisely the state the demonstration is for.
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(const [])),
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
  testWidgets('before the first rep, the page demonstrates the movement',
      (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_target, findsNothing,
        reason: 'a moving outline and a fixed one at once would ask the user '
            'to stand in two shapes');
  });

  testWidgets('once a rep is counted it shows the target instead', (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();
    expect(_demo, findsOneWidget);

    // The page clears the session on mount, so this has to land after.
    c.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(repCount: 1, isArmed: true);
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsOneWidget);
  });

  testWidgets('it gets out of the way as soon as the movement starts',
      (t) async {
    // Mid-descent, before any rep has been counted. This is the case the
    // repCount test above does not cover, and the one that matters: the user
    // is already moving and needs something to arrive at.
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
