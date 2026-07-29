import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// The locale every widget test renders in.
///
/// Production pins Russian (`lib/main.dart`), but the ARB template — and so
/// the text these tests assert on — is authored in English. Pinning `en` here
/// keeps assertions readable and means a Russian copy tweak never breaks a
/// test that is not about translation.
const Locale kTestLocale = Locale('en');

/// Localization wiring every test-owned [MaterialApp] needs. Without the
/// delegates `AppLocalizations.of(context)` throws.
const List<LocalizationsDelegate<dynamic>> kTestLocalizationsDelegates =
    AppLocalizations.localizationsDelegates;

/// Wraps a widget in the minimum app harness needed to render UI that depends
/// on a [Theme], [MediaQuery], localizations, and the aurora background.
Widget testHarness({required Widget child}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuroraBackground(child: child),
    ),
  );
}

/// Wraps a widget tree in a real [GoRouter] so pages that use
/// `context.go(...)` can actually navigate during tests.
Widget routedHarness({
  required Map<String, Widget Function(BuildContext)> routes,
  String initial = '/',
}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: routes.entries
        .map(
          (e) => GoRoute(path: e.key, builder: (ctx, _) => e.value(ctx)),
        )
        .toList(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    ),
  );
}
