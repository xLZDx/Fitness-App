import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_listing.dart';
import '../data/coach_marketplace_service.dart';

abstract class CoachListingRepository {
  Future<List<CoachListing>> list();
  Future<CoachListing?> byId(String uid);
}

class MockCoachListingRepository implements CoachListingRepository {
  static const _seed = [
    CoachListing(
      uid: 'coach_alex',
      displayName: 'Coach Alex',
      bio: 'NSCA-CSCS, 8 years coaching beginner-to-intermediate '
          'powerlifters. Specialty: low-back-friendly programming.',
      specialties: ['strength', 'rehab'],
      priceCentsPerSession: 6000,
      currency: 'USD',
      stripeConnectAccountId: 'acct_mock_alex',
      ratingAverage: 4.8,
      ratingCount: 41,
      isVerified: true,
    ),
    CoachListing(
      uid: 'coach_maria',
      displayName: 'Maria Lopez, DPT',
      bio: 'Doctor of Physical Therapy. Online return-to-load coaching '
          'for athletes recovering from injury.',
      specialties: ['rehab', 'mobility'],
      priceCentsPerSession: 9000,
      currency: 'USD',
      stripeConnectAccountId: 'acct_mock_maria',
      ratingAverage: 5.0,
      ratingCount: 12,
      isVerified: true,
    ),
  ];

  @override
  Future<List<CoachListing>> list() async => _seed;

  @override
  Future<CoachListing?> byId(String uid) async {
    for (final c in _seed) {
      if (c.uid == uid) return c;
    }
    return null;
  }
}

final coachListingRepositoryProvider =
    Provider<CoachListingRepository>((_) => MockCoachListingRepository());

final coachListingsProvider =
    FutureProvider<List<CoachListing>>((ref) {
  return ref.watch(coachListingRepositoryProvider).list();
});

final coachMarketplaceServiceProvider =
    Provider<CoachMarketplaceService>((_) => MockCoachMarketplaceService());
