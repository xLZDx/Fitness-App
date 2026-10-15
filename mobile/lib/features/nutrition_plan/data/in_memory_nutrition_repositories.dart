/// In-memory fakes of [NutritionPlanRepository] and [WeightEntriesRepository]
/// for tests and the unwired default. They run the SAME pure rules as the
/// Firestore implementations (`review_transaction.dart`, `validated()`), so a
/// fake-backed test exercises the real transaction decisions. No latency, no
/// Flutter imports.
library;

import 'dart:async';

import 'plan_repository.dart';
import 'plan_review_record.dart';
import 'review_transaction.dart';
import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';
import 'weight_entry.dart';
import 'weight_repository.dart';

/// Replays the current value, then every change.
Stream<T> _watch<T>(StreamController<void> changes, T Function() read) async* {
  yield read();
  await for (final _ in changes.stream) {
    yield read();
  }
}

class InMemoryPlanRepository implements NutritionPlanRepository {
  final Map<String, StoredNutritionPlan> _plans = {};
  final Map<String, Map<String, PlanReviewRecord>> _reviews = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Test hook: when true every transaction reports `offline` and writes
  /// nothing.
  bool offline = false;

  /// Counts of successful writes, for "wrote nothing" assertions.
  int planWrites = 0;
  int reviewWrites = 0;

  void _notify() => _changes.add(null);

  StoredNutritionPlan? _read(String uid) => _plans[uid]?.validated();

  @override
  Stream<StoredNutritionPlan?> watchPlan(String uid) =>
      _watch(_changes, () => _read(uid));

  @override
  Future<StoredNutritionPlan?> loadPlan(String uid) async => _read(uid);

  @override
  Future<PlanWriteResult> savePlan(
    String uid,
    StoredNutritionPlan plan, {
    required int? expectedVersion,
  }) async {
    if (offline) return const PlanWriteResult(PlanWriteOutcome.offline);
    if (_plans[uid]?.planVersion != expectedVersion) {
      return const PlanWriteResult(PlanWriteOutcome.conflict);
    }
    final next =
        plan.copyWith(planVersion: (expectedVersion ?? 0) + 1).validated();
    _plans[uid] = next;
    planWrites++;
    _notify();
    return PlanWriteResult(PlanWriteOutcome.saved, plan: next);
  }

  @override
  Future<ReviewApplyResult> applyReview(
    String uid, {
    required String week,
    required WeeklyReviewDecision decision,
    required DateTime now,
  }) async {
    if (offline) return const ReviewApplyResult(ReviewApplyOutcome.offline);
    final r = planReviewTransaction(
      week: week,
      decision: decision,
      existingReview: _reviews[uid]?[week],
      currentPlan: _plans[uid],
      now: now,
    );
    if (r.outcome != ReviewApplyOutcome.written) {
      return ReviewApplyResult(r.outcome);
    }
    (_reviews[uid] ??= {})[week] = r.review!;
    reviewWrites++;
    if (r.plan != null) {
      _plans[uid] = r.plan!;
      planWrites++;
    }
    _notify();
    return ReviewApplyResult(
      ReviewApplyOutcome.written,
      review: r.review,
      plan: r.plan,
    );
  }

  @override
  Future<UndoResult> undoLastReview(
    String uid, {
    required int expectedVersion,
    required DateTime now,
  }) async {
    if (offline) return const UndoResult(UndoOutcome.offline);
    final r = planUndoTransaction(
      currentPlan: _plans[uid],
      expectedVersion: expectedVersion,
      now: now,
    );
    if (r.outcome == UndoOutcome.undone) {
      _plans[uid] = r.plan!;
      planWrites++;
      _notify();
    }
    return UndoResult(r.outcome, plan: r.plan);
  }

  List<PlanReviewRecord> _recent(String uid, int limit) {
    final all = (_reviews[uid] ?? const <String, PlanReviewRecord>{})
        .values
        .toList()
      ..sort((a, b) => b.week.compareTo(a.week));
    return all.take(limit).toList();
  }

  @override
  Stream<List<PlanReviewRecord>> watchReviews(String uid, {int limit = 12}) =>
      _watch(_changes, () => _recent(uid, limit));

  @override
  Future<List<PlanReviewRecord>> loadRecentReviews(String uid,
          {int limit = 12}) async =>
      _recent(uid, limit);

  @override
  Future<PlanReviewRecord?> loadReview(String uid, String week) async =>
      _reviews[uid]?[week];

  /// Test seed: stores [plan] as is (no version rules).
  void seedPlan(String uid, StoredNutritionPlan plan) {
    _plans[uid] = plan;
    _notify();
  }

  /// Test seed: stores [review] as is.
  void seedReview(String uid, PlanReviewRecord review) {
    (_reviews[uid] ??= {})[review.week] = review;
    _notify();
  }

  void dispose() => _changes.close();
}

class InMemoryWeightRepository implements WeightEntriesRepository {
  InMemoryWeightRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, Map<String, WeightEntry>> _store = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<WeightLogItem> _log(String uid, int days) {
    final since = _clock().subtract(Duration(days: days));
    final items = [
      for (final e in (_store[uid] ?? const <String, WeightEntry>{}).entries)
        if (!e.value.at.isBefore(since))
          WeightLogItem(id: e.key, entry: e.value),
    ]..sort((a, b) => a.entry.at.compareTo(b.entry.at));
    return items;
  }

  @override
  Stream<List<WeightLogItem>> watchLog(String uid, {int days = 60}) =>
      _watch(_changes, () => _log(uid, days));

  @override
  Future<List<WeightLogItem>> loadLog(String uid, {int days = 60}) async =>
      _log(uid, days);

  @override
  Future<WeightLogItem?> entryForDay(String uid, String dayKey) async {
    final e = _store[uid]?[dayKey];
    return e == null ? null : WeightLogItem(id: dayKey, entry: e);
  }

  static void _check(WeightEntry e) {
    if (!WeightEntry.isValidKg(e.kg)) {
      throw ArgumentError.value(e.kg, 'kg', 'must be within 30..300');
    }
  }

  @override
  Future<void> put(String uid, WeightEntry entry) async {
    _check(entry);
    (_store[uid] ??= {})[entry.dayKey] = entry;
    _changes.add(null);
  }

  @override
  Future<void> replace(
    String uid, {
    required String oldId,
    required WeightEntry entry,
  }) async {
    _check(entry);
    final m = _store[uid] ??= {};
    if (oldId != entry.dayKey) m.remove(oldId);
    m[entry.dayKey] = entry;
    _changes.add(null);
  }

  @override
  Future<void> delete(String uid, String id) async {
    _store[uid]?.remove(id);
    _changes.add(null);
  }

  void dispose() => _changes.close();
}
