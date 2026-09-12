import 'package:flutter/foundation.dart';

/// Client-side mirror of `functions-equipment-identity/src/p2/contract.ts`'s
/// `EquipmentIdentityResponseSchema`.
///
/// ## Why this duplicates the server's invariants instead of trusting it
///
/// The server is the source of truth for the *contract*, but a client that
/// only reads the fields it expects and ignores the rest would silently
/// accept a response that violates its own binding rules (a `MATCH` with no
/// `model`, both `model` and `shadowCandidate` set, and so on) and build a
/// UI on top of a claim that was never actually made. `EquipmentIdentity.
/// fromJson` re-checks every `.superRefine()` invariant the server enforces
/// and throws `FormatException` if any of them is violated, so a malformed
/// or unexpected response fails loudly here rather than reaching a widget
/// that assumes the invariant already holds.
///
/// Hand-written `fromJson`/`toJson`, no codegen -- this project has no
/// `json_serializable`/`freezed` dependency (verified against
/// `mobile/pubspec.yaml`); the convention this file follows is
/// `machine_card.dart`'s.
@immutable
class RecognitionAuthorityTuple {
  const RecognitionAuthorityTuple({
    required this.catalogVersion,
    required this.ocrVersion,
    this.identityParserVersion,
    required this.textPolicyVersion,
    required this.fusionPolicyVersion,
    required this.identityPolicyVersion,
    this.embeddingModelVersion,
    this.embeddingIndexVersion,
    this.exemplarSetVersion,
    this.verifierModelVersion,
  });

  final String catalogVersion;
  final String ocrVersion;
  final String? identityParserVersion;
  final String textPolicyVersion;
  final String fusionPolicyVersion;
  final String identityPolicyVersion;
  final String? embeddingModelVersion;
  final String? embeddingIndexVersion;
  final String? exemplarSetVersion;
  final String? verifierModelVersion;

  // GPT-PM pre-commit review (this gate): needed so `EquipmentIdentityOutcome`
  // (`equipment_identity_outcome_sink.dart`) can compare the COMPLETE
  // authority tuple rather than only 2 of its 10 fields -- see that file's
  // own doc comment for why a policy/algorithm-version divergence between two
  // terminal replies for the same scanId must be a detected conflict, not
  // silently normalised away.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecognitionAuthorityTuple &&
          other.catalogVersion == catalogVersion &&
          other.ocrVersion == ocrVersion &&
          other.identityParserVersion == identityParserVersion &&
          other.textPolicyVersion == textPolicyVersion &&
          other.fusionPolicyVersion == fusionPolicyVersion &&
          other.identityPolicyVersion == identityPolicyVersion &&
          other.embeddingModelVersion == embeddingModelVersion &&
          other.embeddingIndexVersion == embeddingIndexVersion &&
          other.exemplarSetVersion == exemplarSetVersion &&
          other.verifierModelVersion == verifierModelVersion);

  @override
  int get hashCode => Object.hash(
        catalogVersion,
        ocrVersion,
        identityParserVersion,
        textPolicyVersion,
        fusionPolicyVersion,
        identityPolicyVersion,
        embeddingModelVersion,
        embeddingIndexVersion,
        exemplarSetVersion,
        verifierModelVersion,
      );

  static const _allowedKeys = {
    'catalogVersion',
    'ocrVersion',
    'identityParserVersion',
    'textPolicyVersion',
    'fusionPolicyVersion',
    'identityPolicyVersion',
    'embeddingModelVersion',
    'embeddingIndexVersion',
    'exemplarSetVersion',
    'verifierModelVersion',
  };

  static RecognitionAuthorityTuple fromJson(Map<String, dynamic> j) {
    final unknown = j.keys.where((k) => !_allowedKeys.contains(k));
    if (unknown.isNotEmpty) {
      throw FormatException('authority: unrecognised field(s): ${unknown.join(', ')}');
    }
    return RecognitionAuthorityTuple(
      catalogVersion: _requireString(j, 'catalogVersion'),
      ocrVersion: _requireString(j, 'ocrVersion'),
      identityParserVersion: _optionalString(j, 'identityParserVersion'),
      textPolicyVersion: _requireString(j, 'textPolicyVersion'),
      fusionPolicyVersion: _requireString(j, 'fusionPolicyVersion'),
      identityPolicyVersion: _requireString(j, 'identityPolicyVersion'),
      embeddingModelVersion: _optionalString(j, 'embeddingModelVersion'),
      embeddingIndexVersion: _optionalString(j, 'embeddingIndexVersion'),
      exemplarSetVersion: _optionalString(j, 'exemplarSetVersion'),
      verifierModelVersion: _optionalString(j, 'verifierModelVersion'),
    );
  }

  Map<String, dynamic> toJson() => {
        'catalogVersion': catalogVersion,
        'ocrVersion': ocrVersion,
        if (identityParserVersion != null)
          'identityParserVersion': identityParserVersion,
        'textPolicyVersion': textPolicyVersion,
        'fusionPolicyVersion': fusionPolicyVersion,
        'identityPolicyVersion': identityPolicyVersion,
        if (embeddingModelVersion != null)
          'embeddingModelVersion': embeddingModelVersion,
        if (embeddingIndexVersion != null)
          'embeddingIndexVersion': embeddingIndexVersion,
        if (exemplarSetVersion != null) 'exemplarSetVersion': exemplarSetVersion,
        if (verifierModelVersion != null)
          'verifierModelVersion': verifierModelVersion,
      };
}

