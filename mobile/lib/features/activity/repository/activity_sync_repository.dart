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

import 'package:flutter/foundation.dart' show debugPrint;


import '../data/activity_cloud_summary.dart';
import '../data/activity_session.dart';
import '../data/activity_versions.dart';
import '../data/sport_type.dart';
import '../data/summary_fields.dart';
import '../data/summary_overrides.dart';
import '../data/summary_projection.dart';
import '../data/summary_three_way_merge.dart';
import 'activity_cloud_settings_client.dart' show ConsentAccountChangedException;
import 'activity_journal.dart';
import 'journal_errors.dart';
import 'activity_summary_backend.dart';
import 'journal_models.dart';
import 'summary_codec.dart';
import 'summary_write_denial.dart';
import 'sync_models.dart';
import 'uid_scoped_activity_journal.dart' show AccountScopedJournal;

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
typedef ActivityTombstonePusher = Future<void> Function(
    String activityId, String? expectedUid);

/// Creates the retry timer (injectable so tests need no real waiting).
typedef TombstoneRetryTimerFactory = Timer Function(
    Duration delay, void Function() callback);

/// Hard cap of push rounds (of [kMaxSummaryBatch] each) per [syncAll] call:
/// 128 rounds = 1024 deletions.
const int kMaxTombstoneRounds = 128;

/// Scheduled retry attempts per app start.
const int kMaxTombstoneRetries = 6;

/// Backoff before the Nth scheduled retry; the last entry is also the delay
/// after quota exhaustion.
const List<Duration> kTombstoneRetryDelays = [
  Duration(seconds: 60),
  Duration(minutes: 2),
  Duration(minutes: 4),
  Duration(minutes: 8),
  Duration(minutes: 15),
];

/// Delay of the single fallback timer kept after [kMaxTombstoneRetries]
/// scheduled attempts while tombstones are still owed.
const Duration kTombstoneFallbackDelay = Duration(minutes: 60);

/// `FirebaseException.code` of the server quota refusal.
const String kQuotaExhaustedCode = 'resource-exhausted';

/// Failures that end a round at once (retrying the rest of the batch is futile).
const Set<String> _kSystemicCodes = {
  kQuotaExhaustedCode,
  'unavailable',
  'permission-denied',
  'unauthenticated',
  'deadline-exceeded',
};

class _TombstoneRun {
  const _TombstoneRun(
      {this.failureCode, this.capped = false, this.aborted = false});

  final String? failureCode;
  final bool capped;

  /// The pass identity went stale (account switch) during the phase: nothing
  /// more was done and nothing may be concluded from the run.
  final bool aborted;

  bool get failed => failureCode != null;
}

/// The identity of one serialized operation (remediation F1): the account
/// epoch, the uid the scoped journal was bound to, and the signed-in uid, all
/// at the moment the operation started. Every journal write and every backend
/// call re-checks it, so an operation of account A never acts on account B.
class _Pass {
  const _Pass(this.epoch, this.journalUid, this.authUid);

  final int epoch;
  final String? journalUid;
  final String? authUid;
}

class ActivitySyncRepository {
  ActivitySyncRepository({
    required ActivityJournal journal,
    required ActivitySummaryBackend backend,
    ActivityTombstonePusher? tombstonePusher,
    DateTime Function()? clock,
    CalcVersions Function()? versionsInForce,
    TombstoneRetryTimerFactory? retryTimerFactory,
    String? Function()? authUid,
    String? Function()? accountBeingDeleted,
  })  : _journal = journal,
        _backend = backend,
        _pushTombstone = tombstonePusher,
        _timerFactory = retryTimerFactory ?? Timer.new,
        _clock = clock ?? DateTime.now,
        _versions = versionsInForce ?? (() => CalcVersions.current),
        _authUid = authUid,
        _accountBeingDeleted = accountBeingDeleted;

  final ActivityJournal _journal;
  final ActivitySummaryBackend _backend;
  final ActivityTombstonePusher? _pushTombstone;
  final DateTime Function() _clock;
  final CalcVersions Function() _versions;

  /// The signed-in uid as the backend would resolve it (null function = no
  /// check, used by tests). Read synchronously right before each backend call.
  final String? Function()? _authUid;

