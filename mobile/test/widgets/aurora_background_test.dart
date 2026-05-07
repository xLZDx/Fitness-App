import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/aurora_background.dart';

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

    testWidgets('paints a linear gradient layer behind the child',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AuroraBackground(child: SizedBox.expand()),
        ),
      );
      final decorated =
          tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final hasGradient = decorated.any((d) {
        final dec = d.decoration;
        return dec is BoxDecoration && dec.gradient is LinearGradient;
      });
      expect(hasGradient, isTrue);
    });

    testWidgets('uses different stops for light and dark brightness',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AuroraBackground(child: SizedBox.expand()),
        ),
      );
      final lightGradient = _findFirstLinearGradient(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData.dark(),
            child: const AuroraBackground(child: SizedBox.expand()),
          ),
        ),
      );
      final darkGradient = _findFirstLinearGradient(tester);

      expect(lightGradient.colors, isNot(equals(darkGradient.colors)));
    });
  });
}

LinearGradient _findFirstLinearGradient(WidgetTester tester) {
  for (final d in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    final dec = d.decoration;
    if (dec is BoxDecoration && dec.gradient is LinearGradient) {
      return dec.gradient! as LinearGradient;
    }
  }
  fail('No LinearGradient found');
}
