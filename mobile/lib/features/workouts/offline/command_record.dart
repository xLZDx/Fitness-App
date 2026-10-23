/// The local queue record of the offline command protocol (section 3.1),
/// its states and transitions (section 3.2) and operation id minting
/// (section 2.1), limited to what a V0 CompleteSet APPEND can reach.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// The seven canonical states of section 3.2. The enum is complete; transitions
/// are implemented only for the V0 path (see [isTransitionAllowed]).
enum CommandState {
  accepted('ACCEPTED'),
  sending('SENDING'),
  unknownEffect('UNKNOWN_EFFECT'),
  held('HELD'),
  synced('SYNCED'),
  conflicted('CONFLICTED'),
  discarded('DISCARDED');

  const CommandState(this.wire);

  final String wire;

  static CommandState parse(String value) => CommandState.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => throw FormatException('unknown command state: $value'),
      );

  /// States that count toward the 500 record cap (section 3.2).
  bool get countsTowardCap =>
      this != CommandState.synced && this != CommandState.discarded;

  /// States the sender may pick (section 3.2: UNKNOWN_EFFECT is eligible
  /// exactly like ACCEPTED).
  bool get isSendable =>
      this == CommandState.accepted || this == CommandState.unknownEffect;
}

enum HeldReason {
  predecessorUnresolved('PREDECESSOR_UNRESOLVED'),
  predecessorConflicted('PREDECESSOR_CONFLICTED');

  const HeldReason(this.wire);

  final String wire;
}

enum DiscardSource {
  userDiscard('USER_DISCARD'),
  signoutRemove('SIGNOUT_REMOVE'),
  supersededResubmit('SUPERSEDED_RESUBMIT');

  const DiscardSource(this.wire);

  final String wire;
}

/// Transitions implemented in V0: T1 (acceptance, handled by the store), T6
/// (send start), T7 (synced), T8/T9 (terminal refusal), T10 (unknown effect,
/// including recovery of a SENDING record), T11 (no-effect answer) and T12
/// (non-terminal conflict). HELD, T3 to T5, T13 to T17 are not implemented.
bool isTransitionAllowed(CommandState from, CommandState to) {
  switch (from) {
    case CommandState.accepted:
      return to == CommandState.sending; // T6
    case CommandState.unknownEffect:
      return to == CommandState.sending || // T6
          to == CommandState.conflicted; // T9 (C4 only, see store)
    case CommandState.sending:
      return to == CommandState.synced || // T7
          to == CommandState.conflicted || // T8, T9, T12
          to == CommandState.unknownEffect || // T10
          to == CommandState.accepted; // T11
    case CommandState.held:
    case CommandState.synced:
    case CommandState.conflicted:
    case CommandState.discarded:
      return false;
  }
}

/// What the server told us when a record became SYNCED (`ackSummary`).
class AckSummary {
  const AckSummary({
    this.revisionAfter,
    this.serverTimeMs,
    this.detailExpired = false,
    this.superseded = false,
    required this.localAckMs,
  });

  final int? revisionAfter;
  final int? serverTimeMs;
  final bool detailExpired;
  final bool superseded;

  /// Local wall clock at acknowledgement; drives the 7 day stub pruning.
  final int localAckMs;

  Map<String, Object?> toJson() => {
        'revisionAfter': revisionAfter,
        'serverTimeMs': serverTimeMs,
        'detailExpired': detailExpired,
        'superseded': superseded,
        'localAckMs': localAckMs,
      };

  factory AckSummary.fromJson(Map<String, Object?> j) => AckSummary(
        revisionAfter: j['revisionAfter'] as int?,
        serverTimeMs: j['serverTimeMs'] as int?,
        detailExpired: j['detailExpired'] as bool? ?? false,
        superseded: j['superseded'] as bool? ?? false,
        localAckMs: j['localAckMs'] as int,
      );
}

/// One queue record keyed by `(uid, operationId)`. Immutable; the store
/// replaces records, it never mutates them. Identity, ordering and payload
/// fields never change after acceptance; `canonicalBytes` and `payloadFields`
/// are erased at acknowledgement (section 3.6).
class CommandRecord {
  const CommandRecord({
    required this.uid,
    required this.operationId,
    required this.sessionId,
    required this.exerciseId,
    required this.operation,
    required this.sessionGeneration,
    required this.acceptedEpoch,
    required this.seq,
    required this.dependsOn,
    required this.logicalSetId,
    required this.canonicalBytes,
    required this.payloadHash,
    required this.payloadFields,
    required this.protocolVersion,
    required this.hashVersion,
    required this.limitsVersion,
    required this.state,
    this.heldReason,
    this.conflictKind,
    this.conflictTerminal,
    this.maybeSent = false,
    this.attempts = 0,
    this.lastAttemptLocalMs,
    this.lastResultCode,
    required this.originDeviceInstallId,
    required this.intentKey,
    this.ackSummary,
    this.supersedes,
    this.discardSource,
    this.exportedAt,
    this.serverStateUnknown = false,
    required this.acceptedAtLocalWallMs,
    required this.acceptedAtMonotonic,
  });

