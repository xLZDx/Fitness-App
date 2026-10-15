/// Firestore implementation of the server scan history (design s5.1) and an
/// in-memory fake. CLOUD PATH ONLY: scans measured by the on-device
/// provisional estimator live in the encrypted local record and produce no
/// document here (D-52).
///
/// The client may update only `weightKg` and `clientNote` (rules, D-68); create
/// and delete are server-only, so this class never writes anything else.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/body_scan_entry.dart';
import '../data/body_scan_repository.dart';

class FirestoreBodyScanRepository implements BodyScanRepository {
  FirestoreBodyScanRepository({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('body_scans');

  @override
  Stream<List<BodyScanEntry>> watchEntries({int limit = 120}) {
    return _col
        .orderBy('takenAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final out = <BodyScanEntry>[];
      for (final d in snap.docs) {
        final data = d.data();
        final taken = data['takenAt'];
        final entry = BodyScanEntry.tryFromJson(d.id, {
          ...data,
          'takenAt': taken is Timestamp ? taken.toDate() : taken,
        });
        // A document that cannot be read is skipped, never thrown.
        if (entry != null) out.add(entry);
      }
      return List.unmodifiable(out);
    });
  }

  @override
  Future<void> updateRecordedWeight(String scanId, double weightKg) async {
    if (!weightKg.isFinite || weightKg < 30 || weightKg > 300) {
      throw ArgumentError.value(weightKg, 'weightKg', 'must be within 30..300');
    }
    await _col.doc(scanId).update({'weightKg': weightKg});
  }

  @override
  Future<void> updateNote(String scanId, String? note) async {
    final trimmed = note?.trim();
    if (trimmed != null && trimmed.length > 200) {
      throw ArgumentError.value(note, 'note', 'at most 200 characters');
    }
    await _col.doc(scanId).update({
      'clientNote': (trimmed == null || trimmed.isEmpty)
          ? FieldValue.delete()
          : trimmed,
    });
  }
}

/// In-memory repository for tests and for builds without the cloud path.
class InMemoryBodyScanRepository implements BodyScanRepository {
  InMemoryBodyScanRepository([Iterable<BodyScanEntry> initial = const []])
      : _entries = {for (final e in initial) e.scanId: e};

  final Map<String, BodyScanEntry> _entries;
  final StreamController<void> _changed = StreamController<void>.broadcast();

  /// Weight updates, in order (for assertions).
  final List<(String, double)> weightUpdates = [];

  /// Note updates, in order (for assertions).
  final List<(String, String?)> noteUpdates = [];

  List<BodyScanEntry> _sorted(int limit) {
    final all = _entries.values.toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return List.unmodifiable(all.take(limit));
  }

  /// Test seam: inserts or replaces an entry.
  void put(BodyScanEntry entry) {
    _entries[entry.scanId] = entry;
    _changed.add(null);
  }

  @override
  Stream<List<BodyScanEntry>> watchEntries({int limit = 120}) async* {
    yield _sorted(limit);
    await for (final _ in _changed.stream) {
      yield _sorted(limit);
    }
  }

  @override
  Future<void> updateRecordedWeight(String scanId, double weightKg) async {
    if (!weightKg.isFinite || weightKg < 30 || weightKg > 300) {
      throw ArgumentError.value(weightKg, 'weightKg', 'must be within 30..300');
    }
    final e = _entries[scanId];
    if (e == null) return;
    weightUpdates.add((scanId, weightKg));
    _entries[scanId] = BodyScanEntry(
      scanId: e.scanId,
      takenAt: e.takenAt,
      status: e.status,
      photosState: e.photosState,
      weightKg: weightKg,
      estimate: e.estimate,
      providerId: e.providerId,
      clientNote: e.clientNote,
    );
    _changed.add(null);
  }

  @override
  Future<void> updateNote(String scanId, String? note) async {
    final trimmed = note?.trim();
    if (trimmed != null && trimmed.length > 200) {
      throw ArgumentError.value(note, 'note', 'at most 200 characters');
    }
    final e = _entries[scanId];
    if (e == null) return;
    noteUpdates.add((scanId, trimmed));
    _entries[scanId] = BodyScanEntry(
      scanId: e.scanId,
      takenAt: e.takenAt,
      status: e.status,
      photosState: e.photosState,
      weightKg: e.weightKg,
      estimate: e.estimate,
      providerId: e.providerId,
      clientNote: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    _changed.add(null);
  }

  void dispose() => unawaited(_changed.close());
}
