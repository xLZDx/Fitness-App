import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/steps/step_health.dart';

import '../../helpers/test_app.dart';

void main() {
  // F018: `showTitle: true` is StepHealth's default, but its only current
  // call site (step_body.dart) overrides it to false — so the false claim
  // this finding named was not actually reachable in the shipped app. Fixed
  // anyway: the string is still the widget's default, and a future call site
  // that does not override it would silently ship the false claim. The
  // conditions/allergies/medications fields it sits above reach no filter
  // (plan_builder.dart's own comment documents this deliberately, after a
  // prior bug claimed otherwise), so a claim that they "keep your plan safe"
  // is false regardless of whether anyone can see it today.
  testWidgets(
      'the health-snapshot subtitle no longer claims these fields keep the '
      'plan safe', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: StepHealth()),
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('keep your plan safe'), findsNothing);
    expect(find.textContaining('do not read or act on this'), findsOneWidget);
  });
}
