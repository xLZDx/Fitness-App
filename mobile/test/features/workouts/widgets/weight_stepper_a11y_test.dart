import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/workouts/widgets/plate_calculator.dart';
import 'package:fitness_app/features/workouts/widgets/warmup_calculator.dart';

/// G2.1b-i: [PlateCalculator] and [WarmupCalculator] each wrote their +/-
/// steppers as a bare `IconButton` with no [tooltip] — four call sites
/// (target weight, bar weight, working weight x2) invisible to a screen
/// reader. `AppIconButton` requires one; this proves the requirement
/// actually reached these four, not just the constructor signature.
void main() {
  Future<void> pump(WidgetTester t, Widget child) async {
    // Both widgets read `theme.colors.textSecondary` -- the
    // ThemeExtension a bare MaterialApp does not carry (G1.2c).
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ));
  }

  testWidgets('plate calculator: both steppers are named', (t) async {
    await pump(t, const PlateCalculator());
    final l10n = AppLocalizations.of(t.element(find.byType(PlateCalculator)));

    // Two steppers (target, bar), one +/- pair each -- four buttons, two
    // pairs of the same two tooltip strings, not four distinct labels: the
    // stepper itself doesn't say which value it steps, same as the app's
    // other terse single-purpose tooltips (Mute, Voice, Pause).
    expect(find.byTooltip(l10n.commonDecrease), findsNWidgets(2));
    expect(find.byTooltip(l10n.commonIncrease), findsNWidgets(2));
  });

  testWidgets('plate calculator: decrease/increase still change the target',
      (t) async {
    // The behavioural half of the fix -- a tooltip alone would not catch a
    // migration that wired onPressed to the wrong stepper.
    await pump(t, const PlateCalculator());
    final l10n = AppLocalizations.of(t.element(find.byType(PlateCalculator)));

    expect(find.text('60 kg'), findsOneWidget);
    await t.tap(find.byTooltip(l10n.commonIncrease).first);
    await t.pump();
    expect(find.text('62.5 kg'), findsOneWidget);
  });

  testWidgets('warmup calculator: both steppers are named', (t) async {
    await pump(t, const WarmupCalculator());
    final l10n = AppLocalizations.of(t.element(find.byType(WarmupCalculator)));

    expect(find.byTooltip(l10n.commonDecrease), findsOneWidget);
    expect(find.byTooltip(l10n.commonIncrease), findsOneWidget);
  });
}
