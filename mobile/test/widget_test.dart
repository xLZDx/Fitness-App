import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';

void main() {
  testWidgets('App boots: splash renders, then navigates to login',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FitnessApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Fitness App'), findsOneWidget);
    expect(find.text('Scan. Train. Progress.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
