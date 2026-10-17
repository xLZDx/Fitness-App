/// Account-scoped activity journals (S02 remediation E1, design 6.2, 7, 17).
///
/// Ownership is the location: every account has its own journal directory and
/// its own key, derived from the account uid. [UidScopedActivityJournal] holds
/// no data itself; it delegates to the journal currently bound to the signed-in
/// uid. Sign-out and account switch never destroy data (the previous journal is
/// only closed); only account deletion wipes the deleted account's scope.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:path_provider/path_provider.dart';

import '../data/activity_session.dart';
import 'activity_journal.dart';
import 'file_activity_journal.dart';
import 'journal_cipher.dart';
import 'journal_errors.dart';
import 'journal_layout.dart' show kScopedJournalRootDirName;
import 'journal_models.dart';

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
    implements ActivityJournal, AccountScopedJournal {
  /// Cheap: no I/O until [bindUid].
  UidScopedActivityJournal({ActivityJournalFactory? factory})
      : _factory = factory ?? fileActivityJournalFactory();

  final ActivityJournalFactory _factory;
  final JournalMutex _mutex = JournalMutex();
  ActivityJournal? _bound;
  String? _boundUid;

  /// The uid whose scope was wiped while it was the bound one (account
  /// deletion). [bindUid] refuses it until another uid (or null) is bound, so a
  /// same-uid auth re-emission cannot re-create the deleted account's scope.
  String? _wipedUid;

  @override
  String? get boundUid => _boundUid;

  @override
  bool get isBound => _bound != null;

  Future<void> _unbind() async {
    final current = _bound;
    _bound = null;
    _boundUid = null;
    if (current != null) {
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
        // An explicit unbind ends the wiped-uid refusal even when nothing is
        // bound (a wipe of the bound uid already left the journal unbound).
        if (uid == null) _wipedUid = null;
        if (uid == _boundUid && (uid == null || _bound != null)) return true;
        // A different uid or an explicit unbind ends the wiped-uid refusal.
        _wipedUid = null;
        await _unbind();
        if (uid == null) return true;
        ActivityJournal? opened;
        try {
          opened = await _factory(activityJournalScopeId(uid));
          await opened.start();
          _bound = opened;
          _boundUid = uid;
          return true;
        } catch (_) {
          if (opened != null) {
            try {
              await opened.close();
            } catch (_) {}
          }
          return false;
        }
      });

  @override
  Future<void> wipeForUid(String uid) => _mutex.run(() async {
        if (uid.isEmpty) throw const JournalUnbound();
        // Remembered in BOTH branches and even when the wipe fails: the marker
        // retries the wipe and nothing, not even an already queued
        // `bindUid(uid)`, may re-create the scope or its key afterwards.
        _wipedUid = uid;
        if (uid == _boundUid && _bound != null) {
          final current = _bound!;
          try {
            await current.wipe();
          } finally {
            await _unbind();
          }
          return;
        }
        final other = await _factory(activityJournalScopeId(uid));
        try {
          await other.start();
          await other.wipe();
        } finally {
          try {
            await other.close();
          } catch (_) {}
        }
      });

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
