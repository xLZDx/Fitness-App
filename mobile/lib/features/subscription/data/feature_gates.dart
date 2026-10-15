import 'subscription_models.dart';

/// Capability buckets the app actually checks. Adding one here is the
/// only place we need to touch when introducing a new gated feature.
enum AppFeature {
  /// Always-on baseline — available to every signed-in user. Listed so
  /// callers can use the same enum for any feature lookup.
  basicLogging,

  /// Full equipment catalog vs. the trimmed free tier (currently the
  /// 12 hand-seeded exercises minus the heavy-equipment ones).
  fullEquipmentCatalog,

  /// Personalised "For you" recommendations + injury filtering.
  personalisedRecommendations,

  /// Schedule + reminders.
  workoutScheduling,

  /// Celebrity-led video plans (Phase 6+ — gated to top tier from day 1).
  celebrityVideoPlans,

  /// AI coach + form-risk detection (Phase 6+).
  aiCoach,

  /// Advanced analytics: long-term trends, body-composition imports.
  advancedAnalytics,

  // Body Scan + Nutrition Coach (design s22, D-26, operator question Q-2).
  // One entry per feature so the operator's tier decision is a one-line change
  // each. The DEFAULT keeps today's behaviour: only the body scan is gated, and
  // exactly like the existing `scanAccessProvider` (any non-free tier); every
  // other entry is ungated and bounded instead by per-user daily quotas,
  // the anonymous-account refusal and the server kill switch. These are tier
  // gates only; whether a capability exists at all is decided separately by the
  // compile-time `BodyScanFlags` (core/config/body_scan_flags.dart).

  /// Body check-in scan and result. Mirrors `ScanAccess.needsSupporter`.
  bodyScan,

  /// Nutrition targets: plan, ranges, ownership.
  nutritionPlan,

  /// Weekly review of the nutrition plan.
  weeklyReview,

  /// Food diary (bundled search, quick log, saved foods).
  foodDiary,

  /// AI meal-photo / describe-in-text recognition.
  foodAiRecognition,

  /// Barcode and nutrition-label scanning.
  foodBarcodeLabel,
}

/// Pure capability check. Returns true when the [tier] is allowed to use
/// [feature]. Callers should pass `effectiveTier(sub)` rather than the raw
/// stored tier so a lapsed trial doesn't keep premium features open.
bool canAccess(SubscriptionTier tier, AppFeature feature) {
  switch (feature) {
    case AppFeature.basicLogging:
      // Available on every tier.
      return true;
    case AppFeature.fullEquipmentCatalog:
    case AppFeature.personalisedRecommendations:
    case AppFeature.workoutScheduling:
    case AppFeature.advancedAnalytics:
    case AppFeature.bodyScan:
      return tier == SubscriptionTier.standard ||
          tier == SubscriptionTier.celebrityTrainer;
    case AppFeature.nutritionPlan:
    case AppFeature.weeklyReview:
    case AppFeature.foodDiary:
    case AppFeature.foodAiRecognition:
    case AppFeature.foodBarcodeLabel:
      // Ungated by default (Q-2 default, D-26); gate here to change it.
      return true;
    case AppFeature.celebrityVideoPlans:
    case AppFeature.aiCoach:
      return tier == SubscriptionTier.celebrityTrainer;
  }
}
