import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/form_check/widgets/coach_hud.dart';

import '../../helpers/test_app.dart';

/// The coach's picture is dark whatever the app is.
///
/// Behind it sits a camera preview or a photograph, both dark. Every readout
/// drawn on it takes its colour from `Theme.of(context).colors` — which is the
/// right way to write it, and which quietly made the whole HUD follow the app's
/// light/dark setting while the surface under it did not.
///
/// In light mode that is dark text on a dark picture. Photographed on an S23 at
/// 19:02, with the phone in its ordinary light theme: ПОВТОРЫ, ТЕХНИКА, the rep
/// count and the technique percentage were all navy on a photograph — present,
/// correct, and unreadable.
///
/// **Nothing in the suite could see it, and the reason is worth keeping.** Every
/// widget test on this page builds `AppTheme.dark()`, and so does
/// `test/golden/form_coach_golden_test.dart`. The one configuration that breaks
/// is the one configuration nothing rendered — which is what a default argument
/// copied from test to test buys you.

void main() {
  Widget page(ProviderContainer c, ThemeMode mode) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FormCheckPage(),
        ),
      );

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      poseDetectorServiceProvider
          .overrideWithValue(MockPoseDetectorService(const [])),
      coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  void phoneSized(WidgetTester t) {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the readouts on the picture stay on-dark in $mode',
        (tester) async {
      phoneSized(tester);
      await tester.pumpWidget(page(container(), mode));
      await tester.pump();

      final strip = tester.element(find.byType(CoachTopStrip));
      expect(Theme.of(strip).brightness, Brightness.dark,
          reason: 'the rep count and the technique percentage are drawn on a '
              'camera preview or a photograph, and both are dark in either '
              'app theme');
    });
  }

  testWidgets('and the panel below it still follows the app', (tester) async {
    // The positive control, and the reason the fix is scoped to the picture
    // rather than to the page: the counters sit on the page's own surface,
    // which IS light in light mode. A fix that pinned the whole route would
    // pass the assertion above and put white text on a white card here.
    phoneSized(tester);
    await tester.pumpWidget(page(container(), ThemeMode.light));
    await tester.pump();

    final panel = tester.element(find.byType(CoachCountersPanel));
    expect(Theme.of(panel).brightness, Brightness.light);
  });
}
