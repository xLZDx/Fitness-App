import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// 2026-08-09 (Ф1b): two of these tests asserted a gradient background —
/// "paints a linear gradient layer behind the child" and "uses different stops
/// for light and dark brightness". Both were rewritten rather than deleted,
/// because the property worth pinning did not disappear, it inverted.
///
/// The design's background is one flat colour: `src/index.css` in the
/// prototype export says `background: #06060F` and nothing else. The widget
/// used to paint a five-stop vertical gradient plus two lime radial blooms at
/// 34% and 30% alpha, which overlap across most of a phone screen and read as
/// olive. What now needs guarding is that the gradient does not come back.
void main() {
  group('AuroraBackground', () {
    testWidgets('renders the child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AuroraBackground(
            child: Center(child: Text('child-content')),
          ),
        ),
      );
      expect(find.text('child-content'), findsOneWidget);
    });

    testWidgets('paints no gradient — the background is one flat colour',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AuroraBackground(child: SizedBox.expand()),
        ),
      );
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.gradient != null);
      expect(gradients, isEmpty,
          reason: 'a bloom or a base gradient has come back');
    });

    testWidgets('fills with the theme\'s own background token', (tester) async {
      final theme = AppTheme.dark();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const AuroraBackground(child: SizedBox.expand()),
        ),
      );
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(AuroraBackground),
          matching: find.byType(ColoredBox),
        ),
      );
      // Not a hardcoded #06060F: the point is that the widget reads the token
      // rather than carrying its own private palette, which is exactly what
      // let this file drift a whole redesign behind the rest of the app.
      expect(box.color, theme.extension<AppSemanticColors>()!.backgroundPrimary);
    });

    testWidgets('renders under a bare MaterialApp with no app theme',
        (tester) async {
      // Regression guard, 2026-08-09. The first version of the flat rewrite
      // read its colour through `theme.colors`, whose getter ends in
      // `extension<AppSemanticColors>()!`. Every page test pumps a stock
      // MaterialApp, so the bang threw and took down not just this widget but
      // whatever page was inside it — the failures that surfaced were
      // "renders its child" and "invokes onTap", not colour assertions.
      await tester.pumpWidget(
        const MaterialApp(
          home: AuroraBackground(child: Text('no-theme')),
        ),
      );
      expect(find.text('no-theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
