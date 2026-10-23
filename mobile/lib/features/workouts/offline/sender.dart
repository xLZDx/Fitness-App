/// The V0 sender of the offline command protocol (sections 3.5, 4.4, 7.2).
///
/// It sends the oldest eligible record through an injected [CommandTransport]
/// and commits the outcome to the store. It never mints an id, never rebuilds
/// or re-serializes a payload: the stored `canonicalBytes` are sent as is,
/// also on every retry after a lost acknowledgement.
///
/// The sender holds no timers. A caller (app lifecycle, connectivity listener)
/// calls [sendNext] or [sendAvailable]; held sessions are skipped until their
/// probe time.
library;

import 'dart:math';
import 'dart:typed_data';

import 'canonical.dart';
import 'command_queue_store.dart';
import 'command_record.dart';
import 'result_codes.dart';

/// Everything sent with a command (section 2.3). Only [payloadBytes] is
/// authoritative; the other fields are informational or carry the writer
/// credential.
class CommandEnvelope {
  const CommandEnvelope({
    required this.operationId,
    required this.payloadBytes,
    required this.payloadHash,
    required this.writerProof,
    required this.writerEpochClaim,
    required this.deviceInstallId,
    required this.clientBuild,
  });

  final String operationId;
  final Uint8List payloadBytes;
  final String payloadHash;

  /// Secret writer token read at send time; never stored in the record.
  final String? writerProof;
  final int writerEpochClaim;
  final String deviceInstallId;
  final String clientBuild;
}

/// The server's answer for one command.
class TransportAnswer {
  const TransportAnswer({
    required this.code,
    this.revisionAfter,
    this.serverTimeMs,
    this.retryAfterMs,
  });

  /// A result code of section 4.4, e.g. `COMMITTED` or `ALREADY_COMMITTED`.
  final String code;
  final int? revisionAfter;
  final int? serverTimeMs;
  final int? retryAfterMs;
}

/// One round trip. Implementations throw (or never complete) when no answer
/// was received; the sender treats that as a lost acknowledgement.
abstract class CommandTransport {
  Future<TransportAnswer> send(CommandEnvelope envelope);
}

/// Reads the writer token for `(uid, sessionId)` from secure storage.
typedef WriterProofProvider = Future<String?> Function(
    String uid, String sessionId);

enum SendStatus {
  /// Nothing eligible to send.
  idle,

  /// The record became SYNCED.
  synced,

  /// The record became CONFLICTED (terminal or non-terminal).
  conflicted,

  /// No usable answer; the record is resendable with the same bytes.
  retryLater,

  /// An answer proved no effect, the record is back to ACCEPTED.
  heldBack,

  /// Eligible records exist but their sessions are on hold.
  sessionOnHold,

  /// Another send is in flight (one sender per uid).
  busy,

  /// The stored payload failed its integrity check; nothing was sent. The
  /// record and every higher-seq record of its session are blocked.
  integrityFailure,

  /// A writer proof is required but unavailable; nothing was sent, the record
  /// is untouched (ACCEPTED, maybeSent unchanged) and the session is held.
  proofUnavailable,

  /// The queue store threw; see [SendReport.code]. A record left in SENDING is
  /// recovered to UNKNOWN_EFFECT at the start of the next send.
  storeError,
}

class SendReport {
  const SendReport(this.status,
      {this.operationId, this.code, this.nextAttemptAt, this.stuck = false});

  final SendStatus status;
  final String? operationId;
  final String? code;
  final DateTime? nextAttemptAt;

  /// True when the record has been attempted at least
  /// `CommandSender.stuckAttemptThreshold` times without an answer that
  /// settles it. Informational only; the record state is not changed.
  final bool stuck;

  @override
  String toString() => 'SendReport($status, $operationId, $code)';
}

class _Hold {
  _Hold({required this.until, required this.failures, this.untilSignIn = false});

  DateTime until;
  int failures;
  bool untilSignIn;
}

