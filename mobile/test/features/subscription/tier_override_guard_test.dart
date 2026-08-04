import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

/// The tier override, and the build it must not answer in.
///
/// The switch forces `effectiveTierProvider` to report a tier the account has
/// not bought. It exists because the paid surfaces could not be exercised at
/// all -- Stripe sandbox only accepts its own test cards -- and it is the right
/// tool for that. It is also, in a store build, a way to have every paid
/// feature for free.
///
/// The guard is at the read site rather than in Settings: hiding the toggle
/// would leave this provider honouring a value already written to
/// SharedPreferences before the guard shipped.
ProviderContainer _container({required bool allowed, required TierOverride override}) {
  final container = ProviderContainer(overrides: [
    allowTierOverrideProvider.overrideWithValue(allowed),
    settingsControllerProvider.overrideWith(
      () => _FixedSettings(AppSettings(tierOverride: override)),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

class _FixedSettings extends SettingsController {
  _FixedSettings(this._value);
  final AppSettings _value;

  @override
  AppSettings build() => _value;
}

void main() {
  group('when the build allows it', () {
    test('the override answers', () {
      final c = _container(allowed: true, override: TierOverride.celebrity);
      expect(c.read(effectiveTierProvider), SubscriptionTier.celebrityTrainer);
    });

    test('off still means the real subscription', () {
      final c = _container(allowed: true, override: TierOverride.off);
      expect(c.read(effectiveTierProvider), SubscriptionTier.free);
    });
  });

  group('when the build does not', () {
    test('a stored override is ignored, not merely hidden', () {
      // The case a Settings-only guard misses: the value is already in
      // SharedPreferences from before the guard shipped, and the read site
      // would go on honouring it.
      final c = _container(allowed: false, override: TierOverride.celebrity);
      expect(c.read(effectiveTierProvider), SubscriptionTier.free);
    });

    test('every override value is ignored', () {
      for (final value in TierOverride.values) {
        final c = _container(allowed: false, override: value);
        expect(c.read(effectiveTierProvider), SubscriptionTier.free,
            reason: value.name);
      }
    });
  });

  test('the provider reports whatever the build was compiled with', () {
    // Not `expect(kAllowTierOverride, isTrue)`. That asserts the DEFAULT, and
    // fails under the one command that matters:
    //
    //   flutter test --dart-define=ALLOW_TIER_OVERRIDE=false
    //
    // which is how a store build is verified. What must hold in both builds is
    // that the provider and the constant agree -- otherwise the four tests
    // above exercise a seam production does not use.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(allowTierOverrideProvider), kAllowTierOverride);
  });

  test('the default is on, so the operator keeps the switch', () {
    // Personal-use software: defaulting the guard off would restore the exact
    // problem the switch was built for. Skipped when a define is in play,
    // because then there is no default to check.
    expect(kAllowTierOverride, isTrue);
  },
      skip: const bool.hasEnvironment('ALLOW_TIER_OVERRIDE')
          ? 'ALLOW_TIER_OVERRIDE is set; there is no default to assert'
          : null);
}
