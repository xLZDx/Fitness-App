import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/profile_page.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  // Regression: _ProfileSummary held the profile as `dynamic`, and enum
  // extension getters (ActivityLevel.name) do not dispatch dynamically —
  // the page crashed with NoSuchMethodError as soon as a completed profile
  // had an activityLevel set (2026-07-29, seen live on the emulator).
  testWidgets('profile summary renders activity level for a completed profile',
      (tester) async {
    final profile = UserProfile.empty('u1').copyWith(
      personal: const PersonalInfo(
        age: 30,
        heightCm: 180,
        activityLevel: ActivityLevel.moderatelyActive,
      ),
      completedAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) => Stream.value(profile)),
        ],
        child: const MaterialApp(
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfilePage(),
        ),
      ),
    );
    // Let the profile stream emit and the summary rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('moderately active'), findsOneWidget);
    // The crash used to surface as the red error widget instead of the card.
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
