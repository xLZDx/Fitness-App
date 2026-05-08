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
      return tier == SubscriptionTier.standard ||
          tier == SubscriptionTier.celebrityTrainer;
    case AppFeature.celebrityVideoPlans:
    case AppFeature.aiCoach:
      return tier == SubscriptionTier.celebrityTrainer;
  }
}
