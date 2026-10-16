/// Summary sync orchestration over the local journal (S02 design 3.2, 6.2;
/// story S02-12): upload with `rev`, rev rejection and permission-denied,
/// three-way merge against `baseSummary`, `sync_conflict`, and adopted server
/// values through `summaryOverrides`. The resolution operations (user choices)
/// live in `activity_sync_resolution.dart` (a `part` of this library).
///
/// Rules kept here:
/// - the entry is `synced` only after the summary is stored on the server (or
///   already equals it); nothing local is ever deleted except by a server
///   tombstone (delete wins);
/// - the optimistic write needs no read; a rejection reads the tombstone and
///   the server summary, merges and retries ONCE; a second rejection leaves
///   `sync_conflict` (retried at the next start only, never hot-looped);
/// - overrides are persisted BEFORE the merged summary is written, so a crash
///   replays to the same result.
library;

import 'dart:async';
import 'dart:convert';

import '../data/activity_cloud_summary.dart';
import '../data/activity_session.dart';
import '../data/activity_versions.dart';
import '../data/sport_type.dart';
import '../data/summary_fields.dart';
import '../data/summary_overrides.dart';
import '../data/summary_projection.dart';
import '../data/summary_three_way_merge.dart';
import 'activity_journal.dart';
import 'activity_summary_backend.dart';
import 'journal_models.dart';
import 'summary_codec.dart';
import 'summary_write_denial.dart';
import 'sync_models.dart';

part 'activity_sync_resolution.dart';

/// Summary keys the device owns because they are derived metadata of its own
/// record (counts, versions, provenance, flags). They never take part in a
/// cross-device conflict: the local value is written. Only the numeric
/// overridable fields can conflict (design 3.2 examples).
final Set<String> _kDeviceOwnedKeys = Set.unmodifiable(
  kSummaryAllowedKeys
      .difference(kSummaryNumericBounds.keys.toSet())
      .difference(kSummaryImmutableKeys)
      .difference(kSummaryBookkeepingKeys),
);

/// The server summary as read: [summary] null means the document is absent.
class _Server {
  const _Server(this.summary);

  final Map<String, Object?>? summary;
}

class _Analysis {
  const _Analysis.merged(this.summary, this.session) : conflicts = const [];
  const _Analysis.conflict(this.conflicts)
      : summary = null,
        session = null;

  final Map<String, Object>? summary;
  final ActivitySession? session;
  final List<String> conflicts;

  bool get isMerged => summary != null;
}

class _ConflictDetail {
  const _ConflictDetail(this.server, this.fields);

  final Map<String, Object?>? server;
  final List<String> fields;
}

/// Pushes one local delete to the server (the `deleteActivity` callable writes
/// the tombstone first, then removes streams and the summary; idempotent).
/// Throws on failure; the sync layer retries at the next pass.
typedef ActivityTombstonePusher = Future<void> Function(String activityId);

class ActivitySyncRepository {
  ActivitySyncRepository({
    required ActivityJournal journal,
    required ActivitySummaryBackend backend,
    ActivityTombstonePusher? tombstonePusher,
    DateTime Function()? clock,
    CalcVersions Function()? versionsInForce,
  })  : _journal = journal,
        _backend = backend,
        _pushTombstone = tombstonePusher,
        _clock = clock ?? DateTime.now,
        _versions = versionsInForce ?? (() => CalcVersions.current);

  final ActivityJournal _journal;
  final ActivitySummaryBackend _backend;
  final ActivityTombstonePusher? _pushTombstone;
  final DateTime Function() _clock;
  final CalcVersions Function() _versions;

  final JournalMutex _ops = JournalMutex();
  final JournalMutex _stateLock = JournalMutex();
  final StreamController<ActivitySyncState> _changes =
      StreamController<ActivitySyncState>.broadcast();
  final Map<String, _ConflictDetail> _conflictCache = {};
  final Set<String> _conflictTried = {};

  // ---- state stream --------------------------------------------------------

  /// The conflicts and candidates that need the user. Emits the current state
  /// first, then again after every change; an entry leaves the stream only
  /// once its resolution is stored.
  Stream<ActivitySyncState> watch() => Stream.multi((c) {
        final sub = _changes.stream.listen(c.add);
        c.onCancel = sub.cancel;
        unawaited(refreshState().then((s) {
          if (!c.isClosed) c.add(s);
        }));
      });

