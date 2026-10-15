// C18 in_memory_nutrition_repositories_test. The fakes run the SAME pure rules
// as the Firestore repositories, so these tests prove the repository contract:
// version-checked saves, ONE atomic review+plan write, idempotency per week
// (also under concurrent calls), the offline switch that writes nothing, and
// the weigh-in store with its 30..300 kg guard.
import 'dart:async';

import 'package:fitness_app/features/nutrition_plan/data/in_memory_nutrition_repositories.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_repository.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_review_record.dart';
import 'package:fitness_app/features/nutrition_plan/data/review_transaction.dart';
import 'package:fitness_app/features/nutrition_plan/data/stored_nutrition_plan.dart';
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';

void main() {
  group('InMemoryPlanRepository.savePlan', () {
    late InMemoryPlanRepository repo;
    setUp(() => repo = InMemoryPlanRepository());
    tearDown(() => repo.dispose());

    test('the first save (expectedVersion null) stores version 1', () async {
      final r = await repo.savePlan(kUid, storedPlan(version: 99),
          expectedVersion: null);
      expect(r.outcome, PlanWriteOutcome.saved);
      expect(r.plan!.planVersion, 1,
          reason: 'the repository owns the version, not the caller');
      expect((await repo.loadPlan(kUid))!.planVersion, 1);
      expect(repo.planWrites, 1);
    });

    test('a second "first" save conflicts and never overwrites', () async {
      await repo.savePlan(kUid, storedPlan(stepsGoal: 8000),
          expectedVersion: null);
      final r = await repo.savePlan(kUid, storedPlan(stepsGoal: 11000),
          expectedVersion: null);
      expect(r.outcome, PlanWriteOutcome.conflict);
      expect(r.plan, isNull);
      expect((await repo.loadPlan(kUid))!.stepsGoal, 8000);
      expect(repo.planWrites, 1);
    });

    test('a matching expectedVersion bumps by exactly one', () async {
      await repo.savePlan(kUid, storedPlan(), expectedVersion: null);
      final r =
          await repo.savePlan(kUid, storedPlan(stepsGoal: 9000), expectedVersion: 1);
      expect(r.outcome, PlanWriteOutcome.saved);
      expect(r.plan!.planVersion, 2);
      expect((await repo.loadPlan(kUid))!.stepsGoal, 9000);
    });

    test('a wrong expectedVersion conflicts and writes nothing', () async {
      await repo.savePlan(kUid, storedPlan(), expectedVersion: null);
      for (final wrong in [0, 2, 7]) {
        final r = await repo.savePlan(kUid, storedPlan(stepsGoal: 9999),
            expectedVersion: wrong);
        expect(r.outcome, PlanWriteOutcome.conflict, reason: 'expected=$wrong');
      }
      expect((await repo.loadPlan(kUid))!.stepsGoal, 8500);
      expect(repo.planWrites, 1);
    });

    test('expecting a version when no plan exists conflicts', () async {
      final r =
          await repo.savePlan(kUid, storedPlan(), expectedVersion: 1);
      expect(r.outcome, PlanWriteOutcome.conflict);
      expect(await repo.loadPlan(kUid), isNull);
    });

    test('offline: reports offline, stores nothing, counts nothing', () async {
      repo.offline = true;
      final r =
          await repo.savePlan(kUid, storedPlan(), expectedVersion: null);
      expect(r.outcome, PlanWriteOutcome.offline);
      expect(r.plan, isNull);
      expect(repo.planWrites, 0);
      repo.offline = false;
      expect(await repo.loadPlan(kUid), isNull);
    });

    test('the plan is validated on write: an out-of-bounds range is pulled in',
        () async {
      final r = await repo.savePlan(
          kUid, storedPlan(range: const KcalRange(900, 1000)),
          expectedVersion: null);
      expect(r.plan!.kcalRange, const KcalRange(1850, 1950));
      expect(r.plan!.kcalBounds, kLoseBounds);
    });

    test('the plan is validated on read as well (seeded raw document)', () async {
      repo.seedPlan(
          kUid,
          storedPlan(
              range: const KcalRange(900, 1000),
              bounds: const PlanBounds(1, 9999),
              stepsGoal: 1));
      final p = (await repo.loadPlan(kUid))!;
      expect(p.kcalRange, const KcalRange(1850, 1950));
      expect(p.kcalBounds, kLoseBounds);
      expect(p.stepsGoal, 2000);
    });

    test('plans are isolated per uid', () async {
      await repo.savePlan('a', storedPlan(), expectedVersion: null);
      expect(await repo.loadPlan('b'), isNull);
    });
  });

  group('InMemoryPlanRepository.applyReview: atomic review + plan', () {
    late InMemoryPlanRepository repo;
    setUp(() {
      repo = InMemoryPlanRepository()..seedPlan(kUid, storedPlan());
    });
    tearDown(() => repo.dispose());

    Future<ReviewApplyResult> apply(WeeklyReviewDecision d,
            {String week = kWeek}) =>
        repo.applyReview(kUid, week: week, decision: d, now: kNow);

    test('a coached change writes the review AND the plan, once each', () async {
      final r = await apply(decisionOf());
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 1);
      final plan = (await repo.loadPlan(kUid))!;
      expect(plan.planVersion, 4);
      expect(plan.kcalRange, const KcalRange(1850, 2050));
      expect(plan.reviewUndo, isNotNull);
      final review = (await repo.loadReview(kUid, kWeek))!;
      expect(review.basePlanVersion, 3);
      expect(review.deltaKcal, -150);
    });

    test('a keep decision writes the review only', () async {
      final r = await apply(keepDecision());
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 0);
      expect((await repo.loadPlan(kUid))!.planVersion, 3);
    });

    test('a stale decision stores NEITHER document', () async {
      final r = await apply(decisionOf(base: 2));
      expect(r.outcome, ReviewApplyOutcome.staleVersion);
      expect(repo.reviewWrites, 0);
      expect(repo.planWrites, 0);
      expect(await repo.loadReview(kUid, kWeek), isNull);
      expect((await repo.loadPlan(kUid))!.planVersion, 3);
    });

    test('a refused re-check (cooldown) stores NEITHER document', () async {
      repo.seedPlan(kUid,
          storedPlan(lastAdjust: kNow.subtract(const Duration(days: 2))));
      final r = await apply(decisionOf());
      expect(r.outcome, ReviewApplyOutcome.rejected);
      expect(repo.reviewWrites, 0);
      expect(repo.planWrites, 0);
      expect(await repo.loadReview(kUid, kWeek), isNull);
    });

    test('no plan: noPlan and no review document is created', () async {
      final empty = InMemoryPlanRepository();
      final r = await empty.applyReview(kUid,
          week: kWeek, decision: decisionOf(), now: kNow);
      expect(r.outcome, ReviewApplyOutcome.noPlan);
      expect(empty.reviewWrites, 0);
      expect(await empty.loadReview(kUid, kWeek), isNull);
      empty.dispose();
    });

    test('the same week twice: the second call is alreadyReviewed and writes nothing',
        () async {
      await apply(decisionOf());
      final again = await apply(decisionOf(base: 4));
      expect(again.outcome, ReviewApplyOutcome.alreadyReviewed);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 1);
      expect((await repo.loadPlan(kUid))!.planVersion, 4);
    });

    test('offline: nothing is written and nothing is queued', () async {
      repo.offline = true;
      final r = await apply(decisionOf());
      expect(r.outcome, ReviewApplyOutcome.offline);
      expect(repo.reviewWrites, 0);
      expect(repo.planWrites, 0);
      repo.offline = false;
      expect(await repo.loadReview(kUid, kWeek), isNull);
      // Back online the very same review can still be applied (not poisoned).
      expect((await apply(decisionOf())).outcome, ReviewApplyOutcome.written);
    });

    test('shared ownership: the review is stored, the plan is untouched',
        () async {
      repo.seedPlan(kUid, storedPlan(ownership: PlanOwnership.shared));
      final r = await apply(decisionOf(application: ReviewApplication.proposed));
      expect(r.outcome, ReviewApplyOutcome.written);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 0);
      expect((await repo.loadPlan(kUid))!.kcalRange, const KcalRange(2000, 2200));
    });
  });

  group('concurrent reviews are idempotent (D-57)', () {
    late InMemoryPlanRepository repo;
    setUp(() {
      repo = InMemoryPlanRepository()..seedPlan(kUid, storedPlan());
    });
    tearDown(() => repo.dispose());

    test('two devices review the SAME week at once: exactly one applies', () async {
      final results = await Future.wait([
        repo.applyReview(kUid, week: kWeek, decision: decisionOf(), now: kNow),
        repo.applyReview(kUid,
            week: kWeek, decision: decisionOf(), now: kNow),
      ]);
      final outcomes = results.map((r) => r.outcome).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(outcomes, [
        ReviewApplyOutcome.written,
        ReviewApplyOutcome.alreadyReviewed,
      ]);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 1);
      final plan = (await repo.loadPlan(kUid))!;
      expect(plan.planVersion, 4, reason: 'adjusted once, not twice');
      expect(plan.kcalRange, const KcalRange(1850, 2050));
      expect(plan.driftFromInitialKcal, -150);
    });

    test('five concurrent calls: one write, four alreadyReviewed', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          repo.applyReview(kUid,
              week: kWeek, decision: decisionOf(), now: kNow),
      ]);
      expect(
          results.where((r) => r.outcome == ReviewApplyOutcome.written).length,
          1);
      expect(
          results
              .where((r) => r.outcome == ReviewApplyOutcome.alreadyReviewed)
              .length,
          4);
      expect((await repo.loadPlan(kUid))!.planVersion, 4);
    });

    test('two DIFFERENT weeks decided from the same plan version: the second is stale',
        () async {
      // Two devices in different timezones compute different week keys from
      // the same plan version 3. Only one may change the plan.
      final results = await Future.wait([
        repo.applyReview(kUid,
            week: '2026-W42', decision: decisionOf(), now: kNow),
        repo.applyReview(kUid,
            week: '2026-W43', decision: decisionOf(), now: kNow),
      ]);
      expect(results[0].outcome, ReviewApplyOutcome.written);
      expect(results[1].outcome, ReviewApplyOutcome.staleVersion);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 1);
      expect(await repo.loadReview(kUid, '2026-W43'), isNull,
          reason: 'a stale decision leaves no review behind');
      expect((await repo.loadPlan(kUid))!.kcalRange, const KcalRange(1850, 2050));
    });

    test('different weeks decided from a fresh version: the cooldown, not the key, stops a second change',
        () async {
      await repo.applyReview(kUid,
          week: '2026-W42', decision: decisionOf(), now: kNow);
      final next = await repo.applyReview(kUid,
          week: '2026-W43',
          decision: decisionOf(base: 4, deltaKcal: 150),
          now: kNow.add(const Duration(days: 7)));
      expect(next.outcome, ReviewApplyOutcome.rejected);
      expect((await repo.loadPlan(kUid))!.planVersion, 4);
      expect(repo.reviewWrites, 1);
    });

    test('concurrent offline and online repositories never half-write', () async {
      repo.offline = true;
      final off = await repo.applyReview(kUid,
          week: kWeek, decision: decisionOf(), now: kNow);
      repo.offline = false;
      final on = await repo.applyReview(kUid,
          week: kWeek, decision: decisionOf(), now: kNow);
      expect(off.outcome, ReviewApplyOutcome.offline);
      expect(on.outcome, ReviewApplyOutcome.written);
      expect(repo.reviewWrites, 1);
      expect(repo.planWrites, 1);
    });
  });

  group('InMemoryPlanRepository.undoLastReview', () {
    late InMemoryPlanRepository repo;
    setUp(() async {
      repo = InMemoryPlanRepository()..seedPlan(kUid, storedPlan());
      await repo.applyReview(kUid,
          week: kWeek, decision: decisionOf(), now: kNow);
    });
    tearDown(() => repo.dispose());

    test('restores the previous plan values and bumps the version', () async {
      final r = await repo.undoLastReview(kUid,
          expectedVersion: 4, now: kNow.add(const Duration(days: 1)));
      expect(r.outcome, UndoOutcome.undone);
      final p = (await repo.loadPlan(kUid))!;
      expect(p.planVersion, 5);
      expect(p.kcalRange, const KcalRange(2000, 2200));
      expect(p.reviewUndo!.undone, isTrue);
      expect(repo.planWrites, 2);
    });

    test('a stale version, an expired window and a second undo write nothing',
        () async {
      expect(
          (await repo.undoLastReview(kUid, expectedVersion: 3, now: kNow))
              .outcome,
          UndoOutcome.staleVersion);
      expect(
          (await repo.undoLastReview(kUid,
                  expectedVersion: 4, now: kNow.add(const Duration(days: 8))))
              .outcome,
          UndoOutcome.notAvailable);
      await repo.undoLastReview(kUid, expectedVersion: 4, now: kNow);
      expect(
          (await repo.undoLastReview(kUid, expectedVersion: 5, now: kNow))
              .outcome,
          UndoOutcome.notAvailable);
      expect(repo.planWrites, 2);
    });

    test('offline: reports offline and keeps the plan', () async {
      repo.offline = true;
      final r = await repo.undoLastReview(kUid, expectedVersion: 4, now: kNow);
      expect(r.outcome, UndoOutcome.offline);
      repo.offline = false;
      expect((await repo.loadPlan(kUid))!.planVersion, 4);
    });

    test('no plan at all reports noPlan', () async {
      final empty = InMemoryPlanRepository();
      expect(
          (await empty.undoLastReview(kUid, expectedVersion: 1, now: kNow))
              .outcome,
          UndoOutcome.noPlan);
      empty.dispose();
    });
  });

  group('InMemoryPlanRepository: reviews and streams', () {
    late InMemoryPlanRepository repo;
    setUp(() => repo = InMemoryPlanRepository());
    tearDown(() => repo.dispose());

    test('loadRecentReviews is newest-week-first and honours the limit', () async {
      for (final w in ['2026-W38', '2026-W41', '2026-W40', '2026-W39']) {
        repo.seedReview(kUid, _reviewFor(w));
      }
      final two = await repo.loadRecentReviews(kUid, limit: 2);
      expect(two.map((r) => r.week), ['2026-W41', '2026-W40']);
      final all = await repo.loadRecentReviews(kUid);
      expect(all.map((r) => r.week),
          ['2026-W41', '2026-W40', '2026-W39', '2026-W38']);
    });

    test('loadReview returns null for an unknown week', () async {
      expect(await repo.loadReview(kUid, '2026-W01'), isNull);
    });

    test('watchPlan replays the current value, then every change', () async {
      final seen = <int?>[];
      final sub =
          repo.watchPlan(kUid).listen((p) => seen.add(p?.planVersion));
      await pumpEventQueue();
      expect(seen, [null]);
      await repo.savePlan(kUid, storedPlan(), expectedVersion: null);
      await pumpEventQueue();
      await repo.savePlan(kUid, storedPlan(), expectedVersion: 1);
      await pumpEventQueue();
      expect(seen, [null, 1, 2]);
      unawaited(sub.cancel()); // async* waits for its next event; never await it
    });

    test('watchPlan emits nothing for a refused write', () async {
      await repo.savePlan(kUid, storedPlan(), expectedVersion: null);
      final seen = <int?>[];
      final sub =
          repo.watchPlan(kUid).listen((p) => seen.add(p?.planVersion));
      await pumpEventQueue();
      await repo.savePlan(kUid, storedPlan(), expectedVersion: 5); // conflict
      await pumpEventQueue();
      expect(seen, [1]);
      unawaited(sub.cancel()); // async* waits for its next event; never await it
    });

    test('watchReviews emits the new review after applyReview', () async {
      repo.seedPlan(kUid, storedPlan());
      final seen = <int>[];
      final sub =
          repo.watchReviews(kUid).listen((r) => seen.add(r.length));
      await pumpEventQueue();
      await repo.applyReview(kUid,
          week: kWeek, decision: keepDecision(), now: kNow);
      await pumpEventQueue();
      expect(seen, [0, 1]);
      unawaited(sub.cancel()); // async* waits for its next event; never await it
    });
  });

  group('InMemoryWeightRepository', () {
    late InMemoryWeightRepository repo;
    late DateTime clock;
    setUp(() {
      clock = kNow;
      repo = InMemoryWeightRepository(clock: () => clock);
    });
    tearDown(() => repo.dispose());

    WeightEntry w(int daysAgo, double kg,
            {WeightSource source = WeightSource.manual}) =>
        WeightEntry(
            at: DateTime(2026, 10, 15, 8).subtract(Duration(days: daysAgo)),
            kg: kg,
            source: source);

    test('put stores a day-keyed entry; the id is the day key', () async {
      await repo.put(kUid, w(0, 80));
      final log = await repo.loadLog(kUid);
      expect(log.single.id, '2026-10-15');
      expect(log.single.entry.kg, 80);
    });

    test('put on the same day replaces (one entry per day)', () async {
      await repo.put(kUid, w(0, 80));
      await repo.put(kUid, w(0, 79.4, source: WeightSource.scan));
      final log = await repo.loadLog(kUid);
      expect(log, hasLength(1));
      expect(log.single.entry.kg, 79.4);
      expect(log.single.entry.source, WeightSource.scan);
    });

    test('the log is oldest-first', () async {
      await repo.put(kUid, w(0, 80));
      await repo.put(kUid, w(5, 81));
      await repo.put(kUid, w(2, 80.5));
      expect((await repo.loadLog(kUid)).map((i) => i.id),
          ['2026-10-10', '2026-10-13', '2026-10-15']);
    });

    test('the default window is 60 days; older entries are excluded', () async {
      await repo.put(kUid, w(59, 85));
      await repo.put(kUid, w(61, 90));
      final log = await repo.loadLog(kUid);
      expect(log.map((i) => i.entry.kg), [85]);
      expect(await repo.loadLog(kUid, days: 30), isEmpty);
      expect(await repo.loadLog(kUid, days: 100), hasLength(2));
    });

    test('replace on the same day edits in place', () async {
      await repo.put(kUid, w(0, 80));
      await repo.replace(kUid, oldId: '2026-10-15', entry: w(0, 79));
      final log = await repo.loadLog(kUid);
      expect(log, hasLength(1));
      expect(log.single.entry.kg, 79);
    });

    test('replace that moves the day removes the old entry', () async {
      await repo.put(kUid, w(0, 80));
      await repo.replace(kUid, oldId: '2026-10-15', entry: w(3, 80.2));
      final log = await repo.loadLog(kUid);
      expect(log.map((i) => i.id), ['2026-10-12']);
    });

    test('replace onto an occupied day overwrites that day', () async {
      await repo.put(kUid, w(0, 80));
      await repo.put(kUid, w(3, 81));
      await repo.replace(kUid, oldId: '2026-10-15', entry: w(3, 79));
      final log = await repo.loadLog(kUid);
      expect(log.map((i) => '${i.id}:${i.entry.kg}'), ['2026-10-12:79.0']);
    });

    test('delete removes only that id; deleting an unknown id is harmless',
        () async {
      await repo.put(kUid, w(0, 80));
      await repo.put(kUid, w(1, 81));
      await repo.delete(kUid, '2026-10-15');
      await repo.delete(kUid, 'nope');
      expect((await repo.loadLog(kUid)).map((i) => i.id), ['2026-10-14']);
    });

    test('entryForDay finds a stored day and null otherwise', () async {
      await repo.put(kUid, w(0, 80));
      expect((await repo.entryForDay(kUid, '2026-10-15'))!.entry.kg, 80);
      expect(await repo.entryForDay(kUid, '2026-10-14'), isNull);
    });

    test('data is isolated per uid', () async {
      await repo.put('a', w(0, 80));
      expect(await repo.loadLog('b'), isEmpty);
    });

    test('30 and 300 kg are accepted', () async {
      await repo.put(kUid, w(0, 30));
      await repo.put(kUid, w(1, 300));
      expect(await repo.loadLog(kUid), hasLength(2));
    });

    for (final bad in [29.9, 300.1, 0.0, -5.0, double.nan, double.infinity]) {
      test('put of $bad kg throws ArgumentError and stores nothing', () async {
        await repo.put(kUid, w(1, 80));
        await expectLater(repo.put(kUid, w(0, bad)), throwsArgumentError);
        expect(await repo.loadLog(kUid), hasLength(1));
      });
    }

    test('replace with an invalid weight throws and keeps the original', () async {
      await repo.put(kUid, w(0, 80));
      await expectLater(
          repo.replace(kUid, oldId: '2026-10-15', entry: w(3, 29)),
          throwsArgumentError);
      final log = await repo.loadLog(kUid);
      expect(log.single.id, '2026-10-15');
      expect(log.single.entry.kg, 80);
    });

    test('watchLog replays the log, then every change', () async {
      final seen = <int>[];
      final sub = repo.watchLog(kUid).listen((l) => seen.add(l.length));
      await pumpEventQueue();
      await repo.put(kUid, w(0, 80));
      await pumpEventQueue();
      await repo.delete(kUid, '2026-10-15');
      await pumpEventQueue();
      expect(seen, [0, 1, 0]);
      unawaited(sub.cancel()); // async* waits for its next event; never await it
    });
  });
}

/// A minimal stored review for ordering tests.
PlanReviewRecord _reviewFor(String week) =>
    PlanReviewRecord.fromDecision(week, keepDecision(), kNow);
