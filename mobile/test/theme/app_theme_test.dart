import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeData> realiseTheme(WidgetTester tester, ThemeData theme) async {
    late ThemeData captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(builder: (ctx) {
          captured = Theme.of(ctx);
          return const Scaffold(body: SizedBox.shrink());
        }),
      ),
    );
    return captured;
  }

  group('AppTheme', () {
    testWidgets('light theme is Material 3 with transparent scaffold',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.light());
      expect(t.useMaterial3, isTrue);
      expect(t.brightness, Brightness.light);
      expect(t.scaffoldBackgroundColor, Colors.transparent);
      expect(t.canvasColor, Colors.transparent);
    });

    testWidgets('dark theme is Material 3 dark with transparent scaffold',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.dark());
      expect(t.useMaterial3, isTrue);
      expect(t.brightness, Brightness.dark);
      expect(t.scaffoldBackgroundColor, Colors.transparent);
    });

    testWidgets('app bar background is transparent and elevation is 0',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.light());
      expect(t.appBarTheme.backgroundColor, Colors.transparent);
      expect(t.appBarTheme.elevation, 0);
      expect(t.appBarTheme.scrolledUnderElevation, 0);
    });

    testWidgets('card theme has zero elevation and transparent fill',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.light());
      expect(t.cardTheme.elevation, 0);
      expect(t.cardTheme.color, Colors.transparent);
    });

    testWidgets('filled buttons have rounded 20px corners and tall min height',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.light());
      final shape =
          t.filledButtonTheme.style?.shape?.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(20));
      final size = t.filledButtonTheme.style?.minimumSize?.resolve({});
      expect(size?.height, 54);
    });

    testWidgets('page transitions are configured for Android and iOS',
        (tester) async {
      final t = await realiseTheme(tester, AppTheme.light());
      expect(
          t.pageTransitionsTheme.builders[TargetPlatform.android], isNotNull);
      expect(t.pageTransitionsTheme.builders[TargetPlatform.iOS], isNotNull);
    });
  });
}
