// C18 review_scheduler_test. The REAL WeeklyReviewScheduler over the real
// providers and the in-memory repositories. The scheduler must write NOTHING
// (no review, no plan) when signed out, deleting, notice pending, not eligible,
// without a plan, already reviewed, or offline, and must be idempotent per ISO
// week. Write counters of the fake repository are the evidence of "nothing".
import 'package:fitness_app/features/nutrition_plan/data/in_memory_nutrition_repositories.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/review_transaction.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/state/review_scheduler.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';
import '../plan_state_harness.dart';

class _ThrowingPlans extends InMemoryPlanRepository {
  @override
  Future<PlanReviewRecord?> loadReview(String uid, String week) =>
      throw StateError('boom');
}

Future<void> _behindWeights(PlanHarness h) async {
  // Slope -0.1 kg/week on a plan that intends -0.4: classified `behind`.
  for (final e in {14: 80.0, 7: 79.9, 0: 79.8}.entries) {
    await h.weights.put(
        kUid, WeightEntry(at: kNow.subtract(Duration(days: e.key)), kg: e.value));
  }
}

PlanReviewRecord _previousBehind() => PlanReviewRecord(
      week: '2026-W41',
      decidedAt: kNow.subtract(const Duration(days: 7)),
      basePlanVersion: 3,
      decision: ReviewDecisionKind.keep,
      deltaKcal: 0,
      deltaSteps: 0,
      reasonCodes: const [ReviewReason.behindWaiting],
      inputs: const ReviewInputsRecord(
        weightSlopeKgPerWeek: -0.1,
        intendedKgPerWeek: -0.4,
        dataPoints: 3,
      ),
      classification: ReviewClass.behind,
    );

void expectNothingWritten(PlanHarness h) {
  expect(h.plans.reviewWrites, 0, reason: 'no review may be written');
  expect(h.plans.planWrites, 0, reason: 'no plan may be written');
}

