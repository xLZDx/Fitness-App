// Shared host of the C19 plan-UI widget tests (not a test file itself).
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A MaterialApp with the real theme (HUD tokens) and localisations.
Widget planApp(
  Widget home, {
  Locale locale = const Locale('en'),
  ProviderContainer? container,
  GoRouter? router,
  double textScale = 1.0,
}) {
  Widget builder(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
  final Widget app = router != null
      ? MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: builder,
        )
      : MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
          builder: builder,
        );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return app;
}

/// Records every `SemanticsService.announce` message until the test ends.
List<String> captureAnnouncements(WidgetTester tester) {
  final messages = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (dynamic message) async {
      if (message is Map && message['type'] == 'announce') {
        final data = message['data'];
        if (data is Map) messages.add(data['message'] as String);
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return messages;
}

/// A tall phone-sized surface so list pages do not need scrolling.
void tallSurface(WidgetTester tester, {Size size = const Size(800, 3200)}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