  final String uid;
  final String operationId;
  final String sessionId;
  final String exerciseId;
  final String operation;
  final int sessionGeneration;
  final int acceptedEpoch;
  final int seq;
  final List<String> dependsOn;
  final String? logicalSetId;

  /// The exact bytes that are hashed and sent. Null once erased.
  final Uint8List? canonicalBytes;
  final String payloadHash;

  /// Typed values before canonicalization (section 2.5). Null once erased.
  final Map<String, Object?>? payloadFields;
  final int protocolVersion;
  final int hashVersion;
  final int limitsVersion;

  final CommandState state;
  final HeldReason? heldReason;
  final String? conflictKind;
  final bool? conflictTerminal;

  /// True from the commit that moves the record to SENDING; never reset.
  final bool maybeSent;
  final int attempts;
  final int? lastAttemptLocalMs;
  final String? lastResultCode;
  final String originDeviceInstallId;
  final String intentKey;
  final AckSummary? ackSummary;
  final String? supersedes;
  final DiscardSource? discardSource;
  final int? exportedAt;
  final bool serverStateUnknown;
  final int acceptedAtLocalWallMs;
  final int acceptedAtMonotonic;

  bool get hasPayload => canonicalBytes != null;

  CommandRecord copyWith({
    CommandState? state,
    HeldReason? heldReason,
    String? conflictKind,
    bool? conflictTerminal,
    bool? maybeSent,
    int? attempts,
    int? lastAttemptLocalMs,
    String? lastResultCode,
    AckSummary? ackSummary,
    bool? serverStateUnknown,
  }) =>
      _copy(
        state: state,
        heldReason: heldReason,
        conflictKind: conflictKind,
        conflictTerminal: conflictTerminal,
        maybeSent: maybeSent,
        attempts: attempts,
        lastAttemptLocalMs: lastAttemptLocalMs,
        lastResultCode: lastResultCode,
        ackSummary: ackSummary,
        serverStateUnknown: serverStateUnknown,
        keepPayload: true,
      );

  /// Copy with `canonicalBytes` and `payloadFields` erased (section 3.6).
  CommandRecord erasePayload() => _copy(keepPayload: false);

  CommandRecord _copy({
    CommandState? state,
    HeldReason? heldReason,
    String? conflictKind,
    bool? conflictTerminal,
    bool? maybeSent,
    int? attempts,
    int? lastAttemptLocalMs,
    String? lastResultCode,
    AckSummary? ackSummary,
    bool? serverStateUnknown,
    required bool keepPayload,
  }) =>
      CommandRecord(
        uid: uid,
        operationId: operationId,
        sessionId: sessionId,
        exerciseId: exerciseId,
        operation: operation,
        sessionGeneration: sessionGeneration,
        acceptedEpoch: acceptedEpoch,
        seq: seq,
        dependsOn: dependsOn,
        logicalSetId: logicalSetId,
        canonicalBytes: keepPayload ? canonicalBytes : null,
        payloadHash: payloadHash,
        payloadFields: keepPayload ? payloadFields : null,
        protocolVersion: protocolVersion,
        hashVersion: hashVersion,
        limitsVersion: limitsVersion,
        state: state ?? this.state,
        heldReason: heldReason ?? this.heldReason,
        conflictKind: conflictKind ?? this.conflictKind,
        conflictTerminal: conflictTerminal ?? this.conflictTerminal,
        maybeSent: maybeSent ?? this.maybeSent,
        attempts: attempts ?? this.attempts,
        lastAttemptLocalMs: lastAttemptLocalMs ?? this.lastAttemptLocalMs,
        lastResultCode: lastResultCode ?? this.lastResultCode,
        originDeviceInstallId: originDeviceInstallId,
        intentKey: intentKey,
        ackSummary: ackSummary ?? this.ackSummary,
        supersedes: supersedes,
        discardSource: discardSource,
        exportedAt: exportedAt,
        serverStateUnknown: serverStateUnknown ?? this.serverStateUnknown,
        acceptedAtLocalWallMs: acceptedAtLocalWallMs,
        acceptedAtMonotonic: acceptedAtMonotonic,
      );

