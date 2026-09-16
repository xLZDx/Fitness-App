import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;
import 'dart:math' show Random;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:path_provider/path_provider.dart';

import 'cloud_equipment_identity_telemetry_service.dart' show EquipmentIdentityTelemetrySend;

/// One durable pending telemetry report: the body a send attempt failed to
/// deliver, plus enough metadata to retry it later exactly as it would have
/// been sent the first time.
///
/// [id] is a locally-generated identity, stable across read-modify-write
/// cycles -- [drainPending]'s own snapshot-then-reconcile design (see that
/// method's doc comment) removes a report by [id], never by position or
/// content, so a report enqueued by a concurrent [sendOrEnqueue] call while a
/// drain is mid-flight is never confused with one the drain is itself
/// retrying. [enqueuedAt] is diagnostic/ordering only -- never sent to the
/// server and never read by the merge logic on the other end.
@immutable
class PendingTelemetryReport {
  const PendingTelemetryReport({required this.id, required this.body, required this.enqueuedAt});

  final String id;
  final Map<String, dynamic> body;
  final String enqueuedAt;

  Map<String, dynamic> toJson() => {'id': id, 'body': body, 'enqueuedAt': enqueuedAt};

  factory PendingTelemetryReport.fromJson(Map<String, dynamic> json) =>
      PendingTelemetryReport(
        // A pre-existing stored entry from before `id` existed has none --
        // structurally impossible today (this outbox has never shipped) but
        // cheap to tolerate rather than assume.
        id: json['id'] as String? ?? _generateId(),
        body: Map<String, dynamic>.from(json['body'] as Map),
        enqueuedAt: json['enqueuedAt'] as String,
      );
}

/// Not cryptographically unique, only locally unique-enough to disambiguate
/// entries in one device's own queue -- microsecond timestamp plus a random
/// suffix, the same lightweight-ID shape used throughout this codebase where
/// a real UUID package would be overkill (no `uuid` dependency exists in
/// `mobile/pubspec.yaml`).
String _generateId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

/// True for a callable failure that retrying can never turn into a success
/// -- GPT-PM MAJOR, P2.G5-readiness step 3b review round 2, 2026-09-16: an
/// earlier version of this outbox caught and durably re-queued EVERY send
/// failure indiscriminately, including `invalid-argument` -- the ONE error
/// `telemetry_handler.ts` documents as genuinely terminal (a schema-invalid
/// report; see that file's own doc comment: "This is never retried by the
/// mobile outbox regardless (a malformed request stays malformed no matter
/// how many times it is resent)"). Combined with this outbox's own removal
/// of its eviction cap (`sendOrEnqueue`'s doc comment, "no silent drop"),
/// that meant a permanently-broken report would sit in the queue forever,
/// retried on every cold start/resume, and could never drain. Every OTHER
/// failure this outbox can observe is assumed retryable -- a network/`
/// unavailable`/`deadline-exceeded`/etc. failure, or any exception type this
/// classifier does not specifically recognize -- matching the conservative
/// default `classifyRequestFailureReason` (`equipment_identity_telemetry_
/// report.dart`) already uses for the SAME transport.
bool _isPermanentlyUndeliverable(Object error) =>
    error is FirebaseFunctionsException && error.code == 'invalid-argument';

/// Durable retry-on-failure delivery for equipment-identity telemetry
/// reports (P2.G5-readiness step 3b).
///
/// The server's own merge rules (`P2_G5_READINESS_SHADOW_TELEMETRY_LIFECYCLE_
/// CONTRACT_2026-09-12.md` §6 rule 2) make ANY report body safe to resend any
/// number of times: a write whose `payloadFingerprint` matches what is
/// already stored is a pure no-op. That is what makes blind retry safe here
/// -- this outbox never needs to know whether an EARLIER attempt actually
/// reached the server, only whether THIS attempt succeeded (or, per
/// [_isPermanentlyUndeliverable] above, can never succeed).
abstract class EquipmentIdentityTelemetryOutbox {
  /// Attempts to send [body] immediately via [send]. On success, returns
  /// without enqueuing anything. On a retryable failure, persists [body]
  /// durably for a later [drainPending]. On a permanently undeliverable
  /// failure, logs and drops it. Either way returns without rethrowing --
  /// the same "never surfaces to the caller" contract the fire-and-forget
  /// send this replaces already had
  /// (`equipment_identity_providers.dart`'s `_sendTelemetryReport`).
  Future<void> sendOrEnqueue(EquipmentIdentityTelemetrySend send, Map<String, dynamic> body);

