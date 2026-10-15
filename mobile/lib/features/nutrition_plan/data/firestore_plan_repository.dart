// Firestore implementation of [NutritionPlanRepository]. Reads/writes
//   /users/{uid}/nutrition_plan/main
//   /users/{uid}/nutrition_plan_reviews/{yyyy-Www}
// matching the shapes the rules of `firestore.rules` accept (design s5.4/5.5).
// The decisions live in `review_transaction.dart`; this file only moves
// documents and maps Firestore `Timestamp`s to `DateTime`s.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'plan_repository.dart';
import 'plan_review_record.dart';
import 'review_transaction.dart';
import 'stored_nutrition_plan.dart';
import 'weekly_review.dart';

class FirestorePlanRepository implements NutritionPlanRepository {
  FirestorePlanRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _plan(String uid) =>
      _db.collection('users').doc(uid).collection('nutrition_plan').doc('main');

  CollectionReference<Map<String, dynamic>> _reviews(String uid) =>
      _db.collection('users').doc(uid).collection('nutrition_plan_reviews');

  static Object _timestamp(DateTime t) => Timestamp.fromDate(t);

  /// Timestamps in, DateTimes out; the models never see a Firestore type.
  static Object? _decode(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is Map) return {for (final e in v.entries) e.key: _decode(e.value)};
    if (v is List) return [for (final e in v) _decode(e)];
    return v;
  }

  /// A transaction that could not reach the server: deferred, not failed.
  static bool _isOffline(Object e) =>
      e is FirebaseException &&
      (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'network-request-failed');

  StoredNutritionPlan? _readPlan(DocumentSnapshot<Map<String, dynamic>> s) {
    if (!s.exists) return null;
    final plan = StoredNutritionPlan.tryFromMap(_decode(s.data()))?.validated();
    if (plan == null) throw const PlanUnreadableException();
    return plan;
  }

  @override
  Stream<StoredNutritionPlan?> watchPlan(String uid) =>
      _plan(uid).snapshots().map(_readPlan);

  @override
  Future<StoredNutritionPlan?> loadPlan(String uid) async =>
      _readPlan(await _plan(uid).get());

  @override
  Future<PlanWriteResult> savePlan(
    String uid,
    StoredNutritionPlan plan, {
    required int? expectedVersion,
  }) async {
    final ref = _plan(uid);
    try {
      return await _db.runTransaction<PlanWriteResult>((tx) async {
        final snap = await tx.get(ref);
        final stored = snap.exists
            ? StoredNutritionPlan.tryFromMap(_decode(snap.data()))
            : null;
        // An unreadable existing document cannot be versioned safely.
        if (snap.exists && stored == null) {
          return const PlanWriteResult(PlanWriteOutcome.conflict);
        }
        if ((stored?.planVersion) != expectedVersion) {
          return const PlanWriteResult(PlanWriteOutcome.conflict);
        }
        final next = plan
            .copyWith(planVersion: (expectedVersion ?? 0) + 1)
            .validated();
        tx.set(ref, next.toMap(time: _timestamp));
        return PlanWriteResult(PlanWriteOutcome.saved, plan: next);
      });
    } catch (e) {
      if (_isOffline(e)) return const PlanWriteResult(PlanWriteOutcome.offline);
      rethrow;
    }
  }

  @override
  Future<ReviewApplyResult> applyReview(
    String uid, {
    required String week,
    required WeeklyReviewDecision decision,
    required DateTime now,
  }) async {
    final planRef = _plan(uid);
    final reviewRef = _reviews(uid).doc(week);
    try {
      return await _db.runTransaction<ReviewApplyResult>((tx) async {
        // Reads first (the transaction rule), the week key before the plan.
        final reviewSnap = await tx.get(reviewRef);
        final planSnap = await tx.get(planRef);
        if (reviewSnap.exists) {
          return const ReviewApplyResult(ReviewApplyOutcome.alreadyReviewed);
        }
        final current = planSnap.exists
            ? StoredNutritionPlan.tryFromMap(_decode(planSnap.data()))
            : null;
        final r = planReviewTransaction(
          week: week,
          decision: decision,
          existingReview: null,
          currentPlan: current,
          now: now,
        );
        if (r.outcome != ReviewApplyOutcome.written) {
          return ReviewApplyResult(r.outcome);
        }
        tx.set(reviewRef, r.review!.toMap(time: _timestamp));
        if (r.plan != null) {
          tx.set(planRef, r.plan!.toMap(time: _timestamp));
        }
        return ReviewApplyResult(
          ReviewApplyOutcome.written,
          review: r.review,
          plan: r.plan,
        );
      });
    } catch (e) {
      if (_isOffline(e)) {
        return const ReviewApplyResult(ReviewApplyOutcome.offline);
      }
      rethrow;
    }
  }

  @override
  Future<UndoResult> undoLastReview(
    String uid, {
    required int expectedVersion,
    required DateTime now,
  }) async {
    final ref = _plan(uid);
    try {
      return await _db.runTransaction<UndoResult>((tx) async {
        final snap = await tx.get(ref);
        final current = snap.exists
            ? StoredNutritionPlan.tryFromMap(_decode(snap.data()))
            : null;
        final r = planUndoTransaction(
          currentPlan: current,
          expectedVersion: expectedVersion,
          now: now,
        );
        if (r.outcome == UndoOutcome.undone) {
          tx.set(ref, r.plan!.toMap(time: _timestamp));
        }
        return UndoResult(r.outcome, plan: r.plan);
      });
    } catch (e) {
      if (_isOffline(e)) return const UndoResult(UndoOutcome.offline);
      rethrow;
    }
  }

  List<PlanReviewRecord> _readReviews(QuerySnapshot<Map<String, dynamic>> q) => [
        for (final d in q.docs)
          if (PlanReviewRecord.tryFromMap(d.id, _decode(d.data()))
              case final r?)
            r,
      ];

  // Newest first: the ISO week key sorts chronologically, so the document id
  // is the order (no composite index, nothing to deploy).
  Query<Map<String, dynamic>> _recent(String uid, int limit) => _reviews(uid)
      .orderBy(FieldPath.documentId, descending: true)
      .limit(limit);

  @override
  Stream<List<PlanReviewRecord>> watchReviews(String uid, {int limit = 12}) =>
      _recent(uid, limit).snapshots().map(_readReviews);

  @override
  Future<List<PlanReviewRecord>> loadRecentReviews(String uid,
          {int limit = 12}) async =>
      _readReviews(await _recent(uid, limit).get());

  @override
  Future<PlanReviewRecord?> loadReview(String uid, String week) async {
    final s = await _reviews(uid).doc(week).get();
    if (!s.exists) return null;
    return PlanReviewRecord.tryFromMap(week, _decode(s.data()));
  }
}