enum EvidenceLane { textOnly, visual }

const Map<String, EvidenceLane> _evidenceLaneWire = {
  'TEXT_ONLY': EvidenceLane.textOnly,
  'VISUAL': EvidenceLane.visual,
};

enum EquipmentIdentityDecision {
  match,
  abstain,
  needMoreView,
  notSupported,
  cancelledStale,
  unsupportedClientContract,
  unavailableTimeout,
  unavailableNetwork,
  unavailableAppcheck,
  unavailableRateLimit,
  unavailableBackend,
  unavailableCatalogVersion,
}

const Map<String, EquipmentIdentityDecision> _decisionWire = {
  'MATCH': EquipmentIdentityDecision.match,
  'ABSTAIN': EquipmentIdentityDecision.abstain,
  'NEED_MORE_VIEW': EquipmentIdentityDecision.needMoreView,
  'NOT_SUPPORTED': EquipmentIdentityDecision.notSupported,
  'CANCELLED_STALE': EquipmentIdentityDecision.cancelledStale,
  'UNSUPPORTED_CLIENT_CONTRACT': EquipmentIdentityDecision.unsupportedClientContract,
  'UNAVAILABLE_TIMEOUT': EquipmentIdentityDecision.unavailableTimeout,
  'UNAVAILABLE_NETWORK': EquipmentIdentityDecision.unavailableNetwork,
  'UNAVAILABLE_APPCHECK': EquipmentIdentityDecision.unavailableAppcheck,
  'UNAVAILABLE_RATE_LIMIT': EquipmentIdentityDecision.unavailableRateLimit,
  'UNAVAILABLE_BACKEND': EquipmentIdentityDecision.unavailableBackend,
  'UNAVAILABLE_CATALOG_VERSION': EquipmentIdentityDecision.unavailableCatalogVersion,
};

const Set<EquipmentIdentityDecision> _unavailableDecisions = {
  EquipmentIdentityDecision.unavailableTimeout,
  EquipmentIdentityDecision.unavailableNetwork,
  EquipmentIdentityDecision.unavailableAppcheck,
  EquipmentIdentityDecision.unavailableRateLimit,
  EquipmentIdentityDecision.unavailableBackend,
  EquipmentIdentityDecision.unavailableCatalogVersion,
};

