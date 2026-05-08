import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/feature_gates.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';

void main() {
  group('canAccess', () {
    test('basicLogging is open to every tier', () {
      for (final t in SubscriptionTier.values) {
        expect(canAccess(t, AppFeature.basicLogging), isTrue,
            reason: 'tier $t should have basicLogging');
      }
    });

    test('full catalog / recommendations / scheduling / analytics gated to standard+',
        () {
      for (final f in const [
        AppFeature.fullEquipmentCatalog,
        AppFeature.personalisedRecommendations,
        AppFeature.workoutScheduling,
        AppFeature.advancedAnalytics,
      ]) {
        expect(canAccess(SubscriptionTier.free, f), isFalse, reason: '$f');
        expect(canAccess(SubscriptionTier.standard, f), isTrue, reason: '$f');
        expect(canAccess(SubscriptionTier.celebrityTrainer, f), isTrue,
            reason: '$f');
      }
    });

    test('celebrity-only features locked out of free + standard', () {
      for (final f in const [
        AppFeature.celebrityVideoPlans,
        AppFeature.aiCoach,
      ]) {
        expect(canAccess(SubscriptionTier.free, f), isFalse, reason: '$f');
        expect(canAccess(SubscriptionTier.standard, f), isFalse, reason: '$f');
        expect(canAccess(SubscriptionTier.celebrityTrainer, f), isTrue,
            reason: '$f');
      }
    });
  });
}