void main() {
  late PlanHarness h;
  tearDown(() => h.dispose());

  WeeklyReviewScheduler scheduler() =>
      h.container.read(weeklyReviewSchedulerProvider);

  group('skips that write nothing', () {
    test('signed out', () async {
      h = await makeHarness(uid: null);
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.skipped);
      expect(r.reason, ReviewSkipReason.signedOut);
      expectNothingWritten(h);
    });

    test('the account is being deleted', () async {
      h = await makeHarness(deletingUid: kUid);
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.accountBeingDeleted);
      expectNothingWritten(h);
    });

    test('another uid being deleted does not block this user', () async {
      h = await makeHarness(deletingUid: 'someone-else');
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.written);
    });

    test('the data notice is not acknowledged (D-79)', () async {
      h = await makeHarness(noticeAcknowledged: false);
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.skipped);
      expect(r.reason, ReviewSkipReason.noticePending);
      expectNothingWritten(h);
    });

    test('referProfessional (guidance reported): nothing, plan untouched', () async {
      h = await makeHarness(
        profile: eligibleProfile(
          flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none,
          ),
        ),
      );
      h.plans.seedPlan(kUid, storedPlan());
      await _behindWeights(h);
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.notEligible);
      expectNothingWritten(h);
      expect((await h.plans.loadPlan(kUid))!.planVersion, 3);
    });

    test('needsAnswer (safety question unanswered) fails closed', () async {
      h = await makeHarness(
        profile: eligibleProfile(flags: const HealthFlags()),
      );
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.notEligible);
      expectNothingWritten(h);
    });

    test('needsProfile (no height) is not eligible', () async {
      h = await makeHarness(profile: eligibleProfile(heightCm: null));
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.notEligible);
      expectNothingWritten(h);
    });

    test('an unknown verdict (profile not loaded) is not eligible', () async {
      h = await makeHarness(seedEligibleDefaultProfile: false);
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.notEligible);
      expectNothingWritten(h);
    });

    test('an under-18 profile is not eligible', () async {
      h = await makeHarness(profile: eligibleProfile(birthYear: 2010));
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.reason, ReviewSkipReason.notEligible);
      expectNothingWritten(h);
    });

    test('no stored plan', () async {
      h = await makeHarness();
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.skipped);
      expect(r.reason, ReviewSkipReason.noPlan);
      expectNothingWritten(h);
    });

    test('this week was already reviewed (stored review)', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      h.plans.seedReview(
          kUid, PlanReviewRecord.fromDecision(kWeek, keepDecision(), kNow));
      await _behindWeights(h);
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.alreadyReviewed);
      expectNothingWritten(h);
    });

    test('offline: deferred, nothing written, and retried successfully later',
        () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      h.plans.offline = true;
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.deferred);
      expect(r.outcome, ReviewApplyOutcome.offline);
      expectNothingWritten(h);
      h.plans.offline = false;
      final again = await scheduler().run(ReviewTrigger.appForeground);
      expect(again.status, ReviewRunStatus.written,
          reason: 'an offline attempt must not mark the week as done');
      expect(h.plans.reviewWrites, 1);
    });
  });

  group('a run that writes', () {
    test('not enough data: a needMoreData review, the plan is untouched', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.written);
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(r.apply!.kind, ReviewDecisionKind.needMoreData);
      expect(h.plans.reviewWrites, 1);
      expect(h.plans.planWrites, 0);
      final review = (await h.plans.loadReview(kUid, kWeek))!;
      expect(review.decision, ReviewDecisionKind.needMoreData);
      expect(review.basePlanVersion, 3);
      expect((await h.plans.loadPlan(kUid))!.planVersion, 3);
    });

    test('behind two weeks in a row, coached: review + plan in one transaction',
        () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan(stepsGoal: 8500));
      h.plans.seedReview(kUid, _previousBehind());
      await _behindWeights(h);
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.written);
      expect(r.apply!.kind, ReviewDecisionKind.adjustSteps);
      expect(h.plans.reviewWrites, 1);
      expect(h.plans.planWrites, 1);
      final plan = (await h.plans.loadPlan(kUid))!;
      expect(plan.planVersion, 4);
      expect(plan.stepsGoal, 9500);
      expect(plan.reviewUndo!.prevStepsGoal, 8500);
      final review = (await h.plans.loadReview(kUid, kWeek))!;
      expect(review.decision, ReviewDecisionKind.adjustSteps);
      expect(review.deltaSteps, 1000);
      expect(review.basePlanVersion, 3);
      expect(review.classification, ReviewClass.behind);
    });

    test('shared ownership: the proposal is recorded, the plan stays', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan(ownership: PlanOwnership.shared));
      h.plans.seedReview(kUid, _previousBehind());
      await _behindWeights(h);
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.written);
      expect(h.plans.reviewWrites, 1);
      expect(h.plans.planWrites, 0);
      final plan = (await h.plans.loadPlan(kUid))!;
      expect(plan.planVersion, 3);
      expect(plan.stepsGoal, 8500);
      expect((await h.plans.loadReview(kUid, kWeek))!.deltaSteps, 1000);
    });

    test('a hand-edited out-of-bounds plan is validated before the decision',
        () async {
      h = await makeHarness();
      h.plans.seedPlan(
          kUid, storedPlan(range: const KcalRange(900, 1000)));
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.written);
      expect((await h.plans.loadPlan(kUid))!.kcalRange,
          const KcalRange(1850, 1950));
    });
  });

  group('idempotency per ISO week', () {
    test('a second run in the same week writes nothing more', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      final first = await scheduler().run(ReviewTrigger.planSurfaceShown);
      final second = await scheduler().run(ReviewTrigger.scanDone);
      expect(first.status, ReviewRunStatus.written);
      expect(second.status, ReviewRunStatus.skipped);
      expect(second.reason, ReviewSkipReason.alreadyThisWeek);
      expect(h.plans.reviewWrites, 1);
    });

    test('the next ISO week reviews again', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      await scheduler().run(ReviewTrigger.planSurfaceShown);
      h.now = kNow.add(const Duration(days: 7));
      final next = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(next.status, ReviewRunStatus.written);
      expect(h.plans.reviewWrites, 2);
      expect(await h.plans.loadReview(kUid, '2026-W43'), isNotNull);
    });

    test('Sunday and Monday of the same week map to one review', () async {
      h = await makeHarness(now: DateTime(2026, 10, 18, 23, 30)); // Sunday W42
      h.plans.seedPlan(kUid, storedPlan());
      await scheduler().run(ReviewTrigger.planSurfaceShown);
      h.now = DateTime(2026, 10, 19, 0, 30); // Monday W43
      final monday = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(monday.status, ReviewRunStatus.written);
      expect(await h.plans.loadReview(kUid, '2026-W42'), isNotNull);
      expect(await h.plans.loadReview(kUid, '2026-W43'), isNotNull);
    });

    test('two simultaneous runs: one is in flight, exactly one review', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      final s = scheduler();
      final results = await Future.wait([
        s.run(ReviewTrigger.planSurfaceShown),
        s.run(ReviewTrigger.scanDone),
      ]);
      expect(results[0].status, ReviewRunStatus.written);
      expect(results[1].reason, ReviewSkipReason.inFlight);
      expect(h.plans.reviewWrites, 1);
    });

    test('a new day in the same week with a stored review stays a no-op',
        () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      h.plans.seedReview(
          kUid, PlanReviewRecord.fromDecision(kWeek, keepDecision(), kNow));
      h.now = kNow.add(const Duration(days: 2));
      final r = await scheduler().run(ReviewTrigger.appForeground);
      expect(r.status, ReviewRunStatus.alreadyReviewed);
      expect(h.plans.reviewWrites, 0);
    });
  });

  group('scan-done trigger', () {
    test('bumping the signal runs the review once; a repeat is a no-op', () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      h.container.read(weeklyReviewTriggersProvider);
      h.container.read(scanDoneSignalProvider.notifier).state++;
      await pumpEventQueue();
      expect(h.plans.reviewWrites, 1);
      h.container.read(scanDoneSignalProvider.notifier).state++;
      await pumpEventQueue();
      expect(h.plans.reviewWrites, 1);
    });

    test('for a not-eligible user the signal writes nothing', () async {
      h = await makeHarness(profile: eligibleProfile(flags: const HealthFlags()));
      h.plans.seedPlan(kUid, storedPlan());
      h.container.read(weeklyReviewTriggersProvider);
      h.container.read(scanDoneSignalProvider.notifier).state++;
      await pumpEventQueue();
      expectNothingWritten(h);
    });
  });

  group('failure containment', () {
    test('a repository error is reported as failed, never thrown', () async {
      h = await makeHarness(planRepository: _ThrowingPlans());
      final r = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(r.status, ReviewRunStatus.failed);
      expectNothingWritten(h);
      // The scheduler is usable again afterwards (the in-flight flag is reset).
      final again = await scheduler().run(ReviewTrigger.planSurfaceShown);
      expect(again.status, ReviewRunStatus.failed);
    });
  });
}
