/// MK.4 — Insurance discount partnerships.
///
/// MVP shape: insurance partners give us an attestation endpoint we can
/// hit (server-to-server) to confirm a member's premium-discount
/// eligibility based on adherence metrics. We never share PHI with the
/// carrier; we share a signed claim like "this enrolment id has hit ≥3
/// workouts/wk for ≥4 weeks".
class InsurancePartner {
  const InsurancePartner({
    required this.id,
    required this.displayName,
    required this.logoUrl,
    required this.attestationEndpoint,
    required this.requiredWeeklyWorkouts,
    required this.requiredWeeks,
    required this.payloadSchema,
  });

  final String id;
  final String displayName;
  final String logoUrl;
  final String attestationEndpoint;
  final int requiredWeeklyWorkouts;
  final int requiredWeeks;

  /// JSON-schema id describing the attestation payload shape. Each
  /// partner gets its own schema; we pin via id so we can roll out
  /// changes carefully.
  final String payloadSchema;
}

class AttestationClaim {
  const AttestationClaim({
    required this.enrolmentId,
    required this.partnerId,
    required this.weeksObserved,
    required this.weeklyWorkoutsAvg,
    required this.windowStart,
    required this.windowEnd,
  });

  final String enrolmentId;
  final String partnerId;
  final int weeksObserved;
  final double weeklyWorkoutsAvg;
  final DateTime windowStart;
  final DateTime windowEnd;
}

/// Pure: does the user qualify under [partner]'s rules?
bool qualifiesFor(InsurancePartner partner, AttestationClaim claim) {
  return claim.weeksObserved >= partner.requiredWeeks &&
      claim.weeklyWorkoutsAvg >= partner.requiredWeeklyWorkouts;
}
