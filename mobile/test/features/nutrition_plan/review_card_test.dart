// ReviewCard (PLAN-14, PLAN-23, design s15/s18): always shows WHY (closed
// reason codes); the 7-day undo exists only for an applied COACHED change that
// is still inside its window; accept exists only for a current SHARED proposal.
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/widgets/review_card.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_state_fixtures.dart';
import 'plan_widget_host.dart';

PlanReviewRecord review({
  ReviewDecisionKind kind = ReviewDecisionKind.adjustKcal,
  int deltaKcal = -150,
  int deltaSteps = 0,
  List<ReviewReason> reasons = const [ReviewReason.kcalLowered],
  int base = 3,
  String week = kWeek,
  double? slope = -0.1,
  int points = 5,
}) =>
    PlanReviewRecord(
      week: week,
      decidedAt: DateTime(2026, 10, 15, 8),
      basePlanVersion: base,
      decision: kind,
      deltaKcal: deltaKcal,
      deltaSteps: deltaSteps,
      reasonCodes: reasons,
      inputs: ReviewInputsRecord(
          weightSlopeKgPerWeek: slope, intendedKgPerWeek: -0.4, dataPoints: points),
    );

ReviewUndo undoOf({
  String week = kWeek,
  DateTime? expires,
  bool undone = false,
}) =>
    ReviewUndo(
      week: week,
      prevKcalRange: const KcalRange(2150, 2350),
      prevStepsGoal: 8500,
      prevDrift: 0,
      expiresAt: expires ?? kNow.add(const Duration(days: 7)),
      undone: undone,
    );

