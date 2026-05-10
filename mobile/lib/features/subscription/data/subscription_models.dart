/// Three-tier subscription ladder. Order matters: a higher index implies
/// every entitlement of the lower indices.
enum SubscriptionTier {
  /// Free, ad-light tier — limited equipment catalog, basic logging.
  free,

  /// Paid baseline — full catalog, recommendations, calendar reminders.
  standard,

  /// Premium — celebrity-led video plans, AI coach, priority content.
  celebrityTrainer,
}

/// Billing period for a paid tier.
///
/// - [monthly]   $9.99 / $19.99 (Standard / Celebrity)
/// - [annual]    $59.99 / $119.99 — ~50% effective discount, mirrors
///               Sweat / Ladder / Freeletics anchors.
/// - [family2]   2 seats, $14.99 / $24.99
/// - [family4]   4 seats, $19.99 / $34.99 — anchors against Apple
///               Fitness+ family-of-6 at $9.99.
/// - [lifetime]  $499 one-time, Celebrity-tier only. Hevy proved the
///               model with $74.99 lifetime; Celebrity is 6.7x monthly.
enum SubscriptionPeriod {
  monthly,
  annual,
  family2,
  family4,
  lifetime,
}

extension SubscriptionPeriodLabel on SubscriptionPeriod {
  String get displayLabel {
    switch (this) {
      case SubscriptionPeriod.monthly:
        return 'Monthly';
      case SubscriptionPeriod.annual:
        return 'Annual';
      case SubscriptionPeriod.family2:
        return 'Family · 2 seats';
      case SubscriptionPeriod.family4:
        return 'Family · 4 seats';
      case SubscriptionPeriod.lifetime:
        return 'Lifetime';
    }
  }

  /// Number of seats this period grants. 1 unless family.
  int get seatCount {
    switch (this) {
      case SubscriptionPeriod.family2:
        return 2;
      case SubscriptionPeriod.family4:
        return 4;
      default:
        return 1;
    }
  }

  bool get isOneTime => this == SubscriptionPeriod.lifetime;
}

/// Lifecycle states. `none` is the implicit state for a brand-new user
/// before they've started a trial or subscribed.
enum SubscriptionStatus {
  /// User has never started a trial or subscribed.
  none,

  /// User is inside the free-trial window.
  trial,

  /// Paid, in the current billing period.
  active,

  /// User cancelled but is still inside the paid period (downgrades when
  /// `currentPeriodEndsAt` lapses).
  cancelled,

  /// Trial or paid period elapsed without renewal.
  expired,
}

class Subscription {
  const Subscription({
    required this.uid,
    required this.tier,
    required this.status,
    this.trialEndsAt,
    this.currentPeriodEndsAt,
    this.period = SubscriptionPeriod.monthly,
    this.seatCount = 1,
    this.seatedUids = const <String>[],
    this.isLifetime = false,
  });

  final String uid;
  final SubscriptionTier tier;
  final SubscriptionStatus status;

  /// Set while [status] is [SubscriptionStatus.trial]. The user automatically
  /// drops to [SubscriptionTier.free] when this passes.
  final DateTime? trialEndsAt;

  /// Set while [status] is [SubscriptionStatus.active] or
  /// [SubscriptionStatus.cancelled]. Defines when the paid entitlement ends.
  /// `null` for lifetime (no expiry).
  final DateTime? currentPeriodEndsAt;

  /// Billing cadence chosen at checkout. Mirrors Stripe's price + the
  /// app-side enum used by the picker UI.
  final SubscriptionPeriod period;

  /// Total seat count for family plans. 1 for individual / lifetime.
  final int seatCount;

  /// uids that have claimed a family-plan seat. Includes the owner.
  final List<String> seatedUids;

  /// True once a lifetime checkout has cleared. Mirrored on the donor
  /// wall as the LIFETIME badge.
  final bool isLifetime;

  static Subscription emptyFor(String uid) => Subscription(
        uid: uid,
        tier: SubscriptionTier.free,
        status: SubscriptionStatus.none,
      );

