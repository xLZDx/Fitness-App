import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/settings_repository.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/profile_page.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/settings/settings_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

Future<void> _largeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Mirrors how `lib/main.dart` wires settings into the app: theme mode and
/// locale are read from the live settings, so a tap on this page has to change
/// the surrounding MaterialApp, not just a provider value.
Widget _buildApp(InMemorySettingsRepository repo) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
      GoRoute(
        path: '/about',
        builder: (_, __) => const Scaffold(body: Text('about-stub')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    child: Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(settingsControllerProvider);
        final code = settings.language.localeCode;
        return MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode.material,
          locale: code == null ? kTestLocale : Locale(code),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              AuroraBackground(child: child ?? const SizedBox.shrink()),
        );
      },
    ),
  );
}

void main() {
  group('SettingsPage', () {
    testWidgets('renders every control', (tester) async {
      await _largeSurface(tester);
      await tester.pumpWidget(_buildApp(InMemorySettingsRepository()));
      await tester.pump();

      // By Key, not by text: the app defaults to Russian now, and this test
      // is about the controls being present, not about the copy.
      expect(find.byKey(const Key('settings-section-appearance')),
          findsOneWidget);
      expect(find.byKey(const Key('settings-section-language')), findsOneWidget);
      expect(find.byKey(const Key('settings-section-reminders')),
          findsOneWidget);

      for (final mode in AppThemeMode.values) {
        expect(find.byKey(Key('settings-theme-${mode.name}')), findsOneWidget);
      }
      for (final lang in AppLanguage.values) {
        expect(
            find.byKey(Key('settings-language-${lang.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('settings-notifications')), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
    });

    // The point of the page: a tap must reach MaterialApp, not stop at state.
    testWidgets('picking Dark actually re-themes the app', (tester) async {
      await _largeSurface(tester);
      final repo = InMemorySettingsRepository();
      await tester.pumpWidget(_buildApp(repo));
      await tester.pump();

      Brightness brightness() => Theme.of(
            tester.element(find.byKey(const Key('settings-theme-dark'))),
          ).brightness;
      expect(brightness(), Brightness.light);

      await tester.tap(find.byKey(const Key('settings-theme-dark')));
      await tester.pumpAndSettle();

      expect(brightness(), Brightness.dark,
          reason: 'the theme choice has to drive the real MaterialApp');
      expect((await repo.load()).themeMode, AppThemeMode.dark);
    });

    testWidgets('picking English actually switches the locale', (tester) async {
      await _largeSurface(tester);
      final repo = InMemorySettingsRepository();
      await tester.pumpWidget(_buildApp(repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings-language-en')));
      await tester.pumpAndSettle();

      expect(
        Localizations.localeOf(
            tester.element(find.byKey(const Key('settings-language-en')))),
        const Locale('en'),
      );
      expect((await repo.load()).language, AppLanguage.en);
    });

    testWidgets('Russian is the default selection', (tester) async {
      await _largeSurface(tester);
      await tester.pumpWidget(_buildApp(InMemorySettingsRepository()));
      await tester.pump();

      final tile = tester.widget<RadioListTile<AppLanguage>>(
        find.byKey(const Key('settings-language-ru')),
      );
      expect(tile.groupValue, AppLanguage.ru);
    });

    testWidgets('the reminder switch explains what off means', (tester) async {
      await _largeSurface(tester);
      await tester.pumpWidget(_buildApp(InMemorySettingsRepository()));
      await tester.pump();

      // Russian copy: the reminder switch explains the ON state.
      expect(find.textContaining('перед каждым'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-notifications')));
      await tester.pumpAndSettle();

      expect(find.textContaining('без звука'), findsOneWidget);
    });

    testWidgets('About opens the about route', (tester) async {
      await _largeSurface(tester);
      await tester.pumpWidget(_buildApp(InMemorySettingsRepository()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings-about')));
      await tester.pumpAndSettle();

      expect(find.text('about-stub'), findsOneWidget);
    });
  });

  // Regression: the tile rendered and rippled but its onTap was `() {}`, so
  // "settings" was a dead end (operator report, 2026-07-30).
  testWidgets('the profile Settings tile navigates to /settings',
      (tester) async {
    await _largeSurface(tester);
    final profile = UserProfile.empty('u1').copyWith(
      completedAt: DateTime(2026, 1, 1),
    );
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('settings-arrived')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) => Stream.value(profile)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('settings-arrived'), findsOneWidget);
  });
}