  /// The uid whose account deletion is in progress, or null (null function =
  /// never). While it equals the uid of a pass, that pass neither calls the
  /// backend nor writes the journal (remediation H5): the server-side deletion
  /// may complete at any moment and the Firestore rules would still accept the
  /// token, which would re-create data of a deleted account.
  final String? Function()? _accountBeingDeleted;

  /// True when [p] belongs to the account whose deletion is in progress.
  /// Read synchronously, right where the decision is taken.
  bool _deleting(_Pass p) {
    final f = _accountBeingDeleted;
    if (f == null) return false;
    final d = f();
    if (d == null) return false;
    return d == p.journalUid || d == p.authUid;
  }

  /// True when [expectedUid] (the uid captured at tap time) differs from the
  /// uid of the pass that is about to act (remediation H6). A null
  /// [expectedUid] means "no expectation".
  bool _uidMismatch(_Pass p, String? expectedUid) {
    if (expectedUid == null) return false;
    final j = p.journalUid;
    final a = p.authUid;
    return (j != null && j != expectedUid) || (a != null && a != expectedUid);
  }

  /// Identity of the operation now running inside [_ops] (operations are
  /// serialized, so one field is exact).
  _Pass _pass = const _Pass(-1, null, null);

  /// True when the journal is an account-scoped one with nothing bound.
  bool get _journalUnbound {
    if (_journal case final AccountScopedJournal s) return !s.isBound;
    return false;
  }

  String? _boundJournalUid() {
    if (_journal case final AccountScopedJournal s) {
      return s.isBound ? s.boundUid : null;
    }
    return null;
  }

  /// True when the journal is account-scoped AND an auth uid supplier exists:
  /// only then the journal uid and the signed-in uid must agree (remediation
  /// G1). Plain journals and a null supplier keep the old behaviour.
  bool get _tiesJournalToAuth =>
      _authUid != null && _journal is AccountScopedJournal;

  /// Starts a pass. For a scoped journal with an auth supplier the pass is valid
  /// only if the journal is bound and its uid equals the signed-in uid exactly
  /// (case-sensitive): `FirebaseAuth.currentUser` flips before the journal
  /// rebinds, and a pass of that gap would write A's data to B's cloud. A
  /// disagreeing or fail-closed pass gets the dead epoch -1 (never equal to
  /// [_epoch]), so every later [_alive] / [_mayCall] check refuses it.
  _Pass _beginPass() {
    final journalUid = _boundJournalUid();
    final authUid = _authUid?.call();
    if (_deleting(_Pass(_epoch, journalUid, authUid))) {
      return _Pass(-1, journalUid, authUid);
    }
    if (_tiesJournalToAuth &&
        (journalUid == null || authUid == null || journalUid != authUid)) {
      return _Pass(-1, journalUid, authUid);
    }
    return _Pass(_epoch, journalUid, authUid);
  }

  /// Runs [body] serialized, under a fresh pass identity.
  Future<T> _serial<T>(Future<T> Function() body) => _ops.run(() async {
        _pass = _beginPass();
        return body();
      });

  /// True while [p] still describes the current account: same epoch and, for a
  /// scoped journal, still bound to the uid the pass started under. Checked
  /// synchronously before every journal write.
  bool _alive(_Pass p) {
    if (p.epoch != _epoch) return false;
    if (_deleting(p)) return false;
    if (_journal case final AccountScopedJournal s) {
      return p.journalUid != null && s.isBound && s.boundUid == p.journalUid;
    }
    return true;
  }

  /// [_alive] plus the auth uid check; called synchronously immediately before
  /// every backend or tombstone-pusher call (no await in between).
  bool _mayCall(_Pass p) {
    if (!_alive(p)) return false;
    final f = _authUid;
    if (f == null) return true;
    final started = p.authUid;
    final now = f();
    if (started == null || now != started) return false;
    // Scoped journal: the signed-in uid must also still be the journal's uid.
    if (_journal is AccountScopedJournal) return now == p.journalUid;
    return true;
  }

  /// Why [p] may not run: a reason word only, never a uid (remediation G5).
  String _skipReason(_Pass p) {
    if (_deleting(p)) return 'account-deleting';
    if (_journalUnbound) return 'journal-unbound';
    if (_tiesJournalToAuth) {
      if (p.authUid == null) return 'auth-null';
      if (p.journalUid != p.authUid) return 'journal-auth-mismatch';
    }
    if (p.epoch != _epoch) return 'pass-identity';
    return 'auth-changed';
  }

