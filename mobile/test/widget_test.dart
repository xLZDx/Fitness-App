import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';

void main() {
  testWidgets('App boots: splash renders, then navigates to login',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FitnessApp()));
    await tester.pump(const Duration(milliseconds: 100));

    // FitnessApp pins `locale: Locale('ru')`, so booting the real app must
    // render Russian regardless of the host's locale. This is the guard on
    // that default — if someone drops the pin, this assertion fails.
    expect(find.text('Fitness App'), findsOneWidget);
    expect(find.text('Сканируй. Тренируйся. Прогрессируй.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