  Map<String, Object?> toJson() => {
        'uid': uid,
        'operationId': operationId,
        'sessionId': sessionId,
        'exerciseId': exerciseId,
        'operation': operation,
        'sessionGeneration': sessionGeneration,
        'acceptedEpoch': acceptedEpoch,
        'seq': seq,
        'dependsOn': dependsOn,
        'logicalSetId': logicalSetId,
        'canonicalBytes':
            canonicalBytes == null ? null : base64.encode(canonicalBytes!),
        'payloadHash': payloadHash,
        'payloadFields': payloadFields,
        'protocolVersion': protocolVersion,
        'hashVersion': hashVersion,
        'limitsVersion': limitsVersion,
        'state': state.wire,
        'heldReason': heldReason?.wire,
        'conflictKind': conflictKind,
        'conflictTerminal': conflictTerminal,
        'maybeSent': maybeSent,
        'attempts': attempts,
        'lastAttemptLocalMs': lastAttemptLocalMs,
        'lastResultCode': lastResultCode,
        'originDeviceInstallId': originDeviceInstallId,
        'intentKey': intentKey,
        'ackSummary': ackSummary?.toJson(),
        'supersedes': supersedes,
        'discardSource': discardSource?.wire,
        'exportedAt': exportedAt,
        'serverStateUnknown': serverStateUnknown,
        'acceptedAtLocalWallMs': acceptedAtLocalWallMs,
        'acceptedAtMonotonic': acceptedAtMonotonic,
      };

  factory CommandRecord.fromJson(Map<String, Object?> j) {
    final bytes = j['canonicalBytes'] as String?;
    final held = j['heldReason'] as String?;
    final discard = j['discardSource'] as String?;
    final ack = j['ackSummary'] as Map?;
    final fields = j['payloadFields'] as Map?;
    return CommandRecord(
      uid: j['uid'] as String,
      operationId: j['operationId'] as String,
      sessionId: j['sessionId'] as String,
      exerciseId: j['exerciseId'] as String,
      operation: j['operation'] as String,
      sessionGeneration: j['sessionGeneration'] as int,
      acceptedEpoch: j['acceptedEpoch'] as int,
      seq: j['seq'] as int,
      dependsOn: List<String>.from(j['dependsOn'] as List),
      logicalSetId: j['logicalSetId'] as String?,
      canonicalBytes: bytes == null ? null : base64.decode(bytes),
      payloadHash: j['payloadHash'] as String,
      payloadFields:
          fields == null ? null : Map<String, Object?>.from(fields),
      protocolVersion: j['protocolVersion'] as int,
      hashVersion: j['hashVersion'] as int,
      limitsVersion: j['limitsVersion'] as int,
      state: CommandState.parse(j['state'] as String),
      heldReason: held == null
          ? null
          : HeldReason.values.firstWhere((h) => h.wire == held),
      conflictKind: j['conflictKind'] as String?,
      conflictTerminal: j['conflictTerminal'] as bool?,
      maybeSent: j['maybeSent'] as bool? ?? false,
      attempts: j['attempts'] as int? ?? 0,
      lastAttemptLocalMs: j['lastAttemptLocalMs'] as int?,
      lastResultCode: j['lastResultCode'] as String?,
      originDeviceInstallId: j['originDeviceInstallId'] as String,
      intentKey: j['intentKey'] as String,
      ackSummary:
          ack == null ? null : AckSummary.fromJson(Map<String, Object?>.from(ack)),
      supersedes: j['supersedes'] as String?,
      discardSource: discard == null
          ? null
          : DiscardSource.values.firstWhere((d) => d.wire == discard),
      exportedAt: j['exportedAt'] as int?,
      serverStateUnknown: j['serverStateUnknown'] as bool? ?? false,
      acceptedAtLocalWallMs: j['acceptedAtLocalWallMs'] as int,
      acceptedAtMonotonic: j['acceptedAtMonotonic'] as int,
    );
  }
}

String _b64urlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// 8 characters: base64url of the first 6 bytes of `SHA-256("u1|" + uid)`
/// (section 2.1).
String uidTagOf(String uid) {
  final digest = crypto.sha256.convert(utf8.encode('u1|$uid')).bytes;
  return _b64urlNoPad(digest.sublist(0, 6));
}

/// Mints a 30 character operation id: [uidTagOf] plus 22 characters of
/// base64url of 16 CSPRNG bytes (section 2.1). Call it once, at acceptance;
/// retries and restarts reuse the stored id and never call this again.
String mintOperationId(String uid, {Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return uidTagOf(uid) + _b64urlNoPad(bytes);
}
