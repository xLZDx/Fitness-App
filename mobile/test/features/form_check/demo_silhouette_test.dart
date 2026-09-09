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

/// Which screen shows the movement — and that nothing shows the old outline.
///
/// **G17 (2026-09-04) superseded the split this file used to pin.** From
/// 2026-09-02 the picker owned the demonstration and the live screen owned a
/// STILL white target outline, "visible from the very first frame" (GPT-PM,
/// `VERDICT: MAJOR`). The operator (CEO) overruled that on a real S23 after
/// the outline had been through three rounds of repair: filled, composed and
/// tested, it still read as an abstract shape and not as a person, and the
/// design reference never had one — its figure is a video of a real person.
/// So:
///
/// - the picker demonstrates the movement with the avatar-styled figure, for
///   every authored movement except the squat — whose demonstration was the
///   design reference's own clip until G1.2 (2026-09-09) proved that clip to
///   be a screen recording of an older prototype, and which now states its
///   absence rather than substituting the stand-in that was already rejected;
/// - the live screen shows the SAME demonstration while there is nobody to
///   draw, and the user's own figure once there is (`live_demo_test.dart`
///   covers the hand-over);
/// - the white target outline (`form_check.silhouette`) exists on NO screen
///   in NO state. That is the structural half of the operator's requirement,
///   and a widget test is the only thing that can prove it — a screenshot
///   proves the pixels, not the tree.
///
/// Scoring still reads the same targets; only the drawing changed.

final _demo = find.byKey(const Key('form_check.demo'));
final _clip = find.byKey(const Key('form_check.demo_clip'));
final _figure = find.byKey(const Key('form_check.demo_figure'));
final _unavailable = find.byKey(const Key('form_check.demo_unavailable'));
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

ProviderContainer _container({
  CoachPhase phase = CoachPhase.qualityCheck,
  bool avatar = false,
}) {
  // An empty fixture list: start() completes at once and no frame ever
  // arrives, which is precisely the state the demonstration is for.
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(const [])),
    coachInitialPhaseProvider.overrideWithValue(phase),
    avatarModeProvider.overrideWith((_) => avatar),
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
  testWidgets('the picker states the squat has no demonstration yet',
      (t) async {
    _phoneSized(t);
    final c = _container(phase: CoachPhase.selection);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(find.byKey(const Key('coach.selection.demo')), findsOneWidget);
    expect(_demo, findsOneWidget, reason: 'the host, not just its panel');
    expect(_unavailable, findsOneWidget);
    expect(_clip, findsNothing, reason: 'the prototype recording is gone');
    expect(_figure, findsNothing,
        reason: 'and it did NOT fall through to the drawn stand-in');
    // The white outline stays gone in this state too — the state this file
    // exists to guard is not allowed back in through an empty panel.
    expect(_target, findsNothing);
  });

  testWidgets('and the drawn figure for a movement without a clip', (t) async {
    _phoneSized(t);
    final c = _container(phase: CoachPhase.selection);
    c.read(selectedExerciseProvider.notifier).state = FormExercise.curl;
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_figure, findsOneWidget,
        reason: 'no movement lost its demonstration when the squat got a clip');
    expect(_clip, findsNothing);
    expect(_target, findsNothing);
  });

  testWidgets('the live screen shows the demonstration while nobody is '
      'tracked, camera mode', (t) async {
    // The window the old outline filled. A user who has just pressed «Нажмите
    // когда готовы» sees the movement being performed, not a shape.
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_unavailable, findsOneWidget);
    expect(_clip, findsNothing);
    expect(_figure, findsNothing);
    expect(_target, findsNothing);
  });

  testWidgets('and in avatar mode, the default', (t) async {
    _phoneSized(t);
    final c = _container(avatar: true);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_target, findsNothing);
  });

  testWidgets('still demonstrating once repetitions are being counted but '
      'the body is not readable', (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    // The page clears the session on mount, so this has to land after.
    c.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(repCount: 1, isArmed: true);
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_target, findsNothing);
  });

  testWidgets('and mid-descent', (t) async {
    _phoneSized(t);
    final c = _container();
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    c.read(repSessionControllerProvider.notifier).state =
        const RepSessionState(phase: RepPhase.descending, isArmed: true);
    await t.pump();

    expect(_demo, findsOneWidget);
    expect(_target, findsNothing);
  });

  testWidgets('a movement with nothing authored demonstrates nothing',
      (t) async {
    // The deadlift has a rep signal but no target pair. Nothing is drawn
    // rather than half of something.
    _phoneSized(t);
    final c = _container();
    c.read(selectedExerciseProvider.notifier).state = FormExercise.deadlift;
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_demo, findsNothing);
    expect(_target, findsNothing);
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
