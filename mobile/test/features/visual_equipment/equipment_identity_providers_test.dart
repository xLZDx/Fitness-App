import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity_outcome_sink.dart';
import 'package:fitness_app/features/visual_equipment/data/identity_text_parser.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';
import 'package:fitness_app/features/visual_equipment/state/equipment_identity_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart'
    show machineTextRecogniserProvider;

const _fakeEvidence = MachineTextEvidence(fullText: 'LIFE FITNESS 9NPH', lines: []);

EquipmentIdentity _fakeIdentity(String scanId) => EquipmentIdentity.fromJson({
      'scanId': scanId,
      'recognitionSessionId': 'session-$scanId',
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
    });

class _FakeStructuredRecogniser implements StructuredTextRecogniser {
  _FakeStructuredRecogniser({this.throwing = false});

  final bool throwing;
  int readStructuredCalls = 0;

  @override
  Future<MachineTextEvidence> readStructured(String path) async {
    readStructuredCalls++;
    if (throwing) throw StateError('ocr failed');
    return _fakeEvidence;
  }

  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async => _fakeEvidence;

  @override
  Future<String> readText(String path) async => _fakeEvidence.fullText;

  @override
  Future<String> readFrame(InputImage input) async => _fakeEvidence.fullText;

  @override
  Future<void> dispose() async {}
}

class _PlainRecogniser implements MachineTextRecogniser {
  @override
  Future<String> readText(String path) async => '';
  @override
  Future<String> readFrame(InputImage input) async => '';
  @override
  Future<void> dispose() async {}
}

void main() {
  group('equipmentIdentityProvider', () {
    test('disabled by default: no OCR, no ask call, resolves null', () async {
      final recogniser = _FakeStructuredRecogniser();
      var askCalls = 0;
      final container = ProviderContainer(overrides: [
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          askCalls++;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
      expect(recogniser.readStructuredCalls, 0);
      expect(askCalls, 0);
    });

    test('enabled but no imagePath registered: resolves null, no OCR', () async {
      final recogniser = _FakeStructuredRecogniser();
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => const {}),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-missing').future);

      expect(result, isNull);
      expect(recogniser.readStructuredCalls, 0);
    });

    test('non-structured recogniser: resolves null, never calls ask', () async {
      var askCalls = 0;
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(_PlainRecogniser()),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          askCalls++;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
      expect(askCalls, 0);
    });

    test('enabled, real evidence: resolves the ask result, parses evidence first', () async {
      final recogniser = _FakeStructuredRecogniser();
      ParsedIdentityText? seenEvidence;
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          seenEvidence = evidence;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(recogniser.readStructuredCalls, 1);
      expect(result?.scanId, 'scan-1');
      expect(
        seenEvidence,
        parseIdentityText(_fakeEvidence, lexicon: const IdentityLexicon()),
      );
    });

    test('OCR throws: fails open to null, never reaches ask', () async {
      final recogniser = _FakeStructuredRecogniser(throwing: true);
      var askCalls = 0;
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          askCalls++;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
      expect(askCalls, 0);
    });

    test('ask throws: fails open to null', () async {
      final recogniser = _FakeStructuredRecogniser();
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          throw StateError('backend unavailable');
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
    });

    test('disposed and recreated family instance for the SAME scanId still resolves', () async {
      final recogniser = _FakeStructuredRecogniser();
      var askCalls = 0;
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          askCalls++;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final first = await container.read(equipmentIdentityProvider('scan-1').future);
      expect(first?.scanId, 'scan-1');
      expect(askCalls, 1);

      // Simulates transient unwatch/rewatch churn (autoDispose tearing the
      // family instance down and recreating it) WITHOUT the scan itself
      // ending -- scanIdImagePathProvider's entry is untouched, exactly as
      // it would be if only `_scanAgain()` clears it (never this family's
      // own dispose). GPT-PM round-3's own regression requirement.
      container.invalidate(equipmentIdentityProvider('scan-1'));

      final second = await container.read(equipmentIdentityProvider('scan-1').future);
      expect(second?.scanId, 'scan-1');
      expect(askCalls, 2);
    });

    test('a genuine terminal answer is recorded in the outcome sink (Step 8)', () async {
      final recogniser = _FakeStructuredRecogniser();
      final sink = _SpyOutcomeSink();
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityOutcomeSinkProvider.overrideWithValue(sink),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async =>
            _fakeIdentity(scanId)),
      ]);
      addTearDown(container.dispose);

      await container.read(equipmentIdentityProvider('scan-1').future);

      expect(sink.recordedCalls, 1);
      expect(sink.conflictedScanIds, isEmpty);
    });

    test('a fail-open null (OCR failure) never reaches the outcome sink', () async {
      final recogniser = _FakeStructuredRecogniser(throwing: true);
      final sink = _SpyOutcomeSink();
      var askCalls = 0;
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityOutcomeSinkProvider.overrideWithValue(sink),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          askCalls++;
          return _fakeIdentity(scanId);
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
      expect(askCalls, 0);
      expect(sink.recordedCalls, 0);
    });

    test('an ask failure never reaches the outcome sink', () async {
      final recogniser = _FakeStructuredRecogniser();
      final sink = _SpyOutcomeSink();
      final container = ProviderContainer(overrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        machineTextRecogniserProvider.overrideWithValue(recogniser),
        scanIdImagePathProvider.overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        equipmentIdentityOutcomeSinkProvider.overrideWithValue(sink),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async {
          throw StateError('backend unavailable');
        }),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(equipmentIdentityProvider('scan-1').future);

      expect(result, isNull);
      expect(sink.recordedCalls, 0);
    });
  });
}

class _SpyOutcomeSink implements EquipmentIdentityOutcomeSink {
  int recordedCalls = 0;
  final _delegate = InMemoryEquipmentIdentityOutcomeSink();

  @override
  void recordTerminal(String scanId, EquipmentIdentityOutcome outcome) {
    recordedCalls++;
    _delegate.recordTerminal(scanId, outcome);
  }

  @override
  Set<String> get conflictedScanIds => _delegate.conflictedScanIds;
}
