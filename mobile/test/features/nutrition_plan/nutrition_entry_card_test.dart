// NutritionEntryCard (SAFE-12, D-55): the calorie range only for an eligible
// user with a plan; for referProfessional (and every non-eligible verdict) NO
// number at all, even if a plan document exists.
import 'package:fitness_app/features/nutrition_plan/widgets/nutrition_entry_card.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'plan_state_fixtures.dart';
import 'plan_state_harness.dart';
import 'plan_widget_host.dart';

void main() {
  Future<PlanHarness> open(
    WidgetTester tester, {
    HealthFlags flags = kClearFlags,
    int? birthYear = 1985,
    bool seedPlan = true,
    Locale locale = const Locale('en'),
    List<String>? visited,
  }) async {
    final h = (await tester.runAsync(() => makeHarness(
        profile: eligibleProfile(flags: flags, birthYear: birthYear))))!;
    addTearDown(h.dispose);
    if (seedPlan) h.plans.seedPlan(kUid, storedPlan());
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: Center(child: NutritionEntryCard()))),
      GoRoute(
          path: '/nutrition',
          builder: (_, __) {
            visited?.add('/nutrition');
            return const Scaffold(body: Text('PLAN-PAGE'));
          }),
    ]);
    tallSurface(tester);
    await tester.pumpWidget(
        planApp(const SizedBox(), container: h.container, router: router, locale: locale));
    await tester.runAsync(() => pumpEventQueue());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return h;
  }

  List<String> texts(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];

  testWidgets('eligible with a plan: shows the stored range', (tester) async {
    await open(tester);
    expect(find.text('Nutrition plan'), findsOneWidget);
    expect(find.text('2,000–2,200 kcal a day'), findsOneWidget);
  });

  testWidgets('eligible without a plan: set-up prompt, no number',
      (tester) async {
    await open(tester, seedPlan: false);
    expect(find.text('Set up your plan'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('referProfessional: neutral line and NO digit anywhere, even '
      'with a stored plan', (tester) async {
    await open(tester,
        flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none));
    expect(find.text('A doctor or dietitian is the right person to set food targets.'),
        findsOneWidget);
    for (final t in texts(tester)) {
      expect(RegExp(r'\d').hasMatch(t), isFalse, reason: t);
    }
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('under 18 is also referProfessional: no number', (tester) async {
    await open(tester, birthYear: 2015);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.text('A doctor or dietitian is the right person to set food targets.'),
        findsOneWidget);
  });

  testWidgets('needsAnswer (safety question unanswered): set-up, no number',
      (tester) async {
    await open(tester, flags: const HealthFlags());
    expect(find.text('Set up your plan'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('needsProfile (no birth year): set-up, no number',
      (tester) async {
    await open(tester, birthYear: null);
    expect(find.text('Set up your plan'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('tapping the card opens /nutrition', (tester) async {
    final visited = <String>[];
    await open(tester, visited: visited);
    await tester.tap(find.text('Nutrition plan'));
    await tester.pumpAndSettle();
    expect(visited, ['/nutrition']);
    expect(find.text('PLAN-PAGE'), findsOneWidget);
  });

  testWidgets('semantics: one button labelled title plus body, 48 dp tall',
      (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    final node = tester.getSemantics(
        find.bySemanticsLabel('Nutrition plan. 2,000–2,200 kcal a day'));
    // ignore: deprecated_member_use
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(tester.getSize(find.byType(NutritionEntryCard)).height,
        greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets('RU: range line, professional line and set-up line',
      (tester) async {
    await open(tester, locale: const Locale('ru'));
    expect(find.text('План питания'), findsOneWidget);
    expect(find.text('${NumberFormat.decimalPattern('ru').format(2000)}–${NumberFormat.decimalPattern('ru').format(2200)} ккал в день'), findsOneWidget);
    await open(tester,
        locale: const Locale('ru'),
        flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none));
    expect(find.text('Цели по питанию лучше определит врач или диетолог.'),
        findsOneWidget);
    await open(tester, locale: const Locale('ru'), seedPlan: false);
    expect(find.text('Настройте свой план'), findsOneWidget);
  });
}