  Future<ActivitySyncState> refreshState() =>
      _stateLock.run(() async {
        final entries = await _journal.list();
        final conflicts = <SyncConflict>[];
        final candidates = <SyncCandidate>[];
        for (final e in entries) {
          var session = e.session;
          if (!session.isReadOnly) {
            session = SummaryProjection.reconcile(session, inForce: _versions());
          }
          if (e.state.syncState == JournalSyncState.syncConflict) {
            conflicts.add(await _conflictView(e, session));
          }
          candidates.addAll(_candidatesOf(e.id, session));
        }
        return ActivitySyncState(conflicts: conflicts, candidates: candidates);
      });

  void _publish() {
    if (_changes.isClosed || !_changes.hasListener) return;
    unawaited(refreshState().then((s) {
      if (!_changes.isClosed) _changes.add(s);
    }, onError: (Object _) {}));
  }

  Future<void> dispose() => _changes.close();

  List<SyncCandidate> _candidatesOf(String id, ActivitySession s) {
    final out = <SyncCandidate>[];
    final fields = <String>{
      ...s.explicitValues.keys,
      ...s.summaryOverrides.keys,
    }.toList()
      ..sort();
    for (final f in fields) {
      final choices = SummaryProjection.offeredChoices(s, f);
      if (choices.isEmpty) continue;
      final ex = s.explicitValues[f];
      final ov = s.summaryOverrides[f];
      final cand = ex?.sourceCandidate ?? ov?.recalcCandidate;
      if (cand == null) continue;
      out.add(SyncCandidate(
        id: id,
        sport: s.sport,
        startUtc: s.startUtc,
        field: f,
        reason: ex?.sourceCandidate != null
            ? CandidateReason.source
            : CandidateReason.recalculation,
        choices: choices,
        computedValue: cand,
        explicitValue: ex?.value,
        cloudValue: ov?.value,
      ));
    }
    return out;
  }

  Future<SyncConflict> _conflictView(JournalEntry e, ActivitySession s) async {
    var detail = _conflictCache[e.id];
    if (detail == null) {
      try {
        final server = await _backend.readSummary(e.id);
        detail = _detailFor(e, s, server);
        _conflictCache[e.id] = detail;
      } on SummaryBackendUnavailable {
        return SyncConflict(
          id: e.id,
          sport: s.sport,
          startUtc: s.startUtc,
          fields: const [],
          cloudKnown: false,
        );
      }
    }
    final local = _buildLocal(s, e.state, hasRouteKnown: false);
    final server = detail.server;
    return SyncConflict(
      id: e.id,
      sport: s.sport,
      startUtc: s.startUtc,
      cloudKnown: server != null,
      fields: [
        for (final f in detail.fields)
          FieldConflict(
              field: f, deviceValue: local[f], cloudValue: server?[f]),
      ],
    );
  }

  _ConflictDetail _detailFor(
      JournalEntry e, ActivitySession s, Map<String, Object?>? server) {
    if (server == null) return const _ConflictDetail(null, []);
    final local = _buildLocal(s, e.state, hasRouteKnown: false);
    final a = _analyze(s, decodeSummary(e.state.baseSummary), local, server);
    return _ConflictDetail(server, a.conflicts);
  }

  // ---- building and analysing ---------------------------------------------

  /// The summary this device would write now. [hasRouteKnown] is false when the
  /// streams are not loaded: `hasRoute` then comes from the last stored base.
  Map<String, Object> _buildLocal(
    ActivitySession s,
    JournalState state, {
    required bool hasRouteKnown,
    Map<String, Object?>? baseOverride,
    int? baseRevOverride,
  }) {
    final base = baseOverride ?? decodeSummary(state.baseSummary);
    final baseRev = baseRevOverride ?? state.baseRev;
    final m = ActivityCloudSummary.fromSession(s, updatedAt: _clock());
    if (!hasRouteKnown) {
      final b = base?['hasRoute'];
      if (b is bool) {
        m['hasRoute'] = b;
      } else {
        m.remove('hasRoute');
      }
    }
    if (base == null) {
      m['rev'] = 1;
    } else {
      final prev = baseRev ?? summaryRev(base);
      final next = summariesEqual(m, base) ? prev : prev + 1;
      m['rev'] = next < 1 ? 1 : (next > 1000000 ? 1000000 : next);
    }
    return m;
  }