  /// Logs that a pass (or its remainder) did nothing, so a skipped sync is
  /// observable. Reason word only; no uid, no id.
  void _logSkip(String op, _Pass p) {
    debugPrint('activity: $op skipped (${_skipReason(p)})');
  }

  final TombstoneRetryTimerFactory _timerFactory;
  final Set<String> _confirmedTombstones = {};
  final Set<String> _failedTombstones = {};
  Timer? _retryTimer;
  int _retryAttempts = 0;
  bool _disposed = false;

  /// Bumped by [onAccountChanged]; a tombstone pass started under an older
  /// value stops without pushing or scheduling anything.
  int _epoch = 0;

  String? _lastTombstonePushError;
  DateTime? _lastCorruptRead;

  /// Error code (`FirebaseException.code` or the exception type) of the last
  /// failed tombstone push, or null when none failed in this process (SF9).
  String? get lastTombstonePushError => _lastTombstonePushError;

  /// When a corrupt cloud summary was last met in this process (SF4), or null.
  DateTime? get lastCorruptRead => _lastCorruptRead;

  static String _errorCode(Object e) {
    // Duck-typed: callable failures carry a `code`; anything else is its type.
    try {
      final code = (e as dynamic).code;
      if (code is String && code.isNotEmpty) return code;
    } catch (_) {}
    return e.runtimeType.toString();
  }

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
        final sub = _changes.stream.listen(c.add, onError: c.addError);
        c.onCancel = sub.cancel;
        unawaited(refreshState().then((s) {
          if (!c.isClosed) c.add(s);
        }, onError: (Object e, StackTrace st) {
          // A failed refresh (journal I/O) is reported on the stream, never as
          // an uncaught async error and never as a silent empty state.
          if (!c.isClosed) c.addError(e, st);
        }));
      });

  /// The current state. Throws [JournalUnbound] while a scoped journal has no
  /// account bound (nobody signed in, or the bind failed): an unbound journal
  /// reads as empty, which must never be shown as "everything is in sync".
  Future<ActivitySyncState> refreshState() =>
      _stateLock.run(() async {
        // Remediation H7: a result assembled while the account changed
        // (epoch or bound uid moved) mixes two accounts and is discarded; the
        // read is repeated under the new identity, at most [attempts] times.
        const attempts = 3;
        for (var attempt = 0; attempt < attempts; attempt++) {
          if (_journalUnbound) throw const JournalUnbound();
          final stamp = _viewStamp();
          // Remediation I1: like a pass, a read is valid only while the scoped
          // journal's uid equals the signed-in uid; in the gap where auth
          // already points to B and the journal is still A's, A's cards must
          // not be shown. Retried (bounded), then JournalUnbound.
          if (!_viewTied(stamp)) {
            _logSkip('refreshState', stamp);
            continue;
          }
          final entries = await _journal.list();
          final conflicts = <SyncConflict>[];
          final candidates = <SyncCandidate>[];
          for (final e in entries) {
            if (!_viewCurrent(stamp)) break;
            var session = e.session;
            if (!session.isReadOnly) {
              session =
                  SummaryProjection.reconcile(session, inForce: _versions());
            }
            if (e.state.syncState == JournalSyncState.syncConflict) {
              conflicts.add(await _conflictView(e, session, stamp));
            }
            candidates.addAll(_candidatesOf(e.id, session));
          }
          if (!_viewCurrent(stamp)) continue;
          final pending = await _pendingTombstoneCount();
          if (!_viewCurrent(stamp)) continue;
          return ActivitySyncState(
            conflicts: conflicts,
            candidates: candidates,
            pendingTombstones: pending,
            lastTombstonePushError: _lastTombstonePushError,
          );
        }
        // The account kept changing: report "no usable state now"; the change
        // itself publishes a fresh state to every subscriber.
        throw const JournalUnbound();
      });

  /// Identity of one state read (not a serialized operation): epoch, bound
  /// journal uid and signed-in uid at the moment the read started.
  _Pass _viewStamp() => _Pass(_epoch, _boundJournalUid(), _authUid?.call());

  /// True when [stamp] satisfies the journal/auth tie of [_beginPass]: with a
  /// scoped journal and an auth supplier the journal must be bound and its uid
  /// must equal the signed-in uid. Always true for a plain journal or a null
  /// supplier (old behaviour).
  bool _viewTied(_Pass stamp) {
    if (!_tiesJournalToAuth) return true;
    return stamp.journalUid != null && stamp.journalUid == stamp.authUid;
  }

  /// True while the account a state read started under is still the current
  /// one (same epoch, same bound uid, same signed-in uid, no deletion).
  bool _viewCurrent(_Pass stamp) {
    if (!_alive(stamp)) return false;
    if (!_viewTied(stamp)) return false;
    final f = _authUid;
    return f == null || f() == stamp.authUid;
  }

  void _publish() {
    if (_changes.isClosed || !_changes.hasListener) return;
    unawaited(refreshState().then((s) {
      if (!_changes.isClosed) _changes.add(s);
    }, onError: (Object e) {
      // An unbound journal is reported to the listeners (the sheet shows its
      // error state); other refresh failures stay unreported here and surface
      // on the next subscription.
      if (e is JournalUnbound && !_changes.isClosed) _changes.addError(e);
    }));
  }

  Future<void> dispose() {
    _disposed = true;
    cancelTombstoneRetry();
    return _changes.close();
  }

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

  Future<SyncConflict> _conflictView(
      JournalEntry e, ActivitySession s, _Pass stamp) async {
    var detail = _conflictCache[e.id];
    if (detail == null) {
      try {
        // No backend read for an identity that is no longer (or never was)
        // consistent: the conflict then shows with no cloud values.
        if (!_mayCall(stamp)) {
          return SyncConflict(
            id: e.id,
            sport: s.sport,
            startUtc: s.startUtc,
            fields: const [],
            cloudKnown: false,
          );
        }
        final server = await _backend.readSummary(e.id);
        detail = _detailFor(e, s, server);
        // A read that finished after an account change is not cached: the
        // cache belongs to the account the read started under.
        if (_viewCurrent(stamp)) _conflictCache[e.id] = detail;
      } on SummaryBackendUnavailable {
        return SyncConflict(
          id: e.id,
          sport: s.sport,
          startUtc: s.startUtc,
          fields: const [],
          cloudKnown: false,
        );
      } on SummaryCorrupt {
        // Not cached: the cloud document is unreadable, so the conflict stays
        // visible with no cloud values to compare.
        return SyncConflict(
          id: e.id,
          sport: s.sport,
          startUtc: s.startUtc,
          fields: const [],
          cloudKnown: false,
        );
      } catch (_) {
        // Any other backend failure (e.g. permission-denied) is "cloud not
        // known": the conflict stays reachable. Not cached.
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
    if (!_alive(_pass)) return null;
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
  Future<SyncOutcome> syncEntry(String id) => _serial(() => _syncLocked(id));

  /// Start/foreground pass: deletes entries that carry a server tombstone,
  /// then syncs every unsynced entry. `sync_conflict` entries are retried only
  /// when [retryConflicts] is true and only once per process.
  ///
  /// The pass runs under one identity (remediation F1): if the account changes
  /// while it is in flight it stops at the next check with nothing further
  /// written, deleted or pushed (the entries then stay pending for account B's
  /// own pass).
  Future<Map<String, SyncOutcome>> syncAll({bool retryConflicts = false}) =>
      _serial(() async {
        final out = <String, SyncOutcome>{};
        final p = _pass;
        var tombs = <String>{};
        var tombsKnown = false;
        // Nothing is bound: no backend call, no outcomes (not "all synced").
        if (_journalUnbound) {
          _logSkip('syncAll', p);
          return out;
        }
        if (!_mayCall(p)) {
          _logSkip('syncAll', p);
          return out;
        }
        try {
          tombs = await _backend.listTombstoneIds();
          tombsKnown = true;
        } on SummaryBackendUnavailable {
          // unknown is never deletion
        } on SummaryCorrupt {
          // Tombstone ids are document ids and cannot be corrupt; treated as
          // unknown, never as deletion.
        }
        // A listing answered while the account changed belongs to nobody.
        if (!_mayCall(p)) {
          _logSkip('syncAll', p);
          return out;
        }
        // A failed tombstone listing is itself a reason for a backed-off retry.
        _TombstoneRun run;
        if (!tombsKnown) {
          run = const _TombstoneRun(failureCode: 'unavailable');
          if (_alive(p)) _lastTombstonePushError = 'unavailable';
        } else {
          try {
            run = await _pushLocalTombstones(tombs, p);
          } catch (e) {
            // Journal I/O or a missing uid in the tombstone phase: the pass
            // still publishes its state and a retry is scheduled.
            final code = _errorCode(e);
            debugPrint('activity: tombstone phase failed ($code)');
            if (!_alive(p)) return out;
            _lastTombstonePushError = code;
            run = _TombstoneRun(failureCode: code);
          }
        }
        if (!_alive(p) || run.aborted) return out;
        if (tombsKnown && !run.failed && !run.capped) {
          // Fully clean: nothing is owed, so the backoff budget and the last
          // error belong to a past problem.
          _retryAttempts = 0;
          _lastTombstonePushError = null;
        }
        await _maybeScheduleRetry(run, p);
        if (!_alive(p)) return out;
        final listed = await _journal.list();
        for (final e in listed) {
          // Re-checked before every entry: `listed` may belong to the account
          // that has just been left (ids are deterministic across accounts).
          if (!_alive(p)) return out;
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
  /// its copy (design 6.2). Rounds of [kMaxSummaryBatch]; a failure leaves the
  /// local tombstone in place and the push is retried by the backed-off timer
  /// or at the next pass. Ids the server already tombstones are skipped, which keeps the
  /// daily delete quota untouched by repeated passes.
  ///
  /// Continuation (remediation E2): after the first round, further rounds of
  /// [kMaxSummaryBatch] follow inside the same pass while the previous round
  /// pushed at least one and nothing failed, up to [kMaxTombstoneRounds]
  /// rounds (a hard cap, never a hot loop). Any failure in a continuation
  /// round, and any systemic refusal (quota, unavailable, permission) in any
  /// round, ends the pass at once. Ids that failed earlier in this process
  /// are tried last so one poisoned id cannot starve the rest.
  Future<_TombstoneRun> _pushLocalTombstones(
      Set<String> serverTombs, _Pass p) async {
    const aborted = _TombstoneRun(aborted: true);
    final push = _pushTombstone;
    if (!_alive(p)) return aborted;
    _confirmedTombstones.addAll(serverTombs);
    if (push == null) return const _TombstoneRun();
    var rounds = 0;
    while (true) {
      if (!_alive(p)) return aborted;
      final listedTombs = await _journal.listTombstones();
      // The list may belong to the account just left; never push it.
      if (!_alive(p)) return aborted;
      final owed = [
        for (final t in listedTombs)
          if (!_confirmedTombstones.contains(t.id)) t.id,
      ];
      if (owed.isEmpty) return const _TombstoneRun();
      if (rounds >= kMaxTombstoneRounds) {
        return const _TombstoneRun(capped: true);
      }
      rounds++;
      owed.sort((a, b) {
        final fa = _failedTombstones.contains(a) ? 1 : 0;
        final fb = _failedTombstones.contains(b) ? 1 : 0;
        return fa - fb;
      });
      var pushed = 0;
      var anyFailed = false;
      String? code;
      for (final id in owed) {
        if (pushed >= kMaxSummaryBatch) break;
        // Checked synchronously right before the call (no await in between):
        // a push for account A must not start once the account changed.
        if (!_mayCall(p)) return aborted;
        pushed++;
        try {
          await push(id, p.authUid);
          if (!_alive(p)) return aborted;
          _confirmedTombstones.add(id);
          _failedTombstones.remove(id);
        } catch (e) {
          if (!_alive(p)) return aborted;
          // Remediation J2: the account changed under the call (server refusal
          // or a missing uid). Same as `_mayCall` returning false: the pass
          // stops, the tombstone stays pending, no failure bookkeeping.
          if (e is ConsentAccountChangedException) return aborted;
          // Offline or refused: owed, retried later. The error code is kept so
          // a refusal is distinguishable from being offline.
          anyFailed = true;
          code = _errorCode(e);
          _lastTombstonePushError = code;
          _failedTombstones.add(id);
          debugPrint('activity: tombstone push failed ($code)');
          if (rounds > 1 || _kSystemicCodes.contains(code)) break;
        }
      }
      if (anyFailed) return _TombstoneRun(failureCode: code);
      if (pushed == 0) return const _TombstoneRun();
    }
  }

  /// Local tombstones the server has not confirmed (pushed OK or listed).
  Future<int> _pendingTombstoneCount() async => [
        for (final t in await _journal.listTombstones())
          if (!_confirmedTombstones.contains(t.id)) t,
      ].length;

  /// Schedules ONE backed-off retry when tombstones are still owed after a
  /// pass that ended on a failure or on the round cap. At most
  /// [kMaxTombstoneRetries] scheduled attempts per app start; quota exhaustion
  /// uses the longest delay. Cancelled by [dispose]/[cancelTombstoneRetry].
  Future<void> _maybeScheduleRetry(_TombstoneRun run, _Pass p) async {
    if (!_alive(p)) return;
    if (_disposed || _pushTombstone == null || _retryTimer != null) return;
    if (!run.failed && !run.capped) return;
    int owed;
    try {
      owed = await _pendingTombstoneCount();
    } catch (e) {
      // The count cannot be read now: tombstones may be owed, so retry.
      debugPrint('activity: pending tombstone count failed (${_errorCode(e)})');
      owed = 1;
    }
    // The await above may have spanned an account change or a competing
    // schedule: re-check before touching the budget or the timer.
    if (!_alive(p) || _disposed || _retryTimer != null) return;
    if (owed == 0) return;
    final Duration delay;
    if (_retryAttempts >= kMaxTombstoneRetries) {
      // Budget spent: ONE slow fallback timer keeps the session from ending
      // with owed deletions and no timer; it stops when nothing is owed.
      delay = kTombstoneFallbackDelay;
    } else {
      final delays = kTombstoneRetryDelays;
      delay = run.failureCode == kQuotaExhaustedCode
          ? delays.last
          : delays[_retryAttempts.clamp(0, delays.length - 1)];
      _retryAttempts++;
    }
    _retryTimer = _timerFactory(delay, () {
      _retryTimer = null;
      if (_disposed) return;
      unawaited(syncAll().then((_) {}, onError: (Object e) {
        debugPrint('activity: scheduled tombstone retry failed (${e.runtimeType})');
      }));
    });
  }

  /// Runs one normal serialized [syncAll] pass (no conflict retry) for callers
  /// that created a local deletion or came back to the foreground, so owed
  /// tombstones are pushed without waiting for the next start. Serialized
  /// through the same queue as every other operation; a failure is logged,
  /// never thrown to the caller. (S02 has no production local-delete caller;
  /// the delete UI of S03 must call this.)
  Future<void> requestTombstoneSync() async {
    if (_disposed) return;
    try {
      await syncAll();
    } catch (e) {
      debugPrint('activity: tombstone sync request failed (${e.runtimeType})');
    }
  }

  /// Cancels a scheduled tombstone retry.
  void cancelTombstoneRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// The signed-in account went away or changed (sign-out / uid change): the
  /// retry timer, the confirmed/failed id sets, the backoff budget and the
  /// last error belong to the previous account and are dropped, and a pass in
  /// flight stops before its next push. Without this a timer of account A
  /// would fire for account B, and an id A had confirmed (ids are
  /// deterministic) would never be pushed for B.
  void onAccountChanged() {
    _epoch++;
    cancelTombstoneRetry();
    _confirmedTombstones.clear();
    _failedTombstones.clear();
    _retryAttempts = 0;
    _lastTombstonePushError = null;
    // Cloud values read for account A and A's once-per-process conflict retry
    // marks must not leak into account B.
    _conflictCache.clear();
    _conflictTried.clear();
    // A live subscriber (the conflict presenter) must not keep showing the
    // previous account's conflicts: publish now. An unbound journal reaches the
    // stream as [JournalUnbound]. Never throws.
    onJournalBindingChanged();
  }

  /// The journal binding changed (a bind finished with success, failure or an
  /// exception, or an unbind): publish the current state to every subscriber.
  /// An unbound journal reaches the stream as [JournalUnbound], so a live
  /// presenter shows its failed state without a tap. A bind that failed never
  /// runs [syncAll], so nothing else would publish. No-op after [dispose];
  /// never throws.
  void onJournalBindingChanged() {
    if (_disposed) return;
    try {
      _publish();
    } catch (e) {
      debugPrint('activity: publish after binding change failed (${e.runtimeType})');
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
    // An unbound journal reads as empty: that is "cannot sync now", never
    // success and never notFound; no backend call is made.
    final p = _pass;
    if (_journalUnbound) {
      _logSkip('syncEntry', p);
      return SyncOutcome.pending;
    }
    if (!_alive(p)) {
      _logSkip('syncEntry', p);
      return SyncOutcome.pending;
    }
    JournalEntry? entry;
    try {
      entry = await _journal.read(id);
    } on JournalIoException {
      // Local read I/O error: nothing changed, retried at the next pass.
      return SyncOutcome.pending;
    }
    // The read may have resolved against the next account's journal.
    if (!_alive(p)) return SyncOutcome.pending;
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
      if (!_mayCall(p)) return SyncOutcome.pending;
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
    final p = _pass;
    bool? tomb;
    if (!_mayCall(p)) return SyncOutcome.pending;
    try {
      tomb = await _backend.tombstoneExists(entry.id);
    } on SummaryBackendUnavailable {
      tomb = null;
    }
    if (!_mayCall(p)) return SyncOutcome.pending;
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
    final p = _pass;
    Map<String, Object?>? server;
    if (known != null) {
      server = known.summary;
    } else {
      if (!_mayCall(p)) return SyncOutcome.pending;
      try {
        server = await _backend.readSummary(entry.id);
      } on SummaryBackendUnavailable {
        return afterDenial ? _markConflict(entry, null, const []) : _markFailed(entry);
      } on SummaryCorrupt {
        // A corrupt cloud document will not heal by retrying: a visible
        // conflict, local data kept, nothing written.
        _lastCorruptRead = _clock();
        debugPrint('activity: cloud summary unreadable (corrupt)');
        return _markConflict(entry, null, const []);
      }
      // The answer may belong to the account just left.
      if (!_mayCall(p)) return SyncOutcome.pending;
    }
    if (server == null) {
      if (afterDenial) return _markConflict(entry, null, const []);
      // No server document: a create with rev 1.
      final create = {...local, 'rev': 1};
      if (!_mayCall(p)) return SyncOutcome.pending;
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
      if (!_alive(p)) return SyncOutcome.pending;
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
    if (summariesEqual(merged, server)) {
      // Local equals the server on every field (lost acknowledgement, or a
      // resolution that changed nothing): no write, no spurious rev bump.
      return _markStored(current, _clean(server), summaryRev(server));
    }
    if (!_mayCall(p)) return SyncOutcome.pending;
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
    final p = _pass;
    bool? tomb;
    if (!_mayCall(p)) return SyncOutcome.pending;
    try {
      tomb = await _backend.tombstoneExists(entry.id);
    } on SummaryBackendUnavailable {
      tomb = null;
    }
    if (!_mayCall(p)) return SyncOutcome.pending;
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
    // The summary may already be stored under the previous account; the entry
    // of the next account must not be marked synced for it.
    if (!_alive(_pass)) return SyncOutcome.pending;
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
    final p = _pass;
    if (!_alive(p)) return SyncOutcome.pending;
    await _journal.updateSyncState(entry.id, JournalSyncState.syncConflict,
        expectedGeneration: entry.generation);
    // The await may have spanned an account change: a cache fill of account A
    // would be served to account B (ids are deterministic). Remediation H7.
    if (!_alive(p)) return SyncOutcome.pending;
    if (server != null) {
      _conflictCache[entry.id] = _ConflictDetail(server, fields);
    } else {
      _conflictCache.remove(entry.id);
    }
    _publish();
    return SyncOutcome.conflict;
  }

  Future<SyncOutcome> _markFailed(JournalEntry entry) async {
    if (!_alive(_pass)) return SyncOutcome.pending;
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
  Future<SyncOutcome> saveSession(ActivitySession incoming) => _serial(() async {
        final p = _pass;
        if (_journalUnbound) throw const JournalUnbound();
        final JournalEntry? prev;
        try {
          prev = await _journal.read(incoming.id);
        } on JournalIoException {
          // The stored entry (overrides, edits) cannot be read right now: do
          // not overwrite it blindly; nothing is changed, retry later.
          return SyncOutcome.pending;
        }
        // `prev` may come from the next account's journal: never merge it in.
        if (!_alive(p)) return SyncOutcome.pending;
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
        if (!_alive(p)) return SyncOutcome.pending;
        await _journal.put(next, syncState: keep);
        _conflictCache.remove(incoming.id);
        return _syncLocked(incoming.id);
      });
}

/// Display helper: the sport of an entry (kept here so presenters need no
/// journal types).
SportType sportOf(ActivitySession s) => s.sport;