enum EquipmentIdentityLevel { typeOnly, brandAndType, productLine, exactModel }

const Map<String, EquipmentIdentityLevel> _identityLevelWire = {
  'TYPE_ONLY': EquipmentIdentityLevel.typeOnly,
  'BRAND_AND_TYPE': EquipmentIdentityLevel.brandAndType,
  'PRODUCT_LINE': EquipmentIdentityLevel.productLine,
  'EXACT_MODEL': EquipmentIdentityLevel.exactModel,
};

enum EquipmentIdentityAbstainReason {
  lowConfidence,
  outOfDistribution,
  evidenceConflict,
  insufficientEvidence,
}

const Map<String, EquipmentIdentityAbstainReason> _abstainReasonWire = {
  'LOW_CONFIDENCE': EquipmentIdentityAbstainReason.lowConfidence,
  'OUT_OF_DISTRIBUTION': EquipmentIdentityAbstainReason.outOfDistribution,
  'EVIDENCE_CONFLICT': EquipmentIdentityAbstainReason.evidenceConflict,
  'INSUFFICIENT_EVIDENCE': EquipmentIdentityAbstainReason.insufficientEvidence,
};

enum EquipmentIdentityFailureCode {
  timeout,
  network,
  appcheck,
  rateLimited,
  backendError,
  embeddingFailure,
  indexUnavailable,
  verifierSchemaViolation,
  catalogVersionUnavailable,
}

const Map<String, EquipmentIdentityFailureCode> _failureCodeWire = {
  'TIMEOUT': EquipmentIdentityFailureCode.timeout,
  'NETWORK': EquipmentIdentityFailureCode.network,
  'APPCHECK': EquipmentIdentityFailureCode.appcheck,
  'RATE_LIMITED': EquipmentIdentityFailureCode.rateLimited,
  'BACKEND_ERROR': EquipmentIdentityFailureCode.backendError,
  'EMBEDDING_FAILURE': EquipmentIdentityFailureCode.embeddingFailure,
  'INDEX_UNAVAILABLE': EquipmentIdentityFailureCode.indexUnavailable,
  'VERIFIER_SCHEMA_VIOLATION': EquipmentIdentityFailureCode.verifierSchemaViolation,
  'CATALOG_VERSION_UNAVAILABLE': EquipmentIdentityFailureCode.catalogVersionUnavailable,
};

/// An authoritative exact-match claim. Always `textSupportStatus ==
/// 'VERIFIED'` on the wire -- see `EquipmentIdentityShadowCandidate` for
/// where a non-authoritative candidate goes instead.
@immutable
class EquipmentIdentityModel {
  const EquipmentIdentityModel({
    required this.modelId,
    required this.catalogVersion,
  });

  final String modelId;
  final String catalogVersion;

  static EquipmentIdentityModel fromJson(Map<String, dynamic> j) {
    final status = j['textSupportStatus'];
    if (status != 'VERIFIED') {
      throw const FormatException(
        "model.textSupportStatus must be 'VERIFIED'",
      );
    }
    return EquipmentIdentityModel(
      modelId: _requireString(j, 'modelId'),
      catalogVersion: _requireString(j, 'catalogVersion'),
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'catalogVersion': catalogVersion,
        'textSupportStatus': 'VERIFIED',
      };
}

/// A non-authoritative EXPERIMENTAL-text-support candidate -- never a MATCH
/// claim. See `functions-equipment-identity/src/p2/contract.ts`'s
/// `ShadowCandidateSchema` doc comment for why this exists as a separate
/// field rather than a marker on `model`.
@immutable
class EquipmentIdentityShadowCandidate {
  const EquipmentIdentityShadowCandidate({
    required this.modelId,
    required this.catalogVersion,
  });

  final String modelId;
  final String catalogVersion;

