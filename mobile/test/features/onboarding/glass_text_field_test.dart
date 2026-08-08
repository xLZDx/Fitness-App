import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/widgets/inputs.dart';

/// `GlassTextField` used `TextFormField(initialValue: ...)` with no
/// controller and no key -- `initialValue` is read once in `initState` and
/// never again, so a [value] that changes for a reason OTHER than this
/// field's own `onChanged` (e.g. the onboarding draft rehydrating from a
/// cached profile a frame after first mount) left the field showing stale
/// or blank text while the caller already held the real answer. This pins
/// both halves: an external value change is picked up, and the field does
/// not fight the user's own typing.
Widget _harness({
  required String Function() getValue,
  required void Function(String) onExternalChange,
}) {
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => GlassTextField(
          value: getValue(),
          onChanged: (v) => setState(() => onExternalChange(v)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'a value change with no user interaction updates the displayed text',
      (tester) async {
    var value = '';
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return GlassTextField(value: value, onChanged: (_) {});
          },
        ),
      ),
    ));

    expect(find.text('72'), findsNothing);

    // Simulates the async draft rehydrating -- nothing the user typed.
    rebuild(() => value = '72');
    await tester.pump();

    expect(find.text('72'), findsOneWidget,
        reason: 'the field must reflect a value change it did not cause');
  });

  testWidgets('typing is not clobbered by the field\'s own onChanged echo',
      (tester) async {
    var value = '';
    await tester.pumpWidget(_harness(
      getValue: () => value,
      onExternalChange: (v) => value = v,
    ));

    await tester.enterText(find.byType(GlassTextField), '175');
    await tester.pump();

    expect(find.text('175'), findsOneWidget);
  });
}