  /// Retries every currently-pending report via [send]. A report that fails
  /// again retryably stays queued; one that succeeds, or turns out to be
  /// permanently undeliverable, is removed. Never throws -- a drain failure
  /// is exactly the state this exists to tolerate, not a bug to surface to
  /// whatever triggered the drain (app resume).
  Future<void> drainPending(EquipmentIdentityTelemetrySend send);

  /// Diagnostic only, mirroring `EquipmentIdentityOutcomeSink.conflictedScanIds`'s
  /// own "never surfaced to the user" posture.
  Future<int> get pendingCount;
}

/// Local-file-backed implementation.
///
/// Durability, precisely stated (GPT-PM BLOCKER, P2.G5-readiness step 3b
/// review -- both round 1 and, more firmly, round 2, 2026-09-16): an earlier
/// version of this class was `SharedPreferences`-backed, matching this app's
/// OTHER local-durability repositories (`PrefsMomentRepository`,
/// `PrefsSensitiveStore`). GPT-PM round 2 rejected that as insufficient for
/// THIS gate's own stated acceptance contract specifically -- "durable
/// outbox" and "no silent drop" -- because `SharedPreferences`/
/// `NSUserDefaults` writes are documented as reaching disk asynchronously,
/// with no guarantee of persistence at the instant the write's `Future`
/// completes; a process killed in that window could still lose an entry
/// with zero observable failure anywhere. Writing to a local file with
/// `flush: true` closes that gap for real: `dart:io`'s `File.writeAsString`
/// with `flush: true` does not return until the platform's own fsync-
/// equivalent call (`fsync` on POSIX, `FlushFileBuffers` on Windows) has
/// completed, so a successful write genuinely means "on disk," not merely
/// "queued to be written eventually." This is the SAME storage mechanism
/// (`path_provider`'s `getApplicationDocumentsDirectory()` +
/// `writeAsString(..., flush: true)`) this codebase already uses for other
/// durable local JSON state -- `photo_store.dart`'s `_writeIndex`,
/// `photo_directory.dart`'s `index.json` -- so this is an established
/// in-repo convention, not a new one introduced just for this class.
///
/// No migration from the earlier `SharedPreferences`-backed key
/// (`equipment_identity_telemetry_outbox_v1`) is implemented: this outbox
/// has never shipped (P2.G5-readiness enrichment stays behind a hardcoded-
/// `false` flag), so no device anywhere holds real data under that key.
class FileEquipmentIdentityTelemetryOutbox implements EquipmentIdentityTelemetryOutbox {
  FileEquipmentIdentityTelemetryOutbox(this._file);

  final File _file;

  static const _fileName = 'equipment_identity_telemetry_outbox_v2.json';

