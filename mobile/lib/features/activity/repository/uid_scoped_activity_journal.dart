/// Account-scoped activity journals (S02 remediation E1, design 6.2, 7, 17).
///
/// Ownership is the location: every account has its own journal directory and
/// its own key, derived from the account uid. [UidScopedActivityJournal] holds
/// no data itself; it delegates to the journal currently bound to the signed-in
/// uid. Sign-out and account switch never destroy data (the previous journal is
/// only closed); only account deletion wipes the deleted account's scope.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import '../data/activity_session.dart';
import 'activity_journal.dart';
import 'file_activity_journal.dart';
import 'journal_cipher.dart';
import 'journal_errors.dart';
import 'journal_file_system.dart';
import 'journal_layout.dart'
    show
        kRecordingDirName,
        kScopedJournalRootDirName,
        kTempSuffix,
        kWipeMarkerWiped,
        kWipeMarkerWiping,
        kWipedMarkerSuffix;
import 'journal_models.dart';

/// The recording journal's side of the wipe ordering (S04 design 4.7, X2,
/// ARCH3). Implemented by lane R5's recording journal and registered with
/// [UidScopedActivityJournal.recordingGuard]. The repository layer never
/// imports the recorder; with no guard the wipe is exactly the S02 one.
abstract class RecordingScopeGuard {
  /// Drains the in-flight append of the recording journal of [scopeId], closes
  /// it and makes it refuse every further write for that scope (the same
  /// wiped-uid refusal as `UidScopedActivityJournal._wipedUid`). Releases the
  /// directory lock so the wipe can delete the files.
  Future<void> closeScope(String scopeId);
}

/// Optional companion of [RecordingScopeGuard]: a scope that was closed by a
/// wipe is opened again when the same uid binds afterwards (review S4).
abstract class RecordingScopeReopener {
  void reopenScope(String scopeId);
}

/// A put whose owner check and write are one synchronous step (review S2): the
/// delegate of the bound journal is captured only if [expectedUid] is bound at
/// that very moment, so a hand-off for account A can never land in B's store.
abstract class OwnerCheckedPut {
  Future<JournalEntry> putForOwner(
    String expectedUid,
    ActivitySession session, {
    JournalSyncState? syncState,
  });
}

/// The account-binding surface of a scoped journal.
abstract class AccountScopedJournal {
  /// Binds the journal of [uid] (null = unbind, nothing is deleted). Idempotent
  /// for the same uid. False = fail closed: nothing is bound.
  Future<bool> bindUid(String? uid);

  /// The uid currently bound, null while unbound.
  String? get boundUid;

  /// True while a journal is bound (a started journal of [boundUid]).
  bool get isBound;

  /// Wipes the journal scope of [uid] whether or not it is bound.
  Future<void> wipeForUid(String uid);
}

/// Optional read-only view of the recovery report of the last successful bind.
/// Implemented by [UidScopedActivityJournal]; other journals (fakes) need not.
abstract class RecoveryReportSource {
  /// The report returned by `start()` of the currently bound journal, null
  /// while unbound.
  JournalRecoveryReport? get lastRecoveryReport;
}

/// Opens (not yet started) the journal of one account scope.
typedef ActivityJournalFactory = Future<ActivityJournal> Function(
    String scopeId);

/// Scope id: first 32 lowercase hex chars of sha256(uid). The raw uid never
/// appears in a path or a key name.
String activityJournalScopeId(String uid) =>
    sha256Hex(utf8.encode(uid)).substring(0, 32).toLowerCase();

/// Production factory: `<app support>/activity_journal/<scopeId>` with a
/// secure-storage key suffixed by the scope id.
ActivityJournalFactory fileActivityJournalFactory() => (scopeId) async {
      final dir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      return FileActivityJournal(
        rootPath: '${dir.path}$sep$kScopedJournalRootDirName$sep$scopeId',
        keyProvider: SecureStorageJournalKeyProvider(scopeId: scopeId),
      );
    };