  static EquipmentIdentityShadowCandidate fromJson(Map<String, dynamic> j) {
    final status = j['textSupportStatus'];
    if (status != 'EXPERIMENTAL') {
      throw const FormatException(
        "shadowCandidate.textSupportStatus must be 'EXPERIMENTAL'",
      );
    }
    return EquipmentIdentityShadowCandidate(
      modelId: _requireString(j, 'modelId'),
      catalogVersion: _requireString(j, 'catalogVersion'),
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'catalogVersion': catalogVersion,
        'textSupportStatus': 'EXPERIMENTAL',
      };
}

/// Client-side mirror of the server's `EquipmentIdentityResponseSchema`.
///
/// Every invariant the server's `.superRefine()` enforces is re-checked in
/// [fromJson]: an omitted or malformed invariant throws `FormatException`
/// rather than silently producing an object the rest of the app would then
/// have to re-validate itself. Callers (P2.G4 Step 3's
/// `equipmentIdentityProvider`) catch that exception and fail open to
/// `null` -- this class never does that itself, so the failure mode is
/// visible at the boundary that decided it was safe to swallow.
@immutable
class EquipmentIdentity {
  const EquipmentIdentity({
    required this.scanId,
    required this.recognitionSessionId,
    required this.identityContractVersion,
    required this.authority,
    required this.evidenceLane,
    required this.decision,
    this.identityLevel,
    this.model,
    this.shadowCandidate,
    this.abstainReason,
    this.failureCode,
    required this.verifierInvoked,
  });

  final String scanId;
  final String recognitionSessionId;
  final String identityContractVersion;
  final RecognitionAuthorityTuple authority;
  final EvidenceLane evidenceLane;
  final EquipmentIdentityDecision decision;
  final EquipmentIdentityLevel? identityLevel;
  final EquipmentIdentityModel? model;
  final EquipmentIdentityShadowCandidate? shadowCandidate;
  final EquipmentIdentityAbstainReason? abstainReason;
  final EquipmentIdentityFailureCode? failureCode;
  final bool verifierInvoked;

  static const _allowedKeys = {
    'scanId',
    'recognitionSessionId',
    'identityContractVersion',
    'authority',
    'evidenceLane',
    'decision',
    'identityLevel',
    'abstainReason',
    'failureCode',
    'model',
    'shadowCandidate',
    'verifierInvoked',
  };

  static EquipmentIdentity fromJson(Map<String, dynamic> j) {
    final unknown = j.keys.where((k) => !_allowedKeys.contains(k));
    if (unknown.isNotEmpty) {
      throw FormatException('unrecognised field(s): ${unknown.join(', ')}');
    }

    final evidenceLane = _requireEnum(j, 'evidenceLane', _evidenceLaneWire);
    final decision = _requireEnum(j, 'decision', _decisionWire);
    final verifierInvoked = j['verifierInvoked'];
    if (verifierInvoked is! bool) {
      throw const FormatException('verifierInvoked is required and must be a bool');
    }

    if (evidenceLane == EvidenceLane.textOnly && verifierInvoked != false) {
      throw const FormatException(
        'TEXT_ONLY evidenceLane requires verifierInvoked === false',
      );
    }

    final modelJson = j['model'];
    final model = modelJson == null
        ? null
        : EquipmentIdentityModel.fromJson(_asStringKeyedMap(modelJson, 'model'));
    if (decision == EquipmentIdentityDecision.match) {
      if (model == null) {
        throw const FormatException('decision MATCH requires model');
      }
    } else if (model != null) {
      throw const FormatException('model is present but decision is not MATCH');
    }

    final shadowCandidateJson = j['shadowCandidate'];
    final shadowCandidate = shadowCandidateJson == null
        ? null
        : EquipmentIdentityShadowCandidate.fromJson(
            _asStringKeyedMap(shadowCandidateJson, 'shadowCandidate'),
          );
    if (model != null && shadowCandidate != null) {
      throw const FormatException('model and shadowCandidate are mutually exclusive');
    }

    final abstainReason = _optionalEnum(j, 'abstainReason', _abstainReasonWire);
    final failureCode = _optionalEnum(j, 'failureCode', _failureCodeWire);
    if (abstainReason != null && failureCode != null) {
      throw const FormatException('abstainReason and failureCode are mutually exclusive');
    }
    if (abstainReason != null && decision != EquipmentIdentityDecision.abstain) {
      throw const FormatException('abstainReason is present but decision is not ABSTAIN');
    }
    final isUnavailable = _unavailableDecisions.contains(decision);
    if (isUnavailable && failureCode == null) {
      throw FormatException('decision $decision requires a failureCode');
    }
    if (!isUnavailable && failureCode != null) {
      throw const FormatException(
        'failureCode is present but decision is not an UNAVAILABLE_* value',
      );
    }

    return EquipmentIdentity(
      scanId: _requireString(j, 'scanId'),
      recognitionSessionId: _requireString(j, 'recognitionSessionId'),
      identityContractVersion: _requireString(j, 'identityContractVersion'),
      authority: RecognitionAuthorityTuple.fromJson(
        _asStringKeyedMap(j['authority'], 'authority'),
      ),
      evidenceLane: evidenceLane,
      decision: decision,
      identityLevel: _optionalEnum(j, 'identityLevel', _identityLevelWire),
      model: model,
      shadowCandidate: shadowCandidate,
      abstainReason: abstainReason,
      failureCode: failureCode,
      verifierInvoked: verifierInvoked,
    );
  }

