// T86 nutrition_plan_page (PLAN-17, PLAN-28, SAFE-12, SAFE-16, D-55, D-79).
//
// The REAL providers, in-memory repositories and the real NutritionPlanActions
// run under the page; only the weekly-review scheduler is a recording spy
// (except in the two tests that use the real one).
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_plan_page.dart';
import 'package:fitness_app/features/nutrition_plan/state/review_scheduler.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'plan_state_fixtures.dart';
import 'plan_state_harness.dart';
import 'plan_widget_host.dart';

class _SpyScheduler extends WeeklyReviewScheduler {
  _SpyScheduler(super.ref, {this.passThrough = false});

  final bool passThrough;
  final List<ReviewTrigger> triggers = [];

  @override
  Future<ReviewRunResult> run(ReviewTrigger trigger) async {
    triggers.add(trigger);
    if (passThrough) return super.run(trigger);
    return const ReviewRunResult(ReviewRunStatus.skipped,
        reason: ReviewSkipReason.noDecision);
  }
}

class _Page {
  _Page(this.h, this.notice, this.settings, this.spy, this.visited);
  final PlanHarness h;
  final InMemoryDataNoticeStore notice;
  final InMemoryBodyScanSettingsStore settings;
  final _SpyScheduler Function() spy;
  final List<String> visited;
}

const _referFlags = HealthFlags(
    nutritionGuidance: NutritionGuidanceNeed.reported,
    professionalGuidance: ProfessionalGuidanceNeed.none);