  static Future<FileEquipmentIdentityTelemetryOutbox> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return FileEquipmentIdentityTelemetryOutbox(File('${dir.path}/$_fileName'));
  }

  // `sendOrEnqueue` and `drainPending` are both fire-and-forget from every
  // real call site (`_sendTelemetryReport`'s `unawaited(...)`, and the
  // resume/cold-start drain triggers in `main.dart`), so two of either can
  // genuinely overlap -- e.g. two scans fail telemetry in the same burst, or
  // a drain is still running when a third scan's send fails mid-drain. Each
  // method's own STORAGE mutation (read the persisted list, compute the new
  // one, write it back) is NOT atomic against this file by itself, so
  // without this chain two overlapping calls can each read the same stale
  // snapshot and the second write silently clobbers the first -- losing a
  // report that was never actually sent. Chaining every storage mutation
  // through one `Future` makes each call wait for the previous one's read
  // -mutate-write to fully land before starting its own. Sufficient here
  // because this file is touched by ONLY this Dart isolate -- no separate
  // process or isolate writes it, so a same-isolate `Future` chain is a
  // complete lock, not merely a best-effort one.
  //
  // Deliberately does NOT cover network I/O -- see `sendOrEnqueue`'s own
  // comment for why the send() call there stays outside this chain, and
  // `drainPending`'s own comment for why it snapshots-then-reconciles
  // instead of holding this chain across every retry.
  Future<void> _mutationChain = Future<void>.value();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _mutationChain.then((_) => action());
    // Keep the chain alive regardless of whether `action` threw -- a failed
    // mutation must not permanently wedge every later one behind a broken
    // link.
    _mutationChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<PendingTelemetryReport>> _readAll() async {
    // Every failure mode here (file missing, unreadable, corrupt JSON, a
    // corrupt individual entry) degrades to "treat as empty"/"skip this one
    // entry" rather than throwing -- this class's own documented "never
    // throws" contract.
    String raw;
    try {
      if (!await _file.exists()) return const <PendingTelemetryReport>[];
      raw = await _file.readAsString();
    } catch (e) {
      debugPrint('equipment identity telemetry outbox: unreadable store, treating as empty: $e');
      return const <PendingTelemetryReport>[];
    }
    if (raw.isEmpty) return const <PendingTelemetryReport>[];

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      debugPrint('equipment identity telemetry outbox: unparseable store, treating as empty: $e');
      return const <PendingTelemetryReport>[];
    }

    final reports = <PendingTelemetryReport>[];
    for (final entry in decoded) {
      try {
        reports.add(PendingTelemetryReport.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        // A single corrupt entry (a future format change, a truncated
        // write) must not poison every other pending report sitting beside
        // it in the same list -- skip it and keep the rest.
        debugPrint('equipment identity telemetry outbox: dropping unreadable entry: $e');
      }
    }
    return reports;
  }

  // GPT-PM BLOCKER, P2.G5-readiness step 3b review round 3, 2026-09-16: an
  // earlier version of this method wrote straight to `_file` via
  // `writeAsString`. `flush: true` guarantees bytes are on disk once the
  // `Future` completes, but says nothing about the write itself -- Dart's
  // default `FileMode.write` truncates the file FIRST, then writes the new
  // content. A process killed between the truncate and the write completing
  // (a real, not hypothetical, window on Android, which can terminate an
  // app process at any time) would leave `_file` truncated or holding
  // half-written JSON -- and `_readAll`'s own "a wholly unparseable store
  // degrades to empty" tolerance (deliberate, for an unrelated reason: a
  // future format change must not wedge the outbox forever) would then
  // silently destroy every PREVIOUSLY durable report that write's own
  // failure had nothing to do with. This is exactly the crash-safety gap
  // GPT-PM's round-2 BLOCKER required migrating off `SharedPreferences` to
  // close, and moving to a file alone did not close it.
  //
  // Fixed with the standard mitigation for exactly this failure mode (the
  // same technique SQLite, git and most production systems use for
  // crash-safe file replacement): write the complete new content to a
  // sibling temp file, flush it, then atomically rename it over the real
  // file. `dart:io`'s `File.rename` maps to the platform's own atomic
  // rename primitive (`rename(2)` on POSIX, guaranteed atomic for a
  // same-directory/same-filesystem move; the Win32 call Dart's runtime uses
  // is likewise atomic for a same-volume move) -- so a process death can
  // only ever be observed as EITHER "the old file is still fully intact,
  // possibly next to an incomplete `.tmp`" OR "the new file is fully in
  // place" -- never a partially-overwritten real file. `_readAll` only ever
  // reads `_file`, never `.tmp`, so a leftover incomplete `.tmp` from an
  // interrupted write is inert -- ignored on every subsequent read, and
  // silently replaced by the next successful write.
  Future<void> _writeAll(List<PendingTelemetryReport> reports) async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(reports.map((r) => r.toJson()).toList(growable: false)),
        flush: true,
      );
      await tmp.rename(_file.path);
    } catch (e) {
      // Unlike `SharedPreferences.setStringList`'s silently-discardable
      // `Future<bool>`, a real file-write failure here throws -- caught and
      // logged rather than left to propagate into `sendOrEnqueue`'s own
      // "never surfaces to the caller" contract.
      debugPrint('equipment identity telemetry outbox: write failed -- ${reports.length} '
          'pending report(s) may not have persisted: $e');
    }
  }

  @override
  Future<void> sendOrEnqueue(
      EquipmentIdentityTelemetrySend send, Map<String, dynamic> body) async {
    try {
      // Deliberately outside `_mutate`: this is a network round-trip with no
      // bound on how long it can take, and it touches no state this class
      // owns until it actually fails. Serializing it with storage mutations
      // would let one slow send stall every other enqueue/drain in the app
      // for no correctness benefit.
      await send(body);
    } catch (e) {
      if (_isPermanentlyUndeliverable(e)) {
        debugPrint('equipment identity telemetry report permanently undeliverable, dropping: $e');
        return;
      }
      debugPrint('equipment identity telemetry send failed, enqueuing for retry: $e');
      await _mutate(() async {
        final pending = List<PendingTelemetryReport>.of(await _readAll())
          ..add(PendingTelemetryReport(
            id: _generateId(),
            body: body,
            enqueuedAt: DateTime.now().toUtc().toIso8601String(),
          ));
        // Deliberately NO cap here (GPT-PM MAJOR, P2.G5-readiness step 3b
        // review, 2026-09-16, reversing an earlier version of this method
        // that dropped the oldest entry past 200): the frozen P2.G5 design
        // contract's own binding Story DoD requires the readiness metric's
        // denominator to have "no silent drop" (`P2_G5_READINESS_SHADOW_
        // TELEMETRY_LIFECYCLE_CONTRACT_2026-09-12.md` §1, §5.3's
        // `incomplete_evidence_count` formula), and a LOCAL_FAILURE report
        // silently evicted here before it ever reaches the server is not
        // merely "excluded but counted" the way the contract's own 8
        // infrastructure outcomes are (§4.3.2) -- it is gone with no trace
        // anywhere, which is exactly what that DoD forbids. Growth here is
        // bounded by real scans a person physically performs (this queue
        // only grows on an actual RETRYABLE failed telemetry send, never on
        // its own, and a permanently-undeliverable report is dropped above
        // rather than ever entering this list), not by anything an
        // adversary or a bug can inflate without bound.
        await _writeAll(pending);
      });
    }
  }

  @override
  Future<void> drainPending(EquipmentIdentityTelemetrySend send) async {
    // Snapshot-then-reconcile, not "hold the storage lock for the whole
    // drain" (GPT-PM MAJOR, P2.G5-readiness step 3b review, 2026-09-16,
    // reversing an earlier version of this method that wrapped the entire
    // retry loop -- including every `await send(...)` -- inside `_mutate`).
    // That earlier version meant a concurrent `sendOrEnqueue` failure had to
    // wait behind EVERY item in an in-progress drain (potentially many
    // network round-trips) before its own enqueue could touch storage --
    // directly contradicting `_sendTelemetryReport`'s own comment that a
    // failed drain attempt costs "one extra doomed network call", and, more
    // importantly, delaying how quickly a genuinely new failure becomes
    // durable for no correctness benefit.
    //
    // The two storage-touching steps below (snapshot, reconcile) are each
    // individually serialized via `_mutate` as usual; only the N network
    // sends in between run outside any lock. This is safe under
    // concurrency because reconciliation removes entries by their stable
    // [PendingTelemetryReport.id], read FRESH from storage at reconcile
    // time -- never from the stale snapshot -- so a report a concurrent
    // `sendOrEnqueue` added (or one this same drain is racing another
    // drain over -- the server's own idempotent-replay guarantee, §6 rule
    // 2 of the design contract, makes two drains attempting the same report
    // concurrently just a redundant network call, never a correctness
    // problem) is never removed just because it happened to exist when the
    // OLD snapshot was taken.
    final snapshot = await _mutate(() => _readAll());
    if (snapshot.isEmpty) return;

    // Removed for either reason: delivered, or now known to be permanently
    // undeliverable (GPT-PM MAJOR, round 2 -- see [_isPermanentlyUndeliverable]).
    final toRemove = <String>{};
    for (final report in snapshot) {
      try {
        await send(report.body);
        toRemove.add(report.id);
      } catch (e) {
        if (_isPermanentlyUndeliverable(e)) {
          debugPrint('equipment identity telemetry report permanently undeliverable, dropping: $e');
          toRemove.add(report.id);
        } else {
          debugPrint('equipment identity telemetry retry failed, keeping queued: $e');
        }
      }
    }
    if (toRemove.isEmpty) return;

    await _mutate(() async {
      final current = await _readAll();
      final remaining = current.where((r) => !toRemove.contains(r.id)).toList(growable: false);
      await _writeAll(remaining);
    });
  }

  @override
  Future<int> get pendingCount => _mutate(() async => (await _readAll()).length);
}

