import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/marketplace/data/coach_listing.dart';
import 'package:fitness_app/features/marketplace/data/coach_marketplace_service.dart';
import 'package:fitness_app/features/marketplace/marketplace_page.dart';
import 'package:fitness_app/features/marketplace/state/marketplace_providers.dart';

/// M0: the marketplace's mock coach listings used to carry fabricated
/// licensure -- "Coach Alex, NSCA-CSCS" and "Maria Lopez, DPT" -- both
/// `isVerified: true` with invented rating counts, rendered as a real
/// verification badge and a real-looking star rating. A user had no way to
/// tell that apart from an actually vetted coach.
///
/// The seed no longer carries a credential to fabricate. What is left to
/// test is the banner that names the list as sample data, and that tapping
/// a card while it is demo data does not reach the booking backend at all --
/// the banner says booking is disabled, and this is what makes that true.

class _RecordingMarketplaceService implements CoachMarketplaceService {
  final onboardings = <String>[];
  final bookings = <String>[];

  @override
  Future<String> startOnboarding() async {
    onboardings.add('called');
    return 'https://example.test/onboard';
  }

  @override
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  }) async {
    bookings.add(coachUid);
    return (bookingId: 'bk_test', clientSecret: 'secret', amountCents: 100);
  }
}

Widget _host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  group('while the listings are demo data', () {
    testWidgets('the demo banner is shown', (tester) async {
      await tester.pumpWidget(_host(const MarketplacePage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('sample listings'), findsOneWidget);
    });

    testWidgets('no listing shows a verification badge', (tester) async {
      await tester.pumpWidget(_host(const MarketplacePage()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.verified), findsNothing);
    });

    testWidgets('tapping a card does not reach the booking backend',
        (tester) async {
      final svc = _RecordingMarketplaceService();
      await tester.pumpWidget(_host(
        const MarketplacePage(),
        overrides: [coachMarketplaceServiceProvider.overrideWithValue(svc)],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sample listing 1'));
      await tester.pumpAndSettle();

      expect(svc.bookings, isEmpty,
          reason: 'the banner claims booking is disabled -- a network call '
              'going out anyway would make that claim false');
    });
  });

  group('once real coaches are onboarded', () {
    testWidgets('the banner is gone and booking reaches the backend',
        (tester) async {
      final svc = _RecordingMarketplaceService();
      const real = _RealListing();
      await tester.pumpWidget(_host(
        const MarketplacePage(),
        overrides: [
          coachListingRepositoryProvider.overrideWithValue(real),
          coachMarketplaceServiceProvider.overrideWithValue(svc),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('sample listings'), findsNothing);

      await tester.tap(find.text('Real Coach'));
      await tester.pumpAndSettle();

      expect(svc.bookings, ['real_coach'],
          reason: 'a real repository must make the card tappable again');
    });
  });
}

class _RealListing implements CoachListingRepository {
  const _RealListing();

  @override
  Future<List<CoachListing>> list() async => const [
        CoachListing(
          uid: 'real_coach',
          displayName: 'Real Coach',
          bio: 'x',
          specialties: ['strength'],
          priceCentsPerSession: 5000,
          currency: 'USD',
          stripeConnectAccountId: 'acct_real',
        ),
      ];

  @override
  Future<CoachListing?> byId(String uid) async => null;
}
