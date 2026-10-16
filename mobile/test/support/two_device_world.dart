// A TWO-DEVICE fake cloud for the S02 sync tests (test plan step 0, epic 4):
// one fake Firestore server that ENFORCES the rules (`rev` rule, immutable
// `startUtc` and `sport`, closed key shape and bounds, `startUtc` clamp, the
// tombstone check and the account-deletion fence), and any number of devices,
// each with its own journal directory (real `FileActivityJournal` over the
// in-memory file system), its own `ActivitySyncRepository` and a per-device
// view of the backend that can go offline, lose an acknowledgement or run a
// hook between a read and the following write (a racing second device).
//
// The server records every ACCEPTED and every REFUSED write per device, so a
// test can assert the write log ("no write ever carries 4 800") and that the
// loser of a race IS refused before it asserts convergence (a fake that never
// conflicts would make every convergence test pass trivially). Test-only.
import 'dart:async';
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';

import 'journal_harness.dart';

/// The literal version triples of the plan section 1.16 (V1, V2, V3).
const CalcVersions kV1 = CalcVersions(
    formulaVersion: 'f1', metricDefinitionVersion: 'm1', thresholdPolicyVersion: 't1');
const CalcVersions kV2 = CalcVersions(
    formulaVersion: 'f2', metricDefinitionVersion: 'm1', thresholdPolicyVersion: 't1');
const CalcVersions kV3 = CalcVersions(
    formulaVersion: 'f3', metricDefinitionVersion: 'm1', thresholdPolicyVersion: 't1');

/// One write the server ACCEPTED.
class AcceptedWrite {
  AcceptedWrite(this.device, this.id, this.create, this.summary);

  final String device;
  final String id;
  final bool create;
  final Map<String, Object> summary;

  int get rev => summary['rev'] as int;

  num? operator [](String field) => summary[field] as num?;

  @override
  String toString() =>
      'AcceptedWrite($device, rev $rev, distanceM ${summary['distanceM']})';
}

/// One write the server REFUSED (the rules gate said no).
class RefusedWrite {
  RefusedWrite(this.device, this.id, this.create, this.rev, this.reason);

  final String device;
  final String id;
  final bool create;
  final int? rev;
  final String reason;

  @override
  String toString() => 'RefusedWrite($device, rev $rev, $reason)';
}

/// The fake Firestore of one user.
class FakeFirestoreServer {
  final Map<String, Map<String, Object?>> docs = {};
  final Set<String> tombstones = {};

  /// `activity_account_state/{uid}` exists: every summary write is refused.
  bool accountFence = false;

  final List<AcceptedWrite> accepted = [];
  final List<RefusedWrite> refused = [];

  /// Create-shaped writes (client said `create`) for an id that exists.
  int createOverExisting = 0;

  /// `startUtc` outside this window is clamped away by the rules.
  DateTime clampMin = DateTime.utc(2000);
  DateTime clampMax = DateTime.utc(2100);

  /// Accepted writes of one device, in order.
  List<AcceptedWrite> writesBy(String device) =>
      [for (final w in accepted) if (w.device == device) w];

  /// Accepted writes carrying `field == value` (any device).
  List<AcceptedWrite> writesWith(String field, num value) => [
        for (final w in accepted)
          if (w[field] != null && w[field]!.toDouble() == value.toDouble()) w
      ];

  /// Direct server-side change that bypasses the rules (a Cloud Function or
  /// the console): seeds a document or a tombstone.
  void seed(String id, Map<String, Object?> doc) => docs[id] = {...doc};

  String? _shapeError(Map<String, Object> s) {
    for (final k in s.keys) {
      if (!kSummaryAllowedKeys.contains(k)) return 'unknown key $k';
    }
    for (final k in kSummaryRequiredKeys) {
      if (!s.containsKey(k)) return 'missing $k';
    }
    for (final e in kSummaryNumericBounds.entries) {
      final v = s[e.key];
      if (v == null) continue;
      if (v is! num || !e.value.accepts(v)) return 'bound ${e.key}';
    }
    for (final e in kSummaryIntBounds.entries) {
      final v = s[e.key];
      if (v == null) continue;
      if (v is! int || !e.value.accepts(v)) return 'int bound ${e.key}';
    }
    final start = s['startUtc'];
    final end = s['endUtc'];
    if (start is! DateTime || end is! DateTime) return 'timestamps';
    if (end.isBefore(start)) return 'endUtc before startUtc';
    if (start.isBefore(clampMin) || start.isAfter(clampMax)) return 'clamp';
    return null;
  }

