import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/form_check/widgets/coach_readiness_band.dart';
import '../../helpers/test_app.dart';

/// The band is the only thing on this screen that has ever explained WHY the
/// coach is not counting. The gate knew all six reasons; nothing said them.

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CoachReadinessBand()),
      ),
    );

ProviderContainer _container(PoseGateVerdict verdict) {
  final c = ProviderContainer(overrides: [
    poseGateVerdictProvider.overrideWith((_) => verdict),
    // R11h: this file's subject is the camera UI, so it starts where
    // that UI lives instead of tapping through the two intro cards.
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('an unusable view is explained, in the user\'s terms',
      (tester) async {
    await tester.pumpWidget(_harness(_container(PoseGateVerdict.outOfFrame)));
    await tester.pump();

    expect(find.textContaining('outside the frame'), findsOneWidget);
  });

  testWidgets('a body the detector is only guessing at reads as "no body"',
      (tester) async {
    await tester
        .pumpWidget(_harness(_container(PoseGateVerdict.lowConfidence)));
    await tester.pump();

    expect(find.textContaining('Step into frame'), findsOneWidget);
  });

  testWidgets('a sensor bug is never presented as something to fix by moving',
      (tester) async {
    await tester
        .pumpWidget(_harness(_container(PoseGateVerdict.unitMismatch)));
    await tester.pump();

    expect(find.textContaining('cannot read'), findsOneWidget);
    expect(find.textContaining('Move back'), findsNothing,
        reason:
            'no amount of stepping back moves a coordinate from 300 to 0.5');
  });

  testWidgets('a usable view says ready, with no invented settling bar',
      (tester) async {
    await tester.pumpWidget(_harness(_container(PoseGateVerdict.ok)));
    await tester.pump();

    expect(find.textContaining('Ready'), findsOneWidget);
    // The design has a calibration percentage; the prototype fills it with a
    // timer. Nothing here measures settling, so nothing here draws it.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('leaves no timer behind — it is derived, not polled',
      (tester) async {
    await tester.pumpWidget(_harness(_container(PoseGateVerdict.ok)));
    await tester.pump(const Duration(seconds: 2));
    // A pending timer here fails the binding on teardown. This assertion is
    // the teardown itself; reaching it means nothing is polling.
    expect(find.textContaining('Ready'), findsOneWidget);
  });

  testWidgets('says nothing during a running set', (tester) async {
    final container = _container(PoseGateVerdict.ok);
    container.read(coachPhaseControllerProvider.notifier).start();

    await tester.pumpWidget(_harness(container));
    await tester.pump();

    expect(find.byKey(const Key('coach.readinessBand')), findsNothing,
        reason: 'an instruction band mid-rep competes with the cue card');
  });
}
