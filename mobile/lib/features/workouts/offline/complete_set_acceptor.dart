/// Composes the canonical payload, the operation id and the queue record of
/// one V0 CompleteSet APPEND and commits it through the store (the
/// acceptance of protocol section 3.3, without the set-context rule, the
/// writer token step, or dependencies).
///
/// Nothing here touches the network. The UI may show "pending sync" only
/// after [accept] completes.
library;

import 'canonical.dart';
import 'command_queue_store.dart';
import 'command_record.dart';

/// One user event to log as a set. [intentKey] is the opaque id of that event
/// (UI event id of a tap); a repeated call with the same key creates nothing
/// and returns the stored record.
class CompleteSetIntent {
  const CompleteSetIntent({
    required this.sessionId,
    required this.exerciseId,
    required this.setIndex,
    required this.intentKey,
    required this.body,
    this.sessionGeneration = 1,
    this.acceptedEpoch = 0,
    this.sessionInit,
  });

  final String sessionId;
  final String exerciseId;
  final int setIndex;
  final String intentKey;

  /// Exactly [kCompleteSetBodyKeys]; see `buildCompleteSetPayload`.
  final Map<String, Object?> body;

  /// 1 when the client observed nothing (section 2.1).
  final int sessionGeneration;

  /// 0 when the session was never synced (section 2.1).
  final int acceptedEpoch;
  final Map<String, Object?>? sessionInit;
}

class CompleteSetAcceptor {
  CompleteSetAcceptor({
    required this.store,
    required this.originDeviceInstallId,
    int Function()? wallMs,
    int Function()? monotonicMs,
    String Function(String uid)? mintId,
  })  : _wallMs = wallMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _monotonicMs = monotonicMs ?? _defaultMonotonic,
        _mintId = mintId ?? mintOperationId;

  final CommandQueueStore store;
  final String originDeviceInstallId;
  final int Function() _wallMs;
  final int Function() _monotonicMs;
  final String Function(String uid) _mintId;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _defaultMonotonic() => _clock.elapsedMilliseconds;

  /// Durably commits the intent. The operation id is minted here, once; if
  /// the store already holds the same intent the stored record (with its
  /// original id and bytes) is returned and the fresh id is discarded.
  Future<AcceptResult> accept(CompleteSetIntent intent) {
    final uid = store.uid;
    final operationId = _mintId(uid);
    final logicalSetId =
        logicalSetIdOf(intent.sessionId, intent.exerciseId, intent.setIndex);
    final wall = _wallMs();
    final mono = _monotonicMs();

    CommandRecord build(int seq) {
      final payload = buildCompleteSetPayload(
        operationId: operationId,
        uid: uid,
        sessionId: intent.sessionId,
        originDeviceInstallId: originDeviceInstallId,
        sessionGeneration: intent.sessionGeneration,
        acceptedEpoch: intent.acceptedEpoch,
        seq: seq,
        dependsOn: const <String>[],
        exerciseId: intent.exerciseId,
        setIndex: intent.setIndex,
        sessionInit: intent.sessionInit,
        body: intent.body,
      );
      final bytes = canonicalBytes(payload);
      return CommandRecord(
        uid: uid,
        operationId: operationId,
        sessionId: intent.sessionId,
        exerciseId: intent.exerciseId,
        operation: 'CompleteSet',
        sessionGeneration: intent.sessionGeneration,
        acceptedEpoch: intent.acceptedEpoch,
        seq: seq,
        dependsOn: const <String>[],
        logicalSetId: logicalSetId,
        canonicalBytes: bytes,
        payloadHash: payloadHashHex(bytes),
        payloadFields: payload,
        protocolVersion: kProtocolVersion,
        hashVersion: kHashVersion,
        limitsVersion: kLimitsVersion,
        state: CommandState.accepted,
        originDeviceInstallId: originDeviceInstallId,
        intentKey: intent.intentKey,
        acceptedAtLocalWallMs: wall,
        acceptedAtMonotonic: mono,
      );
    }

    return store.accept(AcceptRequest(
      operationId: operationId,
      intentKey: intent.intentKey,
      sessionId: intent.sessionId,
      originDeviceInstallId: originDeviceInstallId,
      logicalSetId: logicalSetId,
      build: build,
    ));
  }
}
