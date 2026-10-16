/// Firestore implementation of [ActivitySummaryBackend] (S02 design 3.2, 6.2).
///
/// Reads and writes `users/{uid}/activities/{id}` and reads the owner-readable
/// tombstones `users/{uid}/activity_tombstones/{id}`. Timestamp keys cross the
/// seam as `DateTime`; the shape, `rev` and tombstone rules live in
/// `firestore.rules`, so this adapter only translates:
///
/// - `permission-denied` on a write -> [SummaryWriteDenied] (never read as a
///   deletion, design 6.2);
/// - every other failure, a timeout, or a missing sign-in ->
///   [SummaryBackendUnavailable] (the write MAY have been applied);
/// - reads use the server source, so a stale local cache is never mistaken for
///   the server state or for an absent tombstone.
///
/// Writes go in batches of at most [kMaxSummaryBatch] (each summary write costs
/// two rule lookups against the batched-write access-call limit).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'activity_summary_backend.dart';

/// One summary to write in a batch.
class SummaryWrite {
  const SummaryWrite(this.id, this.summary, {required this.create});

  final String id;
  final Map<String, Object> summary;

  /// True only when the client knows the document does not exist (rev 1).
  final bool create;
}

class FirestoreActivitySummaryBackend implements ActivitySummaryBackend {
  FirestoreActivitySummaryBackend({
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
    Duration timeout = const Duration(seconds: 15),
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _uid = currentUid ?? _signedInUid,
        _timeout = timeout;

  final FirebaseFirestore _db;
  final String? Function() _uid;
  final Duration _timeout;

  static const GetOptions _serverRead = GetOptions(source: Source.server);

  /// The signed-in non-anonymous uid, or null (rules refuse anonymous users).
  static String? _signedInUid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> _summaryRef(String uid, String id) =>
      _db.collection('users').doc(uid).collection('activities').doc(id);

  CollectionReference<Map<String, dynamic>> _tombstones(String uid) =>
      _db.collection('users').doc(uid).collection('activity_tombstones');

  String _requireUid() {
    final uid = _uid();
    if (uid == null || uid.isEmpty) {
      throw const SummaryBackendUnavailable('not-signed-in');
    }
    return uid;
  }

  Future<T> _read<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_timeout);
    } on SummaryBackendUnavailable {
      rethrow;
    } catch (e) {
      throw SummaryBackendUnavailable(_codeOf(e));
    }
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    final uid = _requireUid();
    return _read(() async {
      final snap = await _summaryRef(uid, id).get(_serverRead);
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return fromFirestoreSummary(data);
    });
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    final uid = _requireUid();
    return _read(() async {
      final snap = await _tombstones(uid).doc(id).get(_serverRead);
      return snap.exists;
    });
  }

  @override
  Future<Set<String>> listTombstoneIds() async {
    final uid = _requireUid();
    return _read(() async {
      final snap = await _tombstones(uid).get(_serverRead);
      return {for (final d in snap.docs) d.id};
    });
  }

  @override
  Future<void> writeSummary(
    String id,
    Map<String, Object> summary, {
    required bool create,
  }) =>
      writeSummaries([SummaryWrite(id, summary, create: create)]);

  /// Writes up to [kMaxSummaryBatch] summaries in one atomic batch. A larger
  /// list is refused before anything is sent ([SummaryBatchTooLarge]). The
  /// whole batch is accepted or denied together.
  Future<void> writeSummaries(List<SummaryWrite> writes) async {
    if (writes.length > kMaxSummaryBatch) {
      throw SummaryBatchTooLarge(writes.length, kMaxSummaryBatch);
    }
    if (writes.isEmpty) return;
    final uid = _requireUid();
    final batch = _db.batch();
    for (final w in writes) {
      // `create` is decided by the rules from the stored document; the flag
      // only documents the caller's knowledge (create => rev 1).
      batch.set(_summaryRef(uid, w.id), toFirestoreSummary(w.summary));
    }
    try {
      await batch.commit().timeout(_timeout);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw SummaryWriteDenied(e.code);
      }
      throw SummaryBackendUnavailable(e.code);
    } catch (e) {
      throw SummaryBackendUnavailable(_codeOf(e));
    }
  }

  static String _codeOf(Object e) =>
      e is FirebaseException ? e.code : e.runtimeType.toString();
}

/// Summary map -> Firestore map: `DateTime` -> `Timestamp`, everything else
/// unchanged (numbers, strings and bools are valid Firestore values).
Map<String, Object> toFirestoreSummary(Map<String, Object> summary) => {
      for (final e in summary.entries)
        e.key: e.value is DateTime
            ? Timestamp.fromDate((e.value as DateTime).toUtc())
            : e.value,
    };

/// Firestore map -> summary map: `Timestamp` -> UTC `DateTime`.
Map<String, Object?> fromFirestoreSummary(Map<String, dynamic> data) => {
      for (final e in data.entries)
        e.key: e.value is Timestamp
            ? (e.value as Timestamp).toDate().toUtc()
            : e.value,
    };