  /// The rules gate. Returns the refusal reason, or null when accepted (and
  /// then applied).
  String? write(String device, String id, Map<String, Object> summary,
      {required bool create}) {
    final rev = summary['rev'];
    String? deny(String reason) {
      refused.add(RefusedWrite(device, id, create, rev is int ? rev : null, reason));
      return reason;
    }

    final stored = docs[id];
    if (create && stored != null) createOverExisting++;
    if (accountFence) return deny('fence');
    if (tombstones.contains(id)) return deny('tombstone');
    final shape = _shapeError(summary);
    if (shape != null) return deny('shape: $shape');
    if (rev is! int) return deny('rev');
    if (stored == null) {
      if (rev != 1) return deny('create needs rev 1');
    } else {
      final old = stored['rev'];
      if (old is! int || rev <= old) return deny('rev must increase');
      for (final k in kSummaryImmutableKeys) {
        final a = stored[k], b = summary[k];
        final same = a is DateTime && b is DateTime ? a.toUtc() == b.toUtc() : a == b;
        if (!same) return deny('immutable $k');
      }
    }
    docs[id] = {...summary};
    accepted.add(AcceptedWrite(device, id, create, {...summary}));
    return null;
  }
}

/// One device's view of the server. Implements the production seam.
class DeviceBackend implements ActivitySummaryBackend {
  DeviceBackend(this.name, this.server);

  final String name;
  final FakeFirestoreServer server;

  /// Every call fails with `SummaryBackendUnavailable`.
  bool offline = false;

  /// The next write is APPLIED and then reported as unavailable.
  bool dropNextAck = false;

  /// Runs once, right after the next `readSummary` computed its answer and
  /// before the answer is returned (a racing second device writes here).
  FutureOr<void> Function()? afterNextRead;

  /// Runs right after a write was accepted and before it returns.
  void Function()? afterApply;

  final List<String> calls = [];

  int count(String call) => calls.where((c) => c == call).length;

  void _guard() {
    if (offline) throw const SummaryBackendUnavailable('offline');
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    calls.add('readSummary');
    _guard();
    final d = server.docs[id];
    final out = d == null ? null : {...d};
    final hook = afterNextRead;
    if (hook != null) {
      afterNextRead = null;
      await hook();
    }
    return out;
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    calls.add('tombstoneExists');
    _guard();
    return server.tombstones.contains(id);
  }

  @override
  Future<Set<String>> listTombstoneIds() async {
    calls.add('listTombstoneIds');
    _guard();
    return {...server.tombstones};
  }

  @override
  Future<void> writeSummary(
    String id,
    Map<String, Object> summary, {
    required bool create,
  }) async {
    calls.add('writeSummary');
    _guard();
    final reason = server.write(name, id, summary, create: create);
    if (reason != null) throw SummaryWriteDenied(reason);
    afterApply?.call();
    if (dropNextAck) {
      dropNextAck = false;
      throw const SummaryBackendUnavailable('answer lost');
    }
  }
}

/// One device: journal directory, repository, backend view, version triple.
class Device {
  Device._(this.name, this.h, this.backend, this.versions);

  final String name;
  final JournalHarness h;
  final DeviceBackend backend;

  /// The calculation versions in force on this device (a test changes it to
  /// simulate an app upgrade or downgrade).
  CalcVersions versions;

  late ActivitySyncRepository repo;
  final List<ActivitySyncState> states = [];
  StreamSubscription<ActivitySyncState>? _sub;

  static Future<Device> open(String name, FakeFirestoreServer server,
      {CalcVersions versions = kV1}) async {
    final h = JournalHarness.memory();
    final d = Device._(name, h, DeviceBackend(name, server), versions);
    await h.open();
    d._newRepo();
    return d;
  }

  void _newRepo() {
    repo = ActivitySyncRepository(
      journal: h.journal,
      backend: backend,
      clock: h.clock.call,
      versionsInForce: () => versions,
      tombstonePusher: pusher,
    );
    _sub = repo.watch().listen(states.add);
  }

  /// Optional tombstone pusher (set before a `restart`).
  ActivityTombstonePusher? pusher;

  /// A new repository AND journal instance on the same directory (what a
  /// process restart does): everything read afterwards comes from disk.
  Future<void> restart() async {
    await _sub?.cancel();
    await repo.dispose();
    await h.restart();
    _newRepo();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await repo.dispose();
    await h.dispose();
  }

  // ---- reading ---------------------------------------------------------

  Future<JournalEntry> entry(String id) async {
    final e = await h.journal.read(id);
    if (e == null) throw StateError('$name has no entry $id');
    return e;
  }

  Future<ActivitySession> session(String id) async => (await entry(id)).session;

  Future<JournalSyncState> syncState(String id) async =>
      (await entry(id)).state.syncState;

  /// `record.json` of the selected generation, read from the file system.
  Future<Map<String, dynamic>> record(String id) async =>
      h.recordJson(id, (await entry(id)).generation);

  Future<Map<String, dynamic>> sessionMap(String id) async =>
      (await record(id))['session'] as Map<String, dynamic>;

  /// `summaryOverrides` of the stored record.
  Future<Map<String, dynamic>> overrides(String id) async =>
      ((await sessionMap(id))['summaryOverrides'] as Map?)?.cast<String, dynamic>() ??
      const {};

