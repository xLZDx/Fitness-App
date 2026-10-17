// FIX-B (U3, U5): Back from the finished screen acknowledges it, "Not now" on
// save-failed is not sticky, and the page marks itself open for the shell.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_flow.dart';

import 'page_harness.dart';

AppLocalizations l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

void main() {
  testWidgets('U3: system Back from the finished screen leaves finished',
      (t) async {
    final w = await pumpPage(t);
    await w.startRecording();
    // Through the screen: a bare `await ctl.stop()` never completes under the
    // fake clock (this was the hang); the real tap flow settles.
    await w.tapKey('gps.rec.stop');
    await w.tapText(l(t).gpsFinishSave);
    expect(w.phase, RecorderPhase.finished);
    final scope = t.widget<PopScope<Object?>>(find
        .ancestor(
            of: find.byKey(const ValueKey<String>('gps.finish.screen')),
            matching: find.byWidgetPredicate((w) => w is PopScope))
        .first);
    scope.onPopInvokedWithResult!(true, null);
    await w.settle(2);
    expect(w.phase, RecorderPhase.idle);
  });

  testWidgets('U3: Not now on save-failed is not sticky', (t) async {
    final w = await pumpPage(t, forceable: true);
    (w.ctl as ForceableRecorder).force((s) => s.copyWith(handOffFailed: true));
    await w.settle(2);
    expect(find.byKey(const ValueKey<String>('gps.saveFailed.screen')),
        findsOneWidget);
    await w.tapText(l(t).gpsNotNow);
    expect(w.closed, isNotEmpty);
    expect(find.byKey(const ValueKey<String>('gps.saveFailed.screen')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('gps.start.screen')),
        findsOneWidget);
  });

  testWidgets('U5: the page marks itself open while mounted', (t) async {
    final w = await pumpPage(t);
    expect(w.c.read(gpsRecordingPageOpenProvider), isTrue);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    await t.pump();
  });
}
