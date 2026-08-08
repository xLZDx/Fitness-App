import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/profile_page.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

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
        child: MaterialApp(
          theme: AppTheme.dark(),
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
    // "Moderately active", not "moderately active": the label is looked up
    // now, where it used to be manufactured from the enum's own identifier by
    // inserting a space before each capital. That trick produced a plausible
    // English phrase for free and produced ONLY English — and it meant
    // renaming `ActivityLevel.moderatelyActive` would have silently renamed
    // what the user reads.
    expect(find.text('Moderately active'), findsOneWidget);
    // The crash used to surface as the red error widget instead of the card.
    expect(find.byType(ErrorWidget), findsNothing);
  });

  /// The progress-photos tile read "End-to-end encrypted, on your device" —
  /// a claim made on the profile screen, before the feature is even opened,
  /// while the only bound repository was an in-memory mock that stores no
  /// bytes and holds no key. The subtitle is gated on the same flag the
  /// photos page uses; the fallback describes what the feature does, which is
  /// true in either state.
  testWidgets('the photos tile withholds the encryption claim in demo mode',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('encrypted'), findsNothing);
    expect(find.textContaining('Compare side-by-side'), findsOneWidget);
  });

  // R11i: the page's nine tiles were one flat card. Grouped now, by what each
  // row DOES -- so no row had to be renamed to fit a heading, and every route
  // that was reachable before still is.
  testWidgets('the rows are grouped under headings, and none went missing',
      (tester) async {
    // Tall enough for every group: a `ListView` does not build what is off
    // screen, and the default 800x600 viewport stops around "Coaching".
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pump();

    for (final heading in const [
      'YOU',
      'PROGRESS',
      'COACHING',
      'COMMUNITY',
      'MEMBERSHIP',
      'APP',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: 'missing $heading');
    }

    // The nine destinations, still all present. A regrouping that quietly
    // dropped a row would leave a feature reachable from nowhere.
    for (final title in const [
      'Injuries',
      'Progress photos',
      'Coaches',
      'Community',
      'Subscription',
      'Settings',
      'Sign out',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing $title');
    }
  });
}