  Map<String, dynamic> toJson() => {
        'scanId': scanId,
        'recognitionSessionId': recognitionSessionId,
        'identityContractVersion': identityContractVersion,
        'authority': authority.toJson(),
        'evidenceLane': _wireNameOf(_evidenceLaneWire, evidenceLane),
        'decision': _wireNameOf(_decisionWire, decision),
        if (identityLevel != null)
          'identityLevel': _wireNameOf(_identityLevelWire, identityLevel!),
        if (model != null) 'model': model!.toJson(),
        if (shadowCandidate != null) 'shadowCandidate': shadowCandidate!.toJson(),
        if (abstainReason != null)
          'abstainReason': _wireNameOf(_abstainReasonWire, abstainReason!),
        if (failureCode != null)
          'failureCode': _wireNameOf(_failureCodeWire, failureCode!),
        'verifierInvoked': verifierInvoked,
      };
}

/// Normalizes a nested JSON object to `Map<String, dynamic>`.
///
/// Cloud Functions' platform channel decodes nested maps as
/// `Map<Object?, Object?>` on some platforms even when the top-level
/// callable result was typed `Map<String, dynamic>` -- a bare
/// `as Map<String, dynamic>` cast on one of those throws at runtime. This
/// re-keys defensively instead of trusting the static type Dart never
/// actually reified for the nested value.
Map<String, dynamic> _asStringKeyedMap(Object? v, String key) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k as String, val));
  }
  throw FormatException('$key must be an object');
}

String _requireString(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('$key is required and must be a non-empty string');
  }
  return v;
}

String? _optionalString(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || v.isEmpty) {
    throw FormatException('$key must be a non-empty string when present');
  }
  return v;
}

T _requireEnum<T>(Map<String, dynamic> j, String key, Map<String, T> wire) {
  final v = j[key];
  if (v is! String || !wire.containsKey(v)) {
    throw FormatException('$key is required and must be one of ${wire.keys}');
  }
  return wire[v] as T;
}

T? _optionalEnum<T>(Map<String, dynamic> j, String key, Map<String, T> wire) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || !wire.containsKey(v)) {
    throw FormatException('$key must be one of ${wire.keys} when present');
  }
  return wire[v] as T;
}

String _wireNameOf<T>(Map<String, T> wire, T value) {
  for (final entry in wire.entries) {
    if (entry.value == value) return entry.key;
  }
  throw StateError('no wire name registered for $value');
}
