import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/insurance/data/insurance_partner.dart';

void main() {
  final partner = InsurancePartner(
    id: 'aetna_demo',
    displayName: 'Demo Carrier',
    logoUrl: '',
    attestationEndpoint: 'https://example.com',
    requiredWeeklyWorkouts: 3,
    requiredWeeks: 4,
    payloadSchema: 'demo.v1',
  );

  test('qualifies when both thresholds met', () {
    final claim = AttestationClaim(
      enrolmentId: 'e1',
      partnerId: partner.id,
      weeksObserved: 4,
      weeklyWorkoutsAvg: 3.0,
      windowStart: DateTime.now().subtract(const Duration(days: 28)),
      windowEnd: DateTime.now(),
    );
    expect(qualifiesFor(partner, claim), isTrue);
  });

  test('disqualifies when weeks too short', () {
    final claim = AttestationClaim(
      enrolmentId: 'e1',
      partnerId: partner.id,
      weeksObserved: 3,
      weeklyWorkoutsAvg: 5.0,
      windowStart: DateTime.now().subtract(const Duration(days: 21)),
      windowEnd: DateTime.now(),
    );
    expect(qualifiesFor(partner, claim), isFalse);
  });

  test('disqualifies when frequency too low', () {
    final claim = AttestationClaim(
      enrolmentId: 'e1',
      partnerId: partner.id,
      weeksObserved: 8,
      weeklyWorkoutsAvg: 2.5,
      windowStart: DateTime.now().subtract(const Duration(days: 56)),
      windowEnd: DateTime.now(),
    );
    expect(qualifiesFor(partner, claim), isFalse);
  });
}
