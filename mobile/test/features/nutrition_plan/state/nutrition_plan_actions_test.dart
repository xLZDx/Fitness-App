// C18 nutrition_plan_actions_test. The REAL NutritionPlanActions over the real
// providers: every write requires an eligible device-local verdict (D-55), is
// fenced by the account-deletion flag, is version-checked (a concurrent device
// is a conflict, never an overwrite), and is re-validated against the
// recomputed bounds. Write counters prove "nothing written" on every refusal.
import 'package:fitness_app/features/nutrition_plan/data/in_memory_nutrition_repositories.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_repository.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_plan_actions.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';
import '../plan_state_harness.dart';

/// Simulates another device writing between this device's read and write.
class _RacingPlans extends InMemoryPlanRepository {
  _RacingPlans(this.races);

  int races;

  @override
  Future<PlanWriteResult> savePlan(
    String uid,
    StoredNutritionPlan plan, {
    required int? expectedVersion,
  }) async {
    if (races > 0) {
      races--;
      final cur = (await loadPlan(uid))!;
      seedPlan(uid, cur.copyWith(planVersion: cur.planVersion + 1));
    }
    return super.savePlan(uid, plan, expectedVersion: expectedVersion);
  }
}

PlanReviewRecord _proposal(
  WeeklyReviewDecision d,
) =>
    PlanReviewRecord.fromDecision(kWeek, d, kNow);

