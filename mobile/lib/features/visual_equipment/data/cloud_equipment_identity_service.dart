import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/firebase/functions_region.dart';
import 'equipment_identity.dart';
import 'identity_contract_version.dart';
import 'parsed_identity_text.dart';

/// The Cloud Function this surface calls
/// (`functions-equipment-identity/src/index.ts`'s `onCall` export). Named
/// once so [CloudEquipmentIdentityService] and its test cannot drift apart
/// on a typo -- the same convention `gemini_equipment_service.dart`'s
/// `kEquipmentRecognitionFunctionName` already uses.
const String kEquipmentIdentityFunctionName = 'equipmentIdentityResolveFromText';

/// Builds the request body for [kEquipmentIdentityFunctionName].
///
/// Pulled out and independently unit-tested against the SAME canonical
/// `core/equipment_identity/p2/equipment_identity_request_fixtures.json`
/// fixtures `functions-equipment-identity/src/p2/__tests__/contract.test.ts`
/// already validates server-side -- `FirebaseFunctions`/`HttpsCallable` have
/// private constructors, so this shape cannot be exercised through the real
/// SDK in a plain unit test, the same gap GPT-PM's G1 review named for
/// `buildEquipmentRecognitionRequest` (see that file's own doc comment).
///
/// `identityContractVersion`/`ocrVersion`/`identityParserVersion` are always
/// this build's OWN epoch constants (`identity_contract_version.dart`),
/// never a value the caller supplies -- a client can only honestly claim
/// the authority it actually has.
@visibleForTesting
Map<String, dynamic> buildEquipmentIdentityRequestBody({
  required String scanId,
  required ParsedIdentityText evidence,
  List<String> clientCapabilities = const [],
}) {
  return {
    'scanId': scanId,
    'identityContractVersion': kMobileIdentityContractVersion,
    'clientCapabilities': clientCapabilities,
    'evidence': {
      'brandCandidates': evidence.brandCandidates,
      'productLineCandidates': evidence.productLineCandidates,
      'modelCodeCandidates': evidence.modelCodeCandidates,
      'typeHints': evidence.typeHints,
      'conflicts': evidence.conflicts,
    },
    'ocrVersion': kOcrAuthorityEpoch,
    'identityParserVersion': kIdentityParserEpoch,
  };
}

/// Signature of "resolve this scan's text evidence into an equipment
/// identity" -- injectable for tests, mirroring `CloudRecognitionAsk`
/// (`gemini_equipment_service.dart`) one file over.
typedef EquipmentIdentityAsk = Future<EquipmentIdentity> Function({
  required String scanId,
  required ParsedIdentityText evidence,
});

/// Calls [kEquipmentIdentityFunctionName] and parses its reply through
/// [EquipmentIdentity.fromJson].
///
/// Deliberately thin: authentication/App-Check/timeout/network failures
/// surface as whatever `cloud_functions` throws (typically
/// `FirebaseFunctionsException`), and a malformed reply surfaces as
/// `FormatException` from `EquipmentIdentity.fromJson` -- this class does
/// not catch or reinterpret either. P2.G4 Step 3's `equipmentIdentityProvider`
/// is the boundary that decides those failures fail open to `null`; this
/// service's own job is only to make a well-formed request and refuse a
/// malformed reply, not to decide what the rest of the app does about it.
class CloudEquipmentIdentityService {
  CloudEquipmentIdentityService({FirebaseFunctions? functions}) : _injected = functions;

  final FirebaseFunctions? _injected;

  // Lazy, like `GeminiVisualEquipmentService._cloud` one file over: touching
  // `functionsForRegion` requires Firebase to already be initialized, so a
  // Provider default that merely CONSTRUCTS this class (never calling
  // `resolveFromText`) must not eagerly reach for it.
  late final FirebaseFunctions _fns = _injected ?? functionsForRegion;

  Future<EquipmentIdentity> resolveFromText({
    required String scanId,
    required ParsedIdentityText evidence,
  }) async {
    final body = buildEquipmentIdentityRequestBody(scanId: scanId, evidence: evidence);
    final result = await _fns
        .httpsCallable(kEquipmentIdentityFunctionName)
        .call<Map<String, dynamic>>(body);
    return EquipmentIdentity.fromJson(result.data);
  }
}
