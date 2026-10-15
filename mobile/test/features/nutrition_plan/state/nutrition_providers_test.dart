// C18 nutrition_providers_test. The 14-day median steps (at least 7 COMPLETED
// days, today excluded, else null so the self-reported bucket applies), the
// device-local verdict gating what is displayed (D-55), and the read-model
// weekly review, which must never write.
import 'package:fitness_app/core/health/health_models.dart';
import 'package:fitness_app/core/health/health_service.dart';
import 'package:fitness_app/core/health/state/health_providers.dart';
import 'package:fitness_app/features/nutrition_plan/data/body_fat_trend_source.dart';
import 'package:fitness_app/features/nutrition_plan/data/in_memory_nutrition_repositories.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';
import '../plan_state_harness.dart';

HealthSnapshot _day(int dayOfOctober, int? steps) =>
    HealthSnapshot(dateUtc: DateTime.utc(2026, 10, dayOfOctober), steps: steps);

/// Fake platform: only `readSnapshots` is implemented.
class _FakeHealth extends Fake implements HealthService {
  _FakeHealth(this.snapshots, {this.throws = false});

  final List<HealthSnapshot> snapshots;
  final bool throws;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  }) async {
    lastFrom = from;
    lastTo = to;
    if (throws) throw StateError('platform down');
    return snapshots;
  }
}

