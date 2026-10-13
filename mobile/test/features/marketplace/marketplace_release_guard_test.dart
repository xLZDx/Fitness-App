import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/marketplace/data/coach_listing.dart';
import 'package:fitness_app/features/marketplace/data/coach_marketplace_service.dart';
import 'package:fitness_app/features/marketplace/state/marketplace_providers.dart';

/// R2-5 operations contract: with demo features off (release semantics) EVERY
/// operation of the guarded marketplace service refuses with
/// [MarketplaceUnavailableException] before the inner service is reached, for
/// both mock and real listings. The UI is bypassed: the guarded provider is
/// called directly. With demo features on and real listings the call reaches
/// the inner service exactly once per operation.

class _CountingService implements CoachMarketplaceService {
  int onboardingCalls = 0;
  final bookingCoaches = <String>[];

  int get totalCalls => onboardingCalls + bookingCoaches.length;

  @override
  Future<String> startOnboarding() async {
    onboardingCalls++;
    return 'https://example.test/onboard';
  }

  @override
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  }) async {
    bookingCoaches.add(coachUid);
    return (bookingId: 'bk', clientSecret: 'secret', amountCents: 100);
  }
}

class _RealListing implements CoachListingRepository {
  const _RealListing();
  @override
  Future<List<CoachListing>> list() async => const [];
  @override
  Future<CoachListing?> byId(String uid) async => null;
}

CoachMarketplaceService _guarded(
  _CountingService svc, {
  required bool realListings,
  required bool demoFeatures,
}) {
  final c = ProviderContainer(overrides: [
    if (realListings)
      coachListingRepositoryProvider.overrideWithValue(const _RealListing()),
    marketplaceDemoFeaturesProvider.overrideWithValue(demoFeatures),
    coachMarketplaceServiceProvider.overrideWithValue(svc),
  ]);
  addTearDown(c.dispose);
  return c.read(guardedCoachMarketplaceServiceProvider);
}

void main() {
  // Every operation the CoachMarketplaceService interface exposes.
  final operations = <String,
      Future<Object?> Function(CoachMarketplaceService s)>{
    'startOnboarding': (s) => s.startOnboarding(),
    'bookSession default duration': (s) =>
        s.bookSession(coachUid: 'coach_1', startsAt: DateTime(2031)),
    'bookSession 30 min': (s) => s.bookSession(
        coachUid: 'coach_2', startsAt: DateTime(2031), durationMinutes: 30),
  };

  for (final realListings in [false, true]) {
    group('demo features OFF, ${realListings ? 'real' : 'mock'} listings', () {
      for (final op in operations.entries) {
        test('${op.key} throws and the inner service is never called',
            () async {
          final svc = _CountingService();
          final guarded =
              _guarded(svc, realListings: realListings, demoFeatures: false);
          await expectLater(
              op.value(guarded),
              throwsA(isA<MarketplaceUnavailableException>()
                  .having((e) => e.reason, 'reason', isNotEmpty)));
          expect(svc.totalCalls, 0);
        });
      }

      test('repeated attempts never leak a call through', () async {
        final svc = _CountingService();
        final guarded =
            _guarded(svc, realListings: realListings, demoFeatures: false);
        for (var i = 0; i < 5; i++) {
          for (final op in operations.values) {
            await expectLater(
                op(guarded), throwsA(isA<MarketplaceUnavailableException>()));
          }
        }
        expect(svc.totalCalls, 0);
      });
    });
  }

  group('demo features ON', () {
    test('mock listings: every operation still refuses', () async {
      final svc = _CountingService();
      final guarded = _guarded(svc, realListings: false, demoFeatures: true);
      for (final op in operations.values) {
        await expectLater(
            op(guarded), throwsA(isA<MarketplaceUnavailableException>()));
      }
      expect(svc.totalCalls, 0);
    });

    test('real listings: every operation reaches the inner service once',
        () async {
      final svc = _CountingService();
      final guarded = _guarded(svc, realListings: true, demoFeatures: true);
      expect(await guarded.startOnboarding(), 'https://example.test/onboard');
      final b = await guarded.bookSession(
          coachUid: 'coach_1', startsAt: DateTime(2031));
      expect(b.bookingId, 'bk');
      await guarded.bookSession(
          coachUid: 'coach_2', startsAt: DateTime(2031), durationMinutes: 30);
      expect(svc.onboardingCalls, 1);
      expect(svc.bookingCoaches, ['coach_1', 'coach_2']);
    });
  });

  test('the guard re-evaluates per call: flipping the flag changes the outcome',
      () async {
    final svc = _CountingService();
    final demo = StateProvider<bool>((_) => false);
    final c = ProviderContainer(overrides: [
      coachListingRepositoryProvider.overrideWithValue(const _RealListing()),
      marketplaceDemoFeaturesProvider.overrideWith((ref) => ref.watch(demo)),
      coachMarketplaceServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    final guarded = c.read(guardedCoachMarketplaceServiceProvider);
    await expectLater(guarded.startOnboarding(),
        throwsA(isA<MarketplaceUnavailableException>()));
    expect(svc.totalCalls, 0);
    c.read(demo.notifier).state = true;
    await guarded.startOnboarding();
    expect(svc.onboardingCalls, 1);
  });
}