void main() {
  late int undos;
  late int accepts;

  Future<void> pump(
    WidgetTester tester, {
    PlanReviewRecord? r,
    StoredNutritionPlan? plan,
    DateTime? now,
    bool wireUndo = true,
    bool wireAccept = true,
    Locale locale = const Locale('en'),
  }) async {
    undos = 0;
    accepts = 0;
    tallSurface(tester);
    await tester.pumpWidget(planApp(
      Scaffold(
        body: SingleChildScrollView(
          child: ReviewCard(
            review: r,
            plan: plan ?? storedPlan(undo: undoOf()),
            now: now ?? kNow,
            onUndo: wireUndo ? () => undos++ : null,
            onAccept: wireAccept ? () => accepts++ : null,
          ),
        ),
      ),
      locale: locale,
    ));
    await tester.pump();
  }

  final undoBtn = find.byKey(const Key('nutrition.review.undo'));
  final acceptBtn = find.byKey(const Key('nutrition.review.accept'));

  testWidgets('no review yet: states the first-review expectation, no buttons',
      (tester) async {
    await pump(tester);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(
        find.text(
            'No review yet. The first one appears after about 3 weigh-ins over 2 weeks.'),
        findsOneWidget);
    expect(undoBtn, findsNothing);
    expect(acceptBtn, findsNothing);
    expect(find.text('Why'), findsNothing);
  });

  group('why-card', () {
    testWidgets('shows date, decision, WHY heading, reason, basis and trend',
        (tester) async {
      await pump(tester, r: review());
      expect(find.text('Reviewed on Oct 15, 2026'), findsOneWidget);
      expect(find.text('Calories lowered by 150 kcal.'), findsOneWidget);
      expect(find.text('Why'), findsOneWidget);
      expect(find.text('The calorie range was lowered a little.'),
          findsOneWidget);
      expect(find.text('Based on 5 weigh-ins'), findsOneWidget);
      expect(find.text('Weight trend: -0.1 kg/week'), findsOneWidget);
    });

    testWidgets('one weigh-in uses the singular form', (tester) async {
      await pump(tester, r: review(points: 1));
      expect(find.text('Based on 1 weigh-in'), findsOneWidget);
    });

    testWidgets('a missing slope hides the trend line', (tester) async {
      await pump(tester, r: review(slope: null));
      expect(find.textContaining('Weight trend'), findsNothing);
    });

    testWidgets('every reason is listed, in order, each with its own text',
        (tester) async {
      await pump(tester,
          r: review(
              kind: ReviewDecisionKind.keep,
              deltaKcal: 0,
              reasons: ReviewReason.values));
      final texts = [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];
      // 14 distinct reason sentences, none a raw key.
      final reasons = texts.where((s) => s.endsWith('.')).toSet();
      expect(reasons.length, greaterThanOrEqualTo(14));
      expect(texts.any((s) => s.startsWith('reviewReason')), isFalse);
      expect(find.text('Your weight trend is close to what the plan expects.'),
          findsOneWidget);
      expect(find.text('Automatic adjustment is off for this part of your plan.'),
          findsOneWidget);
      expect(
          tester.getTopLeft(find.text('Your weight trend is close to what the plan expects.')).dy,
          lessThan(tester
              .getTopLeft(find.text(
                  'Automatic adjustment is off for this part of your plan.'))
              .dy));
    });

    testWidgets('decision wording per kind and ownership', (tester) async {
      Future<void> check(
          PlanReviewRecord r, PlanOwnership o, String expected) async {
        await pump(tester, r: r, plan: storedPlan(ownership: o));
        expect(find.text(expected), findsOneWidget, reason: expected);
      }

      await check(review(), PlanOwnership.shared,
          'Suggestion: lower calories by 150 kcal.');
      await check(review(deltaKcal: 100), PlanOwnership.shared,
          'Suggestion: raise calories by 100 kcal.');
      await check(review(deltaKcal: 100), PlanOwnership.coached,
          'Calories raised by 100 kcal.');
      await check(
          review(), PlanOwnership.manual,
          'Insight: calories could go down by 150 kcal. Your plan is Manual, so nothing changed.');
      final steps = review(
          kind: ReviewDecisionKind.adjustSteps,
          deltaKcal: 0,
          deltaSteps: 1000,
          reasons: const [ReviewReason.stepsRaised]);
      await check(steps, PlanOwnership.coached, 'Steps goal raised by 1,000.');
      await check(steps, PlanOwnership.shared,
          'Suggestion: raise the steps goal by 1,000.');
      await check(
          steps, PlanOwnership.manual,
          'Insight: the steps goal could go up by 1,000. Your plan is Manual, so nothing changed.');
      await check(
          review(kind: ReviewDecisionKind.keep, deltaKcal: 0),
          PlanOwnership.coached,
          'Your plan stays as it is.');
      await check(
          review(kind: ReviewDecisionKind.needMoreData, deltaKcal: 0),
          PlanOwnership.coached,
          'Not enough weigh-ins yet to review your plan.');
    });
  });

  group('7-day undo (coached only)', () {
    testWidgets('shown with the expiry date and calls onUndo', (tester) async {
      await pump(tester, r: review());
      expect(undoBtn, findsOneWidget);
      expect(find.text('You can undo this change until Oct 22, 2026.'),
          findsOneWidget);
      await tester.tap(undoBtn);
      await tester.pump();
      expect(undos, 1);
      expect(accepts, 0);
    });

    testWidgets('also for an applied steps change', (tester) async {
      await pump(tester,
          r: review(
              kind: ReviewDecisionKind.adjustSteps,
              deltaKcal: 0,
              deltaSteps: 500,
              reasons: const [ReviewReason.stepsRaised]));
      expect(undoBtn, findsOneWidget);
    });

    testWidgets('hidden at and after the expiry instant', (tester) async {
      final plan = storedPlan(undo: undoOf());
      await pump(tester,
          r: review(), plan: plan, now: kNow.add(const Duration(days: 7)));
      expect(undoBtn, findsNothing);
      await pump(tester,
          r: review(),
          plan: plan,
          now: kNow.add(const Duration(days: 7)).subtract(const Duration(minutes: 1)));
      expect(undoBtn, findsOneWidget);
    });

    testWidgets('hidden once undone', (tester) async {
      await pump(tester,
          r: review(), plan: storedPlan(undo: undoOf(undone: true)));
      expect(undoBtn, findsNothing);
    });

    testWidgets('hidden when the undo belongs to another week',
        (tester) async {
      await pump(tester,
          r: review(), plan: storedPlan(undo: undoOf(week: '2026-W41')));
      expect(undoBtn, findsNothing);
    });

    testWidgets('hidden with no undo record', (tester) async {
      await pump(tester, r: review(), plan: storedPlan());
      expect(undoBtn, findsNothing);
    });

    testWidgets('hidden for shared and manual plans even with a record',
        (tester) async {
      for (final o in [PlanOwnership.shared, PlanOwnership.manual]) {
        await pump(tester,
            r: review(), plan: storedPlan(ownership: o, undo: undoOf()));
        expect(undoBtn, findsNothing, reason: '$o');
      }
    });

    testWidgets('hidden when the decision changed nothing', (tester) async {
      await pump(tester,
          r: review(kind: ReviewDecisionKind.keep, deltaKcal: 0));
      expect(undoBtn, findsNothing);
    });

    testWidgets('hidden without an onUndo handler', (tester) async {
      await pump(tester, r: review(), wireUndo: false);
      expect(undoBtn, findsNothing);
    });
  });

  group('accept (shared proposal)', () {
    testWidgets('shown for a current proposal and calls onAccept',
        (tester) async {
      await pump(tester,
          r: review(base: 3), plan: storedPlan(ownership: PlanOwnership.shared));
      expect(acceptBtn, findsOneWidget);
      expect(undoBtn, findsNothing);
      await tester.tap(acceptBtn);
      await tester.pump();
      expect(accepts, 1);
      expect(undos, 0);
    });

    testWidgets('hidden when the plan moved on (version differs)',
        (tester) async {
      await pump(tester,
          r: review(base: 2),
          plan: storedPlan(ownership: PlanOwnership.shared, version: 3));
      expect(acceptBtn, findsNothing);
    });

    testWidgets('hidden for coached, manual, keep and without a handler',
        (tester) async {
      for (final o in [PlanOwnership.coached, PlanOwnership.manual]) {
        await pump(tester, r: review(), plan: storedPlan(ownership: o));
        expect(acceptBtn, findsNothing, reason: '$o');
      }
      await pump(tester,
          r: review(kind: ReviewDecisionKind.keep, deltaKcal: 0),
          plan: storedPlan(ownership: PlanOwnership.shared));
      expect(acceptBtn, findsNothing);
      await pump(tester,
          r: review(),
          plan: storedPlan(ownership: PlanOwnership.shared),
          wireAccept: false);
      expect(acceptBtn, findsNothing);
    });
  });

  group('RU', () {
    testWidgets('texts, plural forms and date', (tester) async {
      await pump(tester, r: review(points: 2), locale: const Locale('ru'));
      expect(find.text('Недельная проверка'), findsOneWidget);
      expect(find.text('Почему'), findsOneWidget);
      expect(find.text('Калории уменьшены на 150 ккал.'), findsOneWidget);
      expect(find.text('На основе 2 записей веса'), findsOneWidget);
      expect(find.text('Отменить изменение'), findsOneWidget);
      await pump(tester, r: review(points: 1), locale: const Locale('ru'));
      expect(find.text('На основе 1 записи веса'), findsOneWidget);
      await pump(tester, r: review(points: 5), locale: const Locale('ru'));
      expect(find.text('На основе 5 записей веса'), findsOneWidget);
    });

    testWidgets('no review: RU expectation text', (tester) async {
      await pump(tester, locale: const Locale('ru'));
      expect(find.textContaining('Проверок пока нет. Первая появится примерно после 3 записей'),
          findsOneWidget);
    });
  });
}
