import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/demo_data_banner.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the message when demo', (tester) async {
    await tester.pumpWidget(
      host(const DemoDataBanner(isDemo: true, message: 'Sample data')),
    );
    expect(find.text('Sample data'), findsOneWidget);
  });

  testWidgets('renders nothing once the data is real', (tester) async {
    await tester.pumpWidget(
      host(const DemoDataBanner(isDemo: false, message: 'Sample data')),
    );
    expect(find.text('Sample data'), findsNothing);
    expect(find.byType(DemoDataBanner), findsOneWidget,
        reason: 'the widget itself still mounts -- it renders a zero-size '
            'box, it is not conditionally absent from the tree');
  });

  testWidgets('announces itself to a screen reader', (tester) async {
    await tester.pumpWidget(
      host(const DemoDataBanner(isDemo: true, message: 'Sample data')),
    );
    final node = tester.getSemantics(
      find
          .ancestor(
            of: find.text('Sample data'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
  });
}
