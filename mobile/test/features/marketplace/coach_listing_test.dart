import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/marketplace/data/coach_listing.dart';

void main() {
  group('splitFee', () {
    test('15% default split rounds to whole cents', () {
      final s = splitFee(10000);
      expect(s.coachCents, 8500);
      expect(s.platformCents, 1500);
      expect(s.coachCents + s.platformCents, 10000);
    });

    test('custom split percentage', () {
      final s = splitFee(10000, platformFeePercent: 0.20);
      expect(s.platformCents, 2000);
      expect(s.coachCents, 8000);
    });

    test('rounding never loses cents', () {
      // 999 cents at 15% => 149.85 -> 150 platform, 849 coach
      final s = splitFee(999);
      expect(s.coachCents + s.platformCents, 999);
    });
  });

  group('CoachListing.formattedPrice', () {
    test('whole dollars no decimals', () {
      final c = CoachListing(
        uid: 'c1',
        displayName: 'A',
        bio: '',
        specialties: const [],
        priceCentsPerSession: 5000,
        currency: 'USD',
        stripeConnectAccountId: 'acct_test',
      );
      expect(c.formattedPrice, r'$50 / session');
    });

    test('odd amounts include decimals', () {
      final c = CoachListing(
        uid: 'c1',
        displayName: 'A',
        bio: '',
        specialties: const [],
        priceCentsPerSession: 4999,
        currency: 'USD',
        stripeConnectAccountId: 'acct_test',
      );
      expect(c.formattedPrice, r'$49.99 / session');
    });
  });
}