/// Test double. Never touches real storage; `pending` is directly
/// inspectable so a test can assert a failed send actually queued the right
/// body, without reading through the real JSON round-tripping. Mirrors the
/// real implementation's terminal-vs-retryable distinction
/// ([_isPermanentlyUndeliverable]) so a test exercising this fake sees the
/// same policy the real outbox applies.
class InMemoryEquipmentIdentityTelemetryOutbox implements EquipmentIdentityTelemetryOutbox {
  final List<Map<String, dynamic>> pending = [];
  int drainAttempts = 0;

  @override
  Future<void> sendOrEnqueue(
      EquipmentIdentityTelemetrySend send, Map<String, dynamic> body) async {
    try {
      await send(body);
    } catch (e) {
      if (_isPermanentlyUndeliverable(e)) return;
      pending.add(body);
    }
  }

  @override
  Future<void> drainPending(EquipmentIdentityTelemetrySend send) async {
    drainAttempts++;
    final stillPending = <Map<String, dynamic>>[];
    for (final body in List<Map<String, dynamic>>.of(pending)) {
      try {
        await send(body);
      } catch (e) {
        if (!_isPermanentlyUndeliverable(e)) stillPending.add(body);
      }
    }
    pending
      ..clear()
      ..addAll(stillPending);
  }

  @override
  Future<int> get pendingCount async => pending.length;
}
