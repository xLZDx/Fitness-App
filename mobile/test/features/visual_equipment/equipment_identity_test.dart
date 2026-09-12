import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';

/// Same canonical fixture file
/// `functions-equipment-identity/src/p2/__tests__/contract.test.ts` already
/// validates against the real `EquipmentIdentityResponseSchema` -- proving
/// Dart/TS parity from one shared source rather than two independently
/// hand-typed ones (GPT-PM round-3 requirement, P2.G4 Rosetta plan rev4).
const _fixturesPath =
    '../core/equipment_identity/p2/equipment_identity_response_fixtures.json';

void main() {
  late Map<String, dynamic> fixtures;

  setUpAll(() {
    final raw = File(_fixturesPath).readAsStringSync();
    fixtures = jsonDecode(raw) as Map<String, dynamic>;
  });

  group('EquipmentIdentity.fromJson -- shared valid fixtures', () {
    final cases = <String, Map<String, dynamic>>{};
    setUpAll(() {
      for (final c in fixtures['validCases'] as List) {
        final m = c as Map<String, dynamic>;
        cases[m['name'] as String] = m['response'] as Map<String, dynamic>;
      }
    });

    test('every valid case round-trips through fromJson/toJson', () {
      for (final c in fixtures['validCases'] as List) {
        final m = c as Map<String, dynamic>;
        final name = m['name'] as String;
        final response = m['response'] as Map<String, dynamic>;
        late final EquipmentIdentity identity;
        try {
          identity = EquipmentIdentity.fromJson(response);
        } catch (e) {
          fail('valid fixture "$name" was rejected: $e');
        }
        // Re-serializing and re-parsing must reproduce the same object --
        // proves toJson is a real inverse of fromJson, not merely present.
        final roundTripped = EquipmentIdentity.fromJson(identity.toJson());
        expect(roundTripped.scanId, identity.scanId, reason: name);
        expect(roundTripped.decision, identity.decision, reason: name);
        expect(roundTripped.identityLevel, identity.identityLevel, reason: name);
        expect(roundTripped.abstainReason, identity.abstainReason, reason: name);
        expect(roundTripped.failureCode, identity.failureCode, reason: name);
        expect(roundTripped.verifierInvoked, identity.verifierInvoked, reason: name);
      }
    });

    test('match_exact_model carries a VERIFIED model, no shadowCandidate', () {
      final identity = EquipmentIdentity.fromJson(cases['match_exact_model']!);
      expect(identity.decision, EquipmentIdentityDecision.match);
      expect(identity.identityLevel, EquipmentIdentityLevel.exactModel);
      expect(identity.model, isNotNull);
      expect(identity.model!.modelId, 'life-fitness-9nph-9-15');
      expect(identity.shadowCandidate, isNull);
      expect(identity.verifierInvoked, isFalse);
    });

    test('match_shadow_candidate_experimental carries shadowCandidate, no model', () {
      final identity =
          EquipmentIdentity.fromJson(cases['match_shadow_candidate_experimental']!);
      expect(identity.decision, EquipmentIdentityDecision.abstain);
      expect(identity.abstainReason, EquipmentIdentityAbstainReason.insufficientEvidence);
      expect(identity.model, isNull);
      expect(identity.shadowCandidate, isNotNull);
      expect(identity.shadowCandidate!.modelId, 'star-trac-8trx');
    });

    test('unavailable_timeout carries a matching failureCode', () {
      final identity = EquipmentIdentity.fromJson(cases['unavailable_timeout']!);
      expect(identity.decision, EquipmentIdentityDecision.unavailableTimeout);
      expect(identity.failureCode, EquipmentIdentityFailureCode.timeout);
    });

    test('type_only_identity_level / brand_and_type / product_line parse distinctly', () {
      expect(
        EquipmentIdentity.fromJson(cases['type_only_identity_level']!).identityLevel,
        EquipmentIdentityLevel.typeOnly,
      );
      expect(
        EquipmentIdentity.fromJson(cases['brand_and_type_identity_level']!).identityLevel,
        EquipmentIdentityLevel.brandAndType,
      );
      expect(
        EquipmentIdentity.fromJson(cases['product_line_identity_level']!).identityLevel,
        EquipmentIdentityLevel.productLine,
      );
    });

    test('authority tuple parses with and without identityParserVersion', () {
      final withParser = EquipmentIdentity.fromJson(cases['match_exact_model']!);
      expect(withParser.authority.identityParserVersion, 'p2g2-identity-parser-v1');

      final withoutParser = EquipmentIdentity.fromJson(cases['abstain_low_confidence']!);
      expect(withoutParser.authority.identityParserVersion, isNull);
    });
  });

  group('EquipmentIdentity.fromJson -- shared invalid fixtures', () {
    test('every invalid case throws FormatException', () {
      for (final c in fixtures['invalidCases'] as List) {
        final m = c as Map<String, dynamic>;
        final name = m['name'] as String;
        final response = m['response'] as Map<String, dynamic>;
        expect(
          () => EquipmentIdentity.fromJson(response),
          throwsFormatException,
          reason: 'invalid fixture "$name" should have been rejected',
        );
      }
    });
  });
}
