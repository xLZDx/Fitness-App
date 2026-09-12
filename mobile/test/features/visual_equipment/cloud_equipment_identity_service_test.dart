import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/visual_equipment/data/cloud_equipment_identity_service.dart';
import 'package:fitness_app/features/visual_equipment/data/identity_contract_version.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';

/// Same canonical fixture file the server side validates
/// (`functions-equipment-identity/src/p2/__tests__/contract.test.ts`) --
/// proves the client's request builder produces exactly the shape the
/// server accepts, from one shared source (GPT-PM round-3 requirement,
/// P2.G4 Rosetta plan rev4).
const _fixturesPath =
    '../core/equipment_identity/p2/equipment_identity_request_fixtures.json';

ParsedIdentityText _evidenceFromFixture(Map<String, dynamic> evidence) {
  return ParsedIdentityText(
    brandCandidates: (evidence['brandCandidates'] as List).cast<String>(),
    productLineCandidates:
        (evidence['productLineCandidates'] as List).cast<String>(),
    modelCodeCandidates: (evidence['modelCodeCandidates'] as List).cast<String>(),
    typeHints: (evidence['typeHints'] as List).cast<String>(),
    conflicts: (evidence['conflicts'] as List).cast<String>(),
  );
}

void main() {
  late Map<String, dynamic> fixtures;

  setUpAll(() {
    final raw = File(_fixturesPath).readAsStringSync();
    fixtures = jsonDecode(raw) as Map<String, dynamic>;
  });

  group('buildEquipmentIdentityRequestBody', () {
    test('always sends this build\'s own version constants, not the fixture\'s', () {
      // The fixtures were authored against a hypothetical caller and may
      // record a different identityParserVersion/ocrVersion than THIS
      // build's own epoch constants -- the builder must never echo a
      // caller-supplied version back, only ever emit its own (see the
      // function's own doc comment on why).
      final body = buildEquipmentIdentityRequestBody(
        scanId: 'scan-req-fixture-001',
        evidence: const ParsedIdentityText(
          brandCandidates: ['Life Fitness'],
          productLineCandidates: ['Inspiration'],
          modelCodeCandidates: ['9NPH'],
          typeHints: ['leg press'],
        ),
        clientCapabilities: const ['MULTI_VIEW'],
      );

      expect(body['scanId'], 'scan-req-fixture-001');
      expect(body['identityContractVersion'], kMobileIdentityContractVersion);
      expect(body['ocrVersion'], kOcrAuthorityEpoch);
      expect(body['identityParserVersion'], kIdentityParserEpoch);
      expect(body['clientCapabilities'], ['MULTI_VIEW']);
      expect(body['evidence'], {
        'brandCandidates': ['Life Fitness'],
        'productLineCandidates': ['Inspiration'],
        'modelCodeCandidates': ['9NPH'],
        'typeHints': ['leg press'],
        'conflicts': <String>[],
      });
    });

    test('matches the shared fixture shape field-for-field on every valid case', () {
      for (final c in fixtures['validCases'] as List) {
        final m = c as Map<String, dynamic>;
        final name = m['name'] as String;
        final request = m['request'] as Map<String, dynamic>;
        final evidence = _evidenceFromFixture(
          request['evidence'] as Map<String, dynamic>,
        );
        final body = buildEquipmentIdentityRequestBody(
          scanId: request['scanId'] as String,
          evidence: evidence,
          clientCapabilities:
              (request['clientCapabilities'] as List).cast<String>(),
        );

        // identityContractVersion/ocrVersion/identityParserVersion are this
        // build's own constants, not the fixture's recorded values -- only
        // the CALLER-supplied fields (scanId/clientCapabilities/evidence)
        // are expected to match verbatim.
        expect(body['scanId'], request['scanId'], reason: name);
        expect(body['clientCapabilities'], request['clientCapabilities'], reason: name);
        expect(body['evidence'], request['evidence'], reason: name);
        expect(body['identityContractVersion'], kMobileIdentityContractVersion, reason: name);
      }
    });

    test('evidence_array_at_max_bound: 20-entry array passes through unmodified', () {
      final fixtureCase = (fixtures['validCases'] as List).firstWhere(
        (c) => (c as Map<String, dynamic>)['name'] == 'evidence_array_at_max_bound',
      ) as Map<String, dynamic>;
      final request = fixtureCase['request'] as Map<String, dynamic>;
      final evidence = _evidenceFromFixture(request['evidence'] as Map<String, dynamic>);

      final body = buildEquipmentIdentityRequestBody(
        scanId: request['scanId'] as String,
        evidence: evidence,
      );

      expect((body['evidence'] as Map)['modelCodeCandidates'], hasLength(20));
    });
  });
}
