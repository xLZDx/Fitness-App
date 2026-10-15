// Firestore implementations of the diary and saved-foods ports. Documents are
// exactly what firestore.rules (D-68) accepts: `loggedAt` and `createdAt` are
// Timestamps, entries carry only the allowlisted keys, and the day query is a
// single equality (`where('day', '==', d)`, no composite index; sorted here).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/food_entry.dart';
import 'diary_repository.dart';

class FirestoreDiaryRepository implements FoodDiaryRepository {
  FirestoreDiaryRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('food_entries');

  FoodEntry? _entry(String id, Map<String, dynamic> data) {
    final at = data['loggedAt'];
    final e = FoodEntry.fromJson(id, {
      ...data,
      'loggedAt': at is Timestamp ? at.toDate() : at,
    });
    return e.day.isEmpty ? null : e;
  }

  @override
  Stream<List<FoodEntry>> watchDay(String uid, String day) =>
      _col(uid).where('day', isEqualTo: day).snapshots().map((q) {
        final list = [
          for (final d in q.docs)
            if (_entry(d.id, d.data()) case final e?) e,
        ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
        return list;
      });

  @override
  Future<void> put(String uid, FoodEntry entry) {
    final json = entry.toJson();
    json['loggedAt'] = Timestamp.fromDate(entry.loggedAt);
    return _col(uid).doc(entry.id).set(json);
  }

  @override
  Future<void> delete(String uid, String entryId) =>
      _col(uid).doc(entryId).delete();
}

class FirestoreSavedFoodsRepository implements SavedFoodsRepository {
  FirestoreSavedFoodsRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('saved_foods');

  @override
  Stream<List<SavedFood>> watchAll(String uid) =>
      _col(uid).limit(SavedFood.maxCount).snapshots().map((q) {
        final list = [
          for (final d in q.docs)
            if (SavedFood.tryFromJson(d.id, {
              ...d.data(),
              'createdAt': switch (d.data()['createdAt']) {
                final Timestamp t => t.toDate(),
                final other => other,
              },
            })
                case final f?)
              f,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  @override
  Future<void> put(String uid, SavedFood food) async {
    final json = food.toJson();
    final ref = _col(uid).doc(food.id);
    final existing = await ref.get();
    if (!existing.exists) {
      final count = await _col(uid).count().get();
      if ((count.count ?? 0) >= SavedFood.maxCount) {
        throw StateError('saved foods limit reached');
      }
      json['createdAt'] = Timestamp.fromDate(food.createdAt ?? DateTime.now());
    } else if (existing.data()?['createdAt'] case final Timestamp t) {
      json['createdAt'] = t;
    }
    await ref.set(json);
  }

  @override
  Future<void> delete(String uid, String foodId) =>
      _col(uid).doc(foodId).delete();
}
