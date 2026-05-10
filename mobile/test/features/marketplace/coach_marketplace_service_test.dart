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
    test('list returns the seeded coaches', () async {
      final repo = MockCoachListingRepository();
      final list = await repo.list();
      expect(list.length, greaterThanOrEqualTo(2));
      expect(list.first.isVerified, isTrue);
    });

    test('byId resolves a specific coach', () async {
      final repo = MockCoachListingRepository();
      final c = await repo.byId('coach_maria');
      expect(c, isNotNull);
      expect(c!.specialties, contains('rehab'));
    });
  });
}