void main() {
  late PlanHarness h;
  tearDown(() => h.dispose());

  NutritionPlanActions actions() =>
      h.container.read(nutritionPlanActionsProvider);

  group('gates: nothing is written for anyone who may not', () {
    test('signed out', () async {
      h = await makeHarness(uid: null);
      h.plans.seedPlan(kUid, storedPlan());
      for (final r in [
        await actions().ensurePlan(),
        await actions().setKcalRange(const KcalRange(2000, 2100)),
        await actions().setStepsGoal(9000),
        await actions().setOwnership(PlanOwnership.manual),
        await actions().setAutoAdjust(AutoAdjust.off),
        await actions().undoLastReview(),
      ]) {
        expect(r.status, PlanActionStatus.signedOut);
      }
      expect(h.plans.planWrites, 0);
    });

    test('account being deleted behaves as signed out', () async {
      h = await makeHarness(deletingUid: kUid);
      h.plans.seedPlan(kUid, storedPlan());
      expect((await actions().setStepsGoal(9000)).status,
          PlanActionStatus.signedOut);
      expect(h.plans.planWrites, 0);
    });

    test('not eligible (safety question unanswered): every action refuses',
        () async {
      h = await makeHarness(
          profile: eligibleProfile(flags: const HealthFlags()));
      h.plans.seedPlan(kUid, storedPlan());
      for (final r in [
        await actions().ensurePlan(),
        await actions().setKcalRange(const KcalRange(2000, 2100)),
        await actions().setStepsGoal(9000),
        await actions().setOwnership(PlanOwnership.manual),
        await actions().setAutoAdjust(AutoAdjust.off),
        await actions().acceptProposal(_proposal(decisionOf(
            application: ReviewApplication.proposed))),
        await actions().undoLastReview(),
      ]) {
        expect(r.status, PlanActionStatus.notEligible);
      }
      expect(h.plans.planWrites, 0);
    });

    test('referProfessional (guidance reported): no plan is created', () async {
      h = await makeHarness(
        profile: eligibleProfile(
          flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.reported,
            professionalGuidance: ProfessionalGuidanceNeed.none,
          ),
        ),
      );
      final r = await actions().ensurePlan();
      expect(r.status, PlanActionStatus.notEligible);
      expect(await h.plans.loadPlan(kUid), isNull);
      expect(h.plans.planWrites, 0);
    });

    test('an under-18 profile never gets a plan', () async {
      h = await makeHarness(profile: eligibleProfile(birthYear: 2010));
      expect((await actions().ensurePlan()).status, PlanActionStatus.notEligible);
      expect(h.plans.planWrites, 0);
    });

    test('an unknown verdict (profile not loaded) fails closed', () async {
      h = await makeHarness(seedEligibleDefaultProfile: false);
      expect((await actions().ensurePlan()).status, PlanActionStatus.notEligible);
      expect(h.plans.planWrites, 0);
    });
  });

  group('ensurePlan', () {
    test('creates version 1 from the profile for an eligible user', () async {
      h = await makeHarness();
      final r = await actions().ensurePlan();
      expect(r.status, PlanActionStatus.saved);
      final p = r.plan!;
      expect(p.planVersion, 1);
      expect(p.ownership, PlanOwnership.coached);
      expect(p.goal, GoalDirection.lose);
      expect(p.digest.weightKg, 80);
      expect(p.digest.heightCm, 180);
      expect(p.digest.sexBasis, SexBasis.male);
      expect(p.kcalBounds, p.recomputeBounds());
      expect(p.kcalBounds.contains(p.kcalRange), isTrue);
      expect(p.driftFromInitialKcal, 0);
      expect(p.lastKcalAdjustAt, isNull);
      expect(p.reviewUndo, isNull);
      expect(p.computedAt, kNow);
      expect(h.plans.planWrites, 1);
      expect((await h.plans.loadPlan(kUid))!.planVersion, 1);
    });

    test('the profile ownership choice is honoured', () async {
      h = await makeHarness(
          profile: eligibleProfile(ownership: PlanOwnership.manual));
      final r = await actions().ensurePlan();
      expect(r.plan!.ownership, PlanOwnership.manual);
    });

    test('an existing plan is returned untouched and nothing is written',
        () async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan(version: 6, stepsGoal: 11000));
      final r = await actions().ensurePlan();
      expect(r.status, PlanActionStatus.saved);
      expect(r.plan!.planVersion, 6);
      expect(r.plan!.stepsGoal, 11000);
      expect(h.plans.planWrites, 0);
    });

    test('calling it twice creates exactly one plan', () async {
      h = await makeHarness();
      await actions().ensurePlan();
      await actions().ensurePlan();
      expect(h.plans.planWrites, 1);
      expect((await h.plans.loadPlan(kUid))!.planVersion, 1);
    });

    test('offline: reports offline and creates nothing', () async {
      h = await makeHarness();
      h.plans.offline = true;
      final r = await actions().ensurePlan();
      expect(r.status, PlanActionStatus.offline);
      h.plans.offline = false;
      expect(await h.plans.loadPlan(kUid), isNull);
    });
  });

  group('setKcalRange', () {
    setUp(() async {
      h = await makeHarness();
    });

    test('a coached edit saves the range and flips ownership to shared',
        () async {
      h.plans.seedPlan(kUid, storedPlan());
      final r = await actions().setKcalRange(const KcalRange(2050, 2250));
      expect(r.status, PlanActionStatus.saved);
      expect(r.plan!.kcalRange, const KcalRange(2050, 2250));
      expect(r.plan!.ownership, PlanOwnership.shared);
      expect(r.plan!.planVersion, 4);
      final expected = macrosOf(const KcalRange(2050, 2250));
      expect(r.plan!.carbs.maxG, expected.carbs.maxG);
      expect(r.plan!.protein.maxG, expected.protein.maxG);
    });

    test('shared and manual keep their ownership', () async {
      for (final o in [PlanOwnership.shared, PlanOwnership.manual]) {
        h.plans.seedPlan(kUid, storedPlan(ownership: o));
        final r = await actions().setKcalRange(const KcalRange(2050, 2250));
        expect(r.plan!.ownership, o);
        h.plans.seedPlan(kUid, storedPlan(ownership: o));
      }
    });

    test('a range below the bounds is clamped to 1850..1950', () async {
      h.plans.seedPlan(kUid, storedPlan());
      final r = await actions().setKcalRange(const KcalRange(1000, 1100));
      expect(r.plan!.kcalRange, const KcalRange(1850, 1950));
      expect(r.plan!.kcalBounds, kLoseBounds);
    });

    test('a range above the bounds is clamped to 2300..2400', () async {
      h.plans.seedPlan(kUid, storedPlan());
      final r = await actions().setKcalRange(const KcalRange(3000, 3300));
      expect(r.plan!.kcalRange, const KcalRange(2300, 2400));
    });

    test('a too-wide range is narrowed to 400 kcal', () async {
      h.plans.seedPlan(kUid, storedPlan());
      final r = await actions().setKcalRange(const KcalRange(1900, 2400));
      expect(r.plan!.kcalRange.width, 400);
    });

    test('no plan -> noPlan, nothing written', () async {
      final r = await actions().setKcalRange(const KcalRange(2000, 2100));
      expect(r.status, PlanActionStatus.noPlan);
      expect(h.plans.planWrites, 0);
    });

    test('another device wrote in between: one retry succeeds', () async {
      final racing = _RacingPlans(1);
      h.dispose();
      h = await makeHarness(planRepository: racing);
      racing.seedPlan(kUid, storedPlan(version: 3));
      final r = await actions().setKcalRange(const KcalRange(2050, 2250));
      expect(r.status, PlanActionStatus.saved);
      expect(r.plan!.planVersion, 5,
          reason: 'built on the other device version 4, never overwritten');
    });

    test('a device that keeps losing the race reports conflict, no overwrite',
        () async {
      final racing = _RacingPlans(5);
      h.dispose();
      h = await makeHarness(planRepository: racing);
      racing.seedPlan(kUid, storedPlan(version: 3));
      final r = await actions().setKcalRange(const KcalRange(2050, 2250));
      expect(r.status, PlanActionStatus.conflict);
      expect(racing.planWrites, 0);
      expect((await racing.loadPlan(kUid))!.kcalRange,
          const KcalRange(2000, 2200));
    });

    test('offline reports offline and changes nothing', () async {
      h.plans.seedPlan(kUid, storedPlan());
      h.plans.offline = true;
      final r = await actions().setKcalRange(const KcalRange(2050, 2250));
      expect(r.status, PlanActionStatus.offline);
      h.plans.offline = false;
      expect((await h.plans.loadPlan(kUid))!.planVersion, 3);
    });
  });

  group('steps, ownership and auto-adjust', () {
    setUp(() async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
    });

    test('steps are clamped to 2,000..30,000', () async {
      expect((await actions().setStepsGoal(100)).plan!.stepsGoal, 2000);
      expect((await actions().setStepsGoal(99999)).plan!.stepsGoal, 30000);
      expect((await actions().setStepsGoal(10250)).plan!.stepsGoal, 10250);
    });

    test('a steps edit keeps range and ownership, bumps the version', () async {
      final r = await actions().setStepsGoal(9000);
      expect(r.plan!.kcalRange, const KcalRange(2000, 2200));
      expect(r.plan!.ownership, PlanOwnership.coached);
      expect(r.plan!.planVersion, 4);
    });

    test('ownership changes never rewrite the current range', () async {
      final r = await actions().setOwnership(PlanOwnership.manual);
      expect(r.plan!.ownership, PlanOwnership.manual);
      expect(r.plan!.kcalRange, const KcalRange(2000, 2200));
      expect(r.plan!.stepsGoal, 8500);
    });

    test('auto-adjust toggles are stored as chosen', () async {
      final r = await actions()
          .setAutoAdjust(const AutoAdjust(steps: false, kcal: true));
      expect(r.plan!.autoAdjust.steps, isFalse);
      expect(r.plan!.autoAdjust.kcal, isTrue);
      final off = await actions().setAutoAdjust(AutoAdjust.off);
      expect(off.plan!.autoAdjust.kcal, isFalse);
      expect(off.plan!.planVersion, 5);
    });
  });

  group('acceptProposal (shared plans only)', () {
    setUp(() async {
      h = await makeHarness();
    });

    PlanReviewRecord kcal({int base = 3, int delta = -150}) => _proposal(
        decisionOf(
            base: base,
            deltaKcal: delta,
            application: ReviewApplication.proposed));

    test('applies the kcal change to the plan it was decided against', () async {
      h.plans.seedPlan(
          kUid, storedPlan(ownership: PlanOwnership.shared, drift: -100));
      final r = await actions().acceptProposal(kcal());
      expect(r.status, PlanActionStatus.saved);
      expect(r.plan!.kcalRange, const KcalRange(1850, 2050));
      expect(r.plan!.driftFromInitialKcal, -250);
      expect(r.plan!.planVersion, 4);
      expect(r.plan!.lastKcalAdjustAt, kNow);
      expect(r.plan!.reviewUndo, isNull,
          reason: 'only an automatic coached review has an undo');
      expect(r.plan!.ownership, PlanOwnership.shared);
    });

    test('applies a steps proposal', () async {
      h.plans.seedPlan(kUid, storedPlan(ownership: PlanOwnership.shared));
      final r = await actions().acceptProposal(_proposal(
          stepsDecision(application: ReviewApplication.proposed)));
      expect(r.plan!.stepsGoal, 9500);
      expect(r.plan!.kcalRange, const KcalRange(2000, 2200));
    });

    test('refused on a coached plan', () async {
      h.plans.seedPlan(kUid, storedPlan());
      expect((await actions().acceptProposal(kcal())).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused on a manual plan', () async {
      h.plans.seedPlan(kUid, storedPlan(ownership: PlanOwnership.manual));
      expect((await actions().acceptProposal(kcal())).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused when the plan moved on (version mismatch)', () async {
      h.plans.seedPlan(
          kUid, storedPlan(version: 4, ownership: PlanOwnership.shared));
      expect((await actions().acceptProposal(kcal(base: 3))).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused when the review proposes nothing (keep / needMoreData)',
        () async {
      h.plans.seedPlan(kUid, storedPlan(ownership: PlanOwnership.shared));
      expect((await actions().acceptProposal(_proposal(keepDecision()))).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused when the change would leave the bounds', () async {
      h.plans.seedPlan(
          kUid,
          storedPlan(
              ownership: PlanOwnership.shared,
              range: const KcalRange(1900, 2100)));
      expect((await actions().acceptProposal(kcal())).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused when the cumulative drift would pass 400 kcal', () async {
      h.plans.seedPlan(
          kUid, storedPlan(ownership: PlanOwnership.shared, drift: -300));
      expect((await actions().acceptProposal(kcal())).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 0);
    });

    test('refused when steps would pass 12,000', () async {
      h.plans.seedPlan(
          kUid,
          storedPlan(
              ownership: PlanOwnership.shared, stepsGoal: 11500));
      expect(
          (await actions().acceptProposal(_proposal(
                  stepsDecision(application: ReviewApplication.proposed))))
              .status,
          PlanActionStatus.refused);
    });

    test('no plan -> noPlan', () async {
      expect((await actions().acceptProposal(kcal())).status,
          PlanActionStatus.noPlan);
    });

    test('a second accept of the same proposal is refused (version moved)',
        () async {
      h.plans.seedPlan(kUid, storedPlan(ownership: PlanOwnership.shared));
      final proposal = kcal();
      expect((await actions().acceptProposal(proposal)).saved, isTrue);
      expect((await actions().acceptProposal(proposal)).status,
          PlanActionStatus.refused);
      expect(h.plans.planWrites, 1);
    });
  });

  group('undoLastReview', () {
    setUp(() async {
      h = await makeHarness();
      h.plans.seedPlan(kUid, storedPlan());
      await h.plans.applyReview(kUid,
          week: kWeek, decision: decisionOf(), now: kNow);
    });

    test('restores the pre-review plan within 7 days', () async {
      final r = await actions().undoLastReview();
      expect(r.status, PlanActionStatus.saved);
      expect(r.plan!.kcalRange, const KcalRange(2000, 2200));
      expect(r.plan!.planVersion, 5);
      expect(r.plan!.reviewUndo!.undone, isTrue);
    });

    test('a second undo is refused', () async {
      await actions().undoLastReview();
      expect((await actions().undoLastReview()).status,
          PlanActionStatus.refused);
    });

    test('after the 7-day window it is refused and nothing changes', () async {
      h.now = kNow.add(const Duration(days: 7));
      final r = await actions().undoLastReview();
      expect(r.status, PlanActionStatus.refused);
      expect((await h.plans.loadPlan(kUid))!.kcalRange,
          const KcalRange(1850, 2050));
    });

    test('offline reports offline', () async {
      h.plans.offline = true;
      expect((await actions().undoLastReview()).status,
          PlanActionStatus.offline);
    });

    test('without a plan -> noPlan', () async {
      final empty = await makeHarness();
      expect((await empty.container
                  .read(nutritionPlanActionsProvider)
                  .undoLastReview())
              .status,
          PlanActionStatus.noPlan);
      empty.dispose();
    });
  });
}
