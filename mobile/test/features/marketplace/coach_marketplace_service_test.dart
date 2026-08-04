import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/marketplace/data/coach_marketplace_service.dart';
import 'package:fitness_app/features/marketplace/state/marketplace_providers.dart';

void main() {
  group('MockCoachMarketplaceService', () {
    test('startOnboarding records a call + returns mock URL', () async {
      final svc = MockCoachMarketplaceService();
      final url = await svc.startOnboarding();
      expect(url, contains('mock'));
      expect(svc.onboardings, ['mock']);
    });

    test('bookSession returns booking id derived from coach', () async {
      final svc = MockCoachMarketplaceService();
      final r = await svc.bookSession(
        coachUid: 'coach_alex',
        startsAt: DateTime(2026, 6, 1, 9),
      );
      expect(r.bookingId, contains('coach_alex'));
      expect(r.amountCents, greaterThan(0));
      expect(svc.bookings, ['coach_alex']);
    });
  });

  group('MockCoachListingRepository', () {
    // The seed used to be "Coach Alex, NSCA-CSCS" and "Maria Lopez, DPT",
    // both `isVerified: true` with invented rating counts -- a fabricated
    // licensed-professional credential rendered as a real verification
    // badge and a real-looking star rating (M0). `list().first.isVerified`
    // being true was this test locking that claim in; it now asserts the
    // opposite.
    test('list returns the seeded coaches, none of them verified', () async {
      final repo = MockCoachListingRepository();
      final list = await repo.list();
      expect(list.length, greaterThanOrEqualTo(2));
      expect(list.every((c) => !c.isVerified), isTrue,
          reason: 'demo listings must not carry a fabricated verification '
              'badge');
      expect(list.every((c) => c.ratingAverage == null), isTrue,
          reason: 'demo listings must not carry an invented rating');
    });

    test('byId resolves a specific coach', () async {
      final repo = MockCoachListingRepository();
      final c = await repo.byId('demo_coach_2');
      expect(c, isNotNull);
      expect(c!.specialties, contains('rehab'));
    });

    test('an unknown id resolves to nothing', () async {
      final repo = MockCoachListingRepository();
      expect(await repo.byId('coach_alex'), isNull,
          reason: 'the old seed ids must not still resolve');
    });
  });
}
