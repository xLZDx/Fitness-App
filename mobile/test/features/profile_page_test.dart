import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/profile_page.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  group('ProfilePage', () {
    testWidgets('renders the guest header and the primary menu items',
        (tester) async {
      await tester.pumpWidget(buildApp(MockAuthRepository(latency: Duration.zero),
          MockProfileRepository(latency: Duration.zero)));
      await tester.pump();

      expect(find.text('Guest'), findsOneWidget);
      // Not yet onboarded → CTA wording
      expect(find.text('Complete questionnaire'), findsOneWidget);
      // Discovery tiles for the new feature pages must each be reachable.
      expect(find.text('Progress photos'), findsOneWidget);
      expect(find.text('Coaches'), findsOneWidget);
      expect(find.text('Celebrity plans'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Our mission'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('shows the questionnaire CTA when user is not onboarded',
        (tester) async {
      await tester.pumpWidget(buildApp(MockAuthRepository(latency: Duration.zero),
          MockProfileRepository(latency: Duration.zero)));
      await tester.pump();
      expect(find.text('Complete questionnaire'), findsOneWidget);
      expect(find.text('Personalize your plan'), findsOneWidget);
    });
  });
}

Widget buildApp(
  MockAuthRepository auth,
  MockProfileRepository profiles,
) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      GoRoute(
          path: '/onboarding',
          builder: (_, __) => const Scaffold(body: Text('onboarding-stub'))),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) {
        ref.onDispose(auth.dispose);
        return auth;
      }),
      profileRepositoryProvider.overrideWith((ref) {
        ref.onDispose(profiles.dispose);
        return profiles;
      }),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}
