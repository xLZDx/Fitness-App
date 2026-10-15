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

  // Body Scan + Nutrition Coach entries (design s22, D-26, Q-2 default).
  group('canAccess: Body Scan + Nutrition Coach entries', () {
    test('the enum carries exactly the six new entries after the old eight',
        () {
      // Names and order are a contract: the operator flips a tier decision by
      // editing one `case`, and persisted/analytics code may key off the name.
      expect(
        AppFeature.values.map((f) => f.name).toList(),
        [
          'basicLogging',
          'fullEquipmentCatalog',
          'personalisedRecommendations',
          'workoutScheduling',
          'celebrityVideoPlans',
          'aiCoach',
          'advancedAnalytics',
          'bodyScan',
          'nutritionPlan',
          'weeklyReview',
          'foodDiary',
          'foodAiRecognition',
          'foodBarcodeLabel',
        ],
      );
    });

    test('bodyScan is gated exactly like the existing scan access: any non-free '
        'tier', () {
      expect(canAccess(SubscriptionTier.free, AppFeature.bodyScan), isFalse);
      expect(
          canAccess(SubscriptionTier.standard, AppFeature.bodyScan), isTrue);
      expect(canAccess(SubscriptionTier.celebrityTrainer, AppFeature.bodyScan),
          isTrue);
    });

    test('every other new entry is ungated on EVERY tier by default', () {
      for (final f in const [
        AppFeature.nutritionPlan,
        AppFeature.weeklyReview,
        AppFeature.foodDiary,
        AppFeature.foodAiRecognition,
        AppFeature.foodBarcodeLabel,
      ]) {
        for (final t in SubscriptionTier.values) {
          expect(canAccess(t, f), isTrue, reason: '$f on $t');
        }
      }
    });

    test('the new entries do not widen the celebrity-only features', () {
      // Regression guard on the shared switch: adding cases must not make the
      // celebrity-only entries reachable from a lower tier.
      expect(canAccess(SubscriptionTier.standard, AppFeature.aiCoach),
          isFalse);
      expect(
          canAccess(SubscriptionTier.standard, AppFeature.celebrityVideoPlans),
          isFalse);
      expect(canAccess(SubscriptionTier.free, AppFeature.advancedAnalytics),
          isFalse);
    });

    test('every feature x tier decision is total (no throw) and matches the '
        'documented table', () {
      const gatedToPaid = {
        AppFeature.fullEquipmentCatalog,
        AppFeature.personalisedRecommendations,
        AppFeature.workoutScheduling,
        AppFeature.advancedAnalytics,
        AppFeature.bodyScan,
      };
      const celebrityOnly = {AppFeature.celebrityVideoPlans, AppFeature.aiCoach};
      for (final f in AppFeature.values) {
        for (final t in SubscriptionTier.values) {
          final bool expected;
          if (celebrityOnly.contains(f)) {
            expected = t == SubscriptionTier.celebrityTrainer;
          } else if (gatedToPaid.contains(f)) {
            expected = t != SubscriptionTier.free;
          } else {
            expected = true;
          }
          expect(canAccess(t, f), expected, reason: '$f on $t');
        }
      }
    });
  });
}