void main() {
  group('medianDailySteps', () {
    // kNow is 2026-10-15: the completed days are 1..14, today is 15.
    int? median(List<HealthSnapshot> s, {int minDays = 7}) =>
        medianDailySteps(s, kNow, minDays: minDays);

    test('seven completed days: the middle value', () {
      final s = [
        for (var d = 1; d <= 7; d++) _day(d, d * 1000),
      ];
      expect(median(s), 4000);
    });

    test('six completed days are not enough -> null (bucket applies)', () {
      final s = [for (var d = 1; d <= 6; d++) _day(d, 5000)];
      expect(median(s), isNull);
    });

    test('today is excluded even when it has data', () {
      final six = [for (var d = 9; d <= 14; d++) _day(d, 5000)];
      expect(median([...six, _day(15, 20000)]), isNull,
          reason: 'six completed days + today is still six');
      final seven = [for (var d = 8; d <= 14; d++) _day(d, 5000)];
      expect(median([...seven, _day(15, 20000)]), 5000,
          reason: 'today must not move the median');
    });

    test('an even count averages the two middle values and rounds', () {
      final s = [
        _day(1, 1000),
        _day(2, 2000),
        _day(3, 3000),
        _day(4, 4000),
        _day(5, 5000),
        _day(6, 6000),
        _day(7, 7000),
        _day(8, 8001),
      ];
      // sorted middle: 4000 and 5000 -> 4500
      expect(median(s), 4500);
      final odd = [..._rangeSteps([1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007])];
      expect(median(odd), 1004, reason: '(1003 + 1004) / 2 = 1003.5 rounds to 1004');
    });

    test('order of the snapshots does not matter', () {
      final s = [for (var d = 1; d <= 7; d++) _day(d, d * 1000)];
      expect(median(s.reversed.toList()), median(s));
    });

    test('null and zero step days are ignored, not counted', () {
      final s = [
        for (var d = 1; d <= 6; d++) _day(d, 6000),
        _day(7, 0),
        _day(8, null),
      ];
      expect(median(s), isNull, reason: 'only six real days');
      expect(median([...s, _day(9, 6000)]), 6000);
    });

    test('minDays is honoured', () {
      final s = [for (var d = 1; d <= 3; d++) _day(d, 3000 + d)];
      expect(median(s, minDays: 3), 3002);
      expect(median(s, minDays: 4), isNull);
    });

    test('an empty series is null', () {
      expect(median(const []), isNull);
    });
  });

  group('provider defaults', () {
    test('the plan repository default is the in-memory fake', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(nutritionPlanRepositoryProvider),
          isA<InMemoryPlanRepository>());
    });

    test('the body-fat port defaults to "no trend"', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(bodyFatTrendSourceProvider).currentTrend(), isNull);
    });
  });

  group('healthMedianStepsProvider', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    test('reads a 15-day window ending now and returns the median', () async {
      final health = _FakeHealth([
        for (var d = 1; d <= 9; d++) _day(d, 7000 + d),
      ]);
      h = await makeHarness(extra: [healthServiceProvider.overrideWithValue(health)]);
      expect(await h.container.read(healthMedianStepsProvider.future), 7005);
      expect(health.lastTo, kNow);
      expect(health.lastFrom, kNow.subtract(const Duration(days: 15)));
    });

    test('too little data -> null', () async {
      h = await makeHarness(extra: [
        healthServiceProvider
            .overrideWithValue(_FakeHealth([_day(1, 7000), _day(2, 7000)])),
      ]);
      expect(await h.container.read(healthMedianStepsProvider.future), isNull);
    });

    test('a platform error is swallowed -> null, never thrown', () async {
      h = await makeHarness(extra: [
        healthServiceProvider
            .overrideWithValue(_FakeHealth(const [], throws: true)),
      ]);
      expect(await h.container.read(healthMedianStepsProvider.future), isNull);
    });
  });

  group('nutritionInputsProvider', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    test('resolves inputs from an eligible profile (weight 80, height 180)',
        () async {
      h = await makeHarness();
      final inputs = h.container.read(nutritionInputsProvider)!.inputs!;
      expect(inputs.weightKg, 80);
      expect(inputs.heightCm, 180);
      expect(inputs.goal.name, 'lose');
    });

    test('a loaded platform median replaces the self-reported steps', () async {
      final health = _FakeHealth([for (var d = 1; d <= 9; d++) _day(d, 9000)]);
      h = await makeHarness(extra: [healthServiceProvider.overrideWithValue(health)]);
      await h.container.read(healthMedianStepsProvider.future);
      await pumpEventQueue();
      final inputs = h.container.read(nutritionInputsProvider)!.inputs!;
      expect(inputs.typicalSteps, 9000);
    });

    test('no profile loaded -> null', () async {
      h = await makeHarness(seedEligibleDefaultProfile: false);
      expect(h.container.read(nutritionInputsProvider), isNull);
    });

    test('a missing height lists the missing input and gives no numbers',
        () async {
      h = await makeHarness(profile: eligibleProfile(heightCm: null));
      final r = h.container.read(nutritionInputsProvider)!;
      expect(r.inputs, isNull);
      expect(r.missing, isNotEmpty);
    });
  });

  group('nutritionEligibilityProvider and the display gate (D-55)', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    Future<void> load() async {
      await h.container.read(storedNutritionPlanProvider.future);
      await pumpEventQueue();
    }

    test('eligible: the stored plan is displayed', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(nutritionEligibilityProvider), isA<Eligible>());
      expect(h.container.read(nutritionPlanProvider).valueOrNull!.planVersion, 3);
    });

    test('referProfessional hides an existing plan; the stored one is untouched',
        () async {
      h = await makeHarness(
        profile: eligibleProfile(
          flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none,
          ),
        ),
      );
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(nutritionEligibilityProvider),
          isA<ReferProfessional>());
      expect(h.container.read(nutritionPlanProvider).valueOrNull, isNull);
      expect(h.container.read(storedNutritionPlanProvider).valueOrNull,
          isNotNull,
          reason: 'only the display is gated, the document is not deleted');
    });

    test('needsAnswer (unanswered safety question) hides the plan', () async {
      h = await makeHarness(profile: eligibleProfile(flags: const HealthFlags()));
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(nutritionEligibilityProvider), isA<NeedsAnswer>());
      expect(h.container.read(nutritionPlanProvider).valueOrNull, isNull);
    });

    test('needsProfile hides the plan', () async {
      h = await makeHarness(profile: eligibleProfile(heightCm: null));
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(nutritionEligibilityProvider), isA<NeedsProfile>());
      expect(h.container.read(nutritionPlanProvider).valueOrNull, isNull);
    });

    test('an unknown verdict (no profile) fails closed: null and no plan',
        () async {
      h = await makeHarness(seedEligibleDefaultProfile: false);
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(nutritionEligibilityProvider), isNull);
      expect(h.container.read(nutritionPlanProvider).valueOrNull, isNull);
    });

    test('signed out: no stored plan is read at all', () async {
      h = await makeHarness(uid: null);
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(storedNutritionPlanProvider).valueOrNull, isNull);
    });
  });

  group('nutritionReviewsProvider', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    test('lists reviews newest week first', () async {
      h = await makeHarness();
      for (final w in ['2026-W40', '2026-W42', '2026-W41']) {
        h.plans.seedReview(
            kUid, PlanReviewRecord.fromDecision(w, keepDecision(), kNow));
      }
      final list = await h.container.read(nutritionReviewsProvider.future);
      expect(list.map((r) => r.week), ['2026-W42', '2026-W41', '2026-W40']);
    });

    test('signed out: empty', () async {
      h = await makeHarness(uid: null);
      expect(await h.container.read(nutritionReviewsProvider.future), isEmpty);
    });
  });

  group('weeklyReviewProvider is a read model that never writes', () {
    late PlanHarness h;
    tearDown(() => h.dispose());

    Future<void> load() async {
      await h.container.read(storedNutritionPlanProvider.future);
      await h.container.read(nutritionReviewsProvider.future);
      await pumpEventQueue();
    }

    test('not eligible -> null even with a plan and data', () async {
      h = await makeHarness(profile: eligibleProfile(flags: const HealthFlags()));
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      expect(h.container.read(weeklyReviewProvider), isNull);
    });

    test('eligible without a plan -> null', () async {
      h = await makeHarness();
      await load();
      expect(h.container.read(weeklyReviewProvider), isNull);
    });

    test('eligible with a plan and no weigh-ins -> needMoreData', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      await load();
      final d = h.container.read(weeklyReviewProvider)!;
      expect(d.kind, ReviewDecisionKind.needMoreData);
      expect(d.basePlanVersion, 3);
      expect(h.plans.reviewWrites, 0);
      expect(h.plans.planWrites, 0);
    });

    test('a behind series after a behind review yields the steps change', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      h.plans.seedReview(
        kUid,
        PlanReviewRecord.fromDecision(
          '2026-W41',
          decisionOf(
            kind: ReviewDecisionKind.keep,
            reasons: const [ReviewReason.behindWaiting],
            deltaKcal: 0,
            cls: ReviewClass.behind,
          ),
          kNow.subtract(const Duration(days: 7)),
        ),
      );
      for (final e in {14: 80.0, 7: 79.9, 0: 79.8}.entries) {
        await h.weights.put(kUid,
            WeightEntry(at: kNow.subtract(Duration(days: e.key)), kg: e.value));
      }
      await h.settle();
      await load();
      final d = h.container.read(weeklyReviewProvider)!;
      expect(d.kind, ReviewDecisionKind.adjustSteps);
      expect(d.classification, ReviewClass.behind);
      expect(h.plans.reviewWrites, 0, reason: 'seeding is not a write; the provider adds none');
      expect(h.plans.planWrites, 0);
    });
  });
}

List<HealthSnapshot> _rangeSteps(List<int> steps) => [
      for (var i = 0; i < steps.length; i++) _day(i + 1, steps[i]),
    ];