class UidScopedActivityJournal
    implements
        ActivityJournal,
        AccountScopedJournal,
        RecoveryReportSource,
        OwnerCheckedPut {
  /// Cheap: no I/O until [bindUid].
  UidScopedActivityJournal({
    ActivityJournalFactory? factory,
    JournalFileSystem fileSystem = const IoJournalFileSystem(),
    Future<String> Function()? scopesRoot,
    this.recordingGuard,
  })  : _factory = factory ?? fileActivityJournalFactory(),
        _fs = fileSystem,
        _scopesRoot = scopesRoot ?? _defaultScopesRoot;

  final ActivityJournalFactory _factory;
  final JournalFileSystem _fs;

  /// `<app support>/activity_journal`: the directory that holds every scope
  /// directory and the durable wiped markers beside them.
  final Future<String> Function() _scopesRoot;

  static Future<String> _defaultScopesRoot() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$kScopedJournalRootDirName';
  }

  /// Set by the recorder wiring (lane R5). Null = no recording journal.
  RecordingScopeGuard? recordingGuard;
  final JournalMutex _mutex = JournalMutex();
  ActivityJournal? _bound;
  String? _boundUid;
  JournalRecoveryReport? _lastReport;

  @override
  JournalRecoveryReport? get lastRecoveryReport => _lastReport;

  /// The uid whose scope was wiped while it was the bound one (account
  /// deletion). [bindUid] refuses it until another uid (or null) is bound, so a
  /// same-uid auth re-emission cannot re-create the deleted account's scope.
  String? _wipedUid;

  /// Longest wait for the owner-checked puts in flight on a delegate before it
  /// is closed or wiped.
  static const Duration _kInFlightDrainTimeout = Duration(seconds: 5);

  /// Owner-checked puts that were handed to a bound delegate and have not
  /// finished yet, per delegate (identity). Each future never completes with an
  /// error; it only marks the end of the put.
  final Map<ActivityJournal, Set<Future<void>>> _inFlightPuts =
      Map<ActivityJournal, Set<Future<void>>>.identity();

  /// Uids whose [wipeForUid] has been called and has not finished: from that
  /// moment [putForOwner] refuses them.
  final List<String> _wipingUids = <String>[];

  /// Set when the durable wipe marker of the BOUND uid could not be written:
  /// the transition is aborted, the old binding is dropped and no other uid
  /// may be bound until [wipeForUid] of that uid succeeds.
  String? _wipeBlockedUid;

  @override
  String? get boundUid => _boundUid;

  @override
  bool get isBound => _bound != null;

  /// Waits (bounded) for the owner-checked puts in flight on [delegate]; on a
  /// timeout it proceeds and logs a content-free line.
  Future<void> _drainInFlight(ActivityJournal? delegate) async {
    if (delegate == null) return;
    final set = _inFlightPuts[delegate];
    if (set == null || set.isEmpty) {
      _inFlightPuts.remove(delegate);
      return;
    }
    try {
      await Future.wait<void>(set.toList()).timeout(_kInFlightDrainTimeout);
    } on TimeoutException {
      debugPrint('activity: in-flight puts not finished (timeout)');
    } catch (e) {
      debugPrint('activity: in-flight put drain failed (${e.runtimeType})');
    }
    _inFlightPuts.remove(delegate);
  }

  Future<void> _unbind() async {
    final current = _bound;
    _bound = null;
    _boundUid = null;
    _lastReport = null;
    if (current != null) {
      // New owner-checked puts are refused from here on (`_bound` is null);
      // the ones already handed to [current] finish before it is closed.
      await _drainInFlight(current);
      try {
        await current.close();
      } catch (_) {
        // The directory guard is released best effort; data is untouched.
      }
    }
  }

  @override
  Future<bool> bindUid(String? uid) => _mutex.run(() async {
        if (uid != null && uid.isEmpty) {
          await _unbind();
          return false;
        }
        if (uid != null && uid == _wipedUid) {
          // Fail closed: this account was deleted; create no directory, no key.
          await _unbind();
          return false;
        }
        if (uid != null && _wipeBlockedUid != null) {
          // Fail closed: the durable wipe marker of the previous account could
          // not be written, so the transition was aborted. Bind nothing until
          // that wipe succeeds.
          await _unbind();
          return false;
        }
        // S04 design 4.7: the DURABLE wiped marker survives a relaunch. It
        // refuses the wiped scope until an explicit unbind or another uid.
        if (uid != null && uid != _boundUid) {
          final bool markerPresent;
          try {
            markerPresent = await _wipeMarkerExists(activityJournalScopeId(uid));
          } catch (e) {
            // Fail closed and retryable: an unreadable marker is never read as
            // absent.
            debugPrint('activity: wipe marker not readable (${e.runtimeType})');
            await _unbind();
            return false;
          }
          if (markerPresent) {
            await _unbind();
            return false;
          }
        }
        // An explicit unbind ends the wiped-uid refusal even when nothing is
        // bound (a wipe of the bound uid already left the journal unbound).
        if (uid == null) {
          _wipedUid = null;
          await _clearCompletedWipeMarkers();
        }
        if (uid == _boundUid && (uid == null || _bound != null)) return true;
        // A different uid or an explicit unbind ends the wiped-uid refusal.
        _wipedUid = null;
        if (uid != null) await _clearCompletedWipeMarkers();
        await _unbind();
        if (uid == null) return true;
        ActivityJournal? opened;
        try {
          opened = await _factory(activityJournalScopeId(uid));
          final report = await opened.start();
          _bound = opened;
          _boundUid = uid;
          _lastReport = report;
          final g = recordingGuard;
          if (g is RecordingScopeReopener) {
            (g as RecordingScopeReopener).reopenScope(activityJournalScopeId(uid));
          }
          return true;
        } catch (e) {
          // Fixed message and the exception TYPE only: never a message, path,
          // key or uid, so a keystore error, a corrupt directory and a full
          // disk stay distinguishable in telemetry.
          debugPrint('activity: journal open failed (${e.runtimeType})');
          if (opened != null) {
            try {
              await opened.close();
            } catch (_) {}
          }
          return false;
        }
      });

  @override
  Future<void> wipeForUid(String uid) {
    // Owner-checked puts for [uid] are refused from the moment of the call,
    // not only once the wipe reaches the front of the queue.
    if (uid.isNotEmpty) _wipingUids.add(uid);
    return _wipeForUidLocked(uid).whenComplete(() => _wipingUids.remove(uid));
  }

  Future<void> _wipeForUidLocked(String uid) => _mutex.run(() async {
        if (uid.isEmpty) throw const JournalUnbound();
        // Remembered in BOTH branches and even when the wipe fails: the marker
        // retries the wipe and nothing, not even an already queued
        // `bindUid(uid)`, may re-create the scope or its key afterwards.
        _wipedUid = uid;
        final scopeId = activityJournalScopeId(uid);
        // The puts already handed to the bound delegate finish (bounded) before
        // anything of it is wiped.
        if (uid == _boundUid) await _drainInFlight(_bound);
        // Ordering (S04 design 4.7): (1) the recorder was shut down by the
        // caller; (2) the recording journal drains and refuses writes, and the
        // durable marker is written BEFORE any S02 wipe step; (3) only then the
        // S02 wipe, which also deletes `recording/` and forgets the key.
        final guard = recordingGuard;
        if (guard != null) {
          try {
            await guard.closeScope(scopeId);
          } catch (e) {
            debugPrint('activity: recording close failed (${e.runtimeType})');
          }
        }
        try {
          await _writeWipeMarker(scopeId, kWipeMarkerWiping);
        } catch (e) {
          // Fail closed: without the durable marker a relaunch could not retry
          // or refuse this wipe. Abort the transition: the old binding becomes
          // unusable and no other uid may bind until this wipe succeeds. The
          // caller sees the failure (the existing wipe-incomplete path).
          debugPrint('activity: wipe marker not written (${e.runtimeType})');
          if (uid == _boundUid) {
            _wipeBlockedUid = uid;
            await _unbind();
          }
          rethrow;
        }
        // The recordings go regardless of whether the S02 scope can be started
        // (review S3).
        try {
          await _fs.deleteDir('${await _scopesRoot()}/$scopeId/$kRecordingDirName');
        } catch (e) {
          debugPrint('activity: recordings not deleted (${e.runtimeType})');
        }
        if (uid == _boundUid && _bound != null) {
          final current = _bound!;
          try {
            await current.wipe();
          } finally {
            await _unbind();
          }
          await _writeCompletedMarker(scopeId);
          if (_wipeBlockedUid == uid) _wipeBlockedUid = null;
          return;
        }
        final other = await _factory(scopeId);
        try {
          await other.start();
          await other.wipe();
        } finally {
          try {
            await other.close();
          } catch (_) {}
        }
        await _writeCompletedMarker(scopeId);
        if (_wipeBlockedUid == uid) _wipeBlockedUid = null;
      });

  /// The `wiped` upgrade of the marker. The `wiping` marker is already durable
  /// and keeps the scope refused and the wipe retryable, so a failure here is
  /// only logged.
  Future<void> _writeCompletedMarker(String scopeId) async {
    try {
      await _writeWipeMarker(scopeId, kWipeMarkerWiped);
    } catch (e) {
      debugPrint('activity: wipe marker not completed (${e.runtimeType})');
    }
  }

  // ---- durable wiped marker (S04 design 4.7) --------------------------------

  /// The marker path; throws when the scopes root cannot be resolved (the
  /// marker is then neither writable nor readable: fail closed, never absent).
  Future<String> _markerPath(String scopeId) async =>
      '${await _scopesRoot()}/$scopeId$kWipedMarkerSuffix';

  /// Content-free marker file: temp, fsync, rename. FAIL CLOSED: a failure is
  /// logged by type only by the caller and RETHROWN, so the wipe transition is
  /// aborted instead of continuing without a durable marker.
  Future<void> _writeWipeMarker(String scopeId, String content) async {
    final path = await _markerPath(scopeId);
    final tmp = '$path$kTempSuffix';
    try {
      await _fs.createDir(path.substring(0, path.lastIndexOf('/')));
      final h = await _fs.openWrite(tmp);
      try {
        await h.write(Uint8List.fromList(utf8.encode(content)));
        await h.flush();
        await h.fsync();
      } finally {
        await h.close();
      }
      await _fs.rename(tmp, path);
    } catch (_) {
      try {
        await _fs.deleteFile(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  /// True when the durable marker exists. THROWS when that cannot be read; the
  /// caller must not treat an unreadable marker as absent.
  Future<bool> _wipeMarkerExists(String scopeId) async =>
      _fs.exists(await _markerPath(scopeId));

  /// Removes the markers of COMPLETED wipes (content `wiped`); a marker of a
  /// wipe that did not finish stays so the relaunch path retries it.
  Future<void> _clearCompletedWipeMarkers() async {
    try {
      final root = await _scopesRoot();
      for (final e in await _fs.list(root)) {
        if (e.isDirectory || !e.name.endsWith(kWipedMarkerSuffix)) continue;
        final path = '$root/${e.name}';
        final text = utf8.decode(await _fs.readBytes(path), allowMalformed: true);
        if (text == kWipeMarkerWiped) await _fs.deleteFile(path);
      }
    } catch (_) {
      // Best effort; a stale completed marker is only refused again, never lost.
    }
  }

  ActivityJournal _writer() => _bound ?? (throw const JournalUnbound());

  // ---- reads: empty while unbound -------------------------------------------

  @override
  Future<JournalEntry?> read(String id) async => _bound?.read(id);

  @override
  Future<List<JournalEntry>> list() async =>
      await _bound?.list() ?? const <JournalEntry>[];

  @override
  Future<List<JournalEntry>> listTombstones() async =>
      await _bound?.listTombstones() ?? const <JournalEntry>[];

  @override
  Future<SignOutAssessment> assessSignOut() async =>
      await _bound?.assessSignOut() ??
      const SignOutAssessment(
          entryCount: 0, unsyncedCount: 0, streamLostCount: 0);

  @override
  int get streamLostCount => _bound?.streamLostCount ?? 0;

  // ---- writes: refused while unbound ----------------------------------------

  /// The scoped journal is started by [bindUid]; a direct start is a no-op
  /// report of the bound journal's state and never opens anything.
  @override
  Future<JournalRecoveryReport> start() async => JournalRecoveryReport();

  @override
  Future<JournalEntry> put(
    ActivitySession session, {
    JournalSyncState? syncState,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) async =>
      _writer().put(session,
          syncState: syncState, baseRev: baseRev, baseSummary: baseSummary);

  @override
  Future<JournalEntry> putForOwner(
    String expectedUid,
    ActivitySession session, {
    JournalSyncState? syncState,
  }) {
    final bound = _bound;
    if (bound == null ||
        _boundUid != expectedUid ||
        _wipingUids.contains(expectedUid)) {
      throw const JournalUnbound();
    }
    // The owner check and the hand-over to the delegate are one synchronous
    // step; the put is tracked until it finishes so an unbind or a wipe of this
    // delegate waits (bounded) for it before closing or wiping it.
    final Future<JournalEntry> put = bound.put(session, syncState: syncState);
    final Set<Future<void>> inFlight = _inFlightPuts.putIfAbsent(
        bound, () => <Future<void>>{});
    late final Future<void> marker;
    marker = put.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      inFlight.remove(marker);
    });
    inFlight.add(marker);
    return put;
  }

  @override
  Future<void> delete(String id) async => _writer().delete(id);

  @override
  Future<bool> updateSyncState(
    String id,
    JournalSyncState state, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) async =>
      _writer().updateSyncState(id, state,
          expectedGeneration: expectedGeneration,
          baseRev: baseRev,
          baseSummary: baseSummary);

  @override
  Future<JournalEntry?> updateRecord(
    String id,
    ActivitySession session, {
    JournalSyncState? syncState,
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) async =>
      _writer().updateRecord(id, session,
          syncState: syncState,
          expectedGeneration: expectedGeneration,
          baseRev: baseRev,
          baseSummary: baseSummary);

  @override
  Future<bool> markSynced(
    String id, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  }) async =>
      _writer().markSynced(id,
          expectedGeneration: expectedGeneration,
          baseRev: baseRev,
          baseSummary: baseSummary);

  @override
  Future<bool> markStreamUploaded(String id, {int? expectedGeneration}) async =>
      _writer().markStreamUploaded(id, expectedGeneration: expectedGeneration);

  /// Wipes only the CURRENTLY bound journal; refused while unbound.
  @override
  Future<void> wipe() async => _writer().wipe();

  /// Closes the bound journal and leaves the scoped journal unbound.
  @override
  Future<void> close() async {
    await bindUid(null);
  }
}
