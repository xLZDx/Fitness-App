/// Nutrition state (design s21): inputs, the device-local eligibility verdict,
/// the stored plan and the live weekly-review decision.
///
/// The eligibility verdict is computed on the DEVICE from the merged profile
/// (the device-only health answers) and is never written anywhere (D-55): no
/// provider here persists it, and nothing downstream may.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/health/health_models.dart';
import '../../../core/health/state/health_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../data/body_fat_trend_source.dart';
import '../data/in_memory_nutrition_repositories.dart';
import '../data/nutrition_eligibility.dart';
import '../data/nutrition_inputs.dart';
import '../data/plan_repository.dart';
import '../data/plan_review_record.dart';
import '../data/review_input_builder.dart';
import '../data/stored_nutrition_plan.dart';
import '../data/weekly_review.dart';
import 'weight_providers.dart';

/// Backend-agnostic plan storage. Default is the in-memory fake; `main.dart`
/// overrides it with the Firestore implementation.
final nutritionPlanRepositoryProvider = Provider<NutritionPlanRepository>((ref) {
  final repo = InMemoryPlanRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// PORT for the smoothed body-fat trend (D-71). The safe default reports no
/// trend; the app root overrides it with the body_scan implementation. Watch it
/// (do not read it once) so a provider-bound implementation re-evaluates the
/// review when a scan changes the trend.
final bodyFatTrendSourceProvider =
    Provider<BodyFatTrendSource>((_) => const NoBodyFatTrendSource());

/// Median of the last 14 COMPLETED days of platform steps, or null when fewer
/// than [minDays] of them have data (then the self-reported bucket applies).
/// The seam is the existing `HealthService`; it never throws and returns an
/// empty list without permission.
int? medianDailySteps(
  Iterable<HealthSnapshot> snapshots,
  DateTime now, {
  int minDays = 7,
}) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final values = [
    for (final s in snapshots)
      if (s.dateUtc.isBefore(today) && s.steps != null && s.steps! > 0)
        s.steps!,
  ]..sort();
  if (values.length < minDays) return null;
  final mid = values.length ~/ 2;
  return values.length.isOdd
      ? values[mid]
      : ((values[mid - 1] + values[mid]) / 2).round();
}

/// The 14-day median steps from the health platform, null when unavailable.
final healthMedianStepsProvider = FutureProvider<int?>((ref) async {
  final now = ref.watch(nutritionClockProvider)();
  try {
    final snapshots = await ref.watch(healthServiceProvider).readSnapshots(
          from: now.subtract(const Duration(days: 15)),
          to: now,
        );
    return medianDailySteps(snapshots, now);
  } catch (e) {
    debugPrint('health median steps unavailable: $e');
    return null;
  }
});

/// The resolved inputs, or null while the profile is not loaded.
final nutritionInputsProvider = Provider<NutritionInputsResolution?>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return null;
  return NutritionInputs.resolve(
    profile,
    now: ref.watch(nutritionClockProvider)(),
    weightEntries: ref.watch(weightEntriesProvider).valueOrNull ?? const [],
    healthMedianSteps: ref.watch(healthMedianStepsProvider).valueOrNull,
  );
});

/// The device-local verdict (design s14). Null while the profile is unknown;
/// every consumer treats null as "no numbers" (fail closed).
final nutritionEligibilityProvider = Provider<NutritionEligibility?>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return null;
  return evaluateNutritionEligibility(
    profile,
    ref.watch(nutritionClockProvider)(),
    currentWeightKg: ref.watch(currentWeightProvider)?.kg,
  );
});

/// The stored plan as it is in Firestore (validated, never gated). Writers and
/// the review scheduler use this; screens use [nutritionPlanProvider].
final storedNutritionPlanProvider =
    StreamProvider<StoredNutritionPlan?>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  yield* ref.watch(nutritionPlanRepositoryProvider).watchPlan(user.uid);
});

/// The plan to DISPLAY: the stored plan only while the user is eligible. For
/// `referProfessional`, `needsAnswer`, `needsProfile` (or an unknown verdict)
/// an existing document is simply not shown (D-55).
final nutritionPlanProvider =
    Provider<AsyncValue<StoredNutritionPlan?>>((ref) {
  final verdict = ref.watch(nutritionEligibilityProvider);
  if (verdict == null || !verdict.allowsNumbers) {
    return const AsyncValue.data(null);
  }
  return ref.watch(storedNutritionPlanProvider);
});

/// The last 12 reviews, newest first (the "why" history).
final nutritionReviewsProvider =
    StreamProvider<List<PlanReviewRecord>>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(nutritionPlanRepositoryProvider).watchReviews(user.uid);
});

/// The decision the weekly review would take NOW from live state (the same
/// pure function and builder the scheduler uses). Null for a user who is not
/// eligible, or without a plan. It is a read model: it writes nothing.
final weeklyReviewProvider = Provider<WeeklyReviewDecision?>((ref) {
  final verdict = ref.watch(nutritionEligibilityProvider);
  if (verdict == null || !verdict.allowsNumbers) return null;
  final input = buildReviewInput(
    plan: ref.watch(storedNutritionPlanProvider).valueOrNull,
    eligibility: verdict,
    weights: ref.watch(weightEntriesProvider).valueOrNull ?? const [],
    reviews: ref.watch(nutritionReviewsProvider).valueOrNull ?? const [],
    now: ref.watch(nutritionClockProvider)(),
    bodyFatTrend: ref.watch(bodyFatTrendSourceProvider).currentTrend(),
  );
  return input == null ? null : decide(input);
});
