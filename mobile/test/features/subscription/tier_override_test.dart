import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/settings_repository.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/subscription/data/feature_gates.dart';
import 'package:fitness_app/features/subscription/data/mock_stripe_checkout_service.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

/// Being able to open a paid screen without paying.
///
/// The operator tried to buy the top tier, was handed a Stripe sandbox that
/// rejects invented card numbers, and concluded the flow was broken. It was
/// not — sandbox only takes its own test cards — but "type 4242 4242 4242
/// 4242" is a poor answer to "how do I see what I paid for".
ProviderContainer _container(AppSettings settings) {
  final c = ProviderContainer(overrides: [
    initialSettingsProvider.overrideWithValue(settings),
    settingsRepositoryProvider
        .overrideWithValue(InMemorySettingsRepository(settings)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('the override', () {
    test('off is the default, and the real subscription decides', () {
      final c = _container(const AppSettings());
      expect(c.read(settingsControllerProvider).tierOverride, TierOverride.off);
      // No subscription record in this container, so the real answer is free.
      expect(c.read(effectiveTierProvider), SubscriptionTier.free);
    });

    test('standard opens the Supporter features and not the top ones', () {
      final c = _container(
          const AppSettings(tierOverride: TierOverride.standard));
      expect(c.read(effectiveTierProvider), SubscriptionTier.standard);
      expect(c.read(featureAccessProvider(AppFeature.workoutScheduling)),
          isTrue);
      expect(c.read(featureAccessProvider(AppFeature.aiCoach)), isFalse,
          reason: 'Supporter must not reach the top tier by the back door');
    });

    test('celebrity opens everything', () {
      final c = _container(
          const AppSettings(tierOverride: TierOverride.celebrity));
      expect(c.read(effectiveTierProvider), SubscriptionTier.celebrityTrainer);
      for (final f in AppFeature.values) {
        expect(c.read(featureAccessProvider(f)), isTrue, reason: '$f');
      }
    });

    test('flipping it re-answers every gate at once', () async {
      // The reason this is read in ONE provider rather than at each gate: a
      // per-gate override could leave half the app believing the user paid.
      final c = _container(const AppSettings());
      expect(c.read(featureAccessProvider(AppFeature.aiCoach)), isFalse);

      await c
          .read(settingsControllerProvider.notifier)
          .setTierOverride(TierOverride.celebrity);

      expect(c.read(effectiveTierProvider), SubscriptionTier.celebrityTrainer);
      expect(c.read(featureAccessProvider(AppFeature.aiCoach)), isTrue);
      expect(c.read(featureAccessProvider(AppFeature.advancedAnalytics)),
          isTrue);
    });

    test('it survives a restart', () async {
      final store = InMemorySettingsRepository();
      final c = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      await c
          .read(settingsControllerProvider.notifier)
          .setTierOverride(TierOverride.standard);
      expect((await store.load()).tierOverride, TierOverride.standard);
    });
  });

  group('checkout locale', () {
    test('the app language reaches the payment sheet', () async {
      // Stripe otherwise guesses from the browser, which is how a Russian
      // onboarding handed the operator an English checkout.
      final mock = MockStripeCheckoutService();
      final c = ProviderContainer(overrides: [
        stripeCheckoutServiceProvider.overrideWithValue(mock),
        deviceLocalesProvider.overrideWith((_) => const []),
        initialSettingsProvider
            .overrideWithValue(const AppSettings(language: AppLanguage.ru)),
      ]);
      addTearDown(c.dispose);

      expect(c.read(effectiveLanguageCodeProvider), 'ru');
    });

    test('an unspecified language still resolves to something shipped', () {
      final c = ProviderContainer(overrides: [
        deviceLocalesProvider.overrideWith((_) => const []),
        initialSettingsProvider
            .overrideWithValue(const AppSettings(language: AppLanguage.system)),
      ]);
      addTearDown(c.dispose);
      expect(kSupportedLocaleCodes, contains(c.read(effectiveLanguageCodeProvider)));
    });
  });
}
