/// MK.5 — White-Label Gym Chain SDK foundations.
///
/// A shipping SDK has three pieces:
///   1. Partner-config: branding, colour palette, feature flags.
///   2. SSO bridge: signs gym-issued JWTs we can convert to Firebase
///      custom tokens via a Cloud Function.
///   3. Embeddable views: HomePage / ScannerPage / WorkoutPlayerPage as
///      reusable widgets a partner host app can drop into a tab.
///
/// MVP defines the config model + the JWT envelope. The reusable
/// widgets ship in a follow-up; existing pages are already stateless +
/// Riverpod-bound, so the lift is mostly packaging not rewriting.
class WhiteLabelConfig {
  const WhiteLabelConfig({
    required this.partnerId,
    required this.brandName,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.logoUrl,
    this.enabledFeatures = const {
      'home',
      'scanner',
      'workouts',
      'progress',
    },
    this.disableSubscriptionUpsell = false,
    this.useLocalisedTrademarks = const {},
  });

  final String partnerId;
  final String brandName;
  final String primaryColorHex;
  final String secondaryColorHex;
  final String logoUrl;
  final Set<String> enabledFeatures;

  /// True for partners who already collect membership fees and don't
  /// want a competing donation prompt in their app shell.
  final bool disableSubscriptionUpsell;

  /// "Workout" → "Class" for studios; "Equipment" → "Apparatus" for
  /// some chains. Strings.xml-style overrides without platform
  /// localisation cost.
  final Map<String, String> useLocalisedTrademarks;
}

/// JWT we accept from partner SSO. The Cloud Function `signInAsPartner`
/// validates the signature against the partner's public key registered
/// at `partners/{partnerId}.publicKeyPem`.
class PartnerSsoToken {
  const PartnerSsoToken({
    required this.partnerId,
    required this.partnerMemberId,
    required this.expiresAt,
    required this.rawJwt,
    this.email,
    this.displayName,
  });

  final String partnerId;
  final String partnerMemberId;
  final DateTime expiresAt;
  final String rawJwt;
  final String? email;
  final String? displayName;
}
