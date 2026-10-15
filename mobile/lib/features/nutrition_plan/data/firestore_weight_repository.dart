// Firestore implementation of [WeightEntriesRepository]. Reads/writes
//   /users/{uid}/weight_entries/{yyyy-MM-dd}
// with `{schema: 1, kg, at: Timestamp, source}` exactly as the rules require
// (`at` must be a Timestamp, `kg` 30..300, `source` manual|scan).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'weight_entry.dart';
import 'weight_repository.dart';

class FirestoreWeightRepository implements WeightEntriesRepository {
  FirestoreWeightRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('weight_entries');

  Map<String, dynamic> _toMap(WeightEntry e) => {
        'schema': 1,
        'kg': e.kg,
        'at': Timestamp.fromDate(e.at),
        'source': e.source.name,
      };

  WeightLogItem? _item(String id, Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['at'];
    final entry = WeightEntry.tryFromJson({
      ...data,
      'at': raw is Timestamp ? raw.toDate() : raw,
    });
    return entry == null ? null : WeightLogItem(id: id, entry: entry);
  }

  Query<Map<String, dynamic>> _window(String uid, int days) => _col(uid)
      .where('at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime.now().subtract(Duration(days: days))))
      .orderBy('at');

  List<WeightLogItem> _items(QuerySnapshot<Map<String, dynamic>> q) => [
        for (final d in q.docs)
          if (_item(d.id, d.data()) case final i?) i,
      ];

  @override
  Stream<List<WeightLogItem>> watchLog(String uid, {int days = 60}) =>
      _window(uid, days).snapshots().map(_items);

  @override
  Future<List<WeightLogItem>> loadLog(String uid, {int days = 60}) async =>
      _items(await _window(uid, days).get());

  @override
  Future<WeightLogItem?> entryForDay(String uid, String dayKey) async {
    final s = await _col(uid).doc(dayKey).get();
    return s.exists ? _item(s.id, s.data()) : null;
  }

  static void _check(WeightEntry e) {
    if (!WeightEntry.isValidKg(e.kg)) {
      throw ArgumentError.value(e.kg, 'kg', 'must be within 30..300');
    }
  }

  @override
  Future<void> put(String uid, WeightEntry entry) async {
    _check(entry);
    await _col(uid).doc(entry.dayKey).set(_toMap(entry));
  }

  @override
  Future<void> replace(
    String uid, {
    required String oldId,
    required WeightEntry entry,
  }) async {
    _check(entry);
    final batch = _db.batch();
    if (oldId != entry.dayKey) batch.delete(_col(uid).doc(oldId));
    batch.set(_col(uid).doc(entry.dayKey), _toMap(entry));
    await batch.commit();
  }

  @override
  Future<void> delete(String uid, String id) => _col(uid).doc(id).delete();
}