void main() {
  Future<_Page> open(
    WidgetTester tester, {
    HealthFlags flags = kClearFlags,
    int? birthYear = 1985,
    bool noticeAcknowledged = true,
    StoredNutritionPlan? plan,
    bool passThrough = false,
    Locale locale = const Locale('en'),
  }) async {
    final notice = InMemoryDataNoticeStore(acknowledged: noticeAcknowledged);
    final settings = InMemoryBodyScanSettingsStore();
    _SpyScheduler? spy;
    final visited = <String>[];
    final h = (await tester.runAsync(() => makeHarness(
          profile: eligibleProfile(flags: flags, birthYear: birthYear),
          noticeAcknowledged: noticeAcknowledged,
          extra: [
            dataNoticeStoreProvider.overrideWith((ref) async => notice),
            bodyScanSettingsStoreProvider.overrideWithValue(settings),
            weeklyReviewSchedulerProvider.overrideWith(
                (ref) => spy = _SpyScheduler(ref, passThrough: passThrough)),
          ],
        )))!;
    addTearDown(h.dispose);
    if (plan != null) h.plans.seedPlan(kUid, plan);
    final router = GoRouter(initialLocation: '/nutrition', routes: [
      GoRoute(path: '/nutrition', builder: (_, __) => const NutritionPlanPage()),
      for (final p in [
        '/nutrition/profile',
        '/nutrition/weight',
        '/nutrition/sources',
        '/nutrition/how-it-adapts',
      ])
        GoRoute(
            path: p,
            builder: (_, __) {
              visited.add(p);
              return Scaffold(body: Text('ROUTE $p'));
            }),
    ]);
    tallSurface(tester, size: const Size(800, 7000));
    await tester.pumpWidget(
        planApp(const SizedBox(), container: h.container, router: router, locale: locale));
    await settleAsync(tester);
    return _Page(h, notice, settings, () => spy!, visited);
  }

  Future<StoredNutritionPlan?> stored(WidgetTester t, _Page p) async =>
      (await t.runAsync<StoredNutritionPlan?>(() => p.h.plans.loadPlan(kUid)));

  List<String> texts(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];

  final sheetButton = find.descendant(
      of: find.byType(BottomSheet), matching: find.byType(FilledButton));

  group('verdict gating', () {
    testWidgets('referProfessional sees ONLY the notice and two links, no number '
        'even with a stored plan', (tester) async {
      await open(tester, flags: _referFlags, plan: storedPlan());
      expect(find.text('We cannot set nutrition targets for you here'),
          findsOneWidget);
      for (final gone in [
        'Daily calories',
        'Macros',
        'Who adjusts your plan',
        'Weekly review',
        'Automatic adjustments',
        'Create your plan',
        'Weight log',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      for (final t in texts(tester)) {
        expect(RegExp(r'\d').hasMatch(t), isFalse, reason: t);
      }
      expect(find.text('How your plan adapts'), findsOneWidget);
      expect(find.text('Data sources and limits'), findsOneWidget);
    });

    testWidgets('referProfessional: the review scheduler writes nothing',
        (tester) async {
      final p = await open(tester,
          flags: _referFlags, plan: storedPlan(), passThrough: true);
      await settleAsync(tester);
      expect(p.h.plans.reviewWrites, 0);
      expect(p.h.plans.planWrites, 0);
    });

    testWidgets('needsAnswer links to /nutrition/profile and shows no numbers',
        (tester) async {
      final p = await open(tester, flags: const HealthFlags(), plan: storedPlan());
      expect(find.text('Finish your nutrition profile'), findsOneWidget);
      expect(find.text('Daily calories'), findsNothing);
      expect(find.text('Create your plan'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(p.visited, ['/nutrition/profile']);
    });

    testWidgets('needsProfile (no birth year) links to /nutrition/profile',
        (tester) async {
      final p = await open(tester, birthYear: null);
      expect(find.text('Finish your nutrition profile'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(p.visited, ['/nutrition/profile']);
    });
  });

  group('eligible user with a plan', () {
    testWidgets('renders every block of PLAN-17', (tester) async {
      await open(tester, plan: storedPlan());
      expect(find.text('Nutrition plan'), findsOneWidget);
      expect(find.text('Daily calories'), findsOneWidget);
      expect(find.text('2,000–2,200 kcal'), findsOneWidget);
      expect(find.text('Allowed for you: 1,850–2,400 kcal'), findsOneWidget);
      expect(find.text('Macros'), findsOneWidget);
      expect(find.text('Daily steps goal'), findsOneWidget);
      expect(find.text('8500 steps'), findsOneWidget);
      expect(find.text('Who adjusts your plan'), findsOneWidget);
      expect(find.text('Automatic adjustments'), findsOneWidget);
      expect(find.text('Weekly review'), findsOneWidget);
      expect(find.text('Lowest daily calories: 2,000'), findsOneWidget);
      expect(find.text('How your plan adapts'), findsOneWidget);
      expect(find.text('Data sources and limits'), findsOneWidget);
      expect(find.text('Weight log'), findsOneWidget);
    });

    testWidgets('no ETA promise; neutral no-date copy is shown',
        (tester) async {
      await open(tester, plan: storedPlan());
      expect(
          find.text(
              'We do not predict a date. Progress is rarely a straight line, and a slower week is normal.'),
          findsOneWidget);
      expect(find.text('Body scans work best about once a month; weekly is optional.'),
          findsOneWidget);
      for (final t in texts(tester)) {
        expect(t.toLowerCase().contains('eta'), isFalse, reason: t);
        expect(RegExp(r'weeks? to|reach .* by|by \w+ \d').hasMatch(t), isFalse,
            reason: t);
      }
    });

    testWidgets('first review expectation: "after about 3 weigh-ins over 2 weeks"',
        (tester) async {
      await open(tester, plan: storedPlan());
      expect(
          find.text(
              'Your first review needs about 3 weigh-ins over 2 weeks. Log your weight in the weight log.'),
          findsOneWidget);
      expect(
          find.text(
              'No review yet. The first one appears after about 3 weigh-ins over 2 weeks.'),
          findsOneWidget);
    });

    testWidgets('profile weight shows as last known; a fresh weigh-in as current',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      expect(find.text('Last known weight: 80.0 kg (from your profile)'),
          findsOneWidget);
      await tester.runAsync(() => p.h.weights
          .put(kUid, WeightEntry(at: kNow.subtract(const Duration(days: 1)), kg: 79.5)));
      await settleAsync(tester);
      expect(find.text('Current weight: 79.5 kg'), findsOneWidget);
    });

    testWidgets('links push the weight log, explainer and sources',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      for (final e in {
        'Weight log': '/nutrition/weight',
        'How your plan adapts': '/nutrition/how-it-adapts',
        'Data sources and limits': '/nutrition/sources',
      }.entries) {
        await tester.tap(find.text(e.key));
        await tester.pumpAndSettle();
        expect(p.visited.last, e.value);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
      expect(p.visited.length, 3);
    });

    testWidgets('weekly review is triggered once on first display',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      expect(p.spy().triggers, [ReviewTrigger.planSurfaceShown]);
      // A rebuild caused by a write does not trigger it again.
      await tester.tap(find.byKey(const Key('nutrition.ownership.manual')));
      await settleAsync(tester);
      expect(p.spy().triggers, [ReviewTrigger.planSurfaceShown]);
    });
  });

  group('creating the first plan', () {
    testWidgets('eligible without a plan: create button writes a plan inside '
        'its bounds', (tester) async {
      final p = await open(tester);
      expect(find.text('Create your plan'), findsOneWidget);
      expect(find.text('Daily calories'), findsNothing);
      await tester.tap(find.byKey(const Key('nutrition.create')));
      await settleAsync(tester);
      expect(p.h.plans.planWrites, 1);
      final plan = (await stored(tester, p))!;
      expect(plan.kcalBounds.contains(plan.kcalRange), isTrue);
      expect(plan.planVersion, 1);
      expect(find.text('Daily calories'), findsOneWidget);
    });

    testWidgets('data notice BEFORE the first plan write: declined = no write',
        (tester) async {
      final p = await open(tester, noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('nutrition.create')));
      await tester.pumpAndSettle();
      expect(sheetButton, findsOneWidget, reason: 'the notice sheet is shown');
      expect(p.h.plans.planWrites, 0);
      // Dismiss without acknowledging.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(p.h.plans.planWrites, 0);
      expect(p.notice.acknowledgeCalls, 0);
      expect(find.text('Create your plan'), findsOneWidget);
    });

    testWidgets('data notice acknowledged in the sheet, then the plan is written',
        (tester) async {
      final p = await open(tester, noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('nutrition.create')));
      await tester.pumpAndSettle();
      expect(p.h.plans.planWrites, 0);
      await tester.tap(sheetButton);
      await settleAsync(tester);
      expect(p.notice.acknowledgeCalls, 1);
      expect(p.h.plans.planWrites, 1);
    });
  });

  group('edits go through actions (bounds, version, ownership rules)', () {
    testWidgets('slider +10 on the low thumb saves and flips coached to shared',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      await tester.tap(find.text('+10').first);
      await settleAsync(tester);
      final plan = (await stored(tester, p))!;
      expect(plan.kcalRange, const KcalRange(2010, 2200));
      expect(plan.ownership, PlanOwnership.shared);
      expect(plan.planVersion, 4);
      expect(find.text('Plan saved.'), findsOneWidget);
      expect(find.text('2,010–2,200 kcal'), findsOneWidget);
    });

    testWidgets('slider at the lower bound writes nothing', (tester) async {
      final p = await open(tester,
          plan: storedPlan(range: const KcalRange(1850, 2050)));
      await tester.tap(find.text('-10').first);
      await settleAsync(tester);
      expect(p.h.plans.planWrites, 0);
      expect(find.text('1,850–2,050 kcal'), findsOneWidget);
    });

    testWidgets('steps goal +500 persists 9000', (tester) async {
      final p = await open(tester, plan: storedPlan());
      await tester.tap(find.byIcon(Icons.add));
      await settleAsync(tester);
      expect((await stored(tester, p))!.stepsGoal, 9000);
      expect(find.text('9000 steps'), findsOneWidget);
    });

    testWidgets('ownership change is stored and does not rewrite the range',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      await tester.tap(find.byKey(const Key('nutrition.ownership.manual')));
      await settleAsync(tester);
      final plan = (await stored(tester, p))!;
      expect(plan.ownership, PlanOwnership.manual);
      expect(plan.kcalRange, storedPlan().kcalRange);
    });

    testWidgets('auto-adjust toggle persists only its own flag', (tester) async {
      final p = await open(tester, plan: storedPlan());
      await tester.tap(find.byKey(const Key('nutrition.auto.kcal')));
      await settleAsync(tester);
      final plan = (await stored(tester, p))!;
      expect(plan.autoAdjust.kcal, isFalse);
      expect(plan.autoAdjust.steps, isTrue);
    });

    testWidgets('data notice before ANY edit: declined keeps the stored value',
        (tester) async {
      final p = await open(tester, noticeAcknowledged: false, plan: storedPlan());
      await tester.tap(find.text('+10').first);
      await tester.pumpAndSettle();
      expect(sheetButton, findsOneWidget);
      expect(p.h.plans.planWrites, 0);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(p.h.plans.planWrites, 0);
      expect(find.text('2,000–2,200 kcal'), findsOneWidget);
    });

    testWidgets('data notice before an ownership change and a steps change',
        (tester) async {
      final p = await open(tester, noticeAcknowledged: false, plan: storedPlan());
      await tester.tap(find.byKey(const Key('nutrition.ownership.manual')));
      await tester.pumpAndSettle();
      expect(sheetButton, findsOneWidget);
      expect(p.h.plans.planWrites, 0);
      await tester.tap(sheetButton);
      await settleAsync(tester);
      expect(p.h.plans.planWrites, 1);
      expect(p.notice.acknowledgeCalls, 1);
      // Acknowledged now: the next write needs no sheet.
      await tester.tap(find.byIcon(Icons.add));
      await settleAsync(tester);
      expect(sheetButton, findsNothing);
      expect(p.h.plans.planWrites, 2);
    });

    testWidgets('offline write is reported and not saved', (tester) async {
      final p = await open(tester, plan: storedPlan());
      p.h.plans.offline = true;
      await tester.tap(find.byIcon(Icons.add));
      await settleAsync(tester);
      expect(find.text('You are offline, so the change was not saved.'),
          findsOneWidget);
      expect(p.h.plans.planWrites, 0);
    });
  });

  group('pause toggle', () {
    testWidgets('toggle writes the paused flag to the settings store',
        (tester) async {
      final p = await open(tester, plan: storedPlan());
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('nutrition.pause'))).value,
          isFalse);
      await tester.tap(find.byKey(const Key('nutrition.pause')));
      await settleAsync(tester);
      final first = await tester.runAsync(() => p.settings.watch().first);
      expect(first!.paused, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('nutrition.pause'))).value,
          isTrue);
      await tester.tap(find.byKey(const Key('nutrition.pause')));
      await settleAsync(tester);
      final second = await tester.runAsync(() => p.settings.watch().first);
      expect(second!.paused, isFalse);
    });

    testWidgets('a declined data notice leaves it unpaused', (tester) async {
      final p = await open(tester, noticeAcknowledged: false, plan: storedPlan());
      await tester.tap(find.byKey(const Key('nutrition.pause')));
      await tester.pumpAndSettle();
      expect(sheetButton, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      final v = await tester.runAsync(() => p.settings.watch().first);
      expect(v!.paused, isFalse);
    });
  });

  testWidgets('RU: plan screen texts', (tester) async {
    await open(tester, plan: storedPlan(), locale: const Locale('ru'));
    expect(find.text('План питания'), findsOneWidget);
    expect(find.text('Калории в день'), findsOneWidget);
    expect(find.text('Недельная проверка'), findsOneWidget);
    expect(find.text('Приостановить отслеживание'), findsOneWidget);
    expect(
        find.text('Мы не называем дату. Прогресс редко идёт по прямой, и более медленная неделя — это нормально.'),
        findsOneWidget);
  });

  testWidgets('RU referProfessional: notice only', (tester) async {
    await open(tester,
        flags: _referFlags, plan: storedPlan(), locale: const Locale('ru'));
    expect(find.text('Мы не можем задать здесь цели по питанию'), findsOneWidget);
    expect(find.text('Калории в день'), findsNothing);
  });
}
