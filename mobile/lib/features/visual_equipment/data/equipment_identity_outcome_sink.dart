import 'package:flutter/foundation.dart' show debugPrint, immutable;

import 'equipment_identity.dart';

/// A terminal identity resolution's full shape, for [EquipmentIdentityOutcomeSink].
///
/// Deliberately NOT a bare [EquipmentIdentityDecision]: GPT-PM's round-3
/// correction (`core/DECISION_LOG.md`, 2026-09-11) is that a bare Decision
/// enum loses information a real conflict could hide -- the same MATCH
/// decision with a different `identityLevel`, or the same ABSTAIN with a
/// different `abstainReason`, is a materially different outcome for the
/// same scan and must be detectable as one.
///
/// GPT-PM's PRE-COMMIT review (this gate) widened this further: the first
/// implementation captured only decision/identityLevel/model+shadow ids and
/// catalog versions/2-of-10 authority fields/abstain+failure -- silently
/// treating two replies as identical even when they differed in
/// `ocrVersion`/`textPolicyVersion`/`fusionPolicyVersion`/
/// `identityParserVersion`/`recognitionSessionId`/`identityContractVersion`/
/// `evidenceLane`/`verifierInvoked`. That is exactly the class of divergence
/// rev4's "ANY differing payload is a conflict" rule exists to catch (a
/// policy/algorithm-version drift between two calls for what is supposed to
/// be the same scan). This now captures every field of [EquipmentIdentity]
/// except `scanId` itself (the map key this sink is already keyed by, not
/// part of the payload) -- the complete immutable response projection, not
/// a hand-picked subset.
@immutable
class EquipmentIdentityOutcome {
  const EquipmentIdentityOutcome({
    required this.decision,
    required this.recognitionSessionId,
    required this.identityContractVersion,
    required this.evidenceLane,
    required this.authority,
    required this.verifierInvoked,
    this.identityLevel,
    this.modelId,
    this.modelCatalogVersion,
    this.shadowCandidateModelId,
    this.shadowCandidateCatalogVersion,
    this.abstainReason,
    this.failureCode,
  });

  factory EquipmentIdentityOutcome.fromIdentity(EquipmentIdentity identity) =>
      EquipmentIdentityOutcome(
        decision: identity.decision,
        recognitionSessionId: identity.recognitionSessionId,
        identityContractVersion: identity.identityContractVersion,
        evidenceLane: identity.evidenceLane,
        authority: identity.authority,
        verifierInvoked: identity.verifierInvoked,
        identityLevel: identity.identityLevel,
        modelId: identity.model?.modelId,
        modelCatalogVersion: identity.model?.catalogVersion,
        shadowCandidateModelId: identity.shadowCandidate?.modelId,
        shadowCandidateCatalogVersion: identity.shadowCandidate?.catalogVersion,
        abstainReason: identity.abstainReason,
        failureCode: identity.failureCode,
      );

  final EquipmentIdentityDecision decision;
  final String recognitionSessionId;
  final String identityContractVersion;
  final EvidenceLane evidenceLane;
  final RecognitionAuthorityTuple authority;
  final bool verifierInvoked;
  final EquipmentIdentityLevel? identityLevel;
  final String? modelId;
  final String? modelCatalogVersion;
  final String? shadowCandidateModelId;
  final String? shadowCandidateCatalogVersion;
  final EquipmentIdentityAbstainReason? abstainReason;
  final EquipmentIdentityFailureCode? failureCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EquipmentIdentityOutcome &&
          other.decision == decision &&
          other.recognitionSessionId == recognitionSessionId &&
          other.identityContractVersion == identityContractVersion &&
          other.evidenceLane == evidenceLane &&
          other.authority == authority &&
          other.verifierInvoked == verifierInvoked &&
          other.identityLevel == identityLevel &&
          other.modelId == modelId &&
          other.modelCatalogVersion == modelCatalogVersion &&
          other.shadowCandidateModelId == shadowCandidateModelId &&
          other.shadowCandidateCatalogVersion == shadowCandidateCatalogVersion &&
          other.abstainReason == abstainReason &&
          other.failureCode == failureCode);

  @override
  int get hashCode => Object.hash(
        decision,
        recognitionSessionId,
        identityContractVersion,
        evidenceLane,
        authority,
        verifierInvoked,
        identityLevel,
        modelId,
        modelCatalogVersion,
        shadowCandidateModelId,
        shadowCandidateCatalogVersion,
        abstainReason,
        failureCode,
      );

  @override
  String toString() => 'EquipmentIdentityOutcome(decision: $decision, '
      'recognitionSessionId: $recognitionSessionId, '
      'identityContractVersion: $identityContractVersion, '
      'evidenceLane: $evidenceLane, authority: $authority, '
      'verifierInvoked: $verifierInvoked, identityLevel: $identityLevel, '
      'modelId: $modelId, shadowCandidateModelId: $shadowCandidateModelId, '
      'abstainReason: $abstainReason, failureCode: $failureCode)';
}

/// Records the TERMINAL identity outcome for a scan -- the lossless-handoff
/// seam this gate builds so a later gate (P2.G5's denominator/report
/// arithmetic, deliberately deferred -- see the Rosetta plan's own
/// NOT-IN-SCOPE list) can correlate a scan with what the server actually
/// decided, without re-deriving it from [EquipmentIdentity] itself.
///
/// `recognition_history.dart` is deliberately untouched: that log is keyed
/// by equipmentId and is "not an event log" by its own doc comment. This
/// sink is the opposite shape on purpose -- keyed by scanId, one terminal
/// record per scan.
abstract class EquipmentIdentityOutcomeSink {
  /// Idempotent for an identical replay: the same [scanId] with a
  /// byte-identical [outcome] is a silent no-op, not a second record --
  /// `equipmentIdentityProvider`'s own `autoDispose` churn (rewatching after
  /// a transient dispose/recreate) can legitimately resolve and call this
  /// more than once for the same successful outcome.
  ///
  /// A DIFFERING [outcome] for a [scanId] already recorded is a conflict --
  /// two terminal answers for what must be one scan -- and is recorded as
  /// one rather than silently overwriting or silently being dropped. See
  /// [conflictedScanIds].
  void recordTerminal(String scanId, EquipmentIdentityOutcome outcome);

  /// Every scanId whose recorded outcome was later contradicted by a
  /// differing one for the SAME scanId. Diagnostic only -- never surfaced to
  /// the user, and does not change what [recordTerminal] itself does.
  Set<String> get conflictedScanIds;
}

class InMemoryEquipmentIdentityOutcomeSink implements EquipmentIdentityOutcomeSink {
  final Map<String, EquipmentIdentityOutcome> _recorded = {};
  final Set<String> _conflicted = {};

  @override
  void recordTerminal(String scanId, EquipmentIdentityOutcome outcome) {
    final existing = _recorded[scanId];
    if (existing == null) {
      _recorded[scanId] = outcome;
      return;
    }
    if (existing == outcome) return;
    // The first recorded outcome is kept -- it is whatever the rest of the
    // app already saw and may have acted on (the badge, the outcome sink's
    // own future readers); overwriting it with a later, differing answer
    // would silently rewrite history a UI may already reflect. The conflict
    // itself is recorded rather than silently dropped.
    _conflicted.add(scanId);
    debugPrint(
      'equipment identity outcome conflict for scanId=$scanId: '
      'first=$existing, then=$outcome',
    );
  }

  @override
  Set<String> get conflictedScanIds => Set.unmodifiable(_conflicted);
}
