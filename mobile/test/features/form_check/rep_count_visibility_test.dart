import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// R8: the on-screen rep badge is withheld for movements the MM-Fit
/// measurement found under the 80% accuracy bar, and the interface says why
/// rather than leaving a silent blank corner — the operator's own decision,
/// `core/SESSION_STATE_2026-08-08.md`: "счёт повторов по ним выключен и это
/// сказано в интерфейсе".
final _repCount = find.byKey(const Key('form_check.rep_count'));
final _notTracked = find.byKey(const Key('form_check.rep_count_not_tracked'));
final _summaryTally = find.byKey(const Key('form_check.summary_tally'));

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

ProviderContainer _container(FormExercise exercise) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(const [])),
  ]);
  c.read(selectedExerciseProvider.notifier).state = exercise;
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
  testWidgets('squat shows the live rep badge, not the disclaimer',
      (t) async {
    _phoneSized(t);
    final c = _container(FormExercise.squat);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_repCount, findsOneWidget);
    expect(_notTracked, findsNothing);
  });

  testWidgets('curl (measured, cleared the bar) shows the live rep badge',
      (t) async {
    _phoneSized(t);
    final c = _container(FormExercise.curl);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_repCount, findsOneWidget);
    expect(_notTracked, findsNothing);
  });

  testWidgets(
      'situp (measured at 41%, below the bar) shows the disclaimer instead',
      (t) async {
    _phoneSized(t);
    final c = _container(FormExercise.situp);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    expect(_notTracked, findsOneWidget);
    expect(_repCount, findsNothing);
  });

  testWidgets('the post-set summary is withheld along with the badge',
      (t) async {
    // Both read `session.reps`, which the counter keeps populating on its old
    // fallback signal even with the badge hidden -- the summary would leak
    // the same untrustworthy number back onto the screen if left unguarded.
    _phoneSized(t);
    final c = _container(FormExercise.situp);
    await t.pumpWidget(_page(c));
    await t.pump();
    await t.pump();

    c.read(repSessionControllerProvider.notifier).state = RepSessionState(
      repCount: 1,
      reps: const [
        RepQuality(
          index: 1,
          startMs: 0,
          endMs: 800,
          peakSignal: 1.0,
          severityByRule: {},
        ),
      ],
    );
    await t.pump();

    expect(_summaryTally, findsNothing);
  });
}
