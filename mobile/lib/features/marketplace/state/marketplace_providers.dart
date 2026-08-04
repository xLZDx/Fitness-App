import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_listing.dart';
import '../data/coach_marketplace_service.dart';

abstract class CoachListingRepository {
  Future<List<CoachListing>> list();
  Future<CoachListing?> byId(String uid);
}

class MockCoachListingRepository implements CoachListingRepository {
  // Used to carry "Coach Alex — NSCA-CSCS, 8 years..." and "Maria Lopez,
  // DPT — Doctor of Physical Therapy", both `isVerified: true` with invented
  // rating counts. `isVerified` renders a verification badge
  // (`marketplace_page.dart:89`) and `ratingAverage`/`ratingCount` render a
  // real-looking star rating (`:102-108`) -- a user had no way to tell a
  // fabricated licensed-professional credential from a real one. The booking
  // backend reads coaches from Firestore, not from this list, so nobody
  // could actually be charged to book a nonexistent person
  // (`functions/src/index.ts` `bookCoachSession` 404s on an unknown
  // `coachUid`) -- but the display itself was the false claim, independent
  // of whether money could move.
  //
  // Every field a real, vetted listing WOULD prove is now the value that
  // proves nothing: no verification badge, no rating. `DemoDataBanner` on
  // the page carries the rest of the disclosure -- this and that banner are
  // two views of the same fact, not two separate decisions.
  static const _seed = [
    CoachListing(
      uid: 'demo_coach_1',
      displayName: 'Sample listing 1',
      bio: 'Demo data -- not a real coach. Shows how a listing with '
          'strength/rehab specialties renders.',
      specialties: ['strength', 'rehab'],
      priceCentsPerSession: 6000,
      currency: 'USD',
      stripeConnectAccountId: '',
    ),
    CoachListing(
      uid: 'demo_coach_2',
      displayName: 'Sample listing 2',
      bio: 'Demo data -- not a real coach. Shows how a listing with '
          'rehab/mobility specialties renders.',
      specialties: ['rehab', 'mobility'],
      priceCentsPerSession: 9000,
      currency: 'USD',
      stripeConnectAccountId: '',
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

/// True while [coachListingRepositoryProvider] is still the mock.
///
/// Computed from the runtime type of whatever is actually bound, not from a
/// flag someone has to remember to flip. The day `main.dart` overrides this
/// with a Firestore-backed listing repository, `MarketplacePage`'s demo
/// banner disappears on its own -- the same self-removing shape as
/// `injuryFilteringIsRealProvider`.
final marketplaceListingsAreDemoProvider = Provider<bool>((ref) {
  return ref.watch(coachListingRepositoryProvider) is MockCoachListingRepository;
});

final coachListingsProvider =
    FutureProvider<List<CoachListing>>((ref) {
  return ref.watch(coachListingRepositoryProvider).list();
});

final coachMarketplaceServiceProvider =
    Provider<CoachMarketplaceService>((_) => MockCoachMarketplaceService());
