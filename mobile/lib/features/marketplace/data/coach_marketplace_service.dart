import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';

/// Bridge to the marketplace Cloud Functions
/// (`startCoachOnboarding`, `bookCoachSession`).
///
/// Mock by default so widget tests don't need cloud_functions.
abstract class CoachMarketplaceService {
  /// Returns the URL the coach should open to finish Connect onboarding.
  Future<String> startOnboarding();

  /// Books a session with [coachUid]. Returns the booking id + the
  /// PaymentIntent client_secret the client uses with stripe_payment.
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  });
}

/// Thrown by [GuardedCoachMarketplaceService] when an onboarding or booking
/// action is attempted while the marketplace cannot honour it.
class MarketplaceUnavailableException implements Exception {
  const MarketplaceUnavailableException(this.reason);
  final String reason;

  @override
  String toString() => 'MarketplaceUnavailableException: $reason';
}

/// Service-layer guard: refuses onboarding and booking BEFORE the inner
/// service (and so the backend) is reached. A disabled UI card is not enough;
/// any other caller of the service must hit the same wall.
///
/// [blockedReason] returns null when actions are allowed, otherwise why not.
/// It is evaluated per call, so the guard follows provider changes.
class GuardedCoachMarketplaceService implements CoachMarketplaceService {
  GuardedCoachMarketplaceService(this._inner, this._blockedReason);
  final CoachMarketplaceService _inner;
  final String? Function() _blockedReason;

  void _check() {
    final reason = _blockedReason();
    if (reason != null) throw MarketplaceUnavailableException(reason);
  }

  @override
  Future<String> startOnboarding() async {
    _check();
    return _inner.startOnboarding();
  }

  @override
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  }) async {
    _check();
    return _inner.bookSession(
      coachUid: coachUid,
      startsAt: startsAt,
      durationMinutes: durationMinutes,
    );
  }
}

class MockCoachMarketplaceService implements CoachMarketplaceService {
  /// Records every call for asserting on in tests.
  final List<String> onboardings = [];
  final List<String> bookings = [];

  @override
  Future<String> startOnboarding() async {
    onboardings.add('mock');
    return 'https://mock.example.com/onboard';
  }

  @override
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  }) async {
    bookings.add(coachUid);
    return (
      bookingId: 'bk_mock_$coachUid',
      clientSecret: 'pi_mock_secret',
      amountCents: 5000,
    );
  }
}

class CloudCoachMarketplaceService implements CoachMarketplaceService {
  CloudCoachMarketplaceService({FirebaseFunctions? functions})
      : _functions = functions ??
            functionsForRegion;
  final FirebaseFunctions _functions;

  @override
  Future<String> startOnboarding() async {
    final r = await _functions
        .httpsCallable('startCoachOnboarding')
        .call<Map<String, dynamic>>(<String, dynamic>{});
    final url = r.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Backend returned no onboarding URL.');
    }
    return url;
  }

  @override
  Future<({String bookingId, String clientSecret, int amountCents})>
      bookSession({
    required String coachUid,
    required DateTime startsAt,
    int durationMinutes = 60,
  }) async {
    final r = await _functions
        .httpsCallable('bookCoachSession')
        .call<Map<String, dynamic>>({
      'coachUid': coachUid,
      'startsAt': startsAt.toIso8601String(),
      'durationMinutes': durationMinutes,
    });
    return (
      bookingId: r.data['bookingId'] as String,
      clientSecret: r.data['clientSecret'] as String,
      amountCents: (r.data['amountCents'] as num).toInt(),
    );
  }
}