  _Analysis _analyze(
    ActivitySession session,
    Map<String, Object?>? base,
    Map<String, Object> local,
    Map<String, Object?> server,
  ) {
    final serverForMerge = {...server};
    for (final k in _kDeviceOwnedKeys) {
      if (local.containsKey(k)) {
        serverForMerge[k] = local[k];
      } else {
        serverForMerge.remove(k);
      }
    }
    final mergeLocal = <String, Object?>{...local};
    if (base != null) {
      mergeLocal['rev'] = state0Rev(base);
    }
    final SummaryMergeResult r;
    try {
      r = mergeSummaries(base: base, local: mergeLocal, server: serverForMerge);
    } on ImmutableSummaryFieldViolation catch (e) {
      return _Analysis.conflict([e.field]);
    }
    if (r is SummaryMergeConflict) return _Analysis.conflict(r.fields);
    final merged = r as SummaryMerged;
    var next = session;
    final unresolved = <String>[];
    final serverRev = summaryRev(server);
    for (final f in merged.adoptedFromServer.toList()..sort()) {
      final v = server[f];
      final adopted = v is num && kSummaryNumericBounds.containsKey(f)
          ? SummaryProjection.adoptServerValue(next, f, v.toDouble(), serverRev,
              inForce: _versions())
          : null;
      if (adopted == null) {
        unresolved.add(f);
      } else {
        next = adopted;
      }
    }
    // Rule 3: a server-only change this device cannot reproduce is never
    // declared synced by guessing.
    if (unresolved.isNotEmpty) return _Analysis.conflict(unresolved);
    return _Analysis.merged(merged.summary, next);
  }

  /// The base revision used as the local `rev` inside the merge, so a merged
  /// write is `max(baseRev, serverRev) + 1`.
  int state0Rev(Map<String, Object?> base) => summaryRev(base);

  String _recordKey(ActivitySession s) => jsonEncode([
        s.calcVersions.toJson(),
        encodeSorted<ExplicitValue>(s.explicitValues, (e) => e.toJson()),
        encodeSorted<SummaryOverride>(s.summaryOverrides, (e) => e.toJson()),
      ]);

  /// Runs version reconciliation and the value rules and persists a change in
  /// one generation (design 3.2: mandatory and atomic). Null when the entry
  /// vanished or moved on.
  Future<JournalEntry?> _reconciled(JournalEntry e) async {
    if (e.session.isReadOnly) return e;
    final r = SummaryProjection.reconcile(e.session, inForce: _versions());
    if (_recordKey(r) == _recordKey(e.session)) return e;
    final updated =
        await _journal.updateRecord(e.id, r, expectedGeneration: e.generation);
    if (updated == null) return null;
    return JournalEntry(
      session: r,
      state: updated.state,
      generation: updated.generation,
      streamsLoaded: e.streamsLoaded,
    );
  }

  // ---- sync ----------------------------------------------------------------

  /// Syncs one entry. Safe to call repeatedly; a conflicting entry is retried
  /// by [syncAll] at most once per process.
  Future<SyncOutcome> syncEntry(String id) => _ops.run(() => _syncLocked(id));