  /// `explicitValues` of the stored record.
  Future<Map<String, dynamic>> explicit(String id) async =>
      ((await sessionMap(id))['explicitValues'] as Map?)?.cast<String, dynamic>() ??
      const {};

  Future<Map<String, dynamic>?> baseSummary(String id) async =>
      ((await record(id))['state'] as Map)['baseSummary'] as Map<String, dynamic>?;

  Future<int?> baseRev(String id) async =>
      ((await record(id))['state'] as Map)['baseRev'] as int?;

  Future<int> generation(String id) async => (await entry(id)).generation;

  /// RAW recomputation of a field (what the record itself derives).
  Future<double?> rawOf(String id, String field) async =>
      SummaryProjection.derive(await session(id))[field];

  /// EFFECTIVE value of a field (raw, explicit value, override).
  Future<double?> effectiveOf(String id, String field) async =>
      SummaryProjection.effective(await session(id))[field];

  // ---- passive input changes (kind P) -------------------------------------

  /// A passive change of raw inputs through the real save path: the incoming
  /// session keeps the record state (explicit values, overrides) of the stored
  /// entry, is put as ONE generation and synced.
  Future<SyncOutcome> change(
    String id, {
    double? distanceM,
    double? movingTimeS,
    double? ascentM,
    double? avgSpeedMps,
    List<String>? mergeNotes,
    bool replaceStreams = false,
  }) async {
    final s = (await entry(id)).session;
    final f = {...s.summary.toFieldMap()};
    if (distanceM != null) f['distanceM'] = distanceM;
    if (ascentM != null) f['ascentM'] = ascentM;
    if (avgSpeedMps != null) f['avgSpeedMps'] = avgSpeedMps;
    var next = s.copyWith(
      summary: ActivitySummary.fromFieldMap(f),
      movingTimeS: movingTimeS,
      mergeNotes: mergeNotes,
    );
    if (replaceStreams) {
      next = next.copyWith(streams: journalSession(id, seed: 1).streams);
    }
    return repo.saveSession(next);
  }

  /// The same change but WITHOUT the sync (an offline input change): stores
  /// the generation and leaves the entry `pending`.
  Future<void> changeOffline(String id,
      {double? distanceM, double? movingTimeS, double? ascentM, double? avgSpeedMps}) async {
    final before = backend.offline;
    backend.offline = true;
    try {
      await change(id,
          distanceM: distanceM,
          movingTimeS: movingTimeS,
          ascentM: ascentM,
          avgSpeedMps: avgSpeedMps);
    } finally {
      backend.offline = before;
    }
  }
}

/// Base session of the two-device scenarios: every field the scenarios edit
/// has a value (a device with no value cannot recompute a field, rule 3).
ActivitySession baseSession(String id, {double distanceM = 4800}) =>
    journalSession(id, distanceM: distanceM).copyWith(
      movingTimeS: 1700,
      summary: ActivitySummary(
        distanceM: distanceM,
        ascentM: 30,
        descentM: 25,
        avgSpeedMps: 2.8,
      ),
    );

/// A world with a server and two devices A and B.
class World {
  World._(this.server, this.a, this.b);

  final FakeFirestoreServer server;
  final Device a;
  final Device b;

  static Future<World> open({CalcVersions versions = kV1}) async {
    final s = FakeFirestoreServer();
    return World._(
      s,
      await Device.open('A', s, versions: versions),
      await Device.open('B', s, versions: versions),
    );
  }

  Future<void> dispose() async {
    await a.dispose();
    await b.dispose();
  }

  /// Both devices hold the same activity, synced at rev 1 (the base): the
  /// start of every two-device scenario. Returns the id.
  Future<String> bothSynced({
    int n = 1,
    double distanceM = 4800,
    CalcVersions? versions,
  }) async {
    final id = idFor(n);
    final base = baseSession(id, distanceM: distanceM);
    await a.h.journal.put(base);
    await b.h.journal.put(base);
    final oa = await a.repo.syncEntry(id);
    final ob = await b.repo.syncEntry(id);
    if (oa != SyncOutcome.synced || ob != SyncOutcome.synced) {
      throw StateError('base sync failed: A $oa, B $ob');
    }
    return id;
  }

  /// The common setup of plan 1.16: base 4 800 at rev 1; A writes `distanceM`
  /// 5 000 (rev 2); B changes `movingTimeS` (a stale record that still
  /// recomputes 4 800), is refused, reads, merges three-way, ADOPTS A's value
  /// through an override and writes rev 3.
  Future<String> adopted({int n = 1}) async {
    final id = await bothSynced(n: n);
    final oa = await a.change(id, distanceM: 5000);
    if (oa != SyncOutcome.synced) throw StateError('A write failed: $oa');
    final ob = await b.change(id, movingTimeS: 1800);
    if (ob != SyncOutcome.synced) throw StateError('B merge failed: $ob');
    return id;
  }
}

/// `jsonEncode` helper for deep comparisons of record fragments.
String js(Object? o) => jsonEncode(o);
