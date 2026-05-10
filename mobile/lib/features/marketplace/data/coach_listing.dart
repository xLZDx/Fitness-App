/// TX.5 — Coach Marketplace.
///
/// MVP shape: coaches are vetted users who get a public profile + a
/// per-session price (in USD cents). Bookings flow through Stripe
/// Connect for the platform-fee split; we keep the booking record
/// and the message thread in our Firestore.
class CoachListing {
  const CoachListing({
    required this.uid,
    required this.displayName,
    required this.bio,
    required this.specialties,
    required this.priceCentsPerSession,
    required this.currency,
    required this.stripeConnectAccountId,
    this.photoUrl,
    this.ratingAverage,
    this.ratingCount = 0,
    this.isVerified = false,
  });

  final String uid;
  final String displayName;
  final String bio;
  final List<String> specialties;
  final int priceCentsPerSession;
  final String currency;
  final String stripeConnectAccountId;
  final String? photoUrl;
  final double? ratingAverage;
  final int ratingCount;
  final bool isVerified;

  String get formattedPrice {
    final dollars = priceCentsPerSession / 100;
    return '\$${dollars.toStringAsFixed(dollars == dollars.roundToDouble() ? 0 : 2)} / session';
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'bio': bio,
        'specialties': specialties,
        'priceCentsPerSession': priceCentsPerSession,
        'currency': currency,
        'stripeConnectAccountId': stripeConnectAccountId,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (ratingAverage != null) 'ratingAverage': ratingAverage,
        'ratingCount': ratingCount,
        'isVerified': isVerified,
      };

  factory CoachListing.fromJson(String uid, Map<String, dynamic> j) {
    return CoachListing(
      uid: uid,
      displayName: j['displayName'] as String? ?? 'Coach',
      bio: j['bio'] as String? ?? '',
      specialties: ((j['specialties'] as List?)?.cast<String>()) ?? const [],
      priceCentsPerSession:
          (j['priceCentsPerSession'] as num?)?.toInt() ?? 0,
      currency: j['currency'] as String? ?? 'USD',
      stripeConnectAccountId:
          j['stripeConnectAccountId'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      ratingAverage: (j['ratingAverage'] as num?)?.toDouble(),
      ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
      isVerified: j['isVerified'] == true,
    );
  }
}

class CoachBooking {
  const CoachBooking({
    required this.id,
    required this.coachUid,
    required this.clientUid,
    required this.startsAt,
    required this.durationMinutes,
    required this.priceCents,
    required this.status,
    this.stripePaymentIntentId,
  });

  final String id;
  final String coachUid;
  final String clientUid;
  final DateTime startsAt;
  final int durationMinutes;
  final int priceCents;
  final BookingStatus status;
  final String? stripePaymentIntentId;
}

enum BookingStatus { pending, confirmed, completed, cancelled, refunded }

/// Pure helper: 15% platform-fee split (configurable). Returns the
/// coach payout and the platform fee in cents.
({int coachCents, int platformCents}) splitFee(int totalCents,
    {double platformFeePercent = 0.15}) {
  final platform = (totalCents * platformFeePercent).round();
  return (coachCents: totalCents - platform, platformCents: platform);
}