  /// Start/foreground pass: deletes entries that carry a server tombstone,
  /// then syncs every unsynced entry. `sync_conflict` entries are retried only
  /// when [retryConflicts] is true and only once per process.
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) =>
      _ops.run(() async {
        final out = <String, SyncOutcome>{};
        var tombs = <String>{};
        var tombsKnown = false;
        try {
          tombs = await _backend.listTombstoneIds();
          tombsKnown = true;
        } on SummaryBackendUnavailable {
          // unknown is never deletion
        }
        if (tombsKnown) await _pushLocalTombstones(tombs);
        for (final e in await _journal.list()) {
          if (tombs.contains(e.id)) {
            await _journal.delete(e.id);
            _conflictCache.remove(e.id);
            out[e.id] = SyncOutcome.deletedLocal;
            continue;
          }
          if (e.state.syncState == JournalSyncState.synced) continue;
          if (e.state.syncState == JournalSyncState.syncConflict) {
            if (!retryConflicts || !_conflictTried.add(e.id)) continue;
          }
          out[e.id] = await _syncLocked(e.id);
        }
        _publish();
        return out;
      });

  /// Pushes local deletes the server does not know yet (no server tombstone in
  /// [serverTombs]) through the tombstone pusher, so another device removes
  /// its copy (design 6.2). At most [kMaxSummaryBatch] per pass; a failure
  /// leaves the local tombstone in place and the push is retried at the next
  /// pass. Ids the server already tombstones are skipped, which keeps the
  /// daily delete quota untouched by repeated passes.
  Future<void> _pushLocalTombstones(Set<String> serverTombs) async {
    final push = _pushTombstone;
    if (push == null) return;
    var pushed = 0;
    for (final t in await _journal.listTombstones()) {
      if (serverTombs.contains(t.id)) continue;
      if (pushed >= kMaxSummaryBatch) break;
      pushed++;
      try {
        await push(t.id);
      } catch (_) {
        // Offline or refused: owed, retried at the next pass.
      }
    }
  }

  /// Syncs at most [kMaxSummaryBatch] entries; a larger request is refused
  /// before anything is touched (design 6.2). A refusal is never read as
  /// deletion or conflict.
  Future<Map<String, SyncOutcome>> syncBatch(List<String> ids) async {
    if (ids.length > kMaxSummaryBatch) {
      throw SummaryBatchTooLarge(ids.length, kMaxSummaryBatch);
    }
    final out = <String, SyncOutcome>{};
    for (final id in ids) {
      out[id] = await syncEntry(id);
    }
    return out;
  }

  Future<SyncOutcome> _syncLocked(String id, {_Server? known}) async {
    var entry = await _journal.read(id);
    if (entry == null) return SyncOutcome.notFound;
    if (entry.session.isReadOnly) return SyncOutcome.readOnly;
    final reconciled = await _reconciled(entry);
    if (reconciled == null) return SyncOutcome.pending;
    entry = reconciled;

    final state = entry.state;
    final base = decodeSummary(state.baseSummary);
    final local = _buildLocal(entry.session, state,
        hasRouteKnown: entry.streamsLoaded);
    final conflictState = state.syncState == JournalSyncState.syncConflict;

    if (known == null && base != null && state.baseRev != null && !conflictState) {
      if (summariesEqual(local, base)) {
        if (state.synced) return SyncOutcome.synced;
        return _markStored(entry, base, state.baseRev!);
      }
      // Optimistic update at baseRev + 1: no read.
      try {
        await _backend.writeSummary(id, local, create: false);
      } on SummaryWriteDenied {
        return _onDenied(entry, local);
      } on SummaryBackendUnavailable {
        return _markFailed(entry);
      }
      return _markStored(entry, local, summaryRev(local));
    }
    return _readAndMerge(entry, local, known: known, afterDenial: false);
  }

  Future<SyncOutcome> _onDenied(JournalEntry entry, Map<String, Object> local) async {
    bool? tomb;
    try {
      tomb = await _backend.tombstoneExists(entry.id);
    } on SummaryBackendUnavailable {
      tomb = null;
    }
    if (decideOnSummaryWriteDenied(tombstoneExists: tomb) ==
        SummaryDenialAction.deleteLocal) {
      await _journal.delete(entry.id);
      _conflictCache.remove(entry.id);
      _publish();
      return SyncOutcome.deletedLocal;
    }
    return _readAndMerge(entry, local, known: null, afterDenial: true);
  }

  Future<SyncOutcome> _readAndMerge(
    JournalEntry entry,
    Map<String, Object> local, {
    required _Server? known,
    required bool afterDenial,
  }) async {
    Map<String, Object?>? server;
    if (known != null) {
      server = known.summary;
    } else {
      try {
        server = await _backend.readSummary(entry.id);
      } on SummaryBackendUnavailable {
        return afterDenial ? _markConflict(entry, null, const []) : _markFailed(entry);
      }
    }
    if (server == null) {
      if (afterDenial) return _markConflict(entry, null, const []);
      // No server document: a create with rev 1.
      final create = {...local, 'rev': 1};
      try {
        await _backend.writeSummary(entry.id, create, create: true);
      } on SummaryWriteDenied {
        return _onDeniedNoRetry(entry);
      } on SummaryBackendUnavailable {
        return _markFailed(entry);
      }
      return _markStored(entry, create, 1);
    }

    final base = decodeSummary(entry.state.baseSummary);
    final a = _analyze(entry.session, base, local, server);
    if (!a.isMerged) return _markConflict(entry, server, a.conflicts);

    var current = entry;
    if (_recordKey(a.session!) != _recordKey(entry.session)) {
      // Persist the adopted overrides BEFORE writing (crash-safe replay).
      final updated = await _journal.updateRecord(entry.id, a.session!,
          expectedGeneration: entry.generation);
      if (updated == null) return SyncOutcome.pending;
      current = JournalEntry(
        session: a.session!,
        state: updated.state,
        generation: updated.generation,
        streamsLoaded: entry.streamsLoaded,
      );
    }
    final merged = a.summary!;
    if (base != null && summariesEqual(merged, server)) {
      // Local equals the server on every field (lost acknowledgement, or a
      // resolution that changed nothing): no write, no spurious rev bump.
      return _markStored(current, _clean(server), summaryRev(server));
    }
    try {
      await _backend.writeSummary(entry.id, merged, create: false);
    } on SummaryWriteDenied {
      // A second rejection in the same retry: stay sync_conflict.
      return _markConflict(current, server, const []);
    } on SummaryBackendUnavailable {
      return _markFailed(current);
    }
    return _markStored(current, merged, summaryRev(merged));
  }

  Future<SyncOutcome> _onDeniedNoRetry(JournalEntry entry) async {
    bool? tomb;
    try {
      tomb = await _backend.tombstoneExists(entry.id);
    } on SummaryBackendUnavailable {
      tomb = null;
    }
    if (decideOnSummaryWriteDenied(tombstoneExists: tomb) ==
        SummaryDenialAction.deleteLocal) {
      await _journal.delete(entry.id);
      _conflictCache.remove(entry.id);
      _publish();
      return SyncOutcome.deletedLocal;
    }
    return _markConflict(entry, null, const []);
  }

  Map<String, Object> _clean(Map<String, Object?> server) => {
        for (final e in server.entries)
          if (e.value != null && kSummaryAllowedKeys.contains(e.key))
            e.key: e.value!,
      };

  Future<SyncOutcome> _markStored(
      JournalEntry entry, Map<String, Object?> stored, int rev) async {
    final ok = await _journal.markSynced(
      entry.id,
      expectedGeneration: entry.generation,
      baseRev: rev,
      baseSummary: encodeSummary(stored),
    );
    _conflictCache.remove(entry.id);
    _publish();
    return ok ? SyncOutcome.synced : SyncOutcome.pending;
  }

  Future<SyncOutcome> _markConflict(
      JournalEntry entry, Map<String, Object?>? server, List<String> fields) async {
    await _journal.updateSyncState(entry.id, JournalSyncState.syncConflict,
        expectedGeneration: entry.generation);
    if (server != null) {
      _conflictCache[entry.id] = _ConflictDetail(server, fields);
    } else {
      _conflictCache.remove(entry.id);
    }
    _publish();
    return SyncOutcome.conflict;
  }

  Future<SyncOutcome> _markFailed(JournalEntry entry) async {
    if (entry.state.syncState != JournalSyncState.syncConflict) {
      await _journal.updateSyncState(entry.id, JournalSyncState.uploadFailed,
          expectedGeneration: entry.generation);
    }
    return SyncOutcome.unavailable;
  }

  /// Exposed for the input-change path: a fresh derivation of an existing
  /// activity (for example a re-import) keeps the record state (explicit
  /// values, overrides, edit counter and history) of the stored entry, is put
  /// as ONE generation and synced.
  Future<SyncOutcome> saveSession(ActivitySession incoming) => _ops.run(() async {
        final prev = await _journal.read(incoming.id);
        var next = incoming;
        JournalSyncState? keep;
        if (prev != null) {
          final p = prev.session;
          next = incoming.copyWith(
            explicitValues: p.explicitValues,
            summaryOverrides: p.summaryOverrides,
            userEditCount: p.userEditCount,
            editHistory: p.editHistory,
            userEdits: p.userEdits,
          );
          if (prev.state.syncState == JournalSyncState.syncConflict) {
            keep = JournalSyncState.syncConflict;
          }
        }
        await _journal.put(next, syncState: keep);
        _conflictCache.remove(incoming.id);
        return _syncLocked(incoming.id);
      });
}

/// Display helper: the sport of an entry (kept here so presenters need no
/// journal types).
SportType sportOf(ActivitySession s) => s.sport;
