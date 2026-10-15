/// Runs the weekly review (design s15, D-8, D-55, D-57). Client-side: once per
/// ISO week, on the first Plan/Home display of a new week and right after a scan
/// reaches `done`.
///
/// The scheduler is a plain function of fresh repository reads; it never
/// trusts the live providers' cached values for the decision. It writes
/// NOTHING for a user who is not `eligible`, without a plan, while the data
/// notice is not acknowledged, while the account is being deleted, or offline
/// (the review is deferred, never half-queued). The review document and the
/// plan change go through ONE repository transaction (`applyReview`).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/privacy/data_notice.dart';
import '../../account_deletion/state/account_deletion_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/nutrition_eligibility.dart';
import '../data/review_input_builder.dart';
import '../data/review_transaction.dart';
import '../data/weekly_review.dart';
import 'nutrition_providers.dart';
import 'weight_providers.dart';

/// What woke the scheduler up.
enum ReviewTrigger { planSurfaceShown, scanDone, appForeground }

enum ReviewRunStatus {
  /// A review document (and possibly a plan change) was written.
  written,

  /// This week already has a review; nothing written.
  alreadyReviewed,

  /// Not run; see [ReviewRunResult.reason].
  skipped,

  /// The transaction did not write (stale plan, refused re-check, offline);
  /// the next trigger recomputes from fresh data.
  deferred,

  /// An unexpected error; logged, never rethrown into a screen.
  failed,
}

enum ReviewSkipReason {
  signedOut,
  accountBeingDeleted,
  noticePending,
  notEligible,
  noPlan,
  alreadyThisWeek,
  inFlight,
  noDecision,
}

class ReviewRunResult {
  const ReviewRunResult(this.status, {this.reason, this.outcome, this.apply});

  final ReviewRunStatus status;
  final ReviewSkipReason? reason;
  final ReviewApplyOutcome? outcome;

  /// The decision that was written (for the "plan updated" notification).
  final WeeklyReviewDecision? apply;
}

class WeeklyReviewScheduler {
  WeeklyReviewScheduler(this._ref);

  final Ref _ref;
  bool _running = false;

  /// `uid:isoWeek` pairs that are known to be done in this process.
  final Set<String> _doneWeeks = {};

  ReviewRunResult _skip(ReviewSkipReason r) =>
      ReviewRunResult(ReviewRunStatus.skipped, reason: r);

  Future<ReviewRunResult> run(ReviewTrigger trigger) async {
    if (_running) return _skip(ReviewSkipReason.inFlight);
    _running = true;
    try {
      return await _run();
    } catch (e, st) {
      debugPrint('weekly review failed ($trigger): $e\n$st');
      return const ReviewRunResult(ReviewRunStatus.failed);
    } finally {
      _running = false;
    }
  }

  Future<ReviewRunResult> _run() async {
    final user = await _ref.read(authUserProvider.future);
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) return _skip(ReviewSkipReason.signedOut);
    if (_ref.read(accountBeingDeletedUidProvider) == uid) {
      return _skip(ReviewSkipReason.accountBeingDeleted);
    }
    // Plan and weights are stored server-side: not before the notice (D-79).
    final noticeOk = await _ref.read(dataNoticeAcknowledgedProvider.future);
    if (!noticeOk) return _skip(ReviewSkipReason.noticePending);

    final verdict = _ref.read(nutritionEligibilityProvider);
    if (verdict == null || verdict is! Eligible) {
      return _skip(ReviewSkipReason.notEligible);
    }

    final now = _ref.read(nutritionClockProvider)();
    final week = reviewWeekKey(now, utcOffset: now.timeZoneOffset);
    final doneKey = '$uid:$week';
    if (_doneWeeks.contains(doneKey)) {
      return _skip(ReviewSkipReason.alreadyThisWeek);
    }

    final plans = _ref.read(nutritionPlanRepositoryProvider);
    final weights = _ref.read(weightRepositoryProvider);
    if (await plans.loadReview(uid, week) != null) {
      _doneWeeks.add(doneKey);
      return const ReviewRunResult(ReviewRunStatus.alreadyReviewed);
    }
    final plan = await plans.loadPlan(uid);
    if (plan == null) return _skip(ReviewSkipReason.noPlan);

    final input = buildReviewInput(
      plan: plan,
      eligibility: verdict,
      weights: [for (final i in await weights.loadLog(uid)) i.entry],
      reviews: await plans.loadRecentReviews(uid, limit: 1),
      now: now,
      bodyFatTrend: _ref.read(bodyFatTrendSourceProvider).currentTrend(),
    );
    final decision = input == null ? null : decide(input);
    if (decision == null) return _skip(ReviewSkipReason.noDecision);

    final result = await plans.applyReview(
      uid,
      week: week,
      decision: decision,
      now: now,
    );
    switch (result.outcome) {
      case ReviewApplyOutcome.written:
        _doneWeeks.add(doneKey);
        return ReviewRunResult(
          ReviewRunStatus.written,
          outcome: result.outcome,
          apply: decision,
        );
      case ReviewApplyOutcome.alreadyReviewed:
        _doneWeeks.add(doneKey);
        return ReviewRunResult(
          ReviewRunStatus.alreadyReviewed,
          outcome: result.outcome,
        );
      case ReviewApplyOutcome.noPlan:
        return _skip(ReviewSkipReason.noPlan);
      case ReviewApplyOutcome.staleVersion:
      case ReviewApplyOutcome.rejected:
      case ReviewApplyOutcome.offline:
        return ReviewRunResult(ReviewRunStatus.deferred,
            outcome: result.outcome);
    }
  }
}

final weeklyReviewSchedulerProvider =
    Provider<WeeklyReviewScheduler>((ref) => WeeklyReviewScheduler(ref));

/// Bumped by the app-root bridge when a scan reaches `done` (body_scan does not
/// import this feature, D-71). Each bump runs the review once; the week key
/// keeps it idempotent.
final scanDoneSignalProvider = StateProvider<int>((_) => 0);

/// Keep-alive listener: watch it once at the app root. The plan/Home screens
/// call `run(ReviewTrigger.planSurfaceShown)` on first display of a week.
final weeklyReviewTriggersProvider = Provider<void>((ref) {
  ref.listen<int>(scanDoneSignalProvider, (previous, next) {
    ref.read(weeklyReviewSchedulerProvider).run(ReviewTrigger.scanDone);
  });
});
