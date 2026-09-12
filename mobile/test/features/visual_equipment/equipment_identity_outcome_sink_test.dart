import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity_outcome_sink.dart';

EquipmentIdentity _identity(Map<String, dynamic> overrides) {
  final base = <String, dynamic>{
    'scanId': 'scan-1',
    'recognitionSessionId': 'session-1',
    'identityContractVersion': 'v1',
    'authority': {
      'catalogVersion': 'cv-test',
      'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
      'textPolicyVersion': 'text-policy-v1',
      'fusionPolicyVersion': 'fusion-policy-v1',
      'identityPolicyVersion': 'identity-policy-v1',
    },
    'evidenceLane': 'TEXT_ONLY',
    'decision': 'MATCH',
    'identityLevel': 'EXACT_MODEL',
    'model': {
      'modelId': 'life-fitness-9nph-9-15',
      'catalogVersion': 'cv-test',
      'textSupportStatus': 'VERIFIED',
    },
    'verifierInvoked': false,
  }..addAll(overrides);
  return EquipmentIdentity.fromJson(base);
}

void main() {
  group('EquipmentIdentityOutcome.fromIdentity', () {
    test('two identical identities produce equal outcomes', () {
      final a = EquipmentIdentityOutcome.fromIdentity(_identity({}));
      final b = EquipmentIdentityOutcome.fromIdentity(_identity({}));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('same decision, different identityLevel -- NOT equal', () {
      final matchExact = EquipmentIdentityOutcome.fromIdentity(_identity({
        'identityLevel': 'EXACT_MODEL',
      }));
      final matchBrand = EquipmentIdentityOutcome.fromIdentity(_identity({
        'identityLevel': 'BRAND_AND_TYPE',
        'model': null,
        'decision': 'ABSTAIN',
        'abstainReason': 'INSUFFICIENT_EVIDENCE',
      }));
      expect(matchExact, isNot(matchBrand));
    });

    // GPT-PM pre-commit review (this gate), finding #4: the first
    // implementation captured only decision/identityLevel/model+shadow ids
    // and catalog versions/2-of-10 authority fields/abstain+failure --
    // silently treating two replies as identical even when they differed in
    // exactly these fields. Each mutation below proves one such field is
    // now part of the meaningful payload rather than silently ignored.
    group('every widened field is meaningful, not silently ignored', () {
      test('recognitionSessionId differs -- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(
            _identity({'recognitionSessionId': 'session-1'}));
        final b = EquipmentIdentityOutcome.fromIdentity(
            _identity({'recognitionSessionId': 'session-2'}));
        expect(a, isNot(b));
      });

      test('identityContractVersion differs -- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(
            _identity({'identityContractVersion': 'v1'}));
        final b = EquipmentIdentityOutcome.fromIdentity(
            _identity({'identityContractVersion': 'v2'}));
        expect(a, isNot(b));
      });

      test('evidenceLane differs (TEXT_ONLY vs VISUAL) -- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(
            _identity({'evidenceLane': 'TEXT_ONLY', 'verifierInvoked': false}));
        final b = EquipmentIdentityOutcome.fromIdentity(
            _identity({'evidenceLane': 'VISUAL', 'verifierInvoked': false}));
        expect(a, isNot(b));
      });

      test('verifierInvoked differs (VISUAL lane, which allows either) -- '
          'NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(
            _identity({'evidenceLane': 'VISUAL', 'verifierInvoked': false}));
        final b = EquipmentIdentityOutcome.fromIdentity(
            _identity({'evidenceLane': 'VISUAL', 'verifierInvoked': true}));
        expect(a, isNot(b));
      });

      test('authority.ocrVersion differs -- NOT equal (the whole authority '
          'tuple is now compared, not only catalog+identityPolicy version)',
          () {
        final a = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'ocr-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        final b = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'ocr-v2',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        expect(a, isNot(b));
      });

      test('authority.textPolicyVersion differs -- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        final b = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'textPolicyVersion': 'text-policy-v2',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        expect(a, isNot(b));
      });

      test('authority.fusionPolicyVersion differs -- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        final b = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v2',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        expect(a, isNot(b));
      });

      test('authority.identityParserVersion differs (one absent, one set) '
          '-- NOT equal', () {
        final a = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        final b = EquipmentIdentityOutcome.fromIdentity(_identity({
          'authority': {
            'catalogVersion': 'cv-test',
            'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
            'identityParserVersion': 'p2g2-identity-parser-v1',
            'textPolicyVersion': 'text-policy-v1',
            'fusionPolicyVersion': 'fusion-policy-v1',
            'identityPolicyVersion': 'identity-policy-v1',
          },
        }));
        expect(a, isNot(b));
      });
    });
  });

  group('InMemoryEquipmentIdentityOutcomeSink', () {
    test('first recordTerminal for a scanId is simply recorded, no conflict', () {
      final sink = InMemoryEquipmentIdentityOutcomeSink();
      final outcome = EquipmentIdentityOutcome.fromIdentity(_identity({}));
      sink.recordTerminal('scan-1', outcome);
      expect(sink.conflictedScanIds, isEmpty);
    });

    test('an identical replay for the same scanId is a silent no-op', () {
      final sink = InMemoryEquipmentIdentityOutcomeSink();
      final outcome = EquipmentIdentityOutcome.fromIdentity(_identity({}));
      sink.recordTerminal('scan-1', outcome);
      sink.recordTerminal('scan-1', outcome);
      sink.recordTerminal(
        'scan-1',
        EquipmentIdentityOutcome.fromIdentity(_identity({})),
      );
      expect(sink.conflictedScanIds, isEmpty);
    });

    test('a differing payload for the same scanId is flagged as a conflict', () {
      final sink = InMemoryEquipmentIdentityOutcomeSink();
      sink.recordTerminal(
        'scan-1',
        EquipmentIdentityOutcome.fromIdentity(_identity({})),
      );
      sink.recordTerminal(
        'scan-1',
        EquipmentIdentityOutcome.fromIdentity(_identity({
          'identityLevel': 'BRAND_AND_TYPE',
          'model': null,
          'decision': 'ABSTAIN',
          'abstainReason': 'INSUFFICIENT_EVIDENCE',
        })),
      );
      expect(sink.conflictedScanIds, {'scan-1'});
    });

    test('different scanIds never conflict with each other', () {
      final sink = InMemoryEquipmentIdentityOutcomeSink();
      sink.recordTerminal(
        'scan-1',
        EquipmentIdentityOutcome.fromIdentity(_identity({})),
      );
      sink.recordTerminal(
        'scan-2',
        EquipmentIdentityOutcome.fromIdentity(_identity({
          'decision': 'NOT_SUPPORTED',
          'identityLevel': null,
          'model': null,
        })),
      );
      expect(sink.conflictedScanIds, isEmpty);
    });
  });
}
