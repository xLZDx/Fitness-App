import 'dart:ui' show Locale;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/subscription_page.dart';

/// Pin the donation-framing copy contract for the subscription page.
///
/// Originally written as a widget-render golden, but the
/// AuroraBackground + GoRouter combo creates a pending frame the
/// `flutter test` runner can't settle without an emulator — the picker
/// state test hit a 10-minute isolate timeout. We pin the contract via
/// the page's pure helpers + the price-label resolver instead, which is
/// what marketing copy + the nonprofit plan actually depend on.
void main() {
  // The labels are localised now, so the helper takes the localisations.
  // Resolved for `en` here because this test pins the ENGLISH donation-framing
  // copy that the nonprofit plan and marketing depend on.
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('SubscriptionPage.tierLabel — donation framing', () {
    test('free tier maps to "Member"', () {
      expect(
        SubscriptionPage.tierLabel(l10n, SubscriptionTier.free),
        'Member',
      );
    });

    test('standard tier maps to "Supporter"', () {
      expect(
        SubscriptionPage.tierLabel(l10n, SubscriptionTier.standard),
        'Supporter',
      );
    });

    test('celebrityTrainer tier maps to "Sustainer"', () {
      expect(
        SubscriptionPage.tierLabel(l10n, SubscriptionTier.celebrityTrainer),
        'Sustainer',
      );
    });
  });

  group('SubscriptionPeriod display labels — pricing toggle copy', () {
    test('monthly / annual / family / lifetime labels', () {
      expect(SubscriptionPeriod.monthly.displayLabel, 'Monthly');
      expect(SubscriptionPeriod.annual.displayLabel, 'Annual');
      expect(SubscriptionPeriod.family2.displayLabel, 'Family · 2 seats');
      expect(SubscriptionPeriod.family4.displayLabel, 'Family · 4 seats');
      expect(SubscriptionPeriod.lifetime.displayLabel, 'Lifetime');
    });
  });

  group('Subscription model state surface', () {
    test('emptyFor sets sane defaults for a new user', () {
      final s = Subscription.emptyFor('alice');
      expect(s.tier, SubscriptionTier.free);
      expect(s.status, SubscriptionStatus.none);
      expect(s.period, SubscriptionPeriod.monthly);
      expect(s.seatCount, 1);
      expect(s.isLifetime, isFalse);
    });

    test('copyWith preserves uid and updates targeted fields', () {
      final s0 = Subscription.emptyFor('alice');
      final s1 = s0.copyWith(
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.active,
        period: SubscriptionPeriod.lifetime,
        isLifetime: true,
      );
      expect(s1.uid, 'alice');
      expect(s1.tier, SubscriptionTier.celebrityTrainer);
      expect(s1.status, SubscriptionStatus.active);
      expect(s1.period, SubscriptionPeriod.lifetime);
      expect(s1.isLifetime, isTrue);
    });

    test('effectiveTier downgrades expired trials to free', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final sub = Subscription(
        uid: 'a',
        tier: SubscriptionTier.standard,
        status: SubscriptionStatus.trial,
        trialEndsAt: past,
      );
      expect(effectiveTier(sub), SubscriptionTier.free);
    });

    test('effectiveTier keeps a cancelled-but-still-in-period user paid',
        () {
      final future = DateTime.now().add(const Duration(days: 10));
      final sub = Subscription(
        uid: 'a',
        tier: SubscriptionTier.celebrityTrainer,
        status: SubscriptionStatus.cancelled,
        currentPeriodEndsAt: future,
      );
      expect(effectiveTier(sub), SubscriptionTier.celebrityTrainer);
    });
  });
}