class CommandSender {
  CommandSender({
    required this.store,
    required this.transport,
    required this.deviceInstallId,
    required this.clientBuild,
    required this.writerProof,
    this.sendTimeout = const Duration(seconds: 30),
    this.stuckAttemptThreshold = 10,
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final CommandQueueStore store;
  final CommandTransport transport;
  final String deviceInstallId;
  final String clientBuild;
  /// Mandatory: the real callable rejects a command without a writer proof,
  /// so the sender never sends (or marks SENDING) without one.
  final WriterProofProvider writerProof;
  final Duration sendTimeout;
  final int stuckAttemptThreshold;
  final DateTime Function() _now;
  final Random _random;

  final Map<String, _Hold> _holds = <String, _Hold>{};
  bool _busy = false;

  /// Count of result codes this build does not know (alert hook of 4.6).
  int unknownCodeCount = 0;

  /// App foreground, connectivity change or sign-in: probe at once.
  void resetBackoff({bool signedIn = false}) {
    _holds.removeWhere((_, h) => signedIn || !h.untilSignIn);
  }

  /// Sends at most one record: the oldest eligible one (per session in `seq`
  /// order; across sessions by acceptance time).
  Future<SendReport> sendNext() async {
    if (_busy) return const SendReport(SendStatus.busy);
    _busy = true;
    try {
      return await _sendOne();
    } catch (e) {
      // Only store/proof-independent failures reach here (transport errors are
      // handled inside). Nothing is lost: a record left in SENDING is
      // recovered by the next call.
      return SendReport(SendStatus.storeError, code: e.toString());
    } finally {
      _busy = false;
    }
  }

  /// Calls [sendNext] while it makes progress (SYNCED or CONFLICTED). Stops at
  /// the first report that is not progress and returns all reports.
  Future<List<SendReport>> sendAvailable({int maxRecords = kQueueRecordCap}) async {
    final reports = <SendReport>[];
    for (var i = 0; i < maxRecords; i++) {
      final r = await sendNext();
      reports.add(r);
      if (r.status != SendStatus.synced && r.status != SendStatus.conflicted) {
        break;
      }
    }
    return reports;
  }

  Future<SendReport> _sendOne() async {
    // Inside the busy section no send of this sender is in flight, so any
    // SENDING record is stale (an earlier answer could not be committed): it
    // returns to UNKNOWN_EFFECT (T10) and is resent with the same bytes.
    final all = await store.listAll();
    // Fail-closed barrier (persisted through the record itself): a record
    // stored as non-terminal CONFLICTED (written by an older build) is not
    // sendable, but its session must not let a higher seq overtake it.
    final conflictBarrier = <String, int>{};
    for (final r in all) {
      if (r.state == CommandState.conflicted && r.conflictTerminal == false) {
        final cur = conflictBarrier[r.sessionId];
        if (cur == null || r.seq < cur) conflictBarrier[r.sessionId] = r.seq;
      }
    }
    for (final r in all) {
      if (r.state == CommandState.sending) {
        await store.markResult(
            r.operationId,
            const CommandResult(
                to: CommandState.unknownEffect, resultCode: 'STALE_SENDING'));
      }
    }

    final pending = await store.listPending();
    if (pending.isEmpty) return const SendReport(SendStatus.idle);

    // An integrity failure blocks its record and every higher-seq record of
    // the same session (later sets must not overtake it); other sessions go on.
    final badFromSeq = <String, int>{};
    SendReport? firstBad;
    for (final r in pending) {
      final b = r.canonicalBytes;
      if (b == null || payloadHashHex(b) != r.payloadHash) {
        firstBad ??=
            SendReport(SendStatus.integrityFailure, operationId: r.operationId);
        final cur = badFromSeq[r.sessionId];
        if (cur == null || r.seq < cur) badFromSeq[r.sessionId] = r.seq;
      }
    }

    final now = _now();
    // First (lowest seq) eligible record per session.
    final firstPerSession = <String, CommandRecord>{};
    var anyHeld = false;
    DateTime? earliest;
    for (final r in pending) {
      final badFrom = badFromSeq[r.sessionId];
      if (badFrom != null && r.seq >= badFrom) continue;
      final barrier = conflictBarrier[r.sessionId];
      if (barrier != null && r.seq > barrier) continue;
      final hold = _holds[r.sessionId];
      if (hold != null && !hold.untilSignIn && !now.isBefore(hold.until)) {
        // Probe time reached: the hold stays until a non-hold answer clears it.
      } else if (hold != null) {
        anyHeld = true;
        if (!hold.untilSignIn &&
            (earliest == null || hold.until.isBefore(earliest))) {
          earliest = hold.until;
        }
        continue;
      }
      final cur = firstPerSession[r.sessionId];
      if (cur == null || r.seq < cur.seq) firstPerSession[r.sessionId] = r;
    }
    if (firstPerSession.isEmpty) {
      if (firstBad != null) return firstBad;
      return SendReport(
        anyHeld ? SendStatus.sessionOnHold : SendStatus.idle,
        nextAttemptAt: earliest,
      );
    }
    final candidate = firstPerSession.values.reduce((a, b) {
      final t = a.acceptedAtLocalWallMs.compareTo(b.acceptedAtLocalWallMs);
      if (t != 0) return t < 0 ? a : b;
      return a.seq <= b.seq ? a : b;
    });

    // The proof is read before the SENDING commit: a secure-storage failure
    // must not set maybeSent. A missing, empty or unreadable proof means
    // nothing is marked SENDING and nothing reaches the transport; the record
    // stays sendable.
    String? proof;
    try {
      proof = await writerProof(candidate.uid, candidate.sessionId);
    } catch (_) {
      proof = null;
    }
    if (proof == null || proof.isEmpty) {
      final hold = _bumpHold(candidate.sessionId,
          base: const Duration(seconds: 30), cap: const Duration(minutes: 15));
      return SendReport(SendStatus.proofUnavailable,
          operationId: candidate.operationId, nextAttemptAt: hold.until);
    }

    final sending = await store.markSending(candidate.operationId); // T6
    final envelope = CommandEnvelope(
      operationId: sending.operationId,
      payloadBytes: sending.canonicalBytes!,
      payloadHash: sending.payloadHash,
      writerProof: proof,
      writerEpochClaim: sending.acceptedEpoch,
      deviceInstallId: deviceInstallId,
      clientBuild: clientBuild,
    );

    final TransportAnswer answer;
    try {
      answer = await transport.send(envelope).timeout(sendTimeout);
    } catch (_) {
      // Transport error, timeout or any failure before an answer: the server
      // may or may not have applied it. Same id, same bytes on the next try.
      await store.markResult(
          sending.operationId,
          const CommandResult(
              to: CommandState.unknownEffect, resultCode: 'TRANSPORT_ERROR')); // T10
      final hold = _bumpHold(sending.sessionId,
          base: const Duration(seconds: 2),
          cap: const Duration(minutes: 5),
          fullJitter: false);
      return SendReport(SendStatus.retryLater,
          operationId: sending.operationId,
          nextAttemptAt: hold.until,
          stuck: sending.attempts >= stuckAttemptThreshold);
    }
    return _apply(sending, answer);
  }

  Future<SendReport> _apply(CommandRecord rec, TransportAnswer a) async {
    final id = rec.operationId;
    final code = a.code;
    switch (classifyResultCode(code)) {
      case ResultClass.applied:
      case ResultClass.alreadyApplied:
        await store.markResult(
            id,
            CommandResult(
              to: CommandState.synced, // T7
              resultCode: code,
              revisionAfter: a.revisionAfter,
              serverTimeMs: a.serverTimeMs,
              detailExpired: code == 'ALREADY_COMMITTED_DETAIL_EXPIRED',
              superseded: code == 'SUPERSEDED',
            ));
        _holds.remove(rec.sessionId);
        return SendReport(SendStatus.synced, operationId: id, code: code);

      case ResultClass.refusedTerminal:
      case ResultClass.outcomeUnknownReplayClosed:
      case ResultClass.clientDefect:
        await store.markResult(
            id,
            CommandResult(
              to: CommandState.conflicted, // T8 / T9
              resultCode: code,
              conflictKind: code,
              conflictTerminal: true,
            ));
        _holds.remove(rec.sessionId);
        return SendReport(SendStatus.conflicted, operationId: id, code: code);

      case ResultClass.sessionConflict:
        // NOT_WRITER / SESSION_COMMAND_LIMIT are non-terminal on the server.
        // The record goes back to ACCEPTED (T11, nothing was applied) instead
        // of CONFLICTED: CONFLICTED is excluded from listPending(), so a
        // restart or resetBackoff() would let a higher seq of the same session
        // overtake it. As ACCEPTED it keeps the lowest seq of its session and
        // is retried first, after the backoff hold; the code stays in
        // lastResultCode. Terminal conflicts keep CONFLICTED (above).
        await store.markResult(
            id, CommandResult(to: CommandState.accepted, resultCode: code));
        final hold = _bumpHold(rec.sessionId,
            base: const Duration(seconds: 30),
            cap: const Duration(minutes: 15),
            retryAfterMs: a.retryAfterMs);
        return SendReport(SendStatus.conflicted,
            operationId: id, code: code, nextAttemptAt: hold.until);

      case ResultClass.recordNonTerminal:
      case ResultClass.notAttempted:
      case ResultClass.sessionHold:
      case ResultClass.unknown:
        if (classifyResultCode(code) == ResultClass.unknown) unknownCodeCount++;
        await store.markResult(
            id, CommandResult(to: CommandState.accepted, resultCode: code)); // T11
        final hold = _bumpHold(rec.sessionId,
            base: const Duration(seconds: 30),
            cap: const Duration(minutes: 15),
            retryAfterMs: a.retryAfterMs,
            untilSignIn: code == 'AUTH_REVOKED');
        return SendReport(SendStatus.heldBack,
            operationId: id, code: code, nextAttemptAt: hold.until);

      case ResultClass.retryable:
        await store.markResult(
            id, CommandResult(to: CommandState.unknownEffect, resultCode: code)); // T10
        final hold = _bumpHold(rec.sessionId,
            base: const Duration(seconds: 2),
            cap: const Duration(minutes: 5),
            retryAfterMs: a.retryAfterMs,
            fullJitter: false);
        return SendReport(SendStatus.retryLater,
            operationId: id,
            code: code,
            nextAttemptAt: hold.until,
            stuck: rec.attempts >= stuckAttemptThreshold);

      case ResultClass.retryableNoEffect:
        // FENCE_SHARD_FULL is returned before any mutation: no effect (T11).
        await store.markResult(
            id, CommandResult(to: CommandState.accepted, resultCode: code));
        final hold = _bumpHold(rec.sessionId,
            base: const Duration(seconds: 2),
            cap: const Duration(minutes: 5),
            retryAfterMs: a.retryAfterMs,
            fullJitter: false);
        return SendReport(SendStatus.retryLater,
            operationId: id,
            code: code,
            nextAttemptAt: hold.until,
            stuck: rec.attempts >= stuckAttemptThreshold);
    }
  }

  /// Exponential backoff from [base] to [cap]. Retry backoff keeps half of the
  /// delay fixed (jitter on the other half); holds use full jitter; a server
  /// `retryAfter` wins when larger (section 3.5).
  _Hold _bumpHold(
    String sessionId, {
    required Duration base,
    required Duration cap,
    bool fullJitter = true,
    int? retryAfterMs,
    bool untilSignIn = false,
  }) {
    final prev = _holds[sessionId];
    final failures = (prev?.failures ?? 0) + 1;
    final expMs = min(cap.inMilliseconds,
        base.inMilliseconds * pow(2, min(failures - 1, 20)).toInt());
    var delayMs = fullJitter
        ? _random.nextInt(expMs + 1)
        : expMs ~/ 2 + _random.nextInt(expMs - expMs ~/ 2 + 1);
    if (retryAfterMs != null && retryAfterMs > delayMs) delayMs = retryAfterMs;
    final hold = _Hold(
      until: _now().add(Duration(milliseconds: delayMs)),
      failures: failures,
      untilSignIn: untilSignIn || (prev?.untilSignIn ?? false),
    );
    _holds[sessionId] = hold;
    return hold;
  }
}
