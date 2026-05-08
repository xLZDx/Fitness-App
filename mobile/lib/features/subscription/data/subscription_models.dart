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
  });

  final String uid;
  final SubscriptionTier tier;
  final SubscriptionStatus status;

  /// Set while [status] is [SubscriptionStatus.trial]. The user automatically
  /// drops to [SubscriptionTier.free] when this passes.
  final DateTime? trialEndsAt;

  /// Set while [status] is [SubscriptionStatus.active] or
  /// [SubscriptionStatus.cancelled]. Defines when the paid entitlement ends.
  final DateTime? currentPeriodEndsAt;

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
      );

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'status': status.name,
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
          other.currentPeriodEndsAt == currentPeriodEndsAt;

  @override
  int get hashCode =>
      Object.hash(uid, tier, status, trialEndsAt, currentPeriodEndsAt);
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