  Subscription copyWith({
    SubscriptionTier? tier,
    SubscriptionStatus? status,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEndsAt,
    SubscriptionPeriod? period,
    int? seatCount,
    List<String>? seatedUids,
    bool? isLifetime,
    bool clearTrial = false,
    bool clearPeriod = false,
  }) =>
      Subscription(
        uid: uid,
        tier: tier ?? this.tier,
        status: status ?? this.status,
        trialEndsAt:
            clearTrial ? null : (trialEndsAt ?? this.trialEndsAt),
        currentPeriodEndsAt: clearPeriod
            ? null
            : (currentPeriodEndsAt ?? this.currentPeriodEndsAt),
        period: period ?? this.period,
        seatCount: seatCount ?? this.seatCount,
        seatedUids: seatedUids ?? this.seatedUids,
        isLifetime: isLifetime ?? this.isLifetime,
      );

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'status': status.name,
        'period': period.name,
        'seatCount': seatCount,
        if (seatedUids.isNotEmpty) 'seatedUids': seatedUids,
        if (isLifetime) 'isLifetime': true,
        if (trialEndsAt != null)
          'trialEndsAt': trialEndsAt!.toIso8601String(),
        if (currentPeriodEndsAt != null)
          'currentPeriodEndsAt': currentPeriodEndsAt!.toIso8601String(),
      };

  factory Subscription.fromJson(String uid, Map<String, dynamic> j) {
    DateTime? parse(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      if (raw is DateTime) return raw;
      return null;
    }

    final tierName = j['tier'] as String? ?? 'free';
    final statusName = j['status'] as String? ?? 'none';
    final periodName = j['period'] as String? ?? 'monthly';
    return Subscription(
      uid: uid,
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => SubscriptionTier.free,
      ),
      status: SubscriptionStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => SubscriptionStatus.none,
      ),
      period: SubscriptionPeriod.values.firstWhere(
        (p) => p.name == periodName,
        orElse: () => SubscriptionPeriod.monthly,
      ),
      seatCount: (j['seatCount'] as num?)?.toInt() ?? 1,
      seatedUids:
          ((j['seatedUids'] as List?)?.cast<String>()) ?? const <String>[],
      isLifetime: j['isLifetime'] == true,
      trialEndsAt: parse(j['trialEndsAt']),
      currentPeriodEndsAt: parse(j['currentPeriodEndsAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subscription &&
          other.uid == uid &&
          other.tier == tier &&
          other.status == status &&
          other.trialEndsAt == trialEndsAt &&
          other.currentPeriodEndsAt == currentPeriodEndsAt &&
          other.period == period &&
          other.seatCount == seatCount &&
          _listEq(other.seatedUids, seatedUids) &&
          other.isLifetime == isLifetime;

  @override
  int get hashCode => Object.hash(uid, tier, status, trialEndsAt,
      currentPeriodEndsAt, period, seatCount, isLifetime);
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Computes the user's *effective* tier — the one the rest of the app
/// should gate features on. Pure: takes a [Subscription] + a clock.
///
/// Trials that have lapsed but haven't been written back to the store
/// still resolve to `free` here so the UI doesn't temporarily expose
/// premium features between expiry and the next sync.
SubscriptionTier effectiveTier(Subscription? sub, {DateTime? now}) {
  if (sub == null) return SubscriptionTier.free;
  final t = now ?? DateTime.now();
  switch (sub.status) {
    case SubscriptionStatus.trial:
      if (sub.trialEndsAt != null && t.isAfter(sub.trialEndsAt!)) {
        return SubscriptionTier.free;
      }
      return sub.tier;
    case SubscriptionStatus.active:
      if (sub.currentPeriodEndsAt != null &&
          t.isAfter(sub.currentPeriodEndsAt!)) {
        return SubscriptionTier.free;
      }
      return sub.tier;
    case SubscriptionStatus.cancelled:
      if (sub.currentPeriodEndsAt != null &&
          t.isAfter(sub.currentPeriodEndsAt!)) {
        return SubscriptionTier.free;
      }
      return sub.tier;
    case SubscriptionStatus.expired:
    case SubscriptionStatus.none:
      return SubscriptionTier.free;
  }
}
